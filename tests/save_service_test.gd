extends SceneTree

var checks := 0
var failures := 0
var service: SaveService
var inventory: InventoryData
var storage: InventoryData
var directory: String
var iron := preload("res://data/items/iron_ore.tres")


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func make_service() -> void:
	service = SaveService.new()
	var timer := Timer.new()
	timer.name = "AutosaveTimer"
	timer.one_shot = true
	service.add_child(timer)
	service.save_directory = directory
	service.retry_seconds = 0.1
	root.add_child(service)
	inventory = InventoryData.new(20)
	storage = InventoryData.new(40)
	service.bind_state(inventory, {"starter_ship_storage_01": storage}, [])
	service.bind_economy(SessionEconomy.new())


func write_text(name: String, content: String) -> void:
	var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
	check(file != null, "Test fixture file opens")
	if file != null:
		file.store_string(content)
		file.close()


func clean_files() -> void:
	for name in ["autosave.json", "autosave.json.tmp", "autosave.json.bak"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			check(DirAccess.remove_absolute(path) == OK, "Remove test artifact " + name)


func run() -> void:
	directory = "user://m46_service_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create isolated test directory")
	make_service()
	check(service.load_game() == "starter_ship" and service.writable, "No-save initialization")
	service.complete_location("starter_ship", true)
	inventory.add_item(iron, 12)
	var valid := service.capture()
	check(service.validate(valid).is_empty(), "Valid snapshot accepted")
	for field in ["save_version", "current_location", "player_inventory", "storage_inventories", "ship_pickups"]:
		var missing := valid.duplicate(true)
		missing.erase(field)
		check(not service.validate(missing).is_empty(), "Missing field rejected: " + field)
	for value in [-1, 0, 1.5, true, "1", INF]:
		var malformed := valid.duplicate(true)
		malformed.save_version = value
		check(not service.validate(malformed).is_empty(), "Invalid version rejected")
	for entry in [
		{"slot": -1, "item_id": "iron_ore", "quantity": 1},
		{"slot": 20, "item_id": "iron_ore", "quantity": 1},
		{"slot": 0.5, "item_id": "iron_ore", "quantity": 1},
		{"slot": 0, "item_id": "unknown", "quantity": 1},
		{"slot": 0, "item_id": "iron_ore", "quantity": 0},
		{"slot": 0, "item_id": "iron_ore", "quantity": 101},
		{"slot": 0, "item_id": "iron_ore", "quantity": 1.5},
		{"slot": 0, "item_id": "iron_ore", "quantity": true},
	]:
		var malformed := valid.duplicate(true)
		malformed.player_inventory = [entry]
		check(not service.validate(malformed).is_empty(), "Bad inventory entry rejected")
	var duplicate := valid.duplicate(true)
	duplicate.player_inventory.append(duplicate.player_inventory[0].duplicate())
	check(not service.validate(duplicate).is_empty(), "Duplicate slot rejected")
	var wrong_storage := valid.duplicate(true)
	wrong_storage.storage_inventories = {"different_crate": []}
	check(not service.validate(wrong_storage).is_empty(), "Unknown storage identity rejected")
	var wrong_location := valid.duplicate(true)
	wrong_location.current_location = "unknown"
	check(not service.validate(wrong_location).is_empty(), "Unknown location rejected")
	check(service.flush(), "Initial write succeeds")
	var first_bytes := FileAccess.get_file_as_string(directory.path_join("autosave.json"))
	inventory.add_item(iron, 8)
	check(service.flush(), "Second write succeeds")
	check(FileAccess.get_file_as_string(directory.path_join("autosave.json.bak")) == first_bytes, "Backup is previous known-good save")
	var good_bytes := FileAccess.get_file_as_string(directory.path_join("autosave.json"))
	service.free()
	write_text("autosave.json.tmp", "interrupted next write")
	make_service()
	var inventory_ref := inventory
	var storage_ref := storage
	var slot_ref := inventory.slots[0]
	service.load_game()
	check(inventory == inventory_ref and storage == storage_ref and inventory.slots[0] == slot_ref, "Restore preserves inventory and slot identity")
	check(inventory.slots[0].quantity == 20 and inventory.slots[0].item == iron, "Restore resolves canonical item")
	check(FileAccess.get_file_as_string(directory.path_join("autosave.json.tmp")) == "interrupted next write", "Valid primary wins over partial temporary file without rewriting it")
	service.complete_location("starter_ship", true)
	check(not service.dirty, "Valid unchanged resume is clean")
	check(DirAccess.remove_absolute(directory.path_join("autosave.json.tmp")) == OK, "Remove stale test temporary")
	# A directory at the temporary file path causes a real open failure.
	check(DirAccess.make_dir_absolute(directory.path_join("autosave.json.tmp")) == OK, "Create write blocker")
	inventory.add_item(iron, 1)
	check(not service.flush() and service.dirty and service.writable, "Write failure retains dirty state for retry")
	check(not service.status_message.is_empty(), "Write failure reported")
	check(FileAccess.get_file_as_string(directory.path_join("autosave.json")) == good_bytes, "Failed write preserves primary")
	check(DirAccess.remove_absolute(directory.path_join("autosave.json.tmp")) == OK, "Remove blocker")
	await create_timer(0.2).timeout
	check(not service.dirty and service.status_message.is_empty() and read_quantity() == 21, "Automatic retry succeeds and clears error")
	# Corruption discovered while running must also stop writes.
	write_text("autosave.json", "broken during play")
	inventory.add_item(iron, 1)
	check(not service.flush() and service.dirty and not service.writable, "Externally corrupted primary protected")
	check(FileAccess.get_file_as_string(directory.path_join("autosave.json")) == "broken during play", "Corrupt bytes unchanged")
	service.free()
	# Fresh services exercise interrupted-write and corrupt-primary recovery.
	for primary in ["broken", "missing", "unsupported"]:
		clean_files()
		write_text("autosave.json.bak", first_bytes)
		write_text("autosave.json.tmp", "partial temporary write")
		if primary == "broken":
			write_text("autosave.json", "broken")
		elif primary == "unsupported":
			var unsupported := valid.duplicate(true)
			unsupported.save_version = 99
			write_text("autosave.json", JSON.stringify(unsupported))
		make_service()
		service.load_game()
		check(not service.writable, "Recovery/unsupported session cannot overwrite files")
		check(inventory.slots[0].quantity == (0 if primary == "unsupported" else 12), "Backup restored except for unsupported primary")
		service.complete_location("starter_ship", true)
		inventory.add_item(iron, 1)
		check(not service.flush(true), "Final save respects recovery protection")
		check(FileAccess.get_file_as_string(directory.path_join("autosave.json.bak")) == first_bytes, "Recovery preserves backup")
		check(FileAccess.get_file_as_string(directory.path_join("autosave.json.tmp")) == "partial temporary write", "Recovery preserves temporary evidence")
		service.free()
	clean_files()
	write_text("autosave.json.tmp", "incomplete first save")
	make_service()
	service.load_game()
	check(not service.writable, "Temporary-only startup is protected, not new writable game")
	service.free()
	clean_files()
	# Failed backup rotation leaves the current save and verified temporary intact.
	write_text("autosave.json", good_bytes)
	check(DirAccess.make_dir_absolute(directory.path_join("autosave.json.bak")) == OK, "Create rotation blocker")
	make_service()
	service.load_game()
	service.complete_location("starter_ship", true)
	inventory.add_item(iron, 1)
	check(not service.flush() and service.dirty, "Rotation failure retains dirty state")
	check(FileAccess.get_file_as_string(directory.path_join("autosave.json")) == good_bytes, "Rotation failure preserves primary")
	service.free()
	clean_files()
	# A directory at the destination exercises a failure after temporary verification.
	check(DirAccess.make_dir_absolute(directory.path_join("autosave.json")) == OK, "Create promotion blocker")
	make_service()
	service.load_game()
	service.complete_location("starter_ship", true)
	inventory.add_item(iron, 3)
	check(not service.flush() and service.dirty, "Promotion failure retains dirty state")
	var temporary: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("autosave.json.tmp")))
	check(service.validate(temporary).is_empty(), "Failed promotion retains validated temporary snapshot")
	service.free()
	clean_files()
	check(DirAccess.remove_absolute(directory) == OK, "Remove isolated test directory")
	print("M4.6 save service: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func read_quantity() -> int:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("autosave.json")))
	return int(data.player_inventory[0].quantity)
