extends SceneTree

var failures: int = 0
var checks: int = 0
var scene: Node2D
var player: Player


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)


func run() -> void:
	scene = load("res://scenes/mars/mars_landing_zone.tscn").instantiate()
	root.add_child(scene)
	player = load("res://scenes/characters/player.tscn").instantiate()
	scene.get_node("WorldObjects").add_child(player)
	player.position = scene.get_node("ShipArrival").position
	scene.get_node("Camera2D").target = player
	await physics_frame
	await physics_frame
	check(player.position == scene.get_node("ShipArrival").position, "Player starts at ship arrival")
	await test_movement()
	test_collisions()
	test_walkable_routes()
	test_cliff_tops_and_ground()
	await test_camera()
	check(scene.get_node("WorldObjects").y_sort_enabled, "World objects share Y-sorting")
	check(player.get_node("InventoryUI") != null, "Existing inventory UI is instanced")
	print("M4 tests: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)


func test_movement() -> void:
	var start := player.position
	Input.action_press("move_right")
	for frame in 12:
		await physics_frame
	Input.action_release("move_right")
	await physics_frame
	check(player.position.x > start.x + 20, "Input Map movement works on arrival pad")
	player.position = start
	player.set_physics_process(false)


func expect_blocked(start: Vector2, motion: Vector2, description: String, collider_name: String = "") -> void:
	player.position = start
	var hit := player.move_and_collide(motion)
	check(hit != null, description)
	if hit != null and not collider_name.is_empty():
		check(hit.get_collider().name == collider_name, description + " hits intended obstacle")


func test_collisions() -> void:
	expect_blocked(Vector2(656,160), Vector2(0,-140), "Mining Basin is blocked", "MiningBasinBarrier")
	expect_blocked(Vector2(1120,400), Vector2(160,0), "Red Canyon is blocked", "RedCanyonBarrier")
	expect_blocked(Vector2(672,864), Vector2(0,-160), "Ship hull is solid", "LandedShip")
	expect_blocked(Vector2(256,560), Vector2(0,-100), "Depot base is solid", "SupplyDepot")
	expect_blocked(Vector2(256,392), Vector2(0,100), "Depot roof footprint blocks entry from north", "SupplyDepot")
	expect_blocked(Vector2(784,420), Vector2(0,-70), "Terminal base is solid", "RequestTerminal")
	expect_blocked(Vector2(672,912), Vector2(0,100), "Southern cliffs are solid")
	# Test the perimeter independently, including the scenery beyond the barriers.
	expect_blocked(Vector2(656,16), Vector2(0,-64), "North perimeter is sealed", "BoundaryCollision")
	expect_blocked(Vector2(1264,400), Vector2(64,0), "East perimeter is sealed", "BoundaryCollision")
	var boundary: StaticBody2D = scene.get_node("BoundaryCollision")
	for child in boundary.get_children():
		check(child is CollisionShape2D and not child.disabled, "Active perimeter collider: " + child.name)
	player.position = Vector2(672,864)
	check(player.move_and_collide(Vector2(0,-48)) == null, "South entrance approach is reachable")


func test_walkable_routes() -> void:
	# Flood-fill actual physics clearance, using the player's full footprint.
	# Sampling every 16px is tighter than the requested 64px walking passages.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = player.get_node("CollisionShape2D").shape
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var space := scene.get_world_2d().direct_space_state
	var accessible: Dictionary[Vector2i, bool] = {}
	for y in range(0,61):
		for x in range(0,81):
			query.transform = Transform2D(0,Vector2(x*16,y*16))
			if space.intersect_shape(query,1).is_empty():
				accessible[Vector2i(x,y)] = true
	var start := Vector2i(42,54)
	var reached: Dictionary[Vector2i, bool] = {start:true}
	var previous: Dictionary[Vector2i, Vector2i] = {}
	var queue: Array[Vector2i] = [start]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if accessible.has(next) and not reached.has(next):
				reached[next] = true
				previous[next] = cell
				queue.append(next)
	# Landmark approaches plus a circuit on both sides of the ship and near each
	# irregular boundary. Replay physics movement along the discovered clear paths.
	for destination in [Vector2i(42,51),Vector2i(16,34),Vector2i(49,26),Vector2i(29,17),Vector2i(41,10),Vector2i(70,25),Vector2i(25,44),Vector2i(60,44),Vector2i(14,43),Vector2i(67,35),Vector2i(16,12)]:
		check(reached.has(destination), "Arrival connects to landmark approach at " + str(destination*16))
		if reached.has(destination):
			var steps: Array[Vector2i] = []
			var cursor: Vector2i = destination
			while cursor != start:
				steps.append(cursor)
				cursor = previous[cursor]
			steps.reverse()
			player.position = Vector2(start*16)
			var obstructed := false
			for step in steps:
				if player.move_and_collide(Vector2(step*16)-player.position) != null:
					obstructed = true
					break
			check(not obstructed, "Player walks entire route to " + str(destination*16))
	check(not reached.has(Vector2i(41,2)), "Cannot bypass north barrier")
	check(not reached.has(Vector2i(78,25)), "Cannot bypass east barrier")
	var escaped := false
	for cell in reached:
		if cell.x == 0 or cell.y == 0 or cell.x == 80 or cell.y == 60:
			escaped = true
	check(not escaped, "No reachable path escapes the map perimeter")
	var clearance := RectangleShape2D.new()
	clearance.size = Vector2(64,64)
	query.shape = clearance
	for point in [Vector2(416,544),Vector2(960,656),Vector2(656,240),Vector2(1056,400),Vector2(672,432)]:
		query.transform = Transform2D(0,point)
		check(space.intersect_shape(query,1).is_empty(), "64px walking clearance at " + str(point))


func test_cliff_tops_and_ground() -> void:
	var space := scene.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var cliffs: Node2D = scene.get_node("WorldObjects/CliffVisuals")
	for bank in cliffs.get_children():
		check(bank.y_sort_enabled, "Cliff bank participates in ground-contact sorting")
		for sprite: Sprite2D in bank.get_children():
			# Each approved cliff has its visible plateau near the upper center.
			var top := sprite.global_position + sprite.offset + Vector2(sprite.texture.get_width()/2.0,16)
			if Rect2(0,0,1280,960).has_point(top):
				query.position = top
				check(not space.intersect_point(query,1).is_empty(), "Cliff top is blocked: " + str(sprite.get_path()))
	var ground: TileMapLayer = scene.get_node("Ground")
	var complete := true
	for y in 30:
		for x in 40:
			if ground.get_cell_source_id(Vector2i(x,y)) == -1:
				complete = false
	check(complete, "Flat ground covers every map cell beneath scenery")


func test_camera() -> void:
	var camera: Camera2D = scene.get_node("Camera2D")
	root.content_scale_size = Vector2i.ZERO
	for viewport_size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,1000),Vector2i(540,960)]:
		root.size = viewport_size
		await process_frame
		camera._update_limits()
		for position in [Vector2(112,240),Vector2(672,864),Vector2(1120,400)]:
			player.position = position
			camera._process(0)
			camera.force_update_scroll()
			var center := camera.get_screen_center_position()
			var half := Vector2(viewport_size)/2
			var expected := Vector2(
				clampf(position.x,half.x,1280-half.x) if viewport_size.x<=1280 else 640.0,
				clampf(position.y,half.y,960-half.y) if viewport_size.y<=960 else 480.0)
			check(center.distance_to(expected)<2, "Camera follows/clamps at " + str(viewport_size) + ": " + str(position))
	check(camera.zoom == Vector2.ONE, "Camera preserves native 1x zoom")
