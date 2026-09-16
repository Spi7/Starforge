class_name Player
extends CharacterBody2D

signal container_access_requested(container: InventoryData, title: String)
signal inventory_feedback(message: String)

var inventory: InventoryData = InventoryData.new(20)
var controls_enabled: bool = true

@export var move_speed: float = 200.0

@onready var interaction_detector: Area2D = $InteractionDetector


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
		return
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * move_speed
	move_and_slide()
