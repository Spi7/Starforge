class_name Player
extends CharacterBody2D

signal container_access_requested(container: InventoryData, title: String)
signal inventory_feedback(message: String)
signal mining_completed

var inventory: InventoryData = InventoryData.new(20)
var controls_enabled: bool = true
var facing_direction: StringName = &"down"
var _mining_animation_active: bool = false
var _mining_controls_locked: bool = false
var _prompt_deposit: MiningNode

@export var move_speed: float = 200.0

@onready var interaction_detector: Area2D = $InteractionDetector
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)


func begin_mining(target: Vector2) -> bool:
	if not controls_enabled or _mining_animation_active:
		return false
	_update_movement_animation(target - global_position)
	_mining_controls_locked = true
	$InventoryUI.set_process_input(false)
	controls_enabled = false
	velocity = Vector2.ZERO
	play_mining_animation()
	return true


func play_mining_animation() -> void:
	_mining_animation_active = true
	animated_sprite.stop()
	animated_sprite.play(StringName("mine_" + facing_direction))


func _on_animation_finished() -> void:
	if _mining_animation_active:
		_mining_animation_active = false
		animated_sprite.play(StringName("idle_" + facing_direction))
		if _mining_controls_locked:
			mining_completed.emit()
			_mining_controls_locked = false
			$InventoryUI.set_process_input(true)
			controls_enabled = true


func _update_movement_animation(direction: Vector2) -> void:
	if _mining_animation_active:
		return
	if not direction.is_zero_approx():
		# Horizontal wins ties, including keyboard diagonals.
		if absf(direction.x) >= absf(direction.y):
			facing_direction = &"right" if direction.x > 0.0 else &"left"
		else:
			facing_direction = &"down" if direction.y > 0.0 else &"up"
	var prefix := "idle_" if direction.is_zero_approx() else "walk_"
	animated_sprite.play(StringName(prefix + facing_direction))


func _unhandled_input(event: InputEvent) -> void:
	if controls_enabled and event.is_action_pressed("interact"):
		interact_with_nearest()


func interact_with_nearest() -> void:
	if not controls_enabled:
		return
	var nearest := nearest_interactable()
	if nearest != null:
		nearest.interact(self)


func nearest_interactable() -> Interactable:
	var nearest: Interactable = null
	var nearest_distance: float = INF
	for area in interaction_detector.get_overlapping_areas():
		if area is Interactable and area.collision_layer != 0:
			var distance: float = global_position.distance_squared_to(area.global_position)
			if distance < nearest_distance:
				nearest = area
				nearest_distance = distance
	return nearest


func _update_mining_prompt() -> void:
	if is_instance_valid(_prompt_deposit):
		_prompt_deposit.show_mining_prompt(false)
	_prompt_deposit = null
	if controls_enabled:
		var nearest := nearest_interactable()
		if nearest != null and nearest.get_parent() is MiningNode:
			_prompt_deposit = nearest.get_parent()
			_prompt_deposit.show_mining_prompt(true)


func _physics_process(_delta: float) -> void:
	_update_mining_prompt()
	if not controls_enabled:
		velocity = Vector2.ZERO
		_update_movement_animation(Vector2.ZERO)
		return
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * move_speed
	move_and_slide()
	_update_movement_animation(direction)
