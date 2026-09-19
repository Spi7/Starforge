extends SceneTree

var checks := 0
var failures := 0
var session: Node
var player: Player
var completed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)

func settle() -> void:
	for frame in 90:
		await physics_frame
		if not session.transitioning:
			return
	check(false,"Transition completes within 90 frames")

func press_interact() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func travel(destination: StringName, hold: bool = false) -> void:
	var on_ship: bool = session.current_location == session.SHIP
	player.global_position = session.ship.to_global(Vector2(160,192)) if on_ship else Vector2(672,864)
	await physics_frame
	await physics_frame
	var before := completed
	press_interact()
	if hold:
		for frame in 6:
			await physics_frame
		check(session.transitioning and not player.controls_enabled,"Held E keeps transition locked")
		check(completed == before,"No completion or bounce while E is held")
		press_interact()
		var toggle := InputEventAction.new()
		toggle.action = &"inventory_toggle"
		toggle.pressed = true
		Input.parse_input_event(toggle)
		await process_frame
		check(not player.get_node("InventoryUI").panel.visible,"Inventory input blocked during transition")
	var release := InputEventAction.new()
	release.action = &"interact"
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await settle()
	check(session.current_location == destination,"Arrived at " + str(destination))
	check(completed == before+1,"Exactly one completed transition per press")
	var active: Node2D = session.ship if destination == session.SHIP else session.mars
	var inactive: Node2D = session.mars if destination == session.SHIP else session.ship
	var marker: Marker2D = active.get_node("MarsReturnSpawn" if destination == session.SHIP else "ShipArrival")
	check(player.global_position == marker.global_position,"Spawn at correct marker")
	check(player.get_parent() == active.get_node("WorldObjects"),"Persistent player is in active Y-sort group")
	check(session.active_location.get_child_count() == 1 and not inactive.is_inside_tree(),"Only active location is attached")
	check(root.get_camera_2d() == active.get_node("Camera2D"),"Correct current camera")
	check(session.find_children("*", "Camera2D", true, false).size() == 1,"Only one camera remains in the active tree")
	var resize_connections := 0
	for connection in root.size_changed.get_connections():
		if connection.callable.get_object() == session.mars.get_node("Camera2D"):
			resize_connections += 1
	check(resize_connections == (1 if destination == session.MARS else 0),"Mars resize subscription follows active lifetime")
	check(player.get_node("InventoryUI").player == player,"UI retains same player reference")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = player.get_node("CollisionShape2D").shape
	query.transform = player.global_transform
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	check(player.get_world_2d().direct_space_state.intersect_shape(query).is_empty(),"Spawn has physical clearance")
	var world_shape := RectangleShape2D.new()
	world_shape.size = Vector2(4096,4096)
	query.shape = world_shape
	query.transform = Transform2D(0,Vector2(640,480))
	query.collision_mask = 3
	query.collide_with_areas = true
	var inactive_collision := false
	for hit in player.get_world_2d().direct_space_state.intersect_shape(query,512):
		if inactive.is_ancestor_of(hit.collider):
			inactive_collision = true
	check(not inactive_collision,"Inactive location has no bodies or interaction areas in active physics world")
	await physics_frame
	check(session.current_location == destination and completed == before+1,"Spawn does not automatically retrigger")

func snapshot(inventory: InventoryData) -> Array:
	var result: Array = []
	for slot in inventory.slots:
		result.append([slot.item.id if slot.item != null else &"",slot.quantity])
	return result

func count_type(node: Node, type_name: String) -> int:
	var count := 1 if (node is Player if type_name == "Player" else node.name == "InventoryUI") else 0
	for child in node.get_children():
		count += count_type(child,type_name)
	return count

