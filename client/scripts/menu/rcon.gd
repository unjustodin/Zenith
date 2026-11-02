extends RefCounted
## A Source RCON client (the protocol Factorio's --rcon-port speaks, like tools/rcon.py), for the
## server the menu started: saving, quitting. Calls are awaited and give up after a timeout.
##
##   var rcon := Rcon.new()
##   if await rcon.open(tree, port, password): print(await rcon.run(tree, "/server-save"))

const AUTH := 3
const EXEC := 2
const AUTH_RESPONSE := 2
const TIMEOUT_MSEC := 10000

var error := ""
var _tcp := StreamPeerTCP.new()
var _buffer := PackedByteArray()
var _next_id := 10


func is_open() -> bool:
	_tcp.poll()
	return _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


## Connects and logs in. False (and `error`) if the server isn't listening or refuses.
func open(tree: SceneTree, port: int, password: String) -> bool:
	close()
	if _tcp.connect_to_host("127.0.0.1", port) != OK:
		error = "Can't connect to RCON on port %d" % port
		return false
	var started := Time.get_ticks_msec()
	while true:
		_tcp.poll()
		var status := _tcp.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			break
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE or Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			error = "RCON on port %d doesn't answer" % port
			close()
			return false
		await tree.process_frame
	_send(1, AUTH, password)
	while true:
		var packet: Array = await _read(tree)
		if packet.is_empty():
			error = "RCON login timed out"
			close()
			return false
		if int(packet[1]) == AUTH_RESPONSE:
			if int(packet[0]) == -1:
				error = "RCON password rejected"
				close()
				return false
			return true
	return false


## Runs a console command; its reply ("" if none came in time, or on error).
func run(tree: SceneTree, command: String) -> String:
	if not is_open():
		error = "RCON not connected"
		return ""
	_next_id += 1
	var id := _next_id
	_send(id, EXEC, command)
	while true:
		var packet: Array = await _read(tree)
		if packet.is_empty():
			return ""
		if int(packet[0]) == id:
			return str(packet[2])
	return ""


func close() -> void:
	_tcp.disconnect_from_host()
	_buffer = PackedByteArray()


func _send(id: int, kind: int, body: String) -> void:
	var payload := StreamPeerBuffer.new()
	payload.put_32(id)
	payload.put_32(kind)
	payload.put_data(body.to_utf8_buffer())
	payload.put_u8(0)
	payload.put_u8(0)
	var packet := StreamPeerBuffer.new()
	packet.put_32(payload.data_array.size())
	packet.put_data(payload.data_array)
	_tcp.put_data(packet.data_array)


## The next packet as [id, type, body], or [] after the timeout or when the connection drops.
func _read(tree: SceneTree) -> Array:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < TIMEOUT_MSEC:
		_tcp.poll()
		if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return []
		var available := _tcp.get_available_bytes()
		if available > 0:
			var got: Array = _tcp.get_partial_data(available)
			if int(got[0]) == OK:
				_buffer.append_array(got[1])
		if _buffer.size() >= 4:
			var size := _buffer.decode_s32(0)
			if _buffer.size() >= 4 + size:
				var id := _buffer.decode_s32(4)
				var kind := _buffer.decode_s32(8)
				var body := _buffer.slice(12, 4 + size - 2).get_string_from_utf8()
				_buffer = _buffer.slice(4 + size)
				return [id, kind, body]
		await tree.process_frame
	return []
