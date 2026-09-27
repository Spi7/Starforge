extends "res://tests/mining_test.gd"

var final_alpha := -1.0
var final_y := 0.0

func run() -> void:
	directory = "user://m5c_feedback_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	await start_session()
	await travel(session.MARS)
	interact()
	check(not is_instance_valid(deposit._reward_feedback), "Missing tool creates no reward text")
	for roll in [1, 2, 3]:
		for overflow in [false, true]:
			clear_inventory()
			deposit.restore(0.0)
			deposit.overflow_store.restore({"next_id": 1, "pickups": []})
			player.inventory.add_item(TOOL, 20 if overflow else 1)
			deposit.yield_roller = func() -> int: return roll
			interact()
			check(not is_instance_valid(deposit._reward_feedback), "No reward feedback before completion")
			await finish_animation()
			var label: Label = deposit._reward_feedback
			check(is_instance_valid(label) and label.text == "+%d Iron Ore" % roll, "Text uses actual total roll with or without overflow")
			check(label.visible and is_equal_approx(label.modulate.a, 1.0), "Feedback starts fully opaque")
			check(label.position == Vector2(-50, -44) and label.get_parent() == deposit, "Feedback anchored above original rock")
			check(not deposit.get_node("Sprite2D").visible and label.is_visible_in_tree(), "Text remains visible after rock disappears")
			check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.get_child_count() == 0, "Label has no collision or input blocking")
			check(count_iron() == (0 if overflow else roll), "Feedback preserves inventory reward")
			check(deposit.overflow_store.pickups.size() == (1 if overflow else 0), "Feedback preserves overflow stack count")
			if overflow:
				check(deposit.overflow_store.pickups.values()[0].quantity == roll, "Full overflow still displays total rolled quantity")
			var initial_global := label.global_position
			player.position += Vector2(20, 0)
			check(label.global_position == initial_global, "Feedback does not follow Player")
			player.position -= Vector2(20, 0)
			var snapshot: Dictionary = session.save_service.capture()
			check(snapshot.save_version == 5 and not JSON.stringify(snapshot).contains("MiningRewardFeedback"), "Feedback absent from V5 save data")
			check(session.save_service.flush(), "Completed mining saves normally")
			final_alpha = -1.0
			label.tree_exiting.connect(func() -> void:
				final_alpha = label.modulate.a
				final_y = label.position.y
			, CONNECT_ONE_SHOT)
			await create_timer(0.25).timeout
			var first_alpha := label.modulate.a
			var first_y := label.position.y
			check(first_alpha > 0.0 and first_alpha < 1.0 and first_y < -44.0, "Early lifetime simultaneously rises and fades")
			await create_timer(0.25).timeout
			check(label.modulate.a < first_alpha and label.modulate.a > 0.0 and label.position.y < first_y, "Fade and rise continue through middle of lifetime")
			await create_timer(0.7).timeout
			check(not is_instance_valid(label), "Feedback freed by approximately one second")
			check(is_zero_approx(final_alpha) and is_equal_approx(final_y, -56.0), "Feedback reaches full transparency and exact 12-pixel rise before removal")
			check(session.save_service.capture() == snapshot and not session.save_service.dirty, "Animation changes no persistent state or autosave dirty state")
	# Transition during fade safely disposes presentation, preserving completed mining.
	clear_inventory()
	player.inventory.add_item(TOOL, 1)
	deposit.restore(0.0)
	interact()
	await finish_animation()
	var departing_label: WeakRef = weakref(deposit._reward_feedback)
	await travel(session.SHIP)
	await process_frame
	check(departing_label.get_ref() == null, "Leaving Mars removes transient feedback safely")
	await travel(session.MARS)
	check(not is_instance_valid(deposit._reward_feedback), "Feedback does not return with retained Mars")
	await stop_session()
	for name in ["autosave.json", "autosave.json.bak", "autosave.json.tmp"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("Mining feedback tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
