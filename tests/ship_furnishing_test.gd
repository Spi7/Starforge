extends SceneTree

var checks := 0
var failures := 0
var changes := 0
var session: Node
var furnishings: ShipFurnishings
const IRON := preload("res://data/items/iron_ore.tres")


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func settle() -> void:
	await physics_frame
	await physics_frame


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
	session = load("res://scenes/game/game_session.tscn").instantiate()
	session.persistence_enabled = false
	root.add_child(session)
	while session.transitioning:
		await physics_frame
	furnishings = session.furnishings
	furnishings.changed.connect(func() -> void: changes += 1)
	var player: Player = session.player
	var mode = session.furnish_mode
	var ui = player.get_node("InventoryUI")
	var authored: ShipStorage = session.ship.get_node("WorldObjects/Crate")
	check(authored.persistent_id == "starter_ship_storage_01", "Authored storage retains identity")
	check(furnishings.cell_at(session.ship.to_global(Vector2(95, 127))) == Vector2i(2, 3), "Floor-local snapping with translated ship")
	check(furnishings.cell_center(Vector2i(2, 3)) == session.ship.to_global(Vector2(80, 112)), "Grid center uses 32px tile")
	check(not furnishings.placement_error(Vector2i(-1, 3)).is_empty(), "Outside floor rejected")
	check(not furnishings.placement_error(Vector2i(4, 5)).is_empty(), "Spawn access reserved")
	check(not furnishings.placement_error(Vector2i(4, 6)).is_empty(), "Airlock access reserved")
	check(not furnishings.placement_error(Vector2i(1, 4)).is_empty(), "Authored storage approach reserved")
	check(not furnishings.placement_error(Vector2i(1, 3)).is_empty(), "Authored storage body rejected")
	check(not furnishings.placement_error(Vector2i(4, 0)).is_empty(), "Console body rejected")
	check(not furnishings.placement_error(Vector2i(8, 3)).is_empty(), "Plant body rejected")
	check(furnishings.placement_error(Vector2i(2, 2)) == "Collect the pickup first.", "Pickup footprint rejected")
	player.position = Vector2(80, 112)
	await settle()
	check(not furnishings.placement_error(Vector2i(2, 3)).is_empty(), "Player overlap rejected")
	player.position = Vector2(160, 168)
	await settle()
	check(furnishings.placement_error(Vector2i(2, 3)).is_empty(), "Free cell accepted")
	check(furnishings.create_crate(Vector2i(-1, 0)).is_empty() and furnishings.next_placed_object_id == 1, "Rejected placement allocates nothing")
	action(&"furnish_toggle")
	check(mode.active and not player.controls_enabled and not ui.is_processing_input(), "F enters Furnish Mode and locks gameplay")
	action(&"inventory_toggle")
	check(not ui.panel.visible, "Inventory cannot open in Furnish Mode")
	var locked_position := player.position
	Input.action_press(&"move_left")
	await settle()
	Input.action_release(&"move_left")
	check(player.position == locked_position, "Movement actions are blocked in Furnish Mode")
	action(&"interact")
	check(not ui.panel.visible and not session.transitioning, "E cannot open storage or travel in Furnish Mode")
	mode.select_new()
	check(furnishings.next_placed_object_id == 1 and changes == 0, "Selection and preview do not allocate or dirty")
	check(not mode.confirm_at(Vector2i(4, 5)), "Confirmation revalidates reserved cells")
	check(mode.confirm_at(Vector2i(2, 3)), "Preview commits new crate")
	var id := "placed_object_000001"
	var crate: ShipStorage = furnishings.crates[id].node
	var inventory := crate.inventory
	var slot := inventory.slots[0]
	check(crate.get_parent() == session.ship.get_node("WorldObjects"), "Crate directly participates in WorldObjects Y-sort")
	check(crate.y_sort_enabled and crate.collision_layer == 1, "Crate retains Y-sort and solid collision")
	check(furnishings.next_placed_object_id == 2 and changes == 1, "Commit increments counter and emits one change")
	check(not furnishings.placement_error(Vector2i(2, 3)).is_empty(), "Immediate occupancy rejects overlap")
	var second_id := furnishings.create_crate(Vector2i(6, 3))
	check(second_id == "placed_object_000002", "Second crate has sequential identity")
	var second: ShipStorage = furnishings.crates[second_id].node
	check(second.inventory != inventory and inventory != authored.inventory, "All storage inventories independent")
	inventory.add_item(IRON, 12)
	check(second.inventory.slots[0].item == null and authored.inventory.slots[0].item == null, "Crate contents isolated")
	var before := changes
	mode.select_crate(id)
	mode.begin_move()
	action(&"ui_cancel")
	check(changes == before and crate.position == Vector2(80, 112), "Move cancellation preserves committed state")
	check(mode.active and not mode.placing and mode.selected_id.is_empty(), "Esc cancels move while keeping Furnish Mode active")
	mode.select_crate(id)
	mode.begin_move()
	check(mode.confirm_at(Vector2i(3, 3)), "Move confirmed")
	check(furnishings.crates[id].node == crate and crate.inventory == inventory and inventory.slots[0] == slot, "Move preserves node, inventory and slot references")
	check(crate.persistent_id == id and slot.quantity == 12 and furnishings.next_placed_object_id == 3, "Move preserves ID, contents and counter")
	check(changes == before + 1, "Changed cell emits once")
	before = changes
	check(furnishings.move_crate(id, Vector2i(3, 3)) and changes == before, "Same-cell move is clean")
	check(not furnishings.move_crate(id, Vector2i(6, 3)) and changes == before, "Occupied move is rejected without dirty event")
	check(not furnishings.remove_crate(id) and changes == before, "Nonempty removal refused")
	check(not furnishings.remove_crate(authored.persistent_id), "Authored storage cannot be removed")
	check(furnishings.remove_crate(second_id), "Empty crate removal succeeds")
	check(not furnishings.crates.has(second_id) and furnishings.next_placed_object_id == 3, "Removal retires ID without lowering counter")
	var third_id := furnishings.create_crate(Vector2i(6, 3))
	check(third_id == "placed_object_000003", "Gap never reused")
	before = changes
	mode.select_crate(id)
	mode.begin_move()
	action(&"furnish_toggle")
	await settle()
	await process_frame
	check(not mode.active and player.controls_enabled and ui.is_processing_input(), "F exit restores controls")
	check(changes == before, "Exit does not dirty state")
	check(not mode.placing and crate.position == Vector2(112, 112), "F exit cancels pending move")
	player.position = Vector2(112, 142)
	await settle()
	action(&"interact")
	check(ui.panel.visible and ui.storage == inventory, "Normal E opens moved crate inventory")
	ui.close()
	player.position = Vector2(208, 142)
	await settle()
	action(&"interact")
	check(ui.storage == furnishings.crates[third_id].node.inventory, "E opens second independent crate")
	ui.close()
	# Recovery keeps the original runtime node and inventory, including when nonempty.
	var recovered := furnishings.add_restored_crate("placed_object_000010", Vector2i(99, 99))
	recovered.inventory.add_item(IRON, 7)
	furnishings.next_placed_object_id = 11
	furnishings.pending_validation = true
	before = changes
	furnishings.validate_restored()
	check(changes == before and furnishings.crates[recovered.persistent_id].recovery, "Invalid restored geometry remains recovery state without dirtying")
	check(not recovered.visible and recovered.collision_layer == 0 and recovered.get_node("Interactable").collision_layer == 0, "Recovery object absent from gameplay")
	session._enter_furnish_mode()
	check(mode.recovery.visible and mode.recovery_ids.has(recovered.persistent_id), "Recovery is exposed in Furnish Mode")
	mode.select_crate(recovered.persistent_id)
	check(mode.confirm_at(Vector2i(2, 3)), "Recovery can place a nonempty crate")
	check(furnishings.crates[recovered.persistent_id].node == recovered and recovered.inventory.slots[0].quantity == 7, "Recovery preserves node and contents")
	check(furnishings.next_placed_object_id == 11 and changes == before + 1, "Recovery reuses identity and marks change")
	session._exit_furnish_mode()
	await settle()
	await process_frame
	for round_trip in 2:
		session._request_transition(player, session.SHIP, session.MARS, &"ShipArrival")
		while session.transitioning:
			await physics_frame
		session._enter_furnish_mode()
		check(not mode.active, "Furnishing unavailable on Mars")
		session._request_transition(player, session.MARS, session.SHIP, &"MarsReturnSpawn")
		while session.transitioning:
			await physics_frame
		check(furnishings.crates[id].node == crate and crate.inventory == inventory, "Transitions preserve dynamic node and inventory")
		check(authored.inventory.slots[0].item == null, "Authored storage unaffected by dynamic transitions")
	check(ShipFurnishings.object_id(1000000) == "placed_object_1000000", "Sequence grows beyond six digits")
	furnishings.next_placed_object_id = ShipFurnishings.MAX_NEXT_ID
	check(furnishings.create_crate(Vector2i(7, 3)).is_empty(), "Exhausted counter refuses allocation")
	var ghost = mode.ghost
	check(ghost is Sprite2D and ghost.get_child_count() == 0, "Ghost is purely visual")
	session.queue_free()
	await process_frame
	print("M5A furnishing: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
