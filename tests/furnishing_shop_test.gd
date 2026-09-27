extends SceneTree

const SESSION := preload("res://scenes/game/game_session.tscn")
const IRON := preload("res://data/items/iron_ore.tres")
var checks := 0
var failures := 0
var session: Node
var directory: String
var observations: Array[Dictionary] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)


func start() -> void:
	session = SESSION.instantiate()
	session.get_node("SaveService").save_directory = directory
	session.get_node("SaveService").coalesce_seconds = 0.1
	root.add_child(session)
	await settle()


func settle() -> void:
	for frame in 90:
		await physics_frame
		if not session.transitioning and not session._leaving_furnish and not session._closing_shop:
			return
	check(false, "Session settles")


func stop() -> void:
	session.queue_free()
	await process_frame
	session = null


func action(name: StringName, pressed: bool = true) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(name: StringName) -> void:
	action(name)
	action(name, false)


func click_cart() -> void:
	# process_frame fires before node processing; let the HUD complete its update.
	await process_frame
	await process_frame
	var point: Vector2 = root.get_final_transform() * session.shop.cart.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame


func travel(destination: StringName) -> void:
	session._request_transition(session.player, session.current_location, destination,
		&"ShipArrival" if destination == session.MARS else &"MarsReturnSpawn")
	await settle()


func observe() -> void:
	observations.append(session.save_service.capture())


