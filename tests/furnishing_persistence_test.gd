extends SceneTree

const SESSION := preload("res://scenes/game/game_session.tscn")
const IRON := preload("res://data/items/iron_ore.tres")
var checks := 0
var failures := 0
var directory: String
var session: Node
var writes := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func start() -> void:
	session = SESSION.instantiate()
	var service: SaveService = session.get_node("SaveService")
	service.save_directory = directory
	service.coalesce_seconds = 0.15
	service.saved.connect(func() -> void: writes += 1)
	root.add_child(session)
	await settle()


func settle() -> void:
	for frame in 90:
		await physics_frame
		if not session.transitioning and not session._leaving_furnish:
			return
	check(false, "Session settles within 90 physics frames")


func stop() -> void:
	var reference: WeakRef = weakref(session.furnishings)
	session.queue_free()
	await process_frame
	session = null
	check(reference.get_ref() == null, "Furnishing runtime destroyed before reload")


func travel(destination: StringName) -> void:
	session._request_transition(session.player, session.current_location, destination,
		&"ShipArrival" if destination == session.MARS else &"MarsReturnSpawn")
	await settle()


func write_fixture(data: Dictionary) -> void:
	var file := FileAccess.open(directory.path_join("autosave.json"), FileAccess.WRITE)
	check(file != null, "Isolated fixture opens")
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


func read_save() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("autosave.json")))


func clean() -> void:
	for name in ["autosave.json", "autosave.json.bak", "autosave.json.tmp"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(path) == OK, "Remove isolated " + name)


