extends SceneTree

const SESSION := preload("res://scenes/game/game_session.tscn")
const IRON := preload("res://data/items/iron_ore.tres")
const TOOL := preload("res://data/items/basic_mining_tool.tres")
var checks := 0
var failures := 0
var session: Node
var deposit: MiningNode
var player: Player
var directory: String
var observed_complete := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func settle() -> void:
	for frame in 90:
		await physics_frame
		if not session.transitioning:
			return
	check(false, "Transition timeout")

func start_session() -> void:
	session = SESSION.instantiate()
	session.get_node("SaveService").save_directory = directory
	session.get_node("SaveService").coalesce_seconds = 0.05
	root.add_child(session)
	await settle()
	player = session.player
	deposit = session.mars.get_node("WorldObjects/Rock1")
	for node in session.mars.get_node("WorldObjects").get_children():
		if node is MiningNode:
			node.yield_roller = func() -> int: return 3

func stop_session() -> void:
	session.queue_free()
	await process_frame

func travel(destination: StringName) -> void:
	session._request_transition(player, session.current_location, destination, &"ShipArrival" if destination == session.MARS else &"MarsReturnSpawn")
	await settle()
	check(session.current_location == destination, "Travel completed")

func count_iron() -> int:
	var count := 0
	for slot in player.inventory.slots:
		if slot.item == IRON:
			count += slot.quantity
	return count

func clear_inventory() -> void:
	for slot in player.inventory.slots:
		slot.item = null
		slot.quantity = 0

func interact() -> void:
	deposit.get_node("Interactable").interact(player)

func finish_animation() -> void:
	player.animated_sprite.speed_scale = 30.0
	await player.animated_sprite.animation_finished
	player.animated_sprite.speed_scale = 1.0

func observe_commit() -> void:
	observed_complete = count_iron() == 3 and not deposit.is_available()
	check(observed_complete, "Inventory listeners see both completed sides")
	check(session.save_service.flush(), "Listener can save complete transaction")

