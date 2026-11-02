extends Node
## UDP link to the factorio-3d-bridge mod (autoload "Bridge"). See docs/PROTOCOL.md.
##
## Reliable messages carry a sequence number `r`. On a gap we ask the mod to resend the chunks
## the world mirror knows are incomplete, or the whole handshake if the gap hit the prototype
## dictionaries.
##
## Nothing is sent until `connect_to` (the menu, or main.gd straight away when started with
## --factorio-port / --port); `disconnect_from` says goodbye and closes the socket.
##
## Command-line options (after `--`): --factorio-port=34200 --port=34201 --update-rate=0..3

signal welcomed(msg: Dictionary)
signal message_received(msg: Dictionary)
signal connection_lost

const PROTOCOL := 1
const HELLO_INTERVAL := 1.0
const TIMEOUT_MSEC := 5000
# A little over the mod's 120-tick limit, so a full resync is never dropped for arriving early.
const FULL_RESYNC_COOLDOWN_MSEC := 2500
# Chunk resyncs aren't limited by the mod; this only stops one per gap during a burst.
const CHUNK_RESYNC_COOLDOWN_MSEC := 500
const RECEIVE_BUFFER := 4 * 1024 * 1024
# Prototypes still incomplete and nothing reliable for this long: the end of the handshake was
# lost, and with nothing after it there is no gap to notice, so start it over.
const HANDSHAKE_STALL_MSEC := 3000

var factorio_host := "127.0.0.1"
var factorio_port := 34200
var listen_port := 34201
## Ports after listen_port to try when it is taken (another client on this machine).
const MORE_PORTS := 7
## Ask for decoratives in the hello (main.gd, from the Graphics settings).
var decoratives := true
var bind_error := OK
## True between a welcome and a timeout.
var connected := false
## True once the prototype dictionaries are complete ("ready" arrived).
var world_ready := false
var server_tick := 0
var stats := {"packets": 0, "bytes": 0, "gaps": 0, "handle_usec": 0, "resyncs": 0, "full_resyncs": 0, "bad_json": 0}
## The bridge's last `wb`: its work budget per tick (`b`, in work units), the units it used per tick
## over the last second (`avg`, `max`), ticks over budget (`over`) and its queues' lengths (`q`).
var work_budget := {}
## Main-thread time spent on each message type so far, in microseconds (for perf probes).
var handle_usec := {}
var last_reliable_msec := 0
## Returns the chunks to ask for again after a gap, as [[cx, cy], ...]. Set by the world mirror.
var resync_chunks: Callable
## How much the mod slows its costliest updates down (`rate`, PROTOCOL.md): 0 normal to
## MAX_UPDATE_RATE. Set with set_update_rate; sent again after every handshake.
var update_rate := 0
const MAX_UPDATE_RATE := 3
var _rate_sent := -1

var _udp := PacketPeerUDP.new()
## The socket is read on a thread of its own. Windows keeps only ~64 KB of unread datagrams per
## socket, which the mod's chunk stream fills in a couple of ticks: read only between frames, any
## frame over ~30 ms (a terrain texture loading, a burst of chunk builds) lost chunks, and their
## ground stayed missing until a resync. While the thread runs only it touches _udp: sends queue.
var _io_thread: Thread
var _io_mutex := Mutex.new()
var _io_run := false
var _inbox: Array[PackedByteArray] = []
var _outbox: Array[PackedByteArray] = []
var _session := ""
var _expected_r := 1
var _hello_timer := 0.0
var _last_packet_msec := 0
var _last_resync_msec := -100000
## 0 none, 1 chunks, 2 full. Sent after the frame's packets are handled, so the chunk list
## sees what arrived after the gap, and kept through the cooldown, so packets lost in the middle
## of a resend burst are still asked for.
var _pending_resync := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--factorio-port="):
			factorio_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--port="):
			listen_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--update-rate="):
			set_update_rate(int(arg.get_slice("=", 1)))
	randomize()


## Asks the mod to send its costliest updates less often (0 normal, 1-3 slower and slower): when
## the server is under load the world may lag, but the server won't. Belt items, movers and
## inserter hands still glide (their messages say how far apart they are); the character's own
## updates never slow down.
func set_update_rate(level: int) -> void:
	update_rate = clampi(level, 0, MAX_UPDATE_RATE)


