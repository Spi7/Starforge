extends Node

signal location_changed(location_id: StringName)

const SHIP: StringName = &"starter_ship"
const MARS: StringName = &"mars_landing_zone"
const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const SHIP_SCENE := preload("res://scenes/ship/starter_ship.tscn")
const MARS_SCENE := preload("res://scenes/mars/mars_landing_zone.tscn")

var player: Player
var ship: Node2D
var mars: Node2D
var current_location: StringName
var transitioning: bool = true

@onready var active_location: Node2D = $ActiveLocation
@onready var player_parking: Node2D = $PlayerParking


func _ready() -> void:
	_create_session()
	_activate_location(SHIP, &"PlayerStart")
	_finish_transition()


func _create_session() -> void:
	ship = SHIP_SCENE.instantiate()
	mars = MARS_SCENE.instantiate()
	player = PLAYER_SCENE.instantiate()
	player_parking.add_child(player)
	_lock_input()
	mars.get_node("Camera2D").target = player
	ship.get_node("AirlockExit").interacted.connect(_request_transition.bind(SHIP, MARS, &"ShipArrival"))
	mars.get_node("WorldObjects/LandedShip/ShipEntrance").interacted.connect(_request_transition.bind(MARS, SHIP, &"MarsReturnSpawn"))


func _request_transition(actor: Node, source: StringName, destination: StringName, spawn: StringName) -> void:
	if transitioning or actor != player or current_location != source or not player.controls_enabled:
		return
	transitioning = true
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
	while Input.is_action_pressed("interact"):
		await get_tree().process_frame
	player.get_node("InventoryUI").set_process_input(true)
	player.controls_enabled = true
	transitioning = false
	# Destination, spawn and camera are now established: a future autosave safe point.
	location_changed.emit(current_location)


func _exit_tree() -> void:
	# Detached nodes are not freed with this session's children automatically.
	for location in [ship, mars]:
		if is_instance_valid(location) and location.get_parent() == null:
			location.free()
