extends "res://tests/mining_test.gd"

const MINERAL_TEXTURE := preload("res://assets/sprites/mars/mars_mineral_outcrops_64x32.png")
const ROCK_TEXTURE := preload("res://assets/sprites/mars/mars_rocks_96x32.png")
const AUTHORED := {
	"Rock1": ["mars_iron_deposit_01", Vector2(384, 192), Rect2(32, 0, 32, 32)],
	"Rock0": ["mars_iron_deposit_05", Vector2(192, 344), Rect2(0, 0, 32, 32)],
	"Rock2": ["mars_iron_deposit_06", Vector2(928, 200), Rect2(64, 0, 32, 32)],
	"Rock3": ["mars_iron_deposit_07", Vector2(224, 632), Rect2(0, 0, 32, 32)],
	"Rock4": ["mars_iron_deposit_02", Vector2(432, 200), Rect2(32, 0, 32, 32)],
	"Rock5": ["mars_iron_deposit_08", Vector2(1104, 336), Rect2(64, 0, 32, 32)],
	"Rock6": ["mars_iron_deposit_09", Vector2(336, 664), Rect2(0, 0, 32, 32)],
	"Rock7": ["mars_iron_deposit_03", Vector2(224, 808), Rect2(32, 0, 32, 32)],
	"Rock8": ["mars_iron_deposit_10", Vector2(1072, 520), Rect2(64, 0, 32, 32)],
	"Rock9": ["mars_iron_deposit_11", Vector2(1104, 744), Rect2(0, 0, 32, 32)],
	"Rock10": ["mars_iron_deposit_04", Vector2(992, 272), Rect2(32, 0, 32, 32)],
	"Rock11": ["mars_iron_deposit_12", Vector2(816, 184), Rect2(64, 0, 32, 32)],
	"Rock12": ["mars_iron_deposit_13", Vector2(352, 888), Rect2(0, 0, 32, 32)],
}

func update_overlaps() -> void:
	await physics_frame
	await physics_frame
	player._update_mining_prompt()

