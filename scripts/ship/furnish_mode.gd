extends Node2D

signal exit_requested

var furnishings: ShipFurnishings
var active := false
var placing := false
var selected_id := ""
var preview_cell := Vector2i.ZERO
var preview_rotation_quarters := 0
var recovery_ids: Array[String] = []

@onready var panel: PanelContainer = $UI/Panel
@onready var feedback: Label = $UI/Feedback
@onready var recovery: OptionButton = $UI/Panel/Content/Toolbar/Recovery
@onready var hints: Label = $UI/Hints
@onready var object_actions: PanelContainer = $UI/ObjectActions
@onready var preview_rotate: Button = $UI/PreviewRotate
@onready var selection: Line2D = $Selection
@onready var ghost: Sprite2D = $Ghost


func _ready() -> void:
	furnishings = get_parent().get_node("ShipFurnishings")
	$UI/Panel/Content/Toolbar/Cards/NewCrate.pressed.connect(select_new)
	$UI/ObjectActions/Actions/Move.pressed.connect(begin_move)
	$UI/ObjectActions/Actions/Rotate.pressed.connect(rotate_selected)
	$UI/ObjectActions/Actions/Remove.pressed.connect(remove_selected)
	preview_rotate.pressed.connect(rotate_selected)
	$UI/Panel/Content/Toolbar/Exit.pressed.connect(func() -> void: exit_requested.emit())
	recovery.item_selected.connect(_select_recovery)
	if furnishings.economy != null:
		furnishings.economy.changed.connect(_refresh_owned)
	_refresh_owned()
	set_active(false)


func set_active(value: bool) -> void:
	active = value
	panel.visible = value
	feedback.visible = value
	hints.visible = value
	cancel_preview()
	if active:
		_refresh_owned()
		_refresh_recovery()


func select_new() -> void:
	if furnishings.economy == null or furnishings.economy.owned_storage_crates() <= 0:
		return
	if not active:
		return
	selected_id = ""
	placing = true
	preview_rotation_quarters = 0
	ghost.rotation = 0
	feedback.text = ""
	_update_context()
	_release_focus()


func select_crate(id: String) -> void:
	if not active:
		return
	if not furnishings.crates.has(id):
		cancel_preview()
		return
	selected_id = id
	placing = furnishings.crates[id].recovery
	preview_rotation_quarters = furnishings.crates[id].rotation_quarters
	ghost.rotation = preview_rotation_quarters * PI / 2.0
	feedback.text = ""
	_update_context()
	_release_focus()


func begin_move() -> void:
	if not active or not furnishings.crates.has(selected_id):
		return
	placing = true
	preview_rotation_quarters = furnishings.crates[selected_id].rotation_quarters
	ghost.rotation = preview_rotation_quarters * PI / 2.0
	feedback.text = ""
	_update_context()
	_release_focus()


func rotate_selected() -> void:
	if not active:
		return
	if placing:
		preview_rotation_quarters = (preview_rotation_quarters + 1) % 4
		ghost.rotation = preview_rotation_quarters * PI / 2.0
	elif furnishings.rotate_crate(selected_id):
		feedback.text = "Rotated"
	_release_focus()


func cancel_preview() -> void:
	placing = false
	selected_id = ""
	preview_rotation_quarters = 0
	ghost.hide()
	feedback.text = ""
	_update_context()
	_release_focus()


func _update_context() -> void:
	var has_selection := active and furnishings.crates.has(selected_id)
	selection.visible = has_selection and not furnishings.crates[selected_id].recovery
	object_actions.visible = has_selection and not placing
	preview_rotate.visible = active and placing
	_update_object_actions()
	if not placing:
		hints.text = ""
	elif selected_id.is_empty():
		hints.text = "LMB Place    R Rotate    Esc Cancel"
	else:
		hints.text = "LMB Move    R Rotate    Esc Cancel"


func _update_object_actions() -> void:
	if not selection.visible:
		return
	var crate: ShipStorage = furnishings.crates[selected_id].node
	selection.global_position = crate.global_position
	# Convert the world anchor to CanvasLayer coordinates, including camera zoom.
	var screen_center := crate.get_global_transform_with_canvas().origin
	var half_height := 20.0 * crate.get_global_transform_with_canvas().get_scale().abs().y
	var desired := screen_center - Vector2(object_actions.size.x / 2.0, half_height + object_actions.size.y + 6.0)
	var viewport_size := get_viewport_rect().size
	object_actions.position = desired.clamp(Vector2(8, 8), viewport_size - object_actions.size - Vector2(8, 8))


func _release_focus() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()


func _process(_delta: float) -> void:
	_update_object_actions()
	ghost.visible = active and placing
	if not active or not placing:
		return
	preview_cell = furnishings.cell_at(get_global_mouse_position())
	ghost.global_position = furnishings.cell_center(preview_cell)
	var error := furnishings.placement_error(preview_cell, selected_id)
	ghost.modulate = Color(0.35, 1, 0.5, 0.65) if error.is_empty() else Color(1, 0.25, 0.25, 0.65)
	# Preserve explicit removal feedback until the pointer changes cells.
	if not feedback.text.begins_with("Empty this crate"):
		feedback.text = "Valid placement" if error.is_empty() else error


func _unhandled_input(event: InputEvent) -> void:
	if not active or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		if placing or not selected_id.is_empty():
			cancel_preview()
		else:
			exit_requested.emit()
	elif event.is_action_pressed("furnish_remove"):
		remove_selected()
	elif event.is_action_pressed("furnish_rotate"):
		rotate_selected()
	elif event.is_action_pressed("furnish_confirm"):
		if placing:
			confirm_at(furnishings.cell_at(get_global_mouse_position()))
		else:
			select_crate(furnishings.crate_at(furnishings.cell_at(get_global_mouse_position())))
	else:
		return
	get_viewport().set_input_as_handled()


func confirm_at(cell: Vector2i) -> bool:
	if not active or not placing:
		return false
	var error := furnishings.placement_error(cell, selected_id)
	if not error.is_empty():
		feedback.text = error
		return false
	var success: bool
	if selected_id.is_empty():
		success = not furnishings.create_crate(cell, preview_rotation_quarters).is_empty()
	else:
		success = furnishings.move_crate(selected_id, cell, preview_rotation_quarters)
	if success:
		cancel_preview()
		_refresh_recovery()
	else:
		feedback.text = "Cannot create another crate."
	return success


func remove_selected() -> void:
	if selected_id.is_empty():
		feedback.text = "Select a placed crate first."
		return
	if furnishings.remove_crate(selected_id):
		cancel_preview()
		_refresh_recovery()
	else:
		feedback.text = "Empty this crate before removing it."
	_release_focus()


func _refresh_recovery() -> void:
	recovery.clear()
	recovery_ids.clear()
	recovery.add_item("Crate needs placement…")
	for id: String in furnishings.crates:
		if furnishings.crates[id].recovery:
			recovery_ids.append(id)
			recovery.add_item("Recover Storage Crate %d" % recovery_ids.size())
	recovery.visible = not recovery_ids.is_empty()
	recovery.select(0)


func _select_recovery(index: int) -> void:
	if index > 0:
		select_crate(recovery_ids[index - 1])


func _refresh_owned() -> void:
	var quantity := furnishings.economy.owned_storage_crates() if furnishings.economy != null else 0
	var button: Button = $UI/Panel/Content/Toolbar/Cards/NewCrate
	button.text = "Storage Crate ×%d" % quantity
	button.disabled = quantity == 0
