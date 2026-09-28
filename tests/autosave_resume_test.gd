extends SceneTree

const SESSION := preload("res://scenes/game/game_session.tscn")
const IRON := preload("res://data/items/iron_ore.tres")
const TOOL := preload("res://data/items/basic_mining_tool.tres")
const NUTRIENT := preload("res://data/items/nutrient_pack.tres")
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


func create_session() -> void:
	session = SESSION.instantiate()
	var service: SaveService = session.get_node("SaveService")
	service.save_directory = directory
	service.coalesce_seconds = 0.15
	service.retry_seconds = 0.2
	session.get_node("PositionCheckTimer").wait_time = 0.05
	service.saved.connect(func() -> void: writes += 1)
	root.add_child(session)
	check(not session.player.controls_enabled and not session.player.get_node("InventoryUI").is_processing_input(), "Startup input locked")
	await settle()


func settle() -> void:
	for frame in 90:
		await physics_frame
		if not session.transitioning:
			return
	check(false, "Transition completed within 90 frames")


func destroy_session() -> void:
	var ship_ref: WeakRef = weakref(session.ship)
	var mars_ref: WeakRef = weakref(session.mars)
	var player_ref: WeakRef = weakref(session.player)
	var service_ref: WeakRef = weakref(session.save_service)
	session.queue_free()
	await process_frame
	session = null
	check(ship_ref.get_ref() == null and mars_ref.get_ref() == null and player_ref.get_ref() == null and service_ref.get_ref() == null, "Entire runtime and service destroyed")
	check(auto_accept_quit, "Session teardown restores desktop quit policy")


func storage() -> InventoryData:
	return session.ship.get_node("WorldObjects/Crate").inventory


func travel(destination: StringName) -> void:
	var source: StringName = session.current_location
	session._request_transition(session.player, source, destination, &"ShipArrival" if destination == session.MARS else &"MarsReturnSpawn")
	await settle()


func read_save() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("autosave.json")))


func write_save(text: String) -> void:
	var file := FileAccess.open(directory.path_join("autosave.json"), FileAccess.WRITE)
	check(file != null, "Fixture file opens")
	if file != null:
		file.store_string(text)
		file.close()


func clean_files() -> void:
	for name in ["autosave.json", "autosave.json.tmp", "autosave.json.bak"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(path) == OK, "Remove test artifact " + name)


func populate() -> void:
	# Fill the inventory so the authored iron pickup can only be partially accepted.
	var inventory: InventoryData = session.player.inventory
	inventory.add_item(IRON, 90)
	inventory.add_item(TOOL, 19)
	var iron_pickup: WorldPickup = session.ship.get_node("WorldObjects/IronPickup")
	iron_pickup.get_node("Interactable").interact(session.player)
	check(iron_pickup.quantity == 110, "Partial authored pickup leaves 110")
	inventory.transfer_to(storage(), 4, 1)
	var tool_pickup: WorldPickup = session.ship.get_node("WorldObjects/ToolPickup")
	tool_pickup.get_node("Interactable").interact(session.player)
	check(tool_pickup.quantity == 0, "Authored tool fully collected")
	inventory.transfer_to(storage(), 2, 1)
	inventory.transfer_to(storage(), 7, 1)
	storage().transfer_to(inventory, 1, 1)
	# Player has a hole at 7; storage has a hole at 1 and occupied slot 2.
	check(inventory.slots[7].item == null and storage().slots[1].item == null and storage().slots[2].item == TOOL, "Meaningful holes established")


