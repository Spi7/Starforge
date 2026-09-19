class_name SaveService
extends Node

signal status_changed(message: String)
signal saved

const SAVE_VERSION := 1
const ITEMS := [
	preload("res://data/items/iron_ore.tres"),
	preload("res://data/items/copper_ore.tres"),
	preload("res://data/items/nutrient_pack.tres"),
	preload("res://data/items/basic_mining_tool.tres"),
]
const LOCATIONS := ["starter_ship", "mars_landing_zone"]

@export var save_directory: String = "user://"
@export_range(0.05, 60.0) var coalesce_seconds: float = 2.0
@export_range(0.1, 120.0) var retry_seconds: float = 10.0

var enabled: bool = true
var writable: bool = false
var dirty: bool = false
var startup_complete: bool = false
var safe_to_save: bool = false
var current_location: String = "starter_ship"
var status_message: String = ""
var load_status: String = ""
var _new_game: bool = false
var _player_inventory: InventoryData
var _storages: Dictionary = {}
var _items: Dictionary = {}
var _pickups: Dictionary = {}
var _pickup_limits: Dictionary = {}
var _pickup_remaining: Dictionary = {}

@onready var timer: Timer = $AutosaveTimer


func _ready() -> void:
	timer.timeout.connect(flush)


func bind_state(inventory: InventoryData, storages: Dictionary, pickups: Array[WorldPickup]) -> void:
	_player_inventory = inventory
	_storages = storages.duplicate()
	for item: ItemDefinition in ITEMS:
		assert(item.id != &"" and not _items.has(String(item.id)), "Invalid canonical item IDs")
		_items[String(item.id)] = item
	for pickup in pickups:
		var id := String(pickup.persistent_id)
		assert(not id.is_empty() and not _pickups.has(id), "Invalid authored pickup IDs")
		_pickups[id] = pickup
		_pickup_limits[id] = pickup.quantity
		_pickup_remaining[id] = pickup.quantity
		pickup.quantity_changed.connect(_pickup_changed.bind(id))
	_player_inventory.changed.connect(mark_dirty)
	for storage: InventoryData in _storages.values():
		storage.changed.connect(mark_dirty)


func load_game() -> String:
	if not enabled:
		load_status = "disabled"
		return current_location
	if not save_directory.begins_with("user://") or ".." in save_directory:
		_protect("Save directory must remain under user://.")
		return current_location
	var primary := _read_file(_path("autosave.json"))
	load_status = primary.status
	if primary.status == "valid":
		_apply(primary.data)
		writable = true
	elif primary.status == "missing" and not FileAccess.file_exists(_path("autosave.json.bak")) and not FileAccess.file_exists(_path("autosave.json.tmp")):
		writable = true
		_new_game = true
	elif primary.status == "unsupported":
		_protect("Unsupported save version. Existing files protected; progress will NOT be saved.")
	else:
		var backup := _read_file(_path("autosave.json.bak"))
		if backup.status == "valid":
			_apply(backup.data)
			load_status = "recovered"
			_protect("Recovered previous backup. Existing files protected; progress will NOT be saved.")
		else:
			_protect("Cannot restore autosave (%s). Existing files protected; progress will NOT be saved." % primary.error)
	return current_location


func complete_location(location: String, initial: bool) -> void:
	current_location = location
	startup_complete = true
	safe_to_save = true
	if initial:
		if _new_game:
			mark_dirty()
	else:
		mark_dirty()
		flush()


func mark_dirty() -> void:
	if not enabled or not writable or not startup_complete:
		return
	dirty = true
	# A bounded coalescing window: continuous activity cannot postpone saving forever.
	if timer.is_stopped():
		timer.start(coalesce_seconds)


func _pickup_changed(remaining: int, id: String) -> void:
	_pickup_remaining[id] = remaining
	mark_dirty()


func capture() -> Dictionary:
	var storage_data := {}
	for id: String in _storages:
		storage_data[id] = _capture_inventory(_storages[id])
	return {
		"save_version": SAVE_VERSION,
		"current_location": current_location,
		"player_inventory": _capture_inventory(_player_inventory),
		"storage_inventories": storage_data,
		"ship_pickups": _pickup_remaining.duplicate(),
	}


func _capture_inventory(inventory: InventoryData) -> Array:
	var entries: Array = []
	for index in inventory.slots.size():
		var slot := inventory.slots[index]
		if slot.item != null:
			entries.append({"slot": index, "item_id": String(slot.item.id), "quantity": slot.quantity})
	return entries


