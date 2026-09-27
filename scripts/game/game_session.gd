extends Node

signal location_changed(location_id: StringName)

const SHIP: StringName = &"starter_ship"
const MARS: StringName = &"mars_landing_zone"
const SHIP_STORAGE_ID: String = "starter_ship_storage_01"
const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const SHIP_SCENE := preload("res://scenes/ship/starter_ship.tscn")
const MARS_SCENE := preload("res://scenes/mars/mars_landing_zone.tscn")

var economy := SessionEconomy.new()
var _closing_shop := false
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
var furnishings: ShipFurnishings
var furnish_mode: Node2D
var _leaving_furnish := false

@onready var shop: FurnishingShopUI = $FurnishingShopUI
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
	save_service.bind_furnishings(furnishings)
	save_service.bind_economy(economy)
	var overflow: MiningOverflow = mars.get_node("MiningOverflow")
	overflow.world_objects = mars.get_node("WorldObjects")
	var mining_nodes: Array[MiningNode] = []
	for child in mars.get_node("WorldObjects").get_children():
		if child is MiningNode:
			child.overflow_store = overflow
			mining_nodes.append(child)
	save_service.bind_mining(mining_nodes)
	save_service.bind_mining_overflow(overflow)
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
	furnishings = ship.get_node("ShipFurnishings")
	furnishings.player = player
	furnishings.economy = economy
	shop.bind_economy(economy)
	$ResourceHUD.bind_economy(economy)
	shop.close_requested.connect(_close_shop)
	shop.open_requested.connect(_open_shop)
	furnish_mode = ship.get_node("FurnishMode")
	furnish_mode.exit_requested.connect(_exit_furnish_mode)
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
	if current_location == SHIP:
		furnishings.validate_restored()
		# Crate bodies must exist before testing the saved Player position.
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("furnish_toggle") and not event.is_echo():
		if furnish_mode.active:
			_exit_furnish_mode()
		else:
			_enter_furnish_mode()
		get_viewport().set_input_as_handled()


func _enter_furnish_mode() -> void:
	if not player.controls_enabled or transitioning or current_location != SHIP or _leaving_furnish or shop.is_open or _closing_shop:
		return
	_lock_input()
	furnish_mode.set_active(true)


func _exit_furnish_mode() -> void:
	if not furnish_mode.active or _leaving_furnish:
		return
	_leaving_furnish = true
	furnish_mode.set_active(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	while Input.is_action_pressed("interact") or Input.is_action_pressed("inventory_toggle"):
		await get_tree().process_frame
	if not transitioning:
		player.get_node("InventoryUI").set_process_input(true)
		player.controls_enabled = true
	_leaving_furnish = false


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


func _process(_delta: float) -> void:
	shop.set_access_available(_can_open_shop())


func _can_open_shop() -> bool:
	return not transitioning and player.controls_enabled and not furnish_mode.active and not _leaving_furnish and not shop.is_open and not _closing_shop


func _open_shop() -> void:
	if not _can_open_shop():
		return
	_lock_input()
	shop.open()


func _close_shop() -> void:
	if not shop.is_open or _closing_shop:
		return
	_closing_shop = true
	shop.close()
	await get_tree().process_frame
	while Input.is_action_pressed("interact") or Input.is_action_pressed("ui_cancel") or Input.is_action_pressed("inventory_toggle") or Input.is_action_pressed("furnish_toggle"):
		await get_tree().process_frame
	if not transitioning:
		player.get_node("InventoryUI").set_process_input(true)
		player.controls_enabled = true
	_closing_shop = false