## Starts talking to the mod at host:port from our UDP port `listen`. bind_error says if the
## port couldn't be opened.
func connect_to(host: String, port: int, listen: int) -> void:
	disconnect_from()
	factorio_host = host
	factorio_port = port
	listen_port = listen
	_session = "%d-%d" % [int(Time.get_unix_time_from_system()), randi() % 1000000]
	_udp = PacketPeerUDP.new()
	bind_error = _udp.bind(listen_port, "127.0.0.1", RECEIVE_BUFFER)
	# Another client on this machine has the port: a server takes up to 8 clients, each on its own
	# port, so try the next ones.
	var tries := 0
	while bind_error != OK and tries < MORE_PORTS:
		tries += 1
		_udp = PacketPeerUDP.new()
		bind_error = _udp.bind(listen + tries, "127.0.0.1", RECEIVE_BUFFER)
		if bind_error == OK:
			listen_port = listen + tries
	if bind_error != OK:
		push_error("Can't listen on UDP port %d (error %d). Is another client running?" % [listen_port, bind_error])
		return
	_udp.set_dest_address(host, factorio_port)
	_io_run = true
	_io_thread = Thread.new()
	_io_thread.start(_io_loop)
	# The first hello waits for the first frame. Sent now, the mod's ~200 KB handshake would
	# arrive while the main scene is still loading, and Windows keeps only ~64 KB of unread
	# datagrams per socket.
	_hello_timer = HELLO_INTERVAL


## Says goodbye and closes the socket; nothing more arrives until the next connect_to.
func disconnect_from() -> void:
	_stop_io()
	if _udp.is_bound():
		send({"t": "bye"})
		_udp.close()
	connected = false
	world_ready = false
	bind_error = OK
	server_tick = 0
	stats = {"packets": 0, "bytes": 0, "gaps": 0, "handle_usec": 0, "resyncs": 0, "full_resyncs": 0, "bad_json": 0}
	_waiting.clear()
	_waiting_at = 0
	_expected_r = 1
	_pending_resync = 0
	_last_packet_msec = 0
	last_reliable_msec = 0


func is_active() -> bool:
	return _udp.is_bound()


## The I/O thread: sends what's queued, then reads everything waiting, about once a millisecond.
func _io_loop() -> void:
	while true:
		_io_mutex.lock()
		var run := _io_run
		var out := _outbox
		_outbox = []
		_io_mutex.unlock()
		for data in out:
			_udp.put_packet(data)
		if not run:
			return
		var got: Array[PackedByteArray] = []
		while _udp.get_available_packet_count() > 0:
			got.append(_udp.get_packet())
		if not got.is_empty():
			_io_mutex.lock()
			_inbox.append_array(got)
			_io_mutex.unlock()
		OS.delay_usec(1000)


func _stop_io() -> void:
	if _io_thread == null:
		return
	_io_mutex.lock()
	_io_run = false
	_io_mutex.unlock()
	_io_thread.wait_to_finish()
	_io_thread = null
	_inbox.clear()


func _process(delta: float) -> void:
	if bind_error != OK or not _udp.is_bound():
		return
	_hello_timer += delta
	if _hello_timer >= HELLO_INTERVAL:
		_hello_timer = 0.0
		_send_hello()
	var packets: Array[PackedByteArray] = []
	if _io_thread != null:
		_io_mutex.lock()
		packets = _inbox
		_inbox = []
		_io_mutex.unlock()
	else:
		while _udp.get_available_packet_count() > 0:
			packets.append(_udp.get_packet())
	for packet in packets:
		_queue(packet)
	_drain()
	# A new session's mod starts at 0, and keeps the level through a resync: sent after each
	# handshake unless it is 0 and was never anything else.
	if not world_ready:
		_rate_sent = -1 if _rate_sent > 0 or update_rate > 0 else 0
	elif _rate_sent != update_rate:
		_rate_sent = update_rate
		send({"t": "rate", "l": update_rate})
	if connected and not world_ready and Time.get_ticks_msec() - last_reliable_msec > HANDSHAKE_STALL_MSEC:
		request_resync(true)
	if _pending_resync > 0 and connected:
		_send_resync()
	if connected and Time.get_ticks_msec() - _last_packet_msec > TIMEOUT_MSEC:
		connected = false
		world_ready = false
		connection_lost.emit()