func check_resumed(expected: Dictionary) -> void:
	check(session.current_location == session.MARS, "Fresh session resumes Mars")
	check(session.player.global_position == Vector2(720, 864), "Mars position round trip")
	check(session.save_service.capture() == expected, "All IDs, quantities, slots and location round trip")
	check(not session.ship.is_inside_tree(), "Restored ship stays detached")
	check(session.ship.get_node_or_null("WorldObjects/ToolPickup") == null, "Fully collected pickup stays absent")
	check(session.ship.get_node("WorldObjects/IronPickup").quantity == 110, "Partial pickup amount restored")
	check(session.find_children("*", "Player", true, false).size() == 1, "One player after resume")
	check(session.find_children("InventoryUI", "", true, false).size() == 1, "One UI after resume")
	check(session.player.get_node("InventoryUI").player.inventory == session.player.inventory, "UI retains restored inventory reference")
	check(not session.save_service.dirty, "Loaded state does not dirty itself")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await process_phase(args)
		return
	directory = "user://m46_resume_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create isolated test directory")
	await create_session()
	check(session.current_location == session.SHIP and session.player.position == Vector2(160, 168), "No-save starts at ship PlayerStart")
	check(session.player.inventory.slots[0].item == null and storage().slots[0].item == null, "No-save inventories empty")
	check(session.save_service.capture().ship_pickups.size() == 4, "Four authored pickup identities")
	await create_timer(0.25).timeout
	check(writes == 1, "New-game snapshot autosaves")
	var before := writes
	populate()
	check(writes == before, "Dirty events never write inline during pickup collection")
	await create_timer(0.25).timeout
	check(writes == before + 1, "Rapid inventory/storage/pickup events coalesce into one write")
	check(read_save().ship_pickups.starter_ship_iron_01 == 110 and read_save().ship_pickups.starter_ship_tool_01 == 0, "Autosave captures final pickup quantities")
	await create_timer(0.25).timeout
	check(writes == before + 1, "Idle game does not write repeatedly")
	before = writes
	await travel(session.MARS)
	check(writes == before + 1 and read_save().current_location == "mars_landing_zone", "Completed transition saves immediately")
	check(read_save().player_position == {"x": 672.0, "y": 864.0}, "Transition saves destination arrival position")
	session.player.position = Vector2(720, 864)
	await create_timer(0.3).timeout
	check(read_save().player_position == {"x": 720.0, "y": 864.0}, "Walking alone triggers ordinary position autosave")
	var expected: Dictionary = session.save_service.capture()
	for quantity in [-1, 121, 0.5, true]:
		var bad_pickup := expected.duplicate(true)
		bad_pickup.ship_pickups.starter_ship_iron_01 = quantity
		check(not session.save_service.validate(bad_pickup).is_empty(), "Invalid pickup quantity rejected")
	var missing_pickup := expected.duplicate(true)
	missing_pickup.ship_pickups.erase("starter_ship_tool_01")
	check(not session.save_service.validate(missing_pickup).is_empty(), "Missing collected pickup record rejected")
	var wrong_pickup := expected.duplicate(true)
	wrong_pickup.ship_pickups.erase("starter_ship_tool_01")
	wrong_pickup.ship_pickups.unknown_pickup = 0
	check(not session.save_service.validate(wrong_pickup).is_empty(), "Unknown pickup ID rejected")
	await destroy_session()
	await create_session()
	check_resumed(expected)
	var restored_storage := storage()
	var restored_inventory: InventoryData = session.player.inventory
	await travel(session.SHIP)
	check(storage() == restored_storage and session.player.inventory == restored_inventory, "First ship ready preserves restored inventory identities")
	check(session.save_service.capture().storage_inventories == expected.storage_inventories, "Detached storage survives first activation")
	check(session.ship.get_node("WorldObjects/IronPickup/QuantityLabel").text == "Iron Ore x110", "Restored pickup label initialized")
	var ui = session.player.get_node("InventoryUI")
	ui.open_storage(storage(), "Ship Storage")
	check(ui.storage == restored_storage and ui.storage_list.get_item_count() == 40, "UI opens restored storage")
	ui.close()
	check(read_save().player_position == {"x": 160.0, "y": 192.0}, "Return transition saves ship destination in local coordinates")
	session.player.position = Vector2(160, 140)
	await create_timer(0.3).timeout
	await destroy_session()
	await create_session()
	check(session.current_location == session.SHIP and session.player.position == Vector2(160, 140), "Ship position round trip")
	check(session.ship.get_node_or_null("WorldObjects/ToolPickup") == null, "Collected pickup absent on direct ship resume")
	# Continuous dirty events must not continually restart the coalescing timer.
	before = writes
	for index in 6:
		storage().add_item(IRON, 1)
		await create_timer(0.06).timeout
	check(writes > before, "Continuous events still save within bounded window")
	await create_timer(0.25).timeout
	# An expired timer while transitioning must wait until the safe point.
	before = writes
	session.save_service.safe_to_save = false
	storage().add_item(IRON, 1)
	await create_timer(0.25).timeout
	check(writes == before and session.save_service.dirty, "Unsafe transition defers dirty timer")
	session.save_service.complete_location("starter_ship", false)
	check(writes == before + 1, "Safe completion flushes pending changes")
	# A close attempt during a transition captures the last completed location.
	session.save_service.safe_to_save = false
	storage().add_item(IRON, 1)
	check(session.save_service.flush(true), "Close bypasses transition wait")
	check(read_save().current_location == "starter_ship", "Close uses last completed location")
	await destroy_session()
	# Optional position is validated independently: bad coordinates do not discard inventory.
	for location in ["starter_ship", "mars_landing_zone"]:
		for position in [null, "bad", {"x": true, "y": 100}, {"x": 100}, {"x": 1e100, "y": 100}, {"x": -200, "y": 100}, {"x": 160, "y": 24} if location == "starter_ship" else {"x": 672, "y": 700}]:
			clean_files()
			var fallback := expected.duplicate(true)
			fallback.current_location = location
			if position == null:
				fallback.erase("player_position")
			else:
				fallback.player_position = position
			write_save(JSON.stringify(fallback))
			await create_session()
			var marker := Vector2(160, 168) if location == "starter_ship" else Vector2(672, 864)
			check(session.player.position == marker, "Missing/malformed/outside/blocked position falls back on " + location)
			check(session.save_service.writable and session.save_service.capture().player_inventory == expected.player_inventory, "Position fallback preserves valid progress and writable save")
			check(not session._valid_position({"x": INF, "y": 100}) and not session._valid_position({"x": NAN, "y": 100}), "Non-finite coordinates rejected")
			await destroy_session()
	clean_files()
	await create_session()
	await travel(session.MARS)
	before = writes
	# Repeated small motion over many frames still uses the shared coalescing window.
	for frame in 30:
		session.player.position.x += 1.0
		await create_timer(0.02).timeout
	await create_timer(0.3).timeout
	check(writes > before and writes - before <= 6, "Continuous movement coalesces rather than writing every frame")
	check(read_save().player_position.x == session.player.position.x, "Last walking position eventually saved")
	before = writes
	await create_timer(0.3).timeout
	check(writes == before, "Stationary position does not keep saving")
	await destroy_session()
	# Malformed and unsupported files never turn into a writable new game.
	var invalid_storage := expected.duplicate(true)
	invalid_storage.storage_inventories.starter_ship_storage_01 = [{"slot": 100, "item_id": "iron_ore", "quantity": 1}]
	for text in ["{bad JSON", JSON.stringify({"save_version": 99}), JSON.stringify({"save_version": 1}), JSON.stringify(invalid_storage)]:
		clean_files()
		write_save(text)
		await create_session()
		check(not session.save_service.writable and not session.save_service.status_message.is_empty(), "Invalid save starts protected fallback with clear status")
		check(not session.player.get_node("InventoryUI/SaveStatus").text.is_empty(), "Protection visible in gameplay UI")
		check(session.player.inventory.slots[0].item == null and storage().slots[0].item == null, "Validation failure never partially applies inventories")
		check(session.ship.get_node("WorldObjects/ToolPickup").quantity == 1, "Validation failure never partially applies pickups")
		session.player.inventory.add_item(IRON, 1)
		await create_timer(0.25).timeout
		await travel(session.MARS)
		check(not session.save_service.flush(true), "Invalid save protected on close")
		check(FileAccess.get_file_as_string(directory.path_join("autosave.json")) == text, "Invalid save unchanged after timer, transition and close")
		await destroy_session()
	clean_files()
	# Separate processes ensure no live runtime or service memory can carry progress.
	for phase in ["writer", "reader", "position_writer", "position_reader"]:
		var output: Array = []
		var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/autosave_resume_test.gd", "--", phase, directory], output, true)
		check(result == 0, "Separate-process " + phase)
		for line in output:
			print(line)
	clean_files()
	check(DirAccess.remove_absolute(directory) == OK, "Remove isolated test directory")
	print("M4.6 automatic resume: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func process_phase(args: PackedStringArray) -> void:
	if args.size() != 2 or not args[1].begins_with("user://m46_resume_test_") or ".." in args[1]:
		quit(1)
		return
	directory = args[1]
	await create_session()
	if args[0] == "writer":
		populate()
		await travel(session.MARS)
		# Only the normal close hook can persist this last modification.
		session.player.inventory.add_item(NUTRIENT, 3)
		session.player.position = Vector2(736, 864)
		check(session.save_service.dirty, "Pending progress before desktop close")
		print("M4.6 separate-process writer: %d checks, %d failures" % [checks, failures])
		if failures:
			quit(1)
			return
		session.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	elif args[0] == "position_writer":
		check(not session.save_service.dirty, "Movement-only close begins with a clean save")
		session.player.position = Vector2(752, 864)
		print("M4.6 separate-process position writer: %d checks, %d failures" % [checks, failures])
		if failures:
			quit(1)
			return
		session.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		check(session.current_location == session.MARS, "Separate-process Mars resume")
		var expected_position := Vector2(752, 864) if args[0] == "position_reader" else Vector2(736, 864)
		check(session.player.position == expected_position, "Desktop close captures latest position before sampling timer: " + args[0])
		check(session.player.inventory.slots[7].item == NUTRIENT and session.player.inventory.slots[7].quantity == 3, "Desktop close saved pending inventory change")
		check(storage().slots[2].item == TOOL and storage().slots[1].item == null, "Separate-process storage arrangement")
		check(session.ship.get_node_or_null("WorldObjects/ToolPickup") == null and session.ship.get_node("WorldObjects/IronPickup").quantity == 110, "Separate-process pickup persistence")
		await destroy_session()
		print("M4.6 separate-process reader: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