func validate(data: Variant) -> String:
	if not data is Dictionary:
		return "Save must be an object"
	if not _integer(data.get("save_version"), 1, 2147483647):
		return "Invalid save version"
	if int(data.save_version) != SAVE_VERSION:
		return "Unsupported save version"
	if not data.get("current_location") is String or not LOCATIONS.has(data.current_location):
		return "Unknown location"
	var error := _validate_inventory(data.get("player_inventory"), _player_inventory)
	if not error.is_empty():
		return "Player: " + error
	var storage_data: Variant = data.get("storage_inventories")
	if not storage_data is Dictionary or storage_data.size() != _storages.size():
		return "Invalid storage identities"
	for id: String in _storages:
		error = _validate_inventory(storage_data.get(id), _storages[id])
		if not error.is_empty():
			return "Storage %s: %s" % [id, error]
	var pickup_data: Variant = data.get("ship_pickups")
	if not pickup_data is Dictionary or pickup_data.size() != _pickup_limits.size():
		return "Invalid pickup identities"
	for id: String in _pickup_limits:
		if not _integer(pickup_data.get(id), 0, _pickup_limits[id]):
			return "Invalid pickup quantity: " + id
	return ""


func _validate_inventory(entries: Variant, inventory: InventoryData) -> String:
	if not entries is Array or entries.size() > inventory.slots.size():
		return "Invalid slot list"
	var seen := {}
	for entry: Variant in entries:
		if not entry is Dictionary or not _integer(entry.get("slot"), 0, inventory.slots.size() - 1):
			return "Invalid slot index"
		var index := int(entry.slot)
		if seen.has(index):
			return "Duplicate slot"
		seen[index] = true
		var id: Variant = entry.get("item_id")
		if not id is String or not _items.has(id):
			return "Unknown item ID"
		if not _integer(entry.get("quantity"), 1, _items[id].max_stack):
			return "Invalid stack quantity"
	return ""


func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and value >= minimum and value <= maximum and floor(float(value)) == value


func _apply(data: Dictionary) -> void:
	# All validation has completed. Preserve InventoryData and InventorySlot identity.
	_restore_inventory(_player_inventory, data.player_inventory)
	for id: String in _storages:
		_restore_inventory(_storages[id], data.storage_inventories[id])
	for id: String in _pickups:
		var pickup: WorldPickup = _pickups[id]
		var remaining := int(data.ship_pickups[id])
		_pickup_remaining[id] = remaining
		pickup.quantity = remaining
		if remaining == 0:
			# Startup restoration runs before the ship enters the tree.
			pickup.free()
	_pickups.clear()
	current_location = data.current_location
	_player_inventory.changed.emit()
	for storage: InventoryData in _storages.values():
		storage.changed.emit()


func _restore_inventory(inventory: InventoryData, entries: Array) -> void:
	for slot in inventory.slots:
		slot.item = null
		slot.quantity = 0
	for entry: Dictionary in entries:
		var slot := inventory.slots[int(entry.slot)]
		slot.item = _items[entry.item_id]
		slot.quantity = int(entry.quantity)


func flush(on_close: bool = false) -> bool:
	if not enabled or not writable or not startup_complete or not dirty:
		return false
	if not safe_to_save and not on_close:
		return false
	timer.stop()
	var snapshot := capture()
	var error := validate(snapshot)
	if error.is_empty():
		error = _write(snapshot)
	if not error.is_empty():
		_report("Autosave failed; progress is not yet saved. " + error)
		if writable:
			timer.start(retry_seconds)
		return false
	dirty = false
	_report("")
	saved.emit()
	return true


func _write(snapshot: Dictionary) -> String:
	var error := DirAccess.make_dir_recursive_absolute(save_directory)
	if error != OK:
		return "Cannot create save directory: " + error_string(error)
	var primary_path := _path("autosave.json")
	var temporary_path := _path("autosave.json.tmp")
	# Check before touching even temporary data if the primary became invalid.
	var previous := _read_file(primary_path)
	if previous.status != "missing" and previous.status != "valid":
		writable = false
		return "Existing autosave is invalid; files protected and saving disabled."
	var text := JSON.stringify(snapshot, "\t")
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return "Cannot open temporary save: " + error_string(FileAccess.get_open_error())
	file.store_string(text)
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return "Temporary write failed: " + error_string(error)
	var verified := _read_file(temporary_path)
	if verified.status != "valid" or FileAccess.get_file_as_string(temporary_path) != text:
		return "Temporary save verification failed"
	var directory := DirAccess.open(save_directory)
	if directory == null:
		return "Cannot open save directory"
	if previous.status == "valid":
		error = directory.rename("autosave.json", "autosave.json.bak")
		if error != OK:
			return "Backup rotation failed: " + error_string(error)
	error = directory.rename("autosave.json.tmp", "autosave.json")
	if error != OK:
		return "Save promotion failed: " + error_string(error)
	return ""


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "missing", "error": "file missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"status": "invalid", "error": "file unreadable"}
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return {"status": "invalid", "error": "read failed"}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"status": "invalid", "error": "JSON line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	var error := validate(json.data)
	if not error.is_empty():
		return {"status": "unsupported" if error == "Unsupported save version" else "invalid", "error": error}
	return {"status": "valid", "error": "", "data": json.data}


func _path(filename: String) -> String:
	return save_directory.path_join(filename)


func _protect(message: String) -> void:
	writable = false
	_report(message)


func _report(message: String) -> void:
	if status_message == message:
		return
	status_message = message
	if not message.is_empty():
		push_warning(message)
	status_changed.emit(message)
