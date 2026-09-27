class_name MiningNode
extends StaticBody2D

signal changed

const BASIC_TOOL := preload("res://data/items/basic_mining_tool.tres")
const REWARD_FEEDBACK := preload("res://scenes/mars/mining_reward_feedback.tscn")

@export var persistent_id: StringName
@export var item: ItemDefinition
var yield_roller: Callable
var overflow_store: MiningOverflow
@export_range(1.0, 86400.0) var replenishment_seconds: float = 60.0

var replenishment_deadline: float = 0.0
var _actor: Player
var _reward_feedback: Label


func _ready() -> void:
	$Interactable.interacted.connect(_on_interacted)
	$ReplenishmentTimer.timeout.connect(refresh_availability)
	refresh_availability()


func _enter_tree() -> void:
	# Retained Mars can re-enter long after its timer stopped running.
	refresh_availability.call_deferred()


func is_available() -> bool:
	return Time.get_unix_time_from_system() >= replenishment_deadline


func restore(deadline: float) -> void:
	replenishment_deadline = deadline
	refresh_availability()


func refresh_availability() -> void:
	var available := is_available()
	$Sprite2D.visible = available
	collision_layer = 1 if available else 0
	$Interactable.collision_layer = 2 if available else 0
	# Shape changes are deferred because availability can change during physics callbacks.
	$CollisionShape2D.set_deferred("disabled", not available)
	$Interactable/CollisionShape2D.set_deferred("disabled", not available)
	if not available:
		$MiningPrompt.hide()


func show_mining_prompt(show_prompt: bool) -> void:
	$MiningPrompt.visible = show_prompt and is_available()


func _can_mine(player: Player) -> bool:
	for slot in player.inventory.slots:
		if slot.item == BASIC_TOOL and slot.quantity > 0:
			return true
	player.inventory_feedback.emit("Basic Mining Tool required")
	return false


func roll_yield() -> int:
	return clampi(int(yield_roller.call()), 1, 3) if yield_roller.is_valid() else randi_range(1, 3)


func _overflow_position(player: Player) -> Vector2:
	var candidate := global_position + global_position.direction_to(player.global_position) * 32.0
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	query.shape = shape
	query.transform = Transform2D(0.0, candidate)
	query.collision_mask = 1
	query.exclude = [get_rid(), player.get_rid()]
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		candidate = player.global_position
	return get_parent().to_local(candidate)


func _on_interacted(actor: Node) -> void:
	if not actor is Player or not is_available() or is_instance_valid(_actor):
		return
	var player := actor as Player
	if overflow_store == null or not player.controls_enabled or not _can_mine(player):
		return
	if not player.begin_mining(global_position):
		return
	_actor = player
	player.mining_completed.connect(_complete_mining, CONNECT_ONE_SHOT)


func _complete_mining() -> void:
	var player := _actor
	_actor = null
	# Revalidate the tool at completion in case inventory changed.
	if not is_inside_tree() or not is_available() or not _can_mine(player):
		return
	# Like inventory transfers, publish only after both sides are final.
	var rolled := roll_yield()
	var accepted := player.inventory._add_item(item, rolled)
	if accepted < rolled:
		overflow_store.spawn(rolled - accepted, _overflow_position(player))
	replenishment_deadline = Time.get_unix_time_from_system() + replenishment_seconds
	refresh_availability()
	player.inventory.changed.emit()
	changed.emit()
	_show_reward_feedback(rolled)


func _show_reward_feedback(rolled: int) -> void:
	if is_instance_valid(_reward_feedback):
		_reward_feedback.queue_free()
	_reward_feedback = REWARD_FEEDBACK.instantiate()
	_reward_feedback.text = "+%d %s" % [rolled, item.display_name]
	add_child(_reward_feedback)
	var tween := _reward_feedback.create_tween().set_parallel(true)
	tween.tween_property(_reward_feedback, "position:y", _reward_feedback.position.y - 12.0, 1.0)
	tween.tween_property(_reward_feedback, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(_reward_feedback.queue_free)


func _exit_tree() -> void:
	$MiningPrompt.hide()
	if is_instance_valid(_reward_feedback):
		_reward_feedback.queue_free()
	if is_instance_valid(_actor):
		_actor.mining_completed.disconnect(_complete_mining)
		_actor = null
