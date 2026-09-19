extends Camera2D

const AREA_SIZE := Vector2(1280, 960)

@export var target: Node2D


func _enter_tree() -> void:
	get_viewport().size_changed.connect(_update_limits)
	_update_limits()
	if target != null:
		global_position = target.global_position.round()
	reset_smoothing()


func _exit_tree() -> void:
	get_viewport().size_changed.disconnect(_update_limits)


func _process(_delta: float) -> void:
	if is_instance_valid(target):
		global_position = target.global_position.round()


func _update_limits() -> void:
	# Oversized viewports center the area; the terrain backdrop fills the margins.
	var margin := (get_viewport_rect().size / zoom - AREA_SIZE).max(Vector2.ZERO) / 2.0
	limit_left = -ceili(margin.x)
	limit_top = -ceili(margin.y)
	limit_right = int(AREA_SIZE.x) + ceili(margin.x)
	limit_bottom = int(AREA_SIZE.y) + ceili(margin.y)
