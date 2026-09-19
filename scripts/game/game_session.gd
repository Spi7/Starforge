extends Node

signal location_changed(location_id: StringName)

const SHIP: StringName = &"starter_ship"
const MARS: StringName = &"mars_landing_zone"
const SHIP_STORAGE_ID: String = "starter_ship_storage_01"
const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const SHIP_SCENE := preload("res://scenes/ship/starter_ship.tscn")
const MARS_SCENE := preload("res://scenes/mars/mars_landing_zone.tscn")

var player: Player
var ship: Node2D
var mars: Node2D
var current_location: StringName
var transitioning: bool = true
@export var persistence_enabled: bool = true
var _starting: bool = true
var _previous_auto_quit: bool = true
var _observed_position: Vector2
var _completed_position: Vector2

@onready var save_service: SaveService = $SaveService
@onready var active_location: Node2D = $ActiveLocation
@onready var player_parking: Node2D = $PlayerParking


func _ready() -> void:
	_create_session()
	var storage: ShipStorage = ship.get_node("WorldObjects/Crate")
	storage.ensure_inventory()
	var pickups: Array[WorldPickup] = []
	for child in ship.get_node("WorldObjects").get_children():
		if child is WorldPickup:
			pickups.append(child)
	save_service.enabled = persistence_enabled
	save_service.status_changed.connect(player.get_node("InventoryUI").show_save_status)
	save_service.bind_state(player.inventory, {SHIP_STORAGE_ID: storage.inventory}, pickups)
	save_service.position_provider = _position_for_save
	var destination := StringName(save_service.load_game())
	location_changed.connect(_on_location_changed)
	$PositionCheckTimer.timeout.connect(_check_position)
	_previous_auto_quit = get_tree().auto_accept_quit
	if persistence_enabled:
		get_tree().auto_accept_quit = false
	_activate_location(destination, &"ShipArrival" if destination == MARS else &"PlayerStart")
	_finish_transition()


func _create_session() -> void:
	ship = SHIP_SCENE.instantiate()
	mars = MARS_SCENE.instantiate()
	player = PLAYER_SCENE.instantiate()
	player.controls_enabled = false
	player_parking.add_child(player)
	_lock_input()
	mars.get_node("Camera2D").target = player
	ship.get_node("AirlockExit").interacted.connect(_request_transition.bind(SHIP, MARS, &"ShipArrival"))
	mars.get_node("WorldObjects/LandedShip/ShipEntrance").interacted.connect(_request_transition.bind(MARS, SHIP, &"MarsReturnSpawn"))


func _request_transition(actor: Node, source: StringName, destination: StringName, spawn: StringName) -> void:
	if transitioning or actor != player or current_location != source or not player.controls_enabled:
		return
	_completed_position = _local_position()
	transitioning = true
	save_service.safe_to_save = false
	_lock_input()
	_switch_location.call_deferred(destination, spawn)


func _lock_input() -> void:
	var ui := player.get_node("InventoryUI")
	ui.close()
	ui.set_process_input(false)
	player.controls_enabled = false
	player.velocity = Vector2.ZERO


func _switch_location(destination: StringName, spawn: StringName) -> void:
	var outgoing := active_location.get_child(0)
	player.reparent(player_parking)
	outgoing.get_node("Camera2D").enabled = false
	active_location.remove_child(outgoing)
	_activate_location(destination, spawn)
	_finish_transition()


func _activate_location(destination: StringName, spawn: StringName) -> void:
	var location: Node2D = ship if destination == SHIP else mars
	active_location.add_child(location)
	player.reparent(location.get_node("WorldObjects"))
	player.global_position = location.get_node(NodePath(spawn)).global_position
	player.velocity = Vector2.ZERO
	var camera: Camera2D = location.get_node("Camera2D")
	if destination == MARS:
		camera.global_position = player.global_position.round()
	camera.enabled = true
	camera.make_current()
	camera.reset_smoothing()
	camera.force_update_scroll()
	current_location = destination


func _finish_transition() -> void:
	# Give interaction overlaps time to refresh after reparenting/teleporting.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if _starting and _valid_position(save_service.player_position):
		var data: Dictionary = save_service.player_position
		var location: Node2D = ship if current_location == SHIP else mars
		player.global_position = location.to_global(Vector2(data.x, data.y))
		var camera: Camera2D = location.get_node("Camera2D")
		if current_location == MARS:
			camera.global_position = player.global_position.round()
		camera.reset_smoothing()
		camera.force_update_scroll()
		# Refresh interaction overlaps at the restored position before accepting input.
		await get_tree().physics_frame
		await get_tree().physics_frame
	while Input.is_action_pressed("interact"):
		await get_tree().process_frame
	player.get_node("InventoryUI").set_process_input(true)
	player.controls_enabled = true
	transitioning = false
	# Destination, spawn and camera are now established.
	location_changed.emit(current_location)


func _on_location_changed(location: StringName) -> void:
	_observed_position = _local_position()
	_completed_position = _observed_position
	save_service.complete_location(String(location), _starting)
	_starting = false
	if persistence_enabled:
		$PositionCheckTimer.start()


func _local_position() -> Vector2:
	var location: Node2D = ship if current_location == SHIP else mars
	return location.to_local(player.global_position)


func _position_for_save() -> Dictionary:
	# Never pair a destination position with the last completed source location.
	var position := _completed_position if transitioning else _local_position()
	if not transitioning:
		if _valid_position({"x": position.x, "y": position.y}):
			_completed_position = position
		else:
			position = _completed_position
	return {"x": position.x, "y": position.y}


func _check_position() -> void:
	if transitioning:
		return
	var position := _local_position()
	if position.distance_squared_to(_observed_position) >= 1.0:
		_observed_position = position
		save_service.mark_dirty()


func _valid_position(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for axis in ["x", "y"]:
		var value: Variant = data.get(axis)
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
	var position := Vector2(data.x, data.y)
	# Current map extents, inset by the player's 12px collision half-size.
	var bounds := Rect2(12, 12, 296, 200) if current_location == SHIP else Rect2(12, 12, 1256, 936)
	if not position.is_finite() or not bounds.has_point(position):
		return false
	var location: Node2D = ship if current_location == SHIP else mars
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = player.get_node("CollisionShape2D").shape
	query.transform = Transform2D(0, location.to_global(position))
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	return player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and persistence_enabled and is_node_ready():
		if not transitioning and _valid_position(_position_for_save()):
			# Bypass the sampling interval, including sub-pixel movement, on normal close.
			if _local_position() != _observed_position:
				save_service.mark_dirty()
		# Capture before teardown; an unfinished transition uses the last completed location.
		save_service.flush(true)
		get_tree().quit()


func _exit_tree() -> void:
	if persistence_enabled and is_node_ready():
		get_tree().auto_accept_quit = _previous_auto_quit
	# Detached nodes are not freed with this session's children automatically.
	for location in [ship, mars]:
		if is_instance_valid(location) and location.get_parent() == null:
			location.free()
