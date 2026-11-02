extends RefCounted
## The client's own blueprint library ("My blueprints"), as Factorio's: blueprints, books and
## planners in the order the player arranged them, books holding pages (Factorio's library has no
## folders: books are its folders, and open in place). Kept as the decoded exchange strings in
## user://blueprint-library.json, outside the repo and the game, so it outlives saves and servers,
## like Factorio's blueprint-storage file does.
##
## A place in it is a path: [] the top, [3] inside the fourth record (a book), [3, 0] inside that
## book's first page if it is a book too.

const BpString := preload("res://scripts/ui/factorio/bp_string.gd")

signal changed

## Tests point this elsewhere.
static var save_path := "user://blueprint-library.json"

## [record, ...] at the top.
var records: Array = []


func _init() -> void:
	load_file()


func load_file() -> void:
	records = []
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data is Dictionary and data.get("records") is Array:
		for r in data["records"]:
			if r is Dictionary and BpString.kind(r) != "":
				records.append(r)


func save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"version": 1, "records": BpString._plain(records)}))
		f.close()
	changed.emit()


## The records at a place: the top list, or a book's pages in order.
func list_at(path: Array) -> Array:
	var list := records
	for i in path:
		if i < 0 or i >= list.size() or BpString.kind(list[i]) != "blueprint_book":
			return []
		list = BpString.pages(list[i]).map(func(p: Array) -> Dictionary: return p[1])
	return list


## Writes the list back to that place (a book's pages are renumbered).
func set_list_at(path: Array, list: Array) -> void:
	if path.is_empty():
		records = list
		save()
		return
	var parent := path.slice(0, path.size() - 1)
	var siblings := list_at(parent)
	var i: int = path[-1]
	if i < 0 or i >= siblings.size():
		return
	var book: Dictionary = siblings[i]
	BpString.set_pages(book, list)
	siblings[i] = book
	set_list_at(parent, siblings)


func record_at(path: Array) -> Dictionary:
	if path.is_empty():
		return {}
	var list := list_at(path.slice(0, path.size() - 1))
	var i: int = path[-1]
	return list[i] if i >= 0 and i < list.size() else {}


## Replaces the record at a place (the editors' save).
func set_record(path: Array, record: Dictionary) -> void:
	var parent := path.slice(0, path.size() - 1)
	var list := list_at(parent)
	var i: int = path[-1]
	if i >= 0 and i < list.size():
		list[i] = record
		set_list_at(parent, list)


## Adds a record at the end of a place (or at `at`).
func add(path: Array, record: Dictionary, at := -1) -> void:
	var list := list_at(path)
	if at < 0 or at > list.size():
		list.append(record)
	else:
		list.insert(at, record)
	set_list_at(path, list)


func remove(path: Array, index: int) -> void:
	var list := list_at(path)
	if index >= 0 and index < list.size():
		list.remove_at(index)
		set_list_at(path, list)


## Drag and drop inside one place: the record moves to `to`, the others close up.
func move(path: Array, from: int, to: int) -> void:
	var list := list_at(path)
	if from < 0 or from >= list.size() or from == to:
		return
	var r = list[from]
	list.remove_at(from)
	list.insert(clampi(to, 0, list.size()), r)
	set_list_at(path, list)


## Drops a record onto a book at the same place: it becomes the book's last page (a book can't
## go into itself).
func into_book(path: Array, from: int, book: int) -> bool:
	var list := list_at(path)
	if from == book or book < 0 or book >= list.size() or BpString.kind(list[book]) != "blueprint_book":
		return false
	var r: Dictionary = list[from]
	var pages: Array = BpString.pages(list[book]).map(func(p: Array) -> Dictionary: return p[1])
	pages.append(r)
	BpString.set_pages(list[book], pages)
	list.remove_at(from)
	set_list_at(path, list)
	return true


## Moves a page out of a book to the place above it (Factorio: dragging a page out of the book).
func out_of_book(path: Array, index: int) -> void:
	if path.is_empty():
		return
	var r := record_at(path + [index])
	if r.is_empty():
		return
	remove(path, index)
	add(path.slice(0, path.size() - 1), r)


## Every record whose label (or a page's, inside books) holds the text: [[path, record], ...].
func search(text: String) -> Array:
	var out: Array = []
	_search(records, [], text.strip_edges().to_lower(), out)
	return out


func _search(list: Array, path: Array, q: String, out: Array) -> void:
	for i in list.size():
		var r: Dictionary = list[i]
		if q == "" or BpString.label(r).to_lower().contains(q):
			out.append([path + [i], r])
		if BpString.kind(r) == "blueprint_book":
			_search(BpString.pages(r).map(func(p: Array) -> Dictionary: return p[1]), path + [i], q, out)
