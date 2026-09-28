class_name SaveService
extends Node

signal status_changed(message: String)
signal saved

const SAVE_VERSION := 6
const ITEMS := [
	preload("res://data/items/iron_plate.tres"),
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
# Optional version-1 field. GameSession validates geometry and supplies local coordinates.
var player_position: Variant = null
var position_provider: Callable
var _new_game: bool = false
var _player_inventory: InventoryData
var _storages: Dictionary = {}
var _items: Dictionary = {}
var _pickups: Dictionary = {}
var _pickup_limits: Dictionary = {}
var _pickup_remaining: Dictionary = {}
var _furnishings: ShipFurnishings
var _economy: SessionEconomy
var _counter_repaired := false
var _mining_nodes: Dictionary = {}
var _mining_overflow: MiningOverflow
var _processor: ShipProcessor
var _processor_completed_on_load := false


func bind_processor(processor: ShipProcessor) -> void:
	assert(processor.persistent_id == ShipProcessor.PERSISTENT_ID)
	_processor = processor
	processor.changed.connect(mark_dirty)

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


func bind_furnishings(furnishings: ShipFurnishings) -> void:
	_furnishings = furnishings
	furnishings.changed.connect(mark_dirty)


func bind_economy(economy: SessionEconomy) -> void:
	_economy = economy
	economy.changed.connect(mark_dirty)


func bind_mining(nodes: Array[MiningNode]) -> void:
	for node in nodes:
		var id := String(node.persistent_id)
		assert(not id.is_empty() and not _mining_nodes.has(id), "Invalid mining node ID")
		_mining_nodes[id] = node
		node.changed.connect(mark_dirty)


func bind_mining_overflow(overflow: MiningOverflow) -> void:
	_mining_overflow = overflow
	overflow.changed.connect(mark_dirty)


func _capture_mining() -> Dictionary:
	var state := {}
	for id: String in _mining_nodes:
		state[id] = _mining_nodes[id].replenishment_deadline
	return state


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
		if _new_game or _counter_repaired or _processor_completed_on_load:
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
	var snapshot := {
		"save_version": SAVE_VERSION,
		"processors": {ShipProcessor.PERSISTENT_ID: _processor.capture() if _processor != null else ShipProcessor.idle_snapshot()},
		"mining_nodes": _capture_mining(),
		"mining_overflow": _mining_overflow.capture() if _mining_overflow != null else {"next_id": 1, "pickups": []},
		"credits": _economy.credits,
		"owned_furnishings": {"storage_crate": _economy.owned_storage_crates()},
		"current_location": current_location,
		"player_inventory": _capture_inventory(_player_inventory),
		"storage_inventories": storage_data,
		"ship_pickups": _pickup_remaining.duplicate(),
		"next_placed_object_id": _furnishings.next_placed_object_id if _furnishings != null else 1,
		"placed_crates": _capture_crates(),
	}
	if position_provider.is_valid():
		snapshot["player_position"] = position_provider.call()
	return snapshot


func _capture_crates() -> Array:
	var entries: Array = []
	if _furnishings == null:
		return entries
	for id: String in _furnishings.crates:
		var record: Dictionary = _furnishings.crates[id]
		entries.append({
			"persistent_id": id,
			"object_type": "storage_crate",
			"location_id": "starter_ship",
			"grid_position": {"x": record.cell.x, "y": record.cell.y},
			"rotation_quarters": record.rotation_quarters,
			"inventory": _capture_inventory(record.node.inventory),
		})
	return entries


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
	if int(data.save_version) not in [1, 2, 3, 4, 5, SAVE_VERSION]:
		return "Unsupported save version"
	if not data.get("current_location") is String or not LOCATIONS.has(data.current_location):
		return "Unknown location"
	if int(data.save_version) >= 6:
		var processor_error := _validate_processor(data.get("processors"))
		if not processor_error.is_empty():
			return processor_error
	if int(data.save_version) >= 4:
		var mining: Variant = data.get("mining_nodes")
		if not mining is Dictionary:
			return "Invalid mining identities"
		for id: Variant in mining:
			if not id is String:
				return "Invalid mining identity"
			# V4 IDs described the mistakenly selected orange scenery.
			var known: bool = id in ["mars_iron_deposit_01", "mars_iron_deposit_02", "mars_iron_deposit_03", "mars_iron_deposit_04", "mars_iron_deposit_05"] if int(data.save_version) == 4 else _mining_nodes.has(id)
			if not known:
				return "Invalid mining identity"
			var deadline: Variant = mining[id]
			if not (deadline is int or deadline is float):
				return "Invalid mining deadline"
			if not is_finite(float(deadline)) or deadline < 0.0 or deadline > 253402300799.0:
				return "Invalid mining deadline"
	if int(data.save_version) >= 5:
		var overflow_error := MiningOverflow.validate(data.get("mining_overflow"))
		if not overflow_error.is_empty():
			return overflow_error
	var economy_error := _validate_economy(data)
	if not economy_error.is_empty():
		return economy_error
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
	if int(data.save_version) >= 2:
		return _validate_crates(data)
	return ""


func _validate_processor(entries: Variant) -> String:
	if not entries is Dictionary or entries.size() != 1 or not entries.has(ShipProcessor.PERSISTENT_ID):
		return "Invalid processor identity"
	var entry: Variant = entries[ShipProcessor.PERSISTENT_ID]
	if not entry is Dictionary or entry.size() != 3:
		return "Invalid processor record"
	var remaining: Variant = entry.get("units_remaining")
	var output: Variant = entry.get("held_output")
	if not _integer(remaining, 0, ShipProcessor.MAX_BATCH_UNITS):
		return "Invalid processor remaining units"
	if not _integer(output, 0, ShipProcessor.MAX_BATCH_UNITS * ShipProcessor.OUTPUT_QUANTITY):
		return "Invalid processor output"
	if remaining * ShipProcessor.OUTPUT_QUANTITY + output > ShipProcessor.MAX_BATCH_UNITS * ShipProcessor.OUTPUT_QUANTITY:
		return "Invalid processor batch capacity"
	var deadline: Variant = entry.get("next_unit_deadline")
	if not (deadline is int or deadline is float) or not is_finite(float(deadline)) or deadline < 0.0 or deadline > 253402300799.0:
		return "Invalid processor deadline"
	if (remaining > 0 and deadline == 0) or (remaining == 0 and deadline != 0):
		return "Invalid processor timing state"
	return ""


func _validate_economy(data: Dictionary) -> String:
	if int(data.save_version) >= 3 or data.has("credits"):
		if not _integer(data.get("credits"), 0, SessionEconomy.MAX_BALANCE):
			return "Invalid Credits"
	if int(data.save_version) >= 3 or data.has("owned_furnishings"):
		var owned: Variant = data.get("owned_furnishings")
		if not owned is Dictionary or owned.size() != 1 or not _integer(owned.get("storage_crate"), 0, SessionEconomy.MAX_BALANCE):
			return "Invalid owned furnishings"
	return ""


func _validate_crates(data: Dictionary) -> String:
	if not _integer(data.get("next_placed_object_id"), 1, ShipFurnishings.MAX_NEXT_ID):
		return "Invalid next placed object ID"
	var entries: Variant = data.get("placed_crates")
	if not entries is Array:
		return "Invalid placed crates"
	var seen := {}
	var inventory := InventoryData.new(ShipFurnishings.CRATE_CAPACITY)
	for entry: Variant in entries:
		if not entry is Dictionary:
			return "Invalid placed crate record"
		var id: Variant = entry.get("persistent_id")
		if not id is String or ShipFurnishings.id_sequence(id) == 0 or seen.has(id):
			return "Invalid or duplicate placed object ID"
		seen[id] = true
		if entry.get("object_type") != "storage_crate" or entry.get("location_id") != "starter_ship":
			return "Unsupported placed crate type or location"
		# Pre-release M5A records without orientation retain their original zero rotation.
		if not _integer(entry.get("rotation_quarters", 0), 0, 3):
			return "Invalid crate rotation"
		var cell: Variant = entry.get("grid_position")
		if not cell is Dictionary:
			return "Invalid crate grid position"
		for axis in ["x", "y"]:
			if not _integer(cell.get(axis), -2147483648, 2147483647):
				return "Invalid crate grid position"
		var error := _validate_inventory(entry.get("inventory"), inventory)
		if not error.is_empty():
			return "Placed crate %s: %s" % [id, error]
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
	if _furnishings != null and int(data.save_version) >= 2:
		var saved_next := int(data.next_placed_object_id)
		var effective_next := saved_next
		for entry: Dictionary in data.placed_crates:
			var crate := _furnishings.add_restored_crate(entry.persistent_id, Vector2i(int(entry.grid_position.x), int(entry.grid_position.y)), int(entry.get("rotation_quarters", 0)))
			_restore_inventory(crate.inventory, entry.inventory)
			effective_next = maxi(effective_next, ShipFurnishings.id_sequence(entry.persistent_id) + 1)
		_furnishings.next_placed_object_id = effective_next
		_furnishings.pending_validation = true
		_counter_repaired = effective_next != saved_next
	for id: String in _mining_nodes:
		_mining_nodes[id].restore(float(data.mining_nodes.get(id, 0.0)) if int(data.save_version) >= 5 else 0.0)
	if _mining_overflow != null:
		_mining_overflow.restore(data.mining_overflow if int(data.save_version) >= 5 else {"next_id": 1, "pickups": []})
	if _processor != null:
		_processor_completed_on_load = _processor.restore(data.processors[ShipProcessor.PERSISTENT_ID] if int(data.save_version) >= 6 else ShipProcessor.idle_snapshot())
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
	_economy.restore(int(data.get("credits", SessionEconomy.STARTING_CREDITS)), int(data.get("owned_furnishings", {"storage_crate": 0}).storage_crate))
	current_location = data.current_location
	player_position = data.get("player_position")
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
