extends SceneTree

const IRON := preload("res://data/items/iron_ore.tres")
var checks := 0
var failures := 0
var session: Node
var changes := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func action(name: StringName) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventAction.new()
	event.action = name
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func run() -> void:
	var directory := "user://m5a_rotation_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	session = load("res://scenes/game/game_session.tscn").instantiate()
	session.get_node("SaveService").save_directory = directory
	session.get_node("SaveService").coalesce_seconds = 0.15
	root.add_child(session)
	while session.transitioning:
		await physics_frame
	var service: SaveService = session.save_service
	var furnishings: ShipFurnishings = session.furnishings
	var mode = session.furnish_mode
	var authored: ShipStorage = session.ship.get_node("WorldObjects/Crate")
	session.economy.restore(SessionEconomy.STARTING_CREDITS, 20)
	furnishings.changed.connect(func() -> void: changes += 1)
	check(service.flush(), "Initial isolated save")
	action(&"furnish_toggle")
	check(not mode.object_actions.visible and not mode.preview_rotate.visible, "Idle has no object actions or preview controls")
	check(mode.get_node_or_null("UI/Panel/Content/Toolbar/Remove") == null, "Bottom catalog contains no global Remove")
	mode.get_node("UI/Panel/Content/Toolbar/Cards/NewCrate").pressed.emit()
	check(mode.placing and mode.selected_id.is_empty() and mode.preview_rotation_quarters == 0, "Catalog selects a new zero-rotation preview")
	check(mode.preview_rotate.visible and not mode.object_actions.visible, "New preview has its own compact Rotate control")
	for expected in [1, 2, 3, 0]:
		action(&"furnish_rotate")
		check(mode.preview_rotation_quarters == expected and is_equal_approx(mode.ghost.rotation, expected * PI / 2.0), "Preview cycles to quarter %d" % expected)
	check(changes == 0 and not service.dirty and furnishings.next_placed_object_id == 1, "Preview-only rotation neither saves nor allocates")
	mode.preview_rotate.pressed.emit()
	check(mode.preview_rotation_quarters == 1, "Preview Rotate button works")
	action(&"ui_cancel")
	check(not service.dirty and furnishings.crates.is_empty(), "Cancelled new rotation has no persistent state")
	mode.select_new()
	check(mode.preview_rotation_quarters == 0, "Each new crate starts unrotated")
	action(&"furnish_rotate")
	action(&"furnish_rotate")
	check(mode.confirm_at(Vector2i(2, 3)), "Commit rotated preview")
	var id := "placed_object_000001"
	var record: Dictionary = furnishings.crates[id]
	var crate: ShipStorage = record.node
	var inventory := crate.inventory
	var slot := inventory.slots[0]
	check(record.rotation_quarters == 2 and is_equal_approx(crate.rotation, PI), "Placed node derives rotation from preview quarter")
	inventory.add_item(IRON, 12)
	check(service.flush(), "Flush contents before rotation dirty check")
	var before := changes
	mode.select_crate(id)
	check(mode.object_actions.visible and mode.selection.visible and not mode.placing, "Dynamic selection shows outline and actions without moving")
	check(not mode.confirm_at(Vector2i(3, 3)) and record.cell == Vector2i(2, 3), "Selection alone cannot commit a move")
	check(not service.dirty and changes == before, "Selection remains clean")
	await process_frame
	await process_frame
	for expected in [3, 0, 1, 2]:
		mode.get_node("UI/ObjectActions/Actions/Rotate").pressed.emit()
		check(record.rotation_quarters == expected and is_equal_approx(crate.rotation, expected * PI / 2.0), "Existing rotation cycles to quarter %d" % expected)
		check(record.node == crate and crate.persistent_id == id and crate.inventory == inventory and inventory.slots[0] == slot and slot.quantity == 12, "Rotation preserves all identities and contents")
		check(record.cell == Vector2i(2, 3) and furnishings.crate_at(Vector2i(2, 3)) == id and furnishings.next_placed_object_id == 2, "Rotation preserves cell, occupancy and allocation counter")
	check(changes == before + 4 and service.dirty, "Each committed rotation emits one persistent change")
	await create_timer(0.25).timeout
	check(not service.dirty and JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("autosave.json"))).placed_crates[0].rotation_quarters == 2, "Committed rotations autosave through existing timer")
	mode.get_node("UI/ObjectActions/Actions/Move").pressed.emit()
	check(mode.placing and not mode.object_actions.visible and mode.preview_rotation_quarters == 2, "Move action starts preview at current orientation")
	before = changes
	action(&"furnish_rotate")
	check(record.rotation_quarters == 2 and mode.preview_rotation_quarters == 3 and not service.dirty, "Move-preview rotation remains uncommitted")
	action(&"ui_cancel")
	check(record.rotation_quarters == 2 and record.cell == Vector2i(2, 3) and changes == before and not service.dirty, "Cancelled move preserves committed orientation and position")
	mode.select_crate(id)
	mode.begin_move()
	check(not mode.confirm_at(Vector2i(4, 5)) and not service.dirty, "Invalid rotated move rejected without saving")
	check(mode.confirm_at(Vector2i(3, 3)), "Valid rotated move commits")
	check(record.node == crate and record.rotation_quarters == 2 and is_equal_approx(crate.rotation, PI) and crate.inventory == inventory, "Move preserves orientation and runtime identity")
	check(service.flush(), "Moved rotation saved")
	mode.select_crate(id)
	mode.begin_move()
	action(&"furnish_rotate")
	check(mode.confirm_at(Vector2i(3, 3)) and record.rotation_quarters == 3, "Confirmed move-preview rotation commits even on same cell")
	check(service.flush(), "Confirmed preview rotation saved")
	mode.select_crate(id)
	mode.get_node("UI/ObjectActions/Actions/Remove").pressed.emit()
	check(furnishings.crates.has(id) and mode.feedback.text == "Empty this crate before removing it." and not service.dirty, "Contextual removal preserves nonempty rejection")
	mode.select_crate(authored.persistent_id)
	check(not mode.object_actions.visible and not mode.selection.visible and mode.selected_id.is_empty(), "Authored storage cannot be selected")
	mode.begin_move()
	action(&"furnish_rotate")
	mode.remove_selected()
	check(not furnishings.rotate_crate(authored.persistent_id) and not furnishings.move_crate(authored.persistent_id, Vector2i(2, 3)) and not furnishings.remove_crate(authored.persistent_id), "Authored storage rejected by all contextual operations")
	check(authored.rotation == 0 and not mode.placing and not service.dirty, "Authored storage remains unchanged")
	var second := furnishings.create_crate(Vector2i(6, 3))
	check(furnishings.crates[second].rotation_quarters == 0, "New runtime crates default to zero")
	furnishings.rotate_crate(second)
	mode.select_crate(second)
	mode.remove_selected()
	check(not furnishings.crates.has(second) and not mode.object_actions.visible, "Empty rotated crate removes and clears contextual controls")
	check(furnishings.create_crate(Vector2i(6, 3)) == "placed_object_000003", "Rotation and removal preserve retired IDs")
	# Recovery remains the same owned node, with preview changes committed only on placement.
	var recovered := furnishings.add_restored_crate("placed_object_000010", Vector2i(99, 99), 2)
	recovered.inventory.add_item(IRON, 7)
	furnishings.next_placed_object_id = 11
	furnishings.pending_validation = true
	furnishings.validate_restored()
	check(service.flush(), "Save rotated recovery entry")
	mode._refresh_recovery()
	mode.recovery.item_selected.emit(1)
	check(mode.placing and mode.preview_rotation_quarters == 2 and not mode.object_actions.visible, "Recovery opens oriented preview without world actions")
	action(&"furnish_rotate")
	action(&"ui_cancel")
	check(furnishings.crates[recovered.persistent_id].rotation_quarters == 2 and not service.dirty, "Cancelled recovery rotation preserves saved orientation")
	mode.recovery.item_selected.emit(1)
	action(&"furnish_rotate")
	check(mode.confirm_at(Vector2i(2, 3)), "Recovery confirms selected orientation")
	var recovered_record: Dictionary = furnishings.crates[recovered.persistent_id]
	check(recovered_record.node == recovered and recovered_record.rotation_quarters == 3 and recovered.inventory.slots[0].quantity == 7 and furnishings.next_placed_object_id == 11, "Recovery preserves ID, inventory, contents and selected rotation")
	check(service.dirty and service.flush(), "Recovery orientation and cell save together")
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("autosave.json")))
	check(snapshot.placed_crates[-1].rotation_quarters == 3 and snapshot.placed_crates[-1].grid_position == {"x": 2.0, "y": 3.0}, "Saved recovery record contains selected orientation and cell")
	mode.select_crate(id)
	action(&"furnish_toggle")
	await physics_frame
	await physics_frame
	check(not mode.selection.visible and not mode.object_actions.visible and not mode.preview_rotate.visible, "Leaving Furnish Mode hides all contextual controls")
	session.player.position = Vector2(144, 112)
	await physics_frame
	await physics_frame
	action(&"interact")
	check(session.player.get_node("InventoryUI").storage == inventory, "Normal E opens rotated crate after Furnish Mode")
	session.queue_free()
	await process_frame
	for name in ["autosave.json", "autosave.json.bak", "autosave.json.tmp"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(path) == OK, "Remove isolated rotation save")
	check(DirAccess.remove_absolute(directory) == OK, "Remove isolated rotation directory")
	print("M5A rotation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