func entry(sequence: int, cell: Vector2i, quantity: int = 7) -> Dictionary:
	return {"persistent_id": ShipFurnishings.object_id(sequence), "object_type": "storage_crate",
		"location_id": "starter_ship", "grid_position": {"x": cell.x, "y": cell.y},
		"rotation_quarters": sequence % 4,
		"inventory": [{"slot": 3, "item_id": "iron_ore", "quantity": quantity}]}


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await process_phase(args)
		return
	directory = "user://m5a_persistence_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create isolated directory")
	await start()
	session.economy.restore(SessionEconomy.STARTING_CREDITS, 20)
	var base: Dictionary = session.save_service.capture()
	var valid := base.duplicate(true)
	valid.placed_crates = [entry(1, Vector2i(2, 3))]
	valid.next_placed_object_id = 2
	check(session.save_service.validate(valid).is_empty(), "Version 2 dynamic snapshot valid")
	for quarter in 4:
		var rotated := valid.duplicate(true)
		rotated.placed_crates[0].rotation_quarters = quarter
		check(session.save_service.validate(rotated).is_empty(), "Accept quarter-turn %d" % quarter)
		check(session.save_service.validate(JSON.parse_string(JSON.stringify(rotated))).is_empty(), "Quarter-turn survives JSON numeric parsing")
	for rotation in [-1, 4, 90, 360, 0.5, 1.5, true, false, "1", null, [], {}, INF, NAN]:
		var bad := valid.duplicate(true)
		bad.placed_crates[0].rotation_quarters = rotation
		check(not session.save_service.validate(bad).is_empty(), "Reject malformed rotation: " + str(rotation))
	for id in ["", "starter_ship_storage_01", "placed_object_1", "placed_object_000000",
		"placed_object_-00001", "placed_object_00001x", "placed_object_0000001",
		"placed_object_9007199254740991", "placed_object_99999999999999999", 1, null]:
		var bad := valid.duplicate(true)
		bad.placed_crates[0].persistent_id = id
		check(not session.save_service.validate(bad).is_empty(), "Reject malformed dynamic ID: " + str(id))
	var duplicate := valid.duplicate(true)
	duplicate.placed_crates.append(duplicate.placed_crates[0].duplicate(true))
	check(not session.save_service.validate(duplicate).is_empty(), "Duplicate dynamic ID rejected")
	for counter in [0, -1, 1.5, true, "2", null, ShipFurnishings.MAX_NEXT_ID + 1]:
		var bad := valid.duplicate(true)
		bad.next_placed_object_id = counter
		check(not session.save_service.validate(bad).is_empty(), "Invalid allocation counter rejected")
	for field in ["placed_crates", "next_placed_object_id"]:
		var bad := valid.duplicate(true)
		bad.erase(field)
		check(not session.save_service.validate(bad).is_empty(), "Required v2 field: " + field)
	for replacement in [null, {}, [null]]:
		var bad := valid.duplicate(true)
		bad.placed_crates = replacement
		check(not session.save_service.validate(bad).is_empty(), "Malformed crate collection rejected")
	for field in ["object_type", "location_id", "grid_position", "inventory"]:
		var bad := valid.duplicate(true)
		bad.placed_crates[0][field] = null
		check(not session.save_service.validate(bad).is_empty(), "Malformed crate field: " + field)
	for value in [1.5, true, "3", 2147483648]:
		var bad := valid.duplicate(true)
		bad.placed_crates[0].grid_position.x = value
		check(not session.save_service.validate(bad).is_empty(), "Noninteger/out-of-range cell rejected")
	for inventory in [[{"slot": 40, "item_id": "iron_ore", "quantity": 1}],
		[{"slot": 0, "item_id": "unknown", "quantity": 1}],
		[{"slot": 0, "item_id": "iron_ore", "quantity": 101}]]:
		var bad := valid.duplicate(true)
		bad.placed_crates[0].inventory = inventory
		check(not session.save_service.validate(bad).is_empty(), "Invalid dynamic inventory rejected")
	await stop()
	var old_m5a := valid.duplicate(true)
	old_m5a.save_version = 2
	old_m5a.placed_crates[0].erase("rotation_quarters")
	write_fixture(old_m5a)
	await start()
	check(session.save_service.writable and not session.save_service.dirty, "Development v2 missing rotation loads cleanly")
	check(session.furnishings.crates.placed_object_000001.rotation_quarters == 0 and session.furnishings.crates.placed_object_000001.node.rotation == 0, "Missing orientation defaults to zero")
	check(session.furnishings.crates.placed_object_000001.node.inventory.slots[3].quantity == 7, "Missing orientation preserves crate inventory")
	session.furnishings.rotate_crate("placed_object_000001")
	check(session.save_service.flush() and read_save().placed_crates[0].rotation_quarters == 1, "Next save explicitly writes orientation")
	await stop()
	# Old saves have no furnishing fields and keep authored storage contents.
	var legacy := base.duplicate(true)
	legacy.save_version = 1
	legacy.erase("placed_crates")
	legacy.erase("next_placed_object_id")
	legacy.storage_inventories.starter_ship_storage_01 = [{"slot": 2, "item_id": "iron_ore", "quantity": 11}]
	write_fixture(legacy)
	await start()
	check(session.furnishings.crates.is_empty() and session.furnishings.next_placed_object_id == 1, "Version 1 starts with no dynamic crates")
	check(not session.save_service.dirty, "Version 1 loading alone remains clean")
	check(session.ship.get_node("WorldObjects/Crate").inventory.slots[2].quantity == 11, "Version 1 authored storage retained")
	check(session.furnishings.create_crate(Vector2i(2, 3)) == "placed_object_000001", "Version 1 first allocation")
	check(session.save_service.dirty, "Placement dirties autosave")
	await create_timer(0.25).timeout
	check(read_save().save_version == SaveService.SAVE_VERSION and not session.save_service.dirty, "Next autosave upgrades to current version")
	var crate: ShipStorage = session.furnishings.crates.placed_object_000001.node
	crate.inventory.add_item(IRON, 13)
	check(session.save_service.dirty, "Dynamic inventory change dirties autosave")
	await create_timer(0.25).timeout
	var snapshot := read_save()
	check(snapshot.placed_crates[0].inventory[0].quantity == 13, "Dynamic inventory autosaved")
	var before := writes
	session._enter_furnish_mode()
	session.furnish_mode.select_crate(crate.persistent_id)
	session.furnish_mode.begin_move()
	session.furnish_mode.cancel_preview()
	check(not session.save_service.dirty, "Move preview cancellation remains clean")
	check(not session.furnishings.remove_crate(crate.persistent_id) and not session.save_service.dirty, "Rejected nonempty removal stays clean")
	check(not session.furnishings.move_crate(crate.persistent_id, Vector2i(4, 5)) and not session.save_service.dirty, "Invalid move stays clean")
	check(session.furnishings.move_crate(crate.persistent_id, Vector2i(3, 3)) and session.save_service.dirty, "Committed move dirties autosave")
	await create_timer(0.25).timeout
	check(writes == before + 1, "Preview/rejection/move produce only one write")
	session._exit_furnish_mode()
	await settle()
	snapshot = read_save()
	await stop()
	await start()
	check(JSON.parse_string(JSON.stringify(session.save_service.capture())) == snapshot, "Version 2 complete round trip")
	check(not session.save_service.dirty, "Unchanged version 2 resume remains clean")
	check(session.furnishings.crates.placed_object_000001.node.inventory.slots[0].quantity == 13, "Dynamic inventory restored")
	await stop()
	# Stale counter repair includes hidden recovery records and numeric ID ordering.
	var recovery := base.duplicate(true)
	recovery.next_placed_object_id = 1
	recovery.placed_crates = [entry(10, Vector2i(2, 3)), entry(9, Vector2i(2, 3)),
		entry(11, Vector2i(99, 99)), entry(12, Vector2i(4, 5)),
		entry(13, Vector2i(1, 3)), entry(14, Vector2i(2, 2))]
	recovery.player_position = {"x": 80, "y": 112}
	write_fixture(recovery)
	await start()
	check(session.furnishings.next_placed_object_id == 15 and session.save_service.dirty, "Stale counter repaired above all loaded IDs and marked dirty")
	check(session.player.position == Vector2(160, 168), "Saved Player inside restored crate falls back to spawn")
	check(not session.furnishings.crates.placed_object_000009.recovery, "Lowest numeric ID wins conflicting cell")
	for sequence in [10, 11, 12, 13, 14]:
		var record: Dictionary = session.furnishings.crates[ShipFurnishings.object_id(sequence)]
		check(record.recovery and not record.node.visible and record.node.collision_layer == 0, "Invalid saved geometry held for recovery: %d" % sequence)
		check(record.node.inventory.slots[3].quantity == 7, "Recovery inventory retained: %d" % sequence)
		check(record.rotation_quarters == sequence % 4 and is_equal_approx(record.node.rotation, (sequence % 4) * PI / 2.0), "Recovery retains orientation: %d" % sequence)
	await create_timer(0.25).timeout
	check(read_save().next_placed_object_id == 15 and read_save().placed_crates == JSON.parse_string(JSON.stringify(recovery.placed_crates)), "Repair writes corrected counter without discarding recovery records")
	await stop()
	await start()
	check(not session.save_service.dirty and session.furnishings.crates.size() == 6, "Recovery survives second reload without dirty loop")
	var recovered: ShipStorage = session.furnishings.crates.placed_object_000011.node
	check(session.furnishings.move_crate(recovered.persistent_id, Vector2i(6, 3)), "Recovered crate can be placed")
	check(session.furnishings.crates.placed_object_000011.node == recovered and recovered.inventory.slots[3].quantity == 7, "Recovery preserves identity and inventory")
	check(session.save_service.flush(), "Recovered position saved")
	await stop()
	await start()
	check(not session.furnishings.crates.placed_object_000011.recovery and session.furnishings.crates.placed_object_000011.cell == Vector2i(6, 3), "Recovered position survives reload")
	check(session.furnishings.crates.placed_object_000011.rotation_quarters == 3, "Recovered orientation survives reload")
	await stop()
	# Malformed IDs fail atomically and protect original bytes.
	clean()
	write_fixture(duplicate)
	var original := FileAccess.get_file_as_string(directory.path_join("autosave.json"))
	await start()
	check(not session.save_service.writable and session.furnishings.crates.is_empty(), "Duplicate IDs never partially load")
	check(not session.save_service.flush(true) and FileAccess.get_file_as_string(directory.path_join("autosave.json")) == original, "Malformed ID save protected on close")
	await stop()
	clean()
	var malformed_rotation := valid.duplicate(true)
	malformed_rotation.placed_crates[0].rotation_quarters = 1.5
	write_fixture(malformed_rotation)
	original = FileAccess.get_file_as_string(directory.path_join("autosave.json"))
	await start()
	check(not session.save_service.writable and session.furnishings.crates.is_empty(), "Malformed rotation rejects whole save without partial application")
	check(not session.save_service.flush(true) and FileAccess.get_file_as_string(directory.path_join("autosave.json")) == original, "Malformed rotation save remains protected")
	await stop()
	clean()
	# Each phase is a fresh OS process; writers invoke the actual desktop-close hook.
	for phase in ["ship_writer", "ship_reader", "mars_reader", "retirement_reader"]:
		var output: Array = []
		var result := OS.execute(OS.get_executable_path(), ["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--script", "res://tests/furnishing_persistence_test.gd",
			"--", phase, directory], output, true)
		check(result == 0, "Separate process " + phase)
		for line in output:
			print(line)
	clean()
	check(DirAccess.remove_absolute(directory) == OK, "Remove isolated directory")
	print("M5A persistence: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func process_phase(args: PackedStringArray) -> void:
	if args.size() != 2 or not args[1].begins_with("user://m5a_persistence_test_") or ".." in args[1]:
		quit(1)
		return
	directory = args[1]
	await start()
	var furnishings: ShipFurnishings = session.furnishings
	if args[0] == "ship_writer":
		session.economy.restore(SessionEconomy.STARTING_CREDITS, 20)
		check(furnishings.create_crate(Vector2i(2, 3)) == "placed_object_000001", "First process allocation")
		check(furnishings.rotate_crate("placed_object_000001"), "Rotate before desktop close")
		furnishings.crates.placed_object_000001.node.inventory.add_item(IRON, 17)
		check(furnishings.create_crate(Vector2i(6, 3)) == "placed_object_000002", "Second process allocation")
		check(furnishings.remove_crate("placed_object_000002"), "Retire highest allocated ID")
		session.ship.get_node("WorldObjects/Crate").inventory.add_item(IRON, 4)
		session.player.position = Vector2(160, 140)
		check(session.save_service.dirty, "Close with pending furnishing changes")
	elif args[0] == "ship_reader":
		check(furnishings.crates.placed_object_000001.rotation_quarters == 1 and is_equal_approx(furnishings.crates.placed_object_000001.node.rotation, PI / 2.0), "Rotation restored in fresh ship process")
		check(session.current_location == session.SHIP and session.player.position == Vector2(160, 140), "Fresh process restores ship and Player position")
		check(furnishings.crates.size() == 1 and furnishings.crates.placed_object_000001.node.inventory.slots[0].quantity == 17, "Desktop close persists crate inventory")
		check(session.ship.get_node("WorldObjects/Crate").inventory.slots[0].quantity == 4, "Authored storage remains independent across restart")
		check(furnishings.next_placed_object_id == 3 and furnishings.create_crate(Vector2i(6, 3)) == "placed_object_000003", "Retired highest ID is not reused after restart")
		await travel(session.MARS)
		furnishings.crates.placed_object_000001.node.inventory.add_item(IRON, 2)
	elif args[0] == "mars_reader":
		check(furnishings.crates.placed_object_000001.rotation_quarters == 1, "Rotation restored in detached ship")
		check(session.current_location == session.MARS and not session.ship.is_inside_tree(), "Fresh process resumes detached ship on Mars")
		check(furnishings.crates.placed_object_000001.node.inventory.slots[0].quantity == 19, "Close on Mars persists pending dynamic inventory")
		check(furnishings.pending_validation, "Detached ship validation deferred")
		var crate: ShipStorage = furnishings.crates.placed_object_000001.node
		await travel(session.SHIP)
		check(not furnishings.pending_validation and not furnishings.crates.placed_object_000001.recovery, "First ship activation restores crate")
		check(furnishings.crates.placed_object_000001.node == crate and crate.inventory.slots[0].quantity == 19, "Activation preserves restored node and contents")
		check(is_equal_approx(crate.rotation, PI / 2.0), "Ship to Mars to Ship preserves runtime rotation")
		check(furnishings.remove_crate("placed_object_000003") and session.save_service.dirty, "Empty removal dirties after resumed travel")
	else:
		check(furnishings.next_placed_object_id == 4 and not furnishings.crates.has("placed_object_000003"), "Close persists removal and monotonic counter")
		check(furnishings.create_crate(Vector2i(6, 3)) == "placed_object_000004", "Allocation remains monotonic across multiple processes")
	print("M5A process %s: %d checks, %d failures" % [args[0], checks, failures])
	if failures:
		quit(1)
	else:
		session.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
