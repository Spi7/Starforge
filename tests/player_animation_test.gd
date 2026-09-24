extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)


func run() -> void:
	var player: Player = load("res://scenes/characters/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	check(sprite.animation == &"idle_down" and sprite.is_playing(), "Scene starts idle facing down")
	for direction in ["down", "left", "right", "up"]:
		for kind in ["idle", "walk", "mine"]:
			var animation := StringName(kind + "_" + direction)
			check(sprite.sprite_frames.has_animation(animation), "Animation exists: " + animation)
			check(sprite.sprite_frames.get_frame_count(animation) == (6 if kind == "mine" else 4), "Frame count: " + animation)
			check(sprite.sprite_frames.get_animation_loop(animation) == (kind != "mine"), "Loop setting: " + animation)
	for direction in ["down", "left", "right", "up"]:
		Input.action_press("move_" + direction)
		player._physics_process(1.0 / 60.0)
		check(sprite.animation == StringName("walk_" + direction), "Input selects walk: " + direction)
		Input.action_release("move_" + direction)
		player._physics_process(1.0 / 60.0)
		check(sprite.animation == StringName("idle_" + direction), "Release preserves facing: " + direction)
		player.play_mining_animation()
		check(sprite.animation == StringName("mine_" + direction), "Mining hook selects facing: " + direction)
		player._physics_process(1.0 / 60.0)
		check(sprite.animation == StringName("mine_" + direction), "Locomotion does not overwrite mining")
		sprite.speed_scale = 20.0
		await sprite.animation_finished
		check(sprite.animation == StringName("idle_" + direction), "Mining finishes in matching idle")
		sprite.speed_scale = 1.0
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			player._update_movement_animation(Vector2(x, y))
			check(player.facing_direction == (&"left" if x < 0 else &"right"), "Diagonal ties choose horizontal")
	player._update_movement_animation(Vector2(0.25, -0.75))
	check(player.facing_direction == &"up", "Vertical dominant input faces up")
	player._update_movement_animation(Vector2(-0.75, 0.25))
	check(player.facing_direction == &"left", "Horizontal dominant input faces left")
	Input.action_press("move_right")
	player.controls_enabled = false
	player._physics_process(1.0 / 60.0)
	check(player.velocity == Vector2.ZERO and sprite.animation == &"idle_left", "Disabled controls return to idle")
	Input.action_release("move_right")
	check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and sprite.scale == Vector2.ONE, "Native scale with nearest filtering")
	check(player.get_node("CollisionShape2D").shape.size == Vector2(24, 24), "Existing collision footprint preserved")
	print("Player animation tests: %d checks, %d failures" % [checks, failures])
	player.queue_free()
	await process_frame
	quit(1 if failures else 0)