func run() -> void:
	directory = "user://m5c_mining_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	await start_session()
	check(deposit.persistent_id == &"mars_iron_deposit_01", "Stable authored ID")
	check(deposit.item == IRON and deposit.roll_yield() == 3 and deposit.replenishment_seconds == 60.0, "Canonical configurable deposit")
	check(deposit.is_available(), "Fresh deposit available")
	await travel(session.MARS)
	interact()
	check(count_iron() == 0 and deposit.is_available(), "Missing tool leaves both sides unchanged")
	check(player.controls_enabled and not player._mining_animation_active, "Missing tool never starts action")
	check(player.get_node("InventoryUI/Feedback").text == "Basic Mining Tool required", "Tool feedback")
	player.inventory.add_item(TOOL, 19)
	player.inventory.add_item(IRON, 97)
	interact()
	await finish_animation()
	check(count_iron() == 99 and not deposit.is_available(), "Partial inventory capacity accepts two and depletes")
	check(deposit.overflow_store.pickups.size() == 1 and deposit.overflow_store.pickups.values()[0].quantity == 1, "Remaining ore becomes one pickup")
	deposit.overflow_store.restore({"next_id": 1, "pickups": []})
	deposit.restore(0.0)
	clear_inventory()
	player.inventory.add_item(TOOL, 1)
	player.position = deposit.position + Vector2(0, 40)
	await physics_frame
	await physics_frame
	player.inventory.changed.connect(observe_commit, CONNECT_ONE_SHOT)
	player.interact_with_nearest()
	check(player.animated_sprite.animation == &"mine_up", "Nearest interaction starts facing deposit")
	check(not player.controls_enabled and not player.get_node("InventoryUI").is_processing_input(), "Movement and inventory locked")
	check(not session._can_open_shop(), "Shop locked")
	session._enter_furnish_mode()
	check(not session.furnish_mode.active, "Furnish mode locked")
	Input.action_press("move_right")
	var before := player.position
	player._physics_process(0.1)
	Input.action_release("move_right")
	check(player.position == before and player.velocity == Vector2.ZERO, "Mining prevents movement")
	interact()
	check(count_iron() == 0, "Duplicate interaction has no early reward")
	var started := Time.get_unix_time_from_system()
	await finish_animation()
	check(count_iron() == 3 and not deposit.is_available(), "Exactly three ore and depletion at completion")
	check(observed_complete, "Commit observed")
	check(deposit.replenishment_deadline >= started + 60.0, "Deadline uses full 60 real seconds")
	check(player.controls_enabled and player.get_node("InventoryUI").is_processing_input(), "Controls restored")
	check(player.animated_sprite.animation == &"idle_up", "Matching idle restored")
	check(not deposit.get_node("Sprite2D").visible and not deposit.get_node("MiningPrompt").visible, "Visible depletion")
	interact()
	check(count_iron() == 3 and not player._mining_animation_active, "Depleted interaction rejected")
	var deadline := deposit.replenishment_deadline
	await travel(session.SHIP)
	check(deposit.replenishment_deadline == deadline, "Leaving Mars retains deadline")
	await stop_session()
	await start_session()
	check(session.current_location == session.SHIP and not deposit.is_available(), "Restart on ship restores detached depletion")
	check(count_iron() == 3, "Reload preserves reward exactly once")
	await travel(session.MARS)
	check(not deposit.is_available(), "Return to Mars still depleted before deadline")
	for offset in [Vector2(40, 0), Vector2(-40, 0), Vector2(0, -40), Vector2(40, 40)]:
		deposit.restore(0.0)
		player.position = deposit.position + offset
		interact()
		var facing: String = "left" if offset.x > 0 else ("right" if offset.x < 0 else "down")
		check(player.animated_sprite.animation == StringName("mine_" + facing), "Dominant axis facing " + facing)
		await finish_animation()
		check(player.animated_sprite.animation == StringName("idle_" + facing), "Matching completion idle " + facing)
	# Runtime wakeup uses a short fixture deadline without changing the authored duration.
	deposit.restore(Time.get_unix_time_from_system() + 0.2)
	check(not deposit.is_available(), "Future deadline not available early")
	await create_timer(0.8).timeout
	check(deposit.is_available() and deposit.get_node("Sprite2D").visible, "Runtime timer restores visual on Mars")
	deposit.restore(Time.get_unix_time_from_system() - 1.0)
	await travel(session.SHIP)
	await travel(session.MARS)
	check(deposit.is_available(), "Expired detached deadline refreshes on reentry")
	player.position = Vector2(384, 232)
	session.save_service.mark_dirty()
	check(session.save_service.flush(), "Expired deadline snapshot saved")
	var ore_before := count_iron()
	await stop_session()
	await start_session()
	check(deposit.is_available() and count_iron() == ore_before, "Restart after deadline available without new reward")
	check(player.position == Vector2(384, 232), "Mining position persists")
	for version in [1, 2, 3]:
		var legacy: Dictionary = session.save_service.capture()
		legacy.save_version = version
		legacy.erase("mining_nodes")
		check(session.save_service.validate(legacy).is_empty(), "Legacy version accepted: %d" % version)
		await stop_session()
		var file := FileAccess.open(directory.path_join("autosave.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(legacy))
		file.close()
		await start_session()
		check(deposit.is_available() and count_iron() == ore_before, "Legacy starts available preserving inventory")
	var snapshot: Dictionary = session.save_service.capture()
	check(snapshot.save_version == 5, "V5 snapshot")
	for invalid in [null, true, "123", -1, INF, NAN, 253402300800.0]:
		var bad := snapshot.duplicate(true)
		bad.mining_nodes.mars_iron_deposit_01 = invalid
		check(not session.save_service.validate(bad).is_empty(), "Invalid deadline rejected")
	var bad := snapshot.duplicate(true)
	bad.mining_nodes = {"unknown": 0}
	check(not session.save_service.validate(bad).is_empty(), "Unknown mining identity rejected")
	bad.erase("mining_nodes")
	check(not session.save_service.validate(bad).is_empty(), "Missing V4 mining state rejected")
	# Capacity can change during the animation without losing ore.
	deposit.restore(0.0)
	clear_inventory()
	player.inventory.add_item(TOOL, 1)
	interact()
	player.inventory.add_item(TOOL, 19)
	await finish_animation()
	check(count_iron() == 0 and not deposit.is_available() and player.controls_enabled, "Capacity lost during action produces overflow and depletion")
	check(deposit.overflow_store.pickups.size() == 1 and deposit.overflow_store.pickups.values()[0].quantity == 3, "Full completion yield retained on ground")
	deposit.overflow_store.restore({"next_id": 1, "pickups": []})
	deposit.restore(0.0)
	# Tool loss during animation and node removal both cancel safely.
	clear_inventory()
	player.inventory.add_item(TOOL, 1)
	interact()
	clear_inventory()
	await finish_animation()
	check(count_iron() == 0 and deposit.is_available() and player.controls_enabled, "Tool rechecked at completion")
	player.inventory.add_item(TOOL, 1)
	interact()
	var parent := deposit.get_parent()
	parent.remove_child(deposit)
	await finish_animation()
	check(count_iron() == 0 and player.controls_enabled, "Node removal cancels reward and restores controls")
	parent.add_child(deposit)
	# Exercise the unmodified 60-second authored duration and ordinary coalesced autosave.
	interact()
	await finish_animation()
	check(count_iron() == 3 and not deposit.is_available(), "Can mine again after cancellation")
	await create_timer(0.2).timeout
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("autosave.json")))
	check(saved.mining_nodes.mars_iron_deposit_01 == deposit.replenishment_deadline and not session.save_service.dirty, "Ordinary coalesced autosave captures completed mining")
	check(saved.player_inventory.any(func(entry: Dictionary) -> bool: return entry.item_id == "iron_ore" and entry.quantity == 3), "Autosave includes full reward")
	print("Mining: waiting for the actual 60-second authored replenishment deadline")
	await create_timer(58.0).timeout
	check(not deposit.is_available(), "Actual node remains depleted before 60 seconds")
	await create_timer(2.5).timeout
	check(deposit.is_available() and deposit.get_node("Sprite2D").visible, "Actual node visibly replenishes while remaining on Mars")
	await stop_session()
	for name in ["autosave.json", "autosave.json.bak", "autosave.json.tmp"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("Mining tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