func fixture(data: Dictionary) -> void:
	clean()
	var file := FileAccess.open(directory.path_join("autosave.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func clean() -> void:
	for name in ["autosave.json", "autosave.json.bak", "autosave.json.tmp"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(path) == OK, "Remove isolated test save")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await process_phase(args)
		return
	directory = "user://m5b_economy_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	await start()
	var economy: SessionEconomy = session.economy
	var service: SaveService = session.save_service
	var furnishings: ShipFurnishings = session.furnishings
	var mode = session.furnish_mode
	var price: int = session.shop.storage_crate_price
	var credits_label: Label = session.get_node("ResourceHUD/Resources/Credits")
	check(economy.credits == SessionEconomy.STARTING_CREDITS and economy.owned_storage_crates() == 0, "New game economy")
	check(credits_label.text == "Credits: %d C" % SessionEconomy.STARTING_CREDITS and credits_label.is_visible_in_tree(), "Fresh Ship HUD displays starting Credits")
	await process_frame
	await process_frame
	check(session.shop.cart.visible and not session.shop.cart.disabled, "Normal Ship HUD exposes cart")
	await click_cart()
	check(session.shop.is_open and not session.player.controls_enabled, "Ship cart opens modal shop")
	check(session.shop.get_node("Backdrop/Center/Panel/Content/Title").text == "FURNISHING SHOP", "Global shop has correct title")
	check(session.shop.get_node("Backdrop/Center/Panel/Content/Credits").text == "Credits: %d C" % economy.credits, "Shop displays current Credits")
	check(price == 250 and session.shop.get_node("Backdrop/Center/Panel/Content/Price").text == "250 C", "Storage Crate price remains 250 C")
	var shop_instance: Node = session.shop
	session.shop.cart.pressed.emit()
	check(session.shop == shop_instance and session.shop.is_open and not session.shop.cart.visible, "Repeated cart request reuses the one shop")
	check(credits_label.is_visible_in_tree(), "Resource HUD remains visible independently of shop and cart")
	tap(&"inventory_toggle")
	tap(&"furnish_toggle")
	check(not session.player.get_node("InventoryUI").panel.visible and not mode.active, "Ship shop blocks Inventory and Furnish Mode")
	tap(&"ui_cancel")
	await settle()
	check(not session.shop.is_open and session.player.controls_enabled, "Escape closes Ship shop")
	tap(&"inventory_toggle")
	await process_frame
	await process_frame
	check(session.player.get_node("InventoryUI").panel.visible and not session.shop.cart.visible and session.shop.cart.disabled, "Inventory hides and disables cart")
	check(credits_label.is_visible_in_tree(), "Inventory does not hide resource HUD")
	session.shop.cart.pressed.emit()
	check(not session.shop.is_open and session.player.get_node("InventoryUI").panel.visible, "Cart request cannot interrupt Inventory")
	tap(&"ui_cancel")
	service.flush()
	var base := service.capture()
	economy.changed.connect(observe)
	furnishings.changed.connect(observe)
	session._enter_furnish_mode()
	await process_frame
	await process_frame
	check(not session.shop.cart.visible and session.shop.cart.disabled, "Furnish Mode hides and disables cart")
	check(credits_label.is_visible_in_tree(), "Furnish Mode does not hide resource HUD")
	session.shop.cart.pressed.emit()
	check(not session.shop.is_open and mode.active, "Cart request cannot interrupt Furnish Mode")
	var card: Button = mode.get_node("UI/Panel/Content/Toolbar/Cards/NewCrate")
	check(card.text == "Storage Crate ×0" and card.disabled, "Zero stock displayed")
	mode.select_new()
	check(not mode.placing and furnishings.create_crate(Vector2i(2, 3)).is_empty(), "Both UI and direct creation reject zero stock")
	check(not service.dirty and observations.is_empty(), "Zero stock rejection stays clean")
	check(economy.purchase_storage_crate(price), "Purchase succeeds")
	check(economy.credits == SessionEconomy.STARTING_CREDITS - price and economy.owned_storage_crates() == 1, "Purchase updates both balances")
	check(credits_label.text == "Credits: %d C" % (SessionEconomy.STARTING_CREDITS - price), "Purchase immediately updates HUD to 750 C without a frame or reopen")
	check(observations.size() == 1 and observations[0].credits == economy.credits and observations[0].owned_furnishings.storage_crate == 1, "Purchase listeners see complete state")
	check(card.text == "Storage Crate ×1" and not card.disabled and service.dirty, "Purchase refreshes card and dirties save")
	service.flush()
	observations.clear()
	mode.select_new()
	mode.rotate_selected()
	check(economy.owned_storage_crates() == 1 and not service.dirty, "Preview and preview rotation consume nothing")
	check(not mode.confirm_at(Vector2i(-1, -1)) and economy.owned_storage_crates() == 1 and not service.dirty, "Invalid placement consumes nothing")
	mode.cancel_preview()
	check(economy.owned_storage_crates() == 1 and not service.dirty, "Cancel consumes nothing")
	check(furnishings.create_crate(Vector2i(2, 3), 4).is_empty(), "Invalid rotation rejected")
	furnishings.next_placed_object_id = ShipFurnishings.MAX_NEXT_ID
	check(furnishings.create_crate(Vector2i(2, 3)).is_empty() and economy.owned_storage_crates() == 1, "Exhausted ID consumes nothing")
	furnishings.next_placed_object_id = 1
	mode.select_new()
	mode.rotate_selected()
	check(mode.confirm_at(Vector2i(2, 3)), "New rotated placement commits")
	var id := "placed_object_000001"
	check(economy.owned_storage_crates() == 0 and furnishings.crates[id].rotation_quarters == 1, "Placement consumes exactly one and retains rotation")
	check(observations.size() == 2, "Placement emits economy and furnishing changes")
	for snapshot in observations:
		check(snapshot.owned_furnishings.storage_crate == 0 and snapshot.placed_crates.size() == 1 and snapshot.next_placed_object_id == 2, "Placement listener sees completed world and ownership")
	check(furnishings.move_crate(id, Vector2i(3, 3)) and furnishings.rotate_crate(id), "Existing move and rotation work at zero")
	check(economy.owned_storage_crates() == 0, "Existing operations consume nothing")
	var recovered := furnishings.add_restored_crate("placed_object_000010", Vector2i(99, 99), 2)
	furnishings.next_placed_object_id = 11
	check(furnishings.move_crate(recovered.persistent_id, Vector2i(6, 3)) and economy.owned_storage_crates() == 0, "Recovery works at zero without consumption")
	var crate: ShipStorage = furnishings.crates[id].node
	crate.inventory.add_item(IRON, 7)
	service.flush()
	check(not furnishings.remove_crate(id) and economy.owned_storage_crates() == 0 and not service.dirty, "Nonempty removal stays clean")
	mode.select_crate(id)
	mode.remove_selected()
	check(mode.feedback.text == "Empty this crate before removing it.", "Nonempty feedback preserved")
	check(not furnishings.remove_crate(session.SHIP_STORAGE_ID) and economy.owned_storage_crates() == 0, "Authored storage grants nothing")
	observations.clear()
	check(furnishings.remove_crate(recovered.persistent_id), "Empty removal succeeds")
	check(economy.owned_storage_crates() == 1 and service.dirty, "Removal returns one and dirties save")
	for snapshot in observations:
		check(snapshot.owned_furnishings.storage_crate == 1 and snapshot.placed_crates.size() == 1 and snapshot.next_placed_object_id == 11, "Removal listeners see completed state")
	check(not furnishings.remove_crate("placed_object_000010") and economy.owned_storage_crates() == 1, "Repeated removal cannot duplicate stock")
	check(furnishings.create_crate(Vector2i(6, 3)) == "placed_object_000011" and economy.owned_storage_crates() == 0, "Re-placement uses fresh ID and consumes stock")
	session._exit_furnish_mode()
	await settle()
	await travel(session.MARS)
	check(credits_label.text == "Credits: %d C" % (SessionEconomy.STARTING_CREDITS - price) and credits_label.is_visible_in_tree(), "Mars retains Ship HUD balance")
	check(economy == session.economy and furnishings.crates[id].node.inventory.slots[0].quantity == 7, "Travel preserves economy and crate contents")
	session.player.position = Vector2(260, 540)
	await physics_frame
	await physics_frame
	tap(&"interact")
	check(session.mars.get_node("WorldObjects/SupplyDepot").get_node_or_null("Interactable") == null and not session.shop.is_open, "Supply Depot has no shop interaction")
	check(session.mars.get_node("WorldObjects/SupplyDepot/Sprite2D") != null and session.mars.get_node("WorldObjects/SupplyDepot/CollisionShape2D") != null, "Supply Depot artwork and collision remain")
	session.player.position = Vector2(400, 800)
	await physics_frame
	await process_frame
	check(session.shop.cart.visible and not session.shop.cart.disabled, "Normal Mars HUD exposes cart")
	await click_cart()
	check(session.shop.is_open and not session.player.controls_enabled, "Mars cart opens shop away from depot")
	var position: Vector2 = session.player.position
	Input.action_press(&"move_left")
	tap(&"inventory_toggle")
	tap(&"furnish_toggle")
	tap(&"interact")
	await physics_frame
	await physics_frame
	Input.action_release(&"move_left")
	check(session.player.position == position and not session.player.get_node("InventoryUI").panel.visible and not mode.active and not session.transitioning, "Shop blocks gameplay input")
	economy.restore(price * 2, economy.owned_storage_crates())
	session.shop.get_node("Backdrop/Center/Panel/Content/Buy").pressed.emit()
	check(economy.credits == price and economy.owned_storage_crates() == 1, "Buy button works")
	session.shop.buy()
	check(economy.credits == 0 and economy.owned_storage_crates() == 2, "Repeated exact-funds purchase works")
	service.flush()
	session.shop.buy()
	check(economy.credits == 0 and economy.owned_storage_crates() == 2 and not service.dirty, "Insufficient purchase leaves state clean")
	check(session.shop.feedback.text == "Not enough Credits.", "Insufficient feedback")
	action(&"interact")
	action(&"ui_cancel")
	await process_frame
	check(not session.shop.is_open and not session.player.controls_enabled and session._closing_shop, "Held Escape closes without unlocking")
	action(&"ui_cancel", false)
	await process_frame
	check(not session.player.controls_enabled, "Held E keeps close lock")
	action(&"interact", false)
	await settle()
	check(not session.shop.is_open and session.player.controls_enabled, "Release restores gameplay without reopening")
	tap(&"interact")
	check(not session.shop.is_open, "Fresh E does not reopen furnishing shop")
	await click_cart()
	check(session.shop.is_open, "Fresh cart click reopens")
	session.shop.get_node("Backdrop/Center/Panel/Content/Close").pressed.emit()
	await settle()
	check(not session.shop.is_open and session.player.controls_enabled, "Close button works")
	await travel(session.SHIP)
	check(economy.credits == 0 and economy.owned_storage_crates() == 2 and furnishings.crates[id].rotation_quarters == 2, "Round trip preserves exact economy and rotation")
	check(credits_label.text == "Credits: 0 C" and credits_label.is_visible_in_tree(), "Return to Ship retains current HUD balance")
	await test_validation(base)
	await stop()
	await test_migration(base)
	clean()
	for phase in ["writer", "reader"]:
		var output: Array = []
		var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/furnishing_shop_test.gd", "--", phase, directory], output, true)
		check(result == 0, "Fresh process " + phase)
		for line in output:
			print(line)
	clean()
	check(DirAccess.remove_absolute(directory) == OK, "Remove isolated directory")
	print("M5B economy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_validation(base: Dictionary) -> void:
	var service: SaveService = session.save_service
	for version in [1, 2, 3]:
		for value in [-1, 0.5, true, false, "1", null, [], {}, INF, NAN, SessionEconomy.MAX_BALANCE + 1]:
			for field in ["credits", "owned_furnishings"]:
				var bad := base.duplicate(true)
				bad.save_version = version
				bad[field] = value if field == "credits" else {"storage_crate": value}
				check(not service.validate(bad).is_empty(), "Reject malformed %s in V%d" % [field, version])
	for field in ["credits", "owned_furnishings"]:
		var bad := base.duplicate(true)
		bad.erase(field)
		check(not service.validate(bad).is_empty(), "V3 requires " + field)
	for owned in [null, [], 0, {}, {"other": 1}, {"storage_crate": 0, "other": 1}]:
		var bad := base.duplicate(true)
		bad.owned_furnishings = owned
		check(not service.validate(bad).is_empty(), "Invalid ownership container")
	var maximum := base.duplicate(true)
	maximum.credits = SessionEconomy.MAX_BALANCE
	maximum.owned_furnishings.storage_crate = SessionEconomy.MAX_BALANCE
	check(service.validate(JSON.parse_string(JSON.stringify(maximum))).is_empty(), "Supported maximum survives JSON")
	var state := SessionEconomy.new()
	check(state.restore(SessionEconomy.MAX_BALANCE, SessionEconomy.MAX_BALANCE), "Restore supported limits")
	check(not state.purchase_storage_crate(session.shop.storage_crate_price) and state.credits == SessionEconomy.MAX_BALANCE, "Full ownership rejects purchase without deduction")
	check(not state.return_storage_crate(), "Return cannot overflow")
	for pair in [[-1, 0], [0, -1], [SessionEconomy.MAX_BALANCE + 1, 0], [0, SessionEconomy.MAX_BALANCE + 1]]:
		check(not state.restore(pair[0], pair[1]) and state.credits == SessionEconomy.MAX_BALANCE, "Invalid restore leaves state intact")
	for price in [0, -1, SessionEconomy.MAX_BALANCE + 1]:
		check(not state.purchase_storage_crate(price), "Invalid purchase price rejected")
	state.restore(0, 0)
	check(not state.consume_storage_crate() and not state.purchase_storage_crate(1), "Balances cannot become negative")


func test_migration(base: Dictionary) -> void:
	for version in [1, 2]:
		var legacy := base.duplicate(true)
		legacy.save_version = version
		legacy.erase("credits")
		legacy.erase("owned_furnishings")
		if version == 1:
			legacy.erase("placed_crates")
			legacy.erase("next_placed_object_id")
		else:
			legacy.placed_crates = [{"persistent_id": "placed_object_000001", "object_type": "storage_crate", "location_id": "starter_ship", "grid_position": {"x": 2, "y": 3}, "rotation_quarters": 3, "inventory": []}]
			legacy.next_placed_object_id = 2
		fixture(legacy)
		await start()
		check(session.economy.credits == SessionEconomy.STARTING_CREDITS and session.economy.owned_storage_crates() == 0, "Legacy defaults V%d" % version)
		check(not session.save_service.dirty, "Legacy load remains clean")
		if version == 2:
			check(session.furnishings.crates.size() == 1 and session.furnishings.crates.placed_object_000001.rotation_quarters == 3, "V2 placed crate grandfathered")
			check(session.furnishings.remove_crate("placed_object_000001") and session.economy.owned_storage_crates() == 1, "Grandfathered empty crate returns ownership")
		var price: int = session.shop.storage_crate_price
		check(session.economy.purchase_storage_crate(price), "Legacy purchase")
		await create_timer(0.2).timeout
		check(not session.save_service.dirty, "Legacy purchase autosaves")
		await stop()
		await start()
		check(session.economy.credits == SessionEconomy.STARTING_CREDITS - price and session.economy.owned_storage_crates() == version, "V3 restart restores exact balance without top-up")
		check(session.save_service.capture().save_version == SaveService.SAVE_VERSION, "Migrated schema is current")
		await stop()
		legacy.credits = 17
		legacy.owned_furnishings = {"storage_crate": 2}
		fixture(legacy)
		await start()
		check(session.economy.credits == 17 and session.economy.owned_storage_crates() == 2, "Valid present legacy values retained")
		await stop()
	var corrupt := base.duplicate(true)
	corrupt.credits = -1
	fixture(corrupt)
	var original := FileAccess.get_file_as_string(directory.path_join("autosave.json"))
	await start()
	check(not session.save_service.writable and not session.save_service.flush(true), "Corrupt economy protects save")
	check(FileAccess.get_file_as_string(directory.path_join("autosave.json")) == original, "Corrupt save bytes untouched")
	await stop()


func process_phase(args: PackedStringArray) -> void:
	if args.size() != 2 or not args[1].begins_with("user://m5b_economy_") or ".." in args[1]:
		quit(1)
		return
	directory = args[1]
	await start()
	var price: int = session.shop.storage_crate_price
	if args[0] == "writer":
		check(session.economy.purchase_storage_crate(price) and session.economy.purchase_storage_crate(price), "Process purchases")
		var id: String = session.furnishings.create_crate(Vector2i(2, 3), 3)
		check(not id.is_empty(), "Process places crate")
		session.furnishings.crates[id].node.inventory.add_item(IRON, 9)
		await travel(session.MARS)
		session.economy.purchase_storage_crate(price)
	else:
		check(session.current_location == session.MARS and session.economy.credits == SessionEconomy.STARTING_CREDITS - price * 3 and session.economy.owned_storage_crates() == 2, "Fresh process resumes Mars economy")
		check(session.get_node("ResourceHUD/Resources/Credits").text == "Credits: %d C" % session.economy.credits, "Fresh process HUD displays exact persisted Credits")
		var record: Dictionary = session.furnishings.crates.placed_object_000001
		check(record.rotation_quarters == 3 and record.node.inventory.slots[0].quantity == 9 and session.furnishings.next_placed_object_id == 2, "Fresh process restores independent crate state")
		await travel(session.SHIP)
		check(not record.recovery and session.economy.owned_storage_crates() == 2, "V3 detached ship activates without consumption")
	print("M5B process %s: %d checks, %d failures" % [args[0], checks, failures])
	if failures:
		quit(1)
	else:
		session._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
