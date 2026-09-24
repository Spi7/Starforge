class_name Player
extends CharacterBody2D

signal container_access_requested(container: InventoryData, title: String)
signal inventory_feedback(message: String)

var inventory: InventoryData = InventoryData.new(20)
var controls_enabled: bool = true
var facing_direction: StringName = &"down"
var _mining_animation_active: bool = false

@export var move_speed: float = 200.0

@onready var interaction_detector: Area2D = $InteractionDetector
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)


# Visual-only hook for a future action; movement and tool rules belong to that action.
func play_mining_animation() -> void:
	_mining_animation_active = true
	animated_sprite.stop()
	animated_sprite.play(StringName("mine_" + facing_direction))


func _on_animation_finished() -> void:
	if _mining_animation_active:
		_mining_animation_active = false
		animated_sprite.play(StringName("idle_" + facing_direction))


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
	var nearest: Interactable = null
	var nearest_distance: float = INF
	for area in interaction_detector.get_overlapping_areas():
		if area is Interactable:
			var distance: float = global_position.distance_squared_to(area.global_position)
			if distance < nearest_distance:
				nearest = area
				nearest_distance = distance
	if nearest != null:
		nearest.interact(self)


func _physics_process(_delta: float) -> void:
	if not controls_enabled:
		velocity = Vector2.ZERO
		_update_movement_animation(Vector2.ZERO)
		return
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * move_speed
	move_and_slide()
	_update_movement_animation(direction)