func run() -> void:
	session = load("res://scenes/game/game_session.tscn").instantiate()
	session.persistence_enabled = false
	root.add_child(session)
	player = session.player
	await settle()
	session.location_changed.connect(func(_id: StringName) -> void: completed += 1)
	check(session.current_location == session.SHIP,"New session starts inside ship")
	check(player.position == Vector2(160,168),"Initial ship spawn preserved")
	var ship: Node2D = session.ship
	var mars: Node2D = session.mars
	var inventory := player.inventory
	var storage: ShipStorage = ship.get_node("WorldObjects/Crate")
	var stored := storage.inventory
	var ui := player.get_node("InventoryUI")
	var iron: ItemDefinition = load("res://data/items/iron_ore.tres")
	var tool: ItemDefinition = load("res://data/items/basic_mining_tool.tres")
	inventory.add_item(iron,50)
	ui.open_storage(stored,"Ship Storage")
	ui.player_list.select(0)
	ui.deposit_button.pressed.emit()
	check(stored.slots[0].quantity == 50,"Existing storage UI deposits successfully")
	stored.transfer_to(inventory,0,30)
	ui.close()
	var expected_inventory := snapshot(inventory)
	var expected_storage := snapshot(stored)
	var addition := Node2D.new()
	addition.name = "RuntimeFixture"
	ship.get_node("WorldObjects").add_child(addition)
	var ship_pickup: WorldPickup = ship.get_node("WorldObjects/ToolPickup")
	ship_pickup.get_node("Interactable").interact(player)
	await process_frame
	expected_inventory = snapshot(inventory)
	for round_trip in 5:
		await travel(session.MARS,round_trip==0)
		root.size = Vector2i(1280,720) if round_trip%2==0 else Vector2i(960,540)
		await travel(session.SHIP)
		check(session.player == player and player.inventory == inventory,"Same player and inventory identity")
		check(session.ship == ship and session.mars == mars,"Same two location instances")
		check(storage.inventory == stored and ship.get_node("WorldObjects/Crate") == storage,"Same storage node and inventory")
		check(snapshot(inventory) == expected_inventory and snapshot(stored) == expected_storage,"Player contents and 20 stored iron preserved")
		check(count_type(session,"Player") == 1 and count_type(session,"InventoryUI") == 1,"Exactly one Player and UI")
		check(not is_instance_valid(ship_pickup),"Collected ship pickup stays removed")
		check(addition.get_parent() == ship.get_node("WorldObjects"),"Runtime ship addition survives")
		check(ship.get_node("AirlockExit").interacted.get_connections().size() == 1,"No accumulating airlock connections")
		check(mars.get_node("WorldObjects/LandedShip/ShipEntrance").interacted.get_connections().size() == 1,"No accumulating entrance connections")
	# Mars has no production pickups: fixtures exercise both removal and partial acceptance.
	await travel(session.MARS)
	var pickup: WorldPickup = load("res://scenes/items/world_pickup.tscn").instantiate()
	pickup.item = iron
	pickup.quantity = 1
	mars.get_node("WorldObjects").add_child(pickup)
	pickup.get_node("Interactable").interact(player)
	await process_frame
	check(not is_instance_valid(pickup),"Mars fixture pickup collected")
	for slot in inventory.slots:
		slot.item = null
		slot.quantity = 0
	inventory.add_item(iron,90)
	inventory.add_item(tool,19)
	var partial: WorldPickup = load("res://scenes/items/world_pickup.tscn").instantiate()
	partial.item = iron
	partial.quantity = 20
	mars.get_node("WorldObjects").add_child(partial)
	partial.get_node("Interactable").interact(player)
	check(partial.quantity == 11,"Partial pickup accepts nine, leaves eleven")
	await travel(session.SHIP)
	root.size = Vector2i(1024,768)
	await process_frame
	await travel(session.MARS)
	check(not is_instance_valid(pickup) and partial.quantity == 11,"Mars removal and partial quantity survive re-entry")
	check(player.inventory == inventory,"Partial pickup still uses original inventory")
	await travel(session.SHIP)
	# Nearest interaction and transfer UI still work after all round trips.
	player.global_position = storage.get_node("Interactable").global_position + Vector2(0,24)
	await physics_frame
	await physics_frame
	player.interact_with_nearest()
	check(ui.panel.visible and ui.storage == stored,"Nearest storage interaction works after transitions")
	ui.close()
	var ship_ref: WeakRef = weakref(ship)
	var mars_ref: WeakRef = weakref(mars)
	var player_ref: WeakRef = weakref(player)
	session.queue_free()
	await process_frame
	check(ship_ref.get_ref()==null and mars_ref.get_ref()==null and player_ref.get_ref()==null,"Teardown frees active and detached instances")
	print("M4.5 tests: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
