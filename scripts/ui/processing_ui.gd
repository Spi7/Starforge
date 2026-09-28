class_name ProcessingUI
extends CanvasLayer

signal close_requested

var is_open := false
var processor: ShipProcessor
var inventory: InventoryData
var selected_quantity := 1

@onready var content: Control = $Backdrop/Center/Window


func _ready() -> void:
	content.get_node("Action").pressed.connect(_act)
	content.get_node("Close").pressed.connect(func() -> void: close_requested.emit())
	content.get_node("Selection/Minus").pressed.connect(_change_quantity.bind(-1))
	content.get_node("Selection/Plus").pressed.connect(_change_quantity.bind(1))
	content.get_node("Selection/Max").pressed.connect(_select_max)
	$Backdrop.hide()


func open(station: ShipProcessor, player_inventory: InventoryData) -> void:
	processor = station
	inventory = player_inventory
	selected_quantity = 1
	is_open = true
	content.get_node("Feedback").text = ""
	$Backdrop.show()
	_refresh()
	content.get_node("Close").grab_focus()


func close() -> void:
	is_open = false
	$Backdrop.hide()
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()


func _change_quantity(amount: int) -> void:
	if not is_open or not processor.is_idle():
		return
	selected_quantity = clampi(selected_quantity + amount, 1, maxi(1, processor.max_affordable_units(inventory)))
	_refresh()


func _select_max() -> void:
	if not is_open or not processor.is_idle():
		return
	selected_quantity = maxi(1, processor.max_affordable_units(inventory))
	_refresh()


func _act() -> void:
	if not is_open:
		return
	content.get_node("Feedback").text = ""
	if processor.is_idle():
		processor.start_job(inventory, selected_quantity)
	else:
		var accepted := processor.collect(inventory)
		if accepted == 0 and processor.held_output > 0:
			content.get_node("Feedback").text = "Inventory Full"
		elif accepted > 0 and processor.held_output > 0:
			content.get_node("Feedback").text = "Collected %d; %d held" % [accepted, processor.held_output]
	_refresh()


func _process(_delta: float) -> void:
	if is_open:
		_refresh()


static func format_time(seconds: int) -> String:
	return "%dm %02ds" % [seconds / 60, seconds % 60] if seconds >= 60 else "%ds" % seconds


func _refresh() -> void:
	var idle := processor.is_idle()
	var active := processor.units_remaining > 0
	var affordable := processor.max_affordable_units(inventory)
	selected_quantity = clampi(selected_quantity, 1, maxi(1, affordable))
	content.get_node("Ore").text = "%d Iron Ore" % processor.INPUT_QUANTITY
	content.get_node("Plate").text = "%d Iron Plate" % processor.OUTPUT_QUANTITY
	content.get_node("Available").text = "Available: %d Iron Ore   •   %ds / Plate" % [inventory.count_item(processor.INPUT), processor.DURATION_SECONDS]
	content.get_node("Selection").visible = idle
	content.get_node("Production").visible = not idle
	content.get_node("Selection/Quantity").text = str(selected_quantity)
	content.get_node("Selection/Minus").disabled = selected_quantity <= 1
	content.get_node("Selection/Plus").disabled = selected_quantity >= affordable
	content.get_node("Selection/Max").disabled = affordable == 0
	content.get_node("Selection/Required").text = "Required: %d Iron Ore" % (selected_quantity * processor.INPUT_QUANTITY)
	content.get_node("Selection/Output").text = "Output: %d Iron Plates" % (selected_quantity * processor.OUTPUT_QUANTITY)
	content.get_node("Selection/Time").text = "Time: " + format_time(int(selected_quantity * processor.DURATION_SECONDS))
	var remaining_seconds := maxf(0.0, processor.next_unit_deadline - Time.get_unix_time_from_system())
	content.get_node("Production/Status").text = "PROCESSING" if active else "PRODUCTION COMPLETE"
	content.get_node("Production/Next").text = "Next Plate: %ds" % ceili(remaining_seconds) if active else "Iron Plate ×%d" % processor.held_output
	content.get_node("Production/Remaining").text = "Remaining: %d" % processor.units_remaining if active else "Ready to collect"
	var progress: TextureProgressBar = content.get_node("Production/Progress")
	progress.visible = active
	progress.value = clampf(1.0 - remaining_seconds / processor.DURATION_SECONDS, 0.0, 1.0) * 100.0
	content.get_node("Completed").visible = not idle
	content.get_node("OutputIcon").visible = not idle
	content.get_node("Completed").text = "Completed: %d Iron Plates" % processor.held_output
	var action: Button = content.get_node("Action")
	action.text = "START PROCESSING" if idle else ("COLLECT ×%d" % processor.held_output if active else "COLLECT ALL")
	action.disabled = affordable < selected_quantity if idle else processor.held_output == 0


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action("interact") or event.is_action("inventory_toggle") or event.is_action("furnish_toggle"):
		get_viewport().set_input_as_handled()