## Messages waiting to be handled (text), oldest first from _waiting_at.
var _waiting := PackedStringArray()
var _waiting_at := 0
## Main-thread time a frame spends handling messages: a big base sends 6,000 belt items several
## times a second, which took 20-40 ms to handle in one frame and made the view stutter. The rest
## wait for the next frame; past BACKLOG_MESSAGES waiting, a frame takes up to twice as long.
## 4 ms, not 6: the world's chunk rebuilds come after it in the same frame (world.gd shares one
## allowance with it), and together they made the 20 ms frames walking on the owner's save.
const HANDLE_USEC := 4000
const BACKLOG_MESSAGES := 300
## This frame's message handling, in µs, for world.gd's share of the frame.
var frame_handle_usec := 0
## Messages that took longer than this to handle: [ms, type, bytes] (for --stutter-probe).
const SLOW_MESSAGE_USEC := 8000
var slow_messages: Array = []


func _queue(packet: PackedByteArray) -> void:
	stats["packets"] += 1
	stats["bytes"] += packet.size()
	var text := packet.get_string_from_utf8()
	if text.contains("\n"):
		_waiting.append_array(text.split("\n", false))
	else:
		_waiting.append(text)


var _json := JSON.new()
## A bare inf, -inf or nan where a number goes: Factorio's table_to_json writes a Lua float that
## isn't finite as it is, which isn't JSON.
var _not_finite := RegEx.create_from_string("([:,[]) *(-?)(inf|nan|-nan) *(?=[]},])")
var _bad_types := {}


## One message's text as its Dictionary (or whatever else it held), null when it isn't JSON. A
## message with numbers that aren't finite (seen 4 times in a 30-minute session on a real busy
## base, the whole message lost) is read with them as 1e18, -1e18 or 0, counted in stats
## ("bad_json") and reported once per message type with where it was.
func parse(text: String) -> Variant:
	if _json.parse(text) == OK:
		return _json.data
	if not (text.contains("inf") or text.contains("nan")):
		return null
	var fixed := _not_finite.sub(text, "$1$2NOT_FINITE_$3", true)
	fixed = fixed.replace("-NOT_FINITE_inf", "-1e18").replace("NOT_FINITE_inf", "1e18")
	fixed = fixed.replace("-NOT_FINITE_nan", "0").replace("NOT_FINITE_-nan", "0").replace("NOT_FINITE_nan", "0")
	if _json.parse(fixed) != OK:
		return null
	stats["bad_json"] = int(stats.get("bad_json", 0)) + 1
	var data = _json.data
	var kind := str(data.get("t", "?")) if data is Dictionary else "?"
	if not _bad_types.has(kind):
		_bad_types[kind] = true
		var at := maxi(text.find("inf"), text.find("nan"))
		push_warning("bridge: a '%s' message had a number that isn't finite (read as 1e18 or 0): ...%s..." % [kind, text.substr(maxi(0, at - 120), 160)])
	return data


func _drain() -> void:
	var start := Time.get_ticks_usec()
	var limit := HANDLE_USEC * (2 if _waiting.size() - _waiting_at > BACKLOG_MESSAGES else 1)
	while _waiting_at < _waiting.size():
		var t0 := Time.get_ticks_usec()
		var msg = parse(_waiting[_waiting_at])
		_waiting_at += 1
		if msg is Dictionary:
			_handle(msg)
			var spent := Time.get_ticks_usec() - t0
			if spent > SLOW_MESSAGE_USEC and slow_messages.size() < 200:
				slow_messages.append([spent / 1000.0, str(msg.get("t", "")), _waiting[_waiting_at - 1].length()])
		if Time.get_ticks_usec() - start > limit:
			break
	frame_handle_usec = Time.get_ticks_usec() - start
	stats["handle_usec"] += frame_handle_usec
	if _waiting_at >= _waiting.size():
		_waiting.clear()
		_waiting_at = 0
	elif _waiting_at > 4096:
		_waiting = _waiting.slice(_waiting_at)
		_waiting_at = 0


## Messages received but not handled yet (for tests and the F4 line).
func waiting_count() -> int:
	return _waiting.size() - _waiting_at