func run() -> void:
	directory = "user://m5c_revision_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	await start_session()
	await travel(session.MARS)
	var minerals := 0
	var ids := {}
	for sprite in session.mars.find_children("*", "Sprite2D", true, false):
		if sprite.texture != ROCK_TEXTURE:
			check(not sprite.get_parent() is MiningNode and not sprite.get_parent().has_node("MiningPrompt"), "Other textures remain scenery without mining prompts")
		if sprite.texture != ROCK_TEXTURE:
			continue
		minerals += 1
		var node := sprite.get_parent() as MiningNode
		check(node != null, "Every matching sprite belongs to MiningNode")
		if node == null:
			continue
		check(AUTHORED.has(String(node.name)), "No additional matching rocks")
		check(node.position == AUTHORED[String(node.name)][1], "Authored position preserved")
		check(sprite.region_rect == AUTHORED[String(node.name)][2], "Original visual variant preserved")
		check(String(node.persistent_id) == AUTHORED[String(node.name)][0] and not ids.has(node.persistent_id), "Stable unique ID")
		ids[node.persistent_id] = true
		check(node.item == IRON and node.roll_yield() == 3 and node.replenishment_seconds == 60.0, "Canonical authored values")
		node.get_node("Interactable").interact(player)
		check(node.is_available() and count_iron() == 0 and player.controls_enabled, "Every deposit requires tool")
	check(minerals == 13, "All 13 spritesheet instances covered regardless of region")
	check(session.mars.find_children("*", "MiningNode", true, false).size() == minerals, "Texture instance count equals MiningNode count; zero missing or extra")
	player.inventory.add_item(TOOL, 1)
	player.position = Vector2(672, 864)
	await update_overlaps()
	for name: String in AUTHORED:
		check(not session.mars.get_node("WorldObjects/" + name + "/MiningPrompt").visible, "Far prompt hidden")
	player.position = deposit.position + Vector2(0, 40)
	await update_overlaps()
	check(deposit.get_node("MiningPrompt").visible, "Near prompt visible")
	check(deposit.get_node("MiningPrompt").text == "Iron Ore\n[E] Mine", "Exact contextual prompt")
	player.position = Vector2(408, 225)
	await update_overlaps()
	var prompt_count := 0
	for name: String in AUTHORED:
		if session.mars.get_node("WorldObjects/" + name + "/MiningPrompt").visible:
			prompt_count += 1
	check(prompt_count == 1, "Overlapping range shows only nearest prompt")
	check(player.nearest_interactable().get_parent().get_node("MiningPrompt").visible, "Prompt matches interaction selection")
	player.position = Vector2(672, 864)
	await update_overlaps()
	check(not deposit.get_node("MiningPrompt").visible, "Leaving range hides prompt")
	var first_deadline := 0.0
	for name: String in AUTHORED:
		deposit = session.mars.get_node("WorldObjects/" + name)
		player.position = deposit.position + Vector2(0, 40)
		await update_overlaps()
		var before := count_iron()
		interact()
		await finish_animation()
		await update_overlaps()
		check(count_iron() == before + 3, "Each deposit rewards exactly three")
		check(not deposit.get_node("Sprite2D").visible and not deposit.get_node("MiningPrompt").visible, "Harvest removes visual and UI")
		check(deposit.collision_layer == 0 and deposit.get_node("CollisionShape2D").disabled, "No invisible physical obstacle")
		check(deposit.get_node("Interactable").collision_layer == 0 and deposit.get_node("Interactable/CollisionShape2D").disabled, "Interaction disabled")
		check(not deposit.has_node("StateLabel") and not "Depleted" in deposit.get_node("MiningPrompt").text, "No depleted label")
		interact()
		check(count_iron() == before + 3 and player.controls_enabled, "Unavailable cannot mine again")
		if name == "Rock1":
			first_deadline = deposit.replenishment_deadline
			for other: String in AUTHORED:
				if other != name:
					check(session.mars.get_node("WorldObjects/" + other).replenishment_deadline == 0.0, "Other deposit unaffected")
		else:
			check(deposit.replenishment_deadline > first_deadline, "Later mining has independent later deadline")
	var deadlines: Dictionary = session.save_service.capture().mining_nodes
	await travel(session.SHIP)
	await stop_session()
	await start_session()
	check(session.save_service.capture().mining_nodes == deadlines, "Multiple independent deadlines survive restart on Ship")
	await travel(session.MARS)
	for name: String in AUTHORED:
		var node: MiningNode = session.mars.get_node("WorldObjects/" + name)
		check(not node.is_available() and not node.get_node("Sprite2D").visible, "Every depleted deposit restored hidden")
	# Short fixture deadlines exercise separate runtime wakeups, including detached Mars.
	var other: MiningNode = session.mars.get_node("WorldObjects/Rock4")
	deposit.restore(Time.get_unix_time_from_system() + 0.15)
	other.restore(Time.get_unix_time_from_system() + 2.0)
	await create_timer(0.7).timeout
	await update_overlaps()
	check(deposit.get_node("Sprite2D").visible and not other.get_node("Sprite2D").visible, "Separate deadlines replenish independently")
	check(deposit.collision_layer == 1 and not deposit.get_node("CollisionShape2D").disabled, "Collision restored")
	check(deposit.get_node("Interactable").collision_layer == 2 and not deposit.get_node("Interactable/CollisionShape2D").disabled, "Interaction restored")
	player.position = deposit.position + Vector2(0, 40)
	await update_overlaps()
	check(deposit.get_node("MiningPrompt").visible, "Prompt returns after replenishment")
	await travel(session.SHIP)
	await create_timer(2.0).timeout
	await travel(session.MARS)
	check(other.get_node("Sprite2D").visible, "Deadline passes while Mars detached")
	var sparse: Dictionary = session.save_service.capture()
	sparse.mining_nodes = {"mars_iron_deposit_01": Time.get_unix_time_from_system() + 60.0}
	check(session.save_service.validate(sparse).is_empty(), "Sparse V5 save accepted")
	await stop_session()
	var file := FileAccess.open(directory.path_join("autosave.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(sparse))
	file.close()
	await start_session()
	for name: String in AUTHORED:
		var node: MiningNode = session.mars.get_node("WorldObjects/" + name)
		check(node.is_available() == (name != "Rock1"), "Missing IDs available; original deadline retained")
	for version in [1, 2, 3]:
		var legacy: Dictionary = session.save_service.capture()
		legacy.save_version = version
		legacy.erase("mining_nodes")
		check(session.save_service.validate(legacy).is_empty(), "Legacy valid")
		await stop_session()
		file = FileAccess.open(directory.path_join("autosave.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(legacy))
		file.close()
		await start_session()
		for name: String in AUTHORED:
			check(session.mars.get_node("WorldObjects/" + name).is_available(), "Legacy makes every deposit available")
	await stop_session()
	for name in ["autosave.json", "autosave.json.bak", "autosave.json.tmp"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("Mining revision tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
