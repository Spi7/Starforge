extends "res://tests/mining_test.gd"

var writes := 0
var changes := 0


func processor() -> ShipProcessor:
	return session.processor


func clean_files() -> void:
	for filename in ["autosave.json", "autosave.json.bak", "autosave.json.tmp"]:
		var path := directory.path_join(filename)
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(path) == OK, "Remove isolated fixture")


func write_fixture(data: Dictionary) -> void:
	var file := FileAccess.open(directory.path_join("autosave.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func test_batch_model() -> void:
	var p := ShipProcessor.new()
	var inventory := InventoryData.new(3)
	check(IRON.max_stack == 100, "Canonical ore stack is 100")
	check(p.INPUT == IRON and p.INPUT_QUANTITY == 10 and p.OUTPUT_QUANTITY == 1, "Exact recipe")
	check(p.OUTPUT.id == &"iron_plate" and p.OUTPUT.category == ItemDefinition.Category.RESOURCE and p.OUTPUT.max_stack == 99, "Canonical plate unchanged")
	check(p.DURATION_SECONDS == 30.0 and p.MAX_INPUT_ORE == 100 and p.MAX_BATCH_UNITS == 10, "Independent capacity and duration")
	for pair in [[7, 0], [36, 3], [100, 10], [180, 10]]:
		inventory.add_item(IRON, pair[0])
		check(p.max_affordable_units(inventory) == pair[1], "Affordable batch for %d ore" % pair[0])
		inventory.remove_item(IRON, pair[0])
	inventory.add_item(IRON, 39)
	for quantity in [-1, 0, 4, 11]:
		check(not p.start_job(inventory, quantity) and inventory.count_item(IRON) == 39 and p.is_idle(), "Rejected batch changes nothing")
	# Consume across deliberately separate stacks, publishing only the final batch.
	inventory.slots[0].quantity = 21
	inventory.slots[1].item = IRON
	inventory.slots[1].quantity = 26
	inventory.changed.connect(func() -> void:
		check(p.units_remaining == 4 and inventory.count_item(IRON) == 7, "Start observer sees coherent four-unit batch")
		check(not p.start_job(inventory, 1), "Reentrant start rejected")
	, CONNECT_ONE_SHOT)
	var now := Time.get_unix_time_from_system()
	check(p.start_job(inventory, 4), "Four-unit batch starts")
	var first_deadline := p.next_unit_deadline
	check(first_deadline >= now + 30.0 and first_deadline < now + 30.5, "Deadline uses real system time")
	check(inventory.count_item(IRON) == 7 and inventory.slots[0].item == null, "Exactly forty ore removed across stacks")
	check(not p.start_job(inventory, 1) and inventory.count_item(IRON) == 7, "Repeated start cannot consume again")
	check(not p.refresh_completion(first_deadline - 0.001) and p.held_output == 0, "Before thirty seconds no output")
	check(not p.refresh_completion(first_deadline - 1000), "Backwards clock does not produce")
	for completed in range(1, 5):
		check(p.refresh_completion(first_deadline + (completed - 1) * 30.0), "Sequential boundary advances")
		check(p.held_output == completed and p.units_remaining == 4 - completed, "One plate per thirty seconds")
		check(not p.refresh_completion(first_deadline + (completed - 1) * 30.0), "Repeated refresh is idempotent")
	check(p.next_unit_deadline == 0 and not p.is_idle(), "Finished batch holds output and clears deadline")
	check(not p.start_job(inventory, 1), "Uncollected batch cannot be replaced")
	check(p.collect(inventory) == 4 and p.is_idle(), "All output collected returns idle")
	check(p.collect(inventory) == 0 and inventory.count_item(p.OUTPUT) == 4, "Repeated collection does not duplicate")
	inventory.add_item(IRON, 100)
	check(p.start_job(inventory, 10) and p.units_remaining == 10, "Maximum batch consumes one hundred ore")
	check(inventory.count_item(IRON) == 7, "Maximum batch input atomic")
	p.refresh_completion(p.next_unit_deadline + 10000)
	check(p.held_output == 10 and p.units_remaining == 0, "Long absence bounded by remaining batch")
	p.collect(inventory)
	inventory.add_item(IRON, 10)
	check(p.start_job(inventory, 1), "Minimum batch of one allowed")
	p.free()


func run() -> void:
	test_batch_model()
	directory = "user://m5d_processing_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	await start_session()
	var p := processor()
	var ui: ProcessingUI = session.processing_ui
	check(p.persistent_id == ShipProcessor.PERSISTENT_ID and p.is_idle(), "Authored station starts empty")
	check(player.inventory.slots.size() == 20, "Player slot count unchanged")
	var storage: ShipStorage = session.ship.get_node("WorldObjects/Crate")
	storage.inventory.add_item(IRON, 100)
	check(not p.start_job(player.inventory), "No automatic storage input")
	player.inventory.add_item(IRON, 7)
	player.position = p.position + Vector2(0, 36)
	await physics_frame
	await physics_frame
	check(player.nearest_interactable() == p.get_node("Interactable"), "Authored station reachable")
	var other_actor := Node.new()
	p.get_node("Interactable").interact(other_actor)
	other_actor.free()
	check(not ui.is_open, "Non-player actor rejected")
	player.interact_with_nearest()
	check(ui.is_open and not player.controls_enabled and not player.get_node("InventoryUI").is_processing_input(), "Modal locks movement and inventory")
	check(not session._can_open_shop(), "Shop blocked")
	session._enter_furnish_mode()
	check(not session.furnish_mode.active, "Furnish blocked")
	var position_before := player.position
	Input.action_press("move_left")
	player._physics_process(0.1)
	Input.action_release("move_left")
	check(player.position == position_before, "Modal prevents movement")
	session._request_transition(player, session.SHIP, session.MARS, &"ShipArrival")
	check(not session.transitioning, "Modal prevents world transition")
	ui._select_max()
	ui._act()
	check(ui.content.get_node("Action").disabled and ui.content.get_node("Selection/Max").disabled and p.is_idle() and player.inventory.count_item(IRON) == 7, "Seven ore MAX cannot start")
	player.inventory.add_item(IRON, 29)
	ui._select_max()
	check(ui.selected_quantity == 3, "UI MAX with thirty-six ore")
	player.inventory.add_item(IRON, 64)
	ui._select_max()
	check(ui.selected_quantity == 10, "UI MAX with one hundred ore")
	player.inventory.add_item(IRON, 80)
	ui._select_max()
	ui._change_quantity(1)
	check(ui.selected_quantity == 10 and ui.content.get_node("Selection/Plus").disabled, "UI caps above one hundred ore")
	ui._change_quantity(-100)
	check(ui.selected_quantity == 1 and ui.content.get_node("Selection/Minus").disabled, "UI minimum one")
	player.inventory.remove_item(IRON, 113)
	ui._select_max()
	ui.content.get_node("Selection/Minus").pressed.emit()
	check(ui.selected_quantity == 5, "Quantity button selects five of six affordable")
	check(ui.content.get_node("Selection/Required").text == "Required: 50 Iron Ore", "Selected ore preview")
	check(ui.content.get_node("Selection/Output").text == "Output: 5 Iron Plates", "Selected plate preview")
	check(ui.content.get_node("Selection/Time").text == "Time: 2m 30s", "Selected duration preview")
	check(ui.content.get_node("Frame").texture.resource_path == "res://assets/ui/processor/processor_window_480x300.png", "Actual window asset")
	check(ui.get_node("Backdrop").texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Nearest pixel filtering")
	await create_timer(0.15).timeout
	session.save_service.saved.connect(func() -> void: writes += 1)
	p.changed.connect(func() -> void: changes += 1)
	ui.content.get_node("Action").pressed.emit()
	var deadline := p.next_unit_deadline
	check(p.units_remaining == 5 and p.held_output == 0 and player.inventory.count_item(IRON) == 17, "UI commits entire five-unit batch")
	check(session.save_service.dirty and changes == 1, "Start marks dirty once")
	ui._act()
	check(p.units_remaining == 5 and player.inventory.count_item(IRON) == 17, "Repeated button input cannot start second batch")
	check(ui.content.get_node("Action").disabled and not ui.content.get_node("Selection").visible, "Processing hides selection; empty collection disabled")
	for index in 40:
		ui._refresh()
	check(changes == 1, "Countdown has no state notifications")
	await create_timer(0.2).timeout
	check(writes == 1, "Batch input and state coalesce into one save")
	await create_timer(0.2).timeout
	check(writes == 1 and not session.save_service.dirty, "Countdown does not save repeatedly")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	ui._input(cancel)
	await process_frame
	await process_frame
	check(not ui.is_open and player.controls_enabled and player.get_node("InventoryUI").is_processing_input(), "Escape restores controls")
	check(p.next_unit_deadline == deadline, "Closing preserves timing")
	await travel(session.MARS)
	await travel(session.SHIP)
	check(p.next_unit_deadline == deadline and p.units_remaining == 5, "Travel preserves active batch")
	await stop_session()
	await start_session()
	p = processor()
	check(p.next_unit_deadline == deadline and p.units_remaining == 5 and p.held_output == 0, "Reload before first deadline preserves batch")
	# Save a five-unit batch started 95 seconds ago: next original deadline is 65 seconds past.
	var offline: Dictionary = session.save_service.capture()
	var now := Time.get_unix_time_from_system()
	offline.processors[p.PERSISTENT_ID].next_unit_deadline = now - 65.0
	await stop_session()
	clean_files()
	write_fixture(offline)
	await start_session()
	p = processor()
	check(p.units_remaining == 2 and p.held_output == 3, "Ninety-five seconds offline completes three of five")
	check(is_equal_approx(p.next_unit_deadline, now + 25.0), "Offline partial interval retained")
	check(session.save_service.dirty, "Offline aggregate completion marks dirty")
	check(not p.refresh_completion() and p.held_output == 3, "Repeated refresh does not duplicate offline output")
	check(player.inventory.count_item(p.OUTPUT) == 0, "Completed output is held at station")
	check(session.save_service.flush(), "Offline result persisted")
	var partial: Dictionary = p.capture()
	await stop_session()
	await start_session()
	p = processor()
	check(p.capture() == partial, "Repeated reload preserves aggregate without duplication")
	await travel(session.MARS)
	await travel(session.SHIP)
	check(p.capture() == partial, "Output and active progress survive round trip")
	session._open_processing(player)
	ui = session.processing_ui
	p.next_unit_deadline = Time.get_unix_time_from_system() + 18.0
	ui._refresh()
	check(ui.content.get_node("Production/Next").text == "Next Plate: 18s", "Next-unit countdown")
	check(absf(ui.content.get_node("Production/Progress").value - 40.0) < 0.1, "Progress tracks next unit, not entire batch")
	check(not ui.content.get_node("Action").disabled, "Output collectible while producing")
	deadline = p.next_unit_deadline
	clear_inventory()
	player.inventory.add_item(TOOL, 19)
	player.inventory.add_item(p.OUTPUT, 98)
	player.inventory.changed.connect(func() -> void:
		check(processor().held_output == 2 and player.inventory.count_item(processor().OUTPUT) == 99, "Partial collection publishes coherent quantities")
		check(processor().collect(player.inventory) == 0, "Reentrant full collection cannot duplicate")
	, CONNECT_ONE_SHOT)
	ui.content.get_node("Action").pressed.emit()
	check(p.held_output == 2 and player.inventory.count_item(p.OUTPUT) == 99, "Collect accepts one and retains two")
	check(p.units_remaining == 2 and p.next_unit_deadline == deadline, "Partial collection preserves active production")
	check(session.save_service.dirty, "Collection marks dirty")
	ui._act()
	check(p.held_output == 2 and ui.content.get_node("Feedback").text == "Inventory Full", "Full inventory loses no output")
	player.inventory.remove_item(TOOL, 1)
	ui._act()
	check(p.held_output == 0 and p.units_remaining == 2 and p.next_unit_deadline == deadline, "Collect remaining output while production continues")
	check(player.inventory.count_item(p.OUTPUT) == 101, "All accepted output conserved")
	check(p.collect(player.inventory) == 0, "Repeated empty collection does nothing")
	ui.content.get_node("Close").pressed.emit()
	await process_frame
	await process_frame
	check(player.controls_enabled and not ui.is_open, "Close button restores controls")
	await travel(session.MARS)
	# Session refresh runs even though the ship is detached.
	p.next_unit_deadline = Time.get_unix_time_from_system() - 31.0
	session.save_service.dirty = false
	await process_frame
	await process_frame
	check(p.units_remaining == 0 and p.held_output == 2 and p.next_unit_deadline == 0, "Detached station finishes all due units")
	check(session.save_service.dirty, "Batch completion marks dirty")
	session.save_service.flush()
	await stop_session()
	await start_session()
	p = processor()
	check(p.units_remaining == 0 and p.held_output == 2, "Finished uncollected output survives reload")
	await travel(session.SHIP)
	session._open_processing(player)
	ui = session.processing_ui
	check(ui.content.get_node("Production/Status").text == "PRODUCTION COMPLETE" and ui.content.get_node("Action").text == "COLLECT ALL", "Finished UI")
	ui._act()
	check(p.is_idle() and ui.content.get_node("Selection").visible, "Collect all returns selection UI")
	check(player.inventory.count_item(p.OUTPUT) == 103, "Batch produced exactly five overall")
	check(p.capture().keys().size() == 3 and p.capture().has_all(["units_remaining", "next_unit_deadline", "held_output"]), "Only production state persists; no UI or worker fields")
	await session._close_processing()
	# Rich V5 data ensures the new migration does not alter existing domains.
	deposit.replenishment_deadline = Time.get_unix_time_from_system() + 60.0
	deposit.overflow_store.spawn(2, Vector2(500, 500))
	session.economy.restore(731, 2)
	var crate: ShipStorage = session.furnishings.add_restored_crate("placed_object_000001", Vector2i(2, 2), 1)
	crate.inventory.add_item(IRON, 17)
	session.furnishings.next_placed_object_id = 2
	var snapshot: Dictionary = session.save_service.capture()
	snapshot.save_version = 5
	snapshot.erase("processors")
	await stop_session()
	clean_files()
	write_fixture(snapshot)
	await start_session()
	var migrated: Dictionary = session.save_service.capture()
	check(processor().is_idle() and migrated.save_version == 6, "V5 migrates to V6 idle")
	for field in ["mining_nodes", "mining_overflow", "credits", "owned_furnishings", "placed_crates", "next_placed_object_id", "player_inventory", "storage_inventories", "ship_pickups"]:
		check(migrated[field] == snapshot[field], "V5 preserves " + field)
	for version in [1, 2, 3, 4]:
		var old := snapshot.duplicate(true)
		old.save_version = version
		old.erase("mining_overflow")
		old.mining_nodes = {}
		await stop_session()
		clean_files()
		write_fixture(old)
		await start_session()
		check(session.save_service.writable and processor().is_idle(), "V%d loads idle" % version)
	var valid: Dictionary = session.save_service.capture()
	check(session.save_service.validate(valid).is_empty(), "V6 valid")
	for bad in [null, {}, {"unknown": ShipProcessor.idle_snapshot()}, {ShipProcessor.PERSISTENT_ID: null}]:
		var malformed := valid.duplicate(true)
		malformed.processors = bad
		check(not session.save_service.validate(malformed).is_empty(), "Malformed identities rejected")
	for field in ["units_remaining", "next_unit_deadline", "held_output"]:
		for value in [null, true, -1, "bad", INF, NAN]:
			var malformed := valid.duplicate(true)
			malformed.processors[ShipProcessor.PERSISTENT_ID][field] = value
			check(not session.save_service.validate(malformed).is_empty(), "Malformed processor " + field)
	for record in [
		{"units_remaining": 1, "next_unit_deadline": 0, "held_output": 0},
		{"units_remaining": 0, "next_unit_deadline": 1, "held_output": 0},
		{"units_remaining": 8, "next_unit_deadline": 1, "held_output": 3},
		{"units_remaining": 11, "next_unit_deadline": 1, "held_output": 0},
		{"units_remaining": 1.5, "next_unit_deadline": 1, "held_output": 0},
		{"units_remaining": 0, "next_unit_deadline": 0, "held_output": 1.5},
		{"units_remaining": 0, "next_unit_deadline": 0, "held_output": 11},
		{"state": "IDLE", "completion_deadline": 0, "held_output": 0},
	]:
		var malformed := valid.duplicate(true)
		malformed.processors[ShipProcessor.PERSISTENT_ID] = record
		check(not session.save_service.validate(malformed).is_empty(), "Impossible state rejected")
	await stop_session()
	clean_files()
	valid.processors[ShipProcessor.PERSISTENT_ID].held_output = 11
	write_fixture(valid)
	var protected_text := FileAccess.get_file_as_string(directory.path_join("autosave.json"))
	await start_session()
	check(not session.save_service.writable and processor().is_idle(), "Malformed processing file starts protected recovery")
	player.inventory.add_item(IRON, 10)
	processor().start_job(player.inventory)
	check(not session.save_service.flush(true), "Protected processing cannot overwrite corrupted save")
	check(FileAccess.get_file_as_string(directory.path_join("autosave.json")) == protected_text, "Malformed file remains unchanged")
	await stop_session()
	clean_files()
	DirAccess.remove_absolute(directory)
	print("M5D processing: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