## One datagram from the mod, handled at once: a message, or several joined by newlines (`b` in the hello: sending a
## datagram costs Factorio about a millisecond, so the mod fills each one). Anything that isn't a
## JSON object is dropped (tests/bridge_fuzz_test.gd throws garbage at this).
func receive(packet: PackedByteArray) -> void:
	stats["packets"] += 1
	stats["bytes"] += packet.size()
	var text := packet.get_string_from_utf8()
	if not text.contains("\n"):
		var msg = parse(text)
		if msg is Dictionary:
			_handle(msg)
		return
	for line in text.split("\n", false):
		var msg = parse(line)
		if msg is Dictionary:
			_handle(msg)


## A JSON number as an int, or `default` for anything else. Packets come from a local port any
## program can write to, so their fields aren't trusted to be numbers.
static func _int_or(v: Variant, default: int) -> int:
	if v is int:
		return v
	if v is float and is_finite(v) and absf(v) < 9.0e18:
		return int(v)
	return default


func _exit_tree() -> void:
	_stop_io()
	send({"t": "bye"})


## Sets the bridge's work budget per tick, in work units (it clamps it to 50-20000).
func set_work_budget(units: int) -> void:
	send({"t": "budget", "u": units})


func send(cmd: Dictionary) -> void:
	if bind_error != OK or not _udp.is_bound():
		return
	var data := JSON.stringify(cmd).to_utf8_buffer()
	if _io_thread != null:
		_io_mutex.lock()
		_outbox.append(data)
		_io_mutex.unlock()
	else:
		_udp.put_packet(data)


func request_resync(full: bool) -> void:
	_pending_resync = maxi(_pending_resync, 2 if full else 1)


func _send_resync() -> void:
	var full := _pending_resync == 2
	var now := Time.get_ticks_msec()
	if now - _last_resync_msec < (FULL_RESYNC_COOLDOWN_MSEC if full else CHUNK_RESYNC_COOLDOWN_MSEC):
		return
	_last_resync_msec = now
	_pending_resync = 0
	if full:
		stats["full_resyncs"] += 1
		send({"t": "resync", "full": 1})
	elif resync_chunks.is_valid():
		var list: Array = resync_chunks.call()
		if not list.is_empty():
			stats["resyncs"] += 1
			send({"t": "resync", "full": 0, "c": list})


func _send_hello() -> void:
	# z: bi, ih and mv lists delta-coded (see PROTOCOL.md), most of a busy base's traffic.
	# dc: decoratives (dprotos, dec), as Settings → Graphics → Decoratives says (main.gd sets it).
	var hello := {"t": "hello", "v": PROTOCOL, "sid": _session, "w": 1 if connected else 0, "z": 1, "b": 1}
	if decoratives:
		hello["dc"] = 1
	send(hello)


func _handle(msg: Dictionary) -> void:
	_last_packet_msec = Time.get_ticks_msec()
	server_tick = _int_or(msg.get("k"), server_tick)
	var t := str(msg.get("t", ""))
	if msg.has("r"):
		last_reliable_msec = _last_packet_msec
		var r := _int_or(msg["r"], -1)
		# A sequence number that isn't one, or one wildly ahead, is garbage, not a gap.
		if r < 1 or (connected and r - _expected_r > 1000000):
			return
		if t == "welcome":
			if _int_or(msg.get("v"), 0) != PROTOCOL:
				push_warning("Bridge mod speaks protocol %s, this client %d" % [str(msg.get("v")), PROTOCOL])
			_expected_r = r + 1
			connected = true
			world_ready = false
			_pending_resync = 0
			welcomed.emit(msg)
			return
		if not connected:
			return
		if r < _expected_r:
			# The numbering went backwards: the server reloaded a save. Start over.
			request_resync(true)
			return
		if r > _expected_r:
			stats["gaps"] += 1
			request_resync(not world_ready)
		_expected_r = r + 1
		if t == "ready":
			world_ready = true
	elif not connected:
		return
	if t == "wb":
		# The bridge's work per tick (once a second): kept here for whatever reads it.
		work_budget = msg
		return
	var t0 := Time.get_ticks_usec()
	message_received.emit(msg)
	handle_usec[t] = int(handle_usec.get(t, 0)) + Time.get_ticks_usec() - t0
