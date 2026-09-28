extends "res://tests/mining_test.gd"

var forced_roll := 1
var roll_calls := 0
var before_iron := 0
var observed_total := 0

func controlled_roll() -> int:
	roll_calls += 1
	return forced_roll

func ground_quantity() -> int:
	var result := 0
	for pickup: WorldPickup in deposit.overflow_store.pickups.values():
		result += pickup.quantity
	return result

func observe_reward() -> void:
	observed_total = count_iron() - before_iron + ground_quantity()
	check(observed_total == forced_roll and not deposit.is_available(), "Observer sees conserved reward and completed depletion")
	check(session.save_service.flush(), "Observer can save coherent completed reward")

func run() -> void:
	directory = "user://m5c_overflow_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	await start_session()
	await travel(session.MARS)
	deposit.yield_roller = Callable()
	for attempt in 20:
		check(deposit.roll_yield() in [1, 2, 3], "Production random roll bounded 1-3")
	deposit.yield_roller = controlled_roll
	interact()
	check(roll_calls == 0 and count_iron() == 0 and ground_quantity() == 0 and deposit.is_available(), "Missing tool performs no roll or reward")
	for roll in [1, 2, 3]:
		forced_roll = roll
		for free_space in [0, 1, 2, 3]:
			clear_inventory()
			deposit.overflow_store.restore({"next_id": 1, "pickups": []})
			deposit.restore(0.0)
			player.position = deposit.position + Vector2(0, 40)
			player.inventory.add_item(TOOL, 19)
			player.inventory.add_item(IRON, IRON.max_stack - free_space)
			before_iron = count_iron()
			player.inventory.changed.connect(observe_reward, CONNECT_ONE_SHOT)
			var calls_before := roll_calls
			interact()
			interact()
			check(roll_calls == calls_before and count_iron() == before_iron, "No roll until completion; duplicate E blocked")
			await finish_animation()
			check(roll_calls == calls_before + 1, "Exactly one roll per completed action")
			var expected_accepted := mini(free_space, roll)
			var expected_overflow: int = roll - expected_accepted
			check(count_iron() == before_iron + expected_accepted, "Inventory partial-acceptance result")
			check(ground_quantity() == expected_overflow, "Ground quantity matches remainder")
			check(deposit.overflow_store.pickups.size() == (1 if expected_overflow > 0 else 0), "At most one overflow stack per mining action")
			check(observed_total == roll, "No loss or duplication in transaction")
			if expected_overflow > 0:
				var pickup: WorldPickup = deposit.overflow_store.pickups.values()[0]
				check(pickup.item == IRON and pickup.position.distance_to(deposit.position) <= 40.0, "Canonical overflow spawns near mined rock")
				var query := PhysicsPointQueryParameters2D.new()
				query.position = pickup.global_position
				query.collision_mask = 1
				query.exclude = [player.get_rid(), deposit.get_rid()]
				check(player.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "Overflow position clear of world blockers")
	# Keep a full roll on the ground and verify retention plus save/reload.
	clear_inventory()
	player.inventory.add_item(TOOL, 20)
	deposit.restore(0.0)
	forced_roll = 3
	interact()
	await finish_animation()
	var retained: Dictionary = deposit.overflow_store.capture()
	check(ground_quantity() == 3, "Full inventory mines successfully into one ground stack")
	await travel(session.SHIP)
	await travel(session.MARS)
	check(deposit.overflow_store.capture() == retained, "Overflow survives location roundtrip")
	await stop_session()
	await start_session()
	check(deposit.overflow_store.capture() == retained and not deposit.is_available(), "Restart restores overflow and depleted rock")
	await stop_session()
	await start_session()
	check(deposit.overflow_store.capture() == retained, "Repeated reload never duplicates pickup")
	# Existing WorldPickup handles partial collection and publishes coherent state.
	clear_inventory()
	player.inventory.add_item(TOOL, 19)
	player.inventory.add_item(IRON, IRON.max_stack - 1)
	var pickup: WorldPickup = deposit.overflow_store.pickups.values()[0]
	var original_id := pickup.persistent_id
	player.inventory.changed.connect(func() -> void:
		check(count_iron() == IRON.max_stack and ground_quantity() == 2, "Partial collection observer sees both sides")
		check(session.save_service.flush(), "Partial collection saves coherently")
	, CONNECT_ONE_SHOT)
	pickup.get_node("Interactable").interact(player)
	check(pickup.quantity == 2 and pickup.persistent_id == original_id, "Partial collection keeps stable pickup identity")
	await stop_session()
	await start_session()
	check(ground_quantity() == 2 and count_iron() == IRON.max_stack, "Partial collection survives reload without duplication")
	player.inventory.slots[1].item = null
	player.inventory.slots[1].quantity = 0
	pickup = deposit.overflow_store.pickups.values()[0]
	player.inventory.changed.connect(func() -> void:
		check(count_iron() == IRON.max_stack + 2 and ground_quantity() == 0, "Final collection observer sees no ground remainder")
		check(session.save_service.flush(), "Final collection saves coherently")
	, CONNECT_ONE_SHOT)
	pickup.get_node("Interactable").interact(player)
	await process_frame
	check(not is_instance_valid(pickup), "Collected pickup removed")
	await stop_session()
	await start_session()
	check(ground_quantity() == 0 and count_iron() == IRON.max_stack + 2, "Collected overflow does not respawn after reload")
	# V1-V4 keep inventory while retiring mistaken scenery deadlines.
	for version in [1, 2, 3, 4]:
		var legacy: Dictionary = session.save_service.capture()
		legacy.save_version = version
		legacy.erase("mining_overflow")
		legacy.mining_nodes = {"mars_iron_deposit_01": Time.get_unix_time_from_system() + 60.0, "mars_iron_deposit_05": Time.get_unix_time_from_system() + 60.0}
		check(session.save_service.validate(legacy).is_empty(), "Legacy save accepted including old fifth scenery ID")
		await stop_session()
		var file := FileAccess.open(directory.path_join("autosave.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(legacy))
		file.close()
		await start_session()
		check(deposit.is_available() and ground_quantity() == 0 and count_iron() == IRON.max_stack + 2, "Migration preserves inventory and starts corrected rocks available")
	# Strict validation of the new world-state fields.
	var valid: Dictionary = session.save_service.capture()
	var entry := {"persistent_id": "mars_mining_overflow_1", "item_id": "iron_ore", "quantity": 3, "position": {"x": 384.0, "y": 224.0}}
	valid.mining_overflow = {"next_id": 2, "pickups": [entry]}
	check(session.save_service.validate(valid).is_empty(), "Valid overflow record accepted")
	for field in ["persistent_id", "item_id", "quantity", "position"]:
		var bad := valid.duplicate(true)
		bad.mining_overflow.pickups[0].erase(field)
		check(not session.save_service.validate(bad).is_empty(), "Missing overflow field rejected")
	for quantity in [0, 4, 1.5, true, "3"]:
		var bad := valid.duplicate(true)
		bad.mining_overflow.pickups[0].quantity = quantity
		check(not session.save_service.validate(bad).is_empty(), "Malformed overflow quantity rejected")
	for position in [{"x": INF, "y": 0}, {"x": -1, "y": 0}, {"x": 0, "y": 961}, {"x": true, "y": 0}]:
		var bad := valid.duplicate(true)
		bad.mining_overflow.pickups[0].position = position
		check(not session.save_service.validate(bad).is_empty(), "Malformed overflow position rejected")
	var duplicate := valid.duplicate(true)
	duplicate.mining_overflow.pickups.append(entry)
	check(not session.save_service.validate(duplicate).is_empty(), "Duplicate overflow identity rejected")
	duplicate = valid.duplicate(true)
	duplicate.mining_overflow.next_id = 1
	check(not session.save_service.validate(duplicate).is_empty(), "Reused counter rejected")
	duplicate.erase("mining_overflow")
	check(not session.save_service.validate(duplicate).is_empty(), "Missing V5 overflow state rejected")
	await stop_session()
	for name in ["autosave.json", "autosave.json.bak", "autosave.json.tmp"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("Mining overflow tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
