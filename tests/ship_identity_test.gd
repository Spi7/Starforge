extends SceneTree

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func run() -> void:
	var ship: Node2D = load("res://scenes/ship/starter_ship.tscn").instantiate()
	root.add_child(ship)
	var player: Player = load("res://scenes/characters/player.tscn").instantiate()
	ship.get_node("WorldObjects").add_child(player)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame
	var floor_layer: TileMapLayer = ship.get_node("Floor")
	for cell in floor_layer.get_used_cells():
		check(cell.x >= 0 and cell.x <= 9 and cell.y >= 0 and cell.y <= 6, "Floor stays inside original cabin")
	# Sweep the actual player collider against every section of the perimeter.
	for y in range(44, 181, 8):
		check_blocked(player, Vector2(16, y), Vector2(-200, 0), ship)
		check_blocked(player, Vector2(304, y), Vector2(200, 0), ship)
	for x in range(48, 273, 8):
		check_blocked(player, Vector2(x, 16), Vector2(0, -200), ship)
	for x in range(80, 241, 8):
		check_blocked(player, Vector2(x, 208), Vector2(0, 200), ship)
	for x in [16, 48, 272, 304]:
		check_blocked(player, Vector2(x, 176), Vector2(0, 200), ship)
	for corner in [Vector2(48, 48), Vector2(272, 48), Vector2(80, 176), Vector2(240, 176)]:
		var direction := Vector2(-1 if corner.x < 160 else 1, -1 if corner.y < 112 else 1)
		check_blocked(player, corner, direction * 200, ship)
	# Approach each closed door with the normal movement Input Map action.
	for left in [true, false]:
		player.position = Vector2(16 if left else 304, 144)
		var action: StringName = &"move_left" if left else &"move_right"
		Input.action_press(action)
		for frame in range(12):
			await physics_frame
			player._physics_process(1.0 / 60.0)
		Input.action_release(action)
		check(player.position.x >= 11.9 and player.position.x <= 308.1, "Locked door blocks movement")
	for pickup_name in ["IronPickup", "CopperPickup", "NutrientPickup", "ToolPickup"]:
		var pickup: WorldPickup = ship.get_node("WorldObjects/" + pickup_name)
		player.position = pickup.position + Vector2(0, 24)
		await physics_frame
		await physics_frame
		player.interact_with_nearest()
		check(pickup.is_queued_for_deletion(), pickup_name + " is reachable through nearest interaction")
		await process_frame
	var capture_args := OS.get_cmdline_user_args()
	if not capture_args.is_empty():
		# Optional rendered QA; invoke without --headless and pass an output directory.
		ship.free()
		ship = load("res://scenes/ship/starter_ship.tscn").instantiate()
		root.add_child(ship)
		player = load("res://scenes/characters/player.tscn").instantiate()
		ship.get_node("WorldObjects").add_child(player)
		player.set_physics_process(false)
		player.position = Vector2(160, 168)
		for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1024, 768)]:
			root.size = window_size
			await process_frame
			await RenderingServer.frame_post_draw
			var path: String = capture_args[0].path_join("ship_%dx%d.png" % [window_size.x, window_size.y])
			check(root.get_texture().get_image().save_png(path) == OK, "Save rendered ship")
		root.size = Vector2i(960, 540)
		for pose in [Vector2(160, 54), Vector2(160, 96), Vector2(48, 86), Vector2(48, 130), Vector2(272, 96), Vector2(272, 138)]:
			player.position = pose
			await process_frame
			await RenderingServer.frame_post_draw
			var path: String = capture_args[0].path_join("sorting_%d_%d.png" % [pose.x, pose.y])
			check(root.get_texture().get_image().save_png(path) == OK, "Save sorting pose")
	print("M3.5 tests: %d checks, %d failures" % [checks, failures])
	ship.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)


func check_blocked(player: Player, start: Vector2, motion: Vector2, ship: Node2D) -> void:
	var start_transform := Transform2D(0.0, ship.to_global(start))
	check(player.test_move(start_transform, motion), "Sealed boundary from %s toward %s" % [start, motion])
