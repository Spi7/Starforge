class_name FurnishingShopUI
extends CanvasLayer

signal close_requested
signal open_requested

@export_range(1, 2147483647) var storage_crate_price: int = 250
var economy: SessionEconomy
var is_open := false

@onready var panel: Control = $Backdrop
@onready var cart: Button = $Cart
@onready var feedback: Label = $Backdrop/Center/Panel/Content/Feedback


func _ready() -> void:
	cart.pressed.connect(func() -> void: open_requested.emit())
	$Backdrop/Center/Panel/Content/Buy.pressed.connect(buy)
	$Backdrop/Center/Panel/Content/Close.pressed.connect(func() -> void: close_requested.emit())
	$FeedbackTimer.timeout.connect(func() -> void: feedback.text = "")
	panel.hide()
	set_access_available(false)


func set_access_available(available: bool) -> void:
	cart.visible = available
	cart.disabled = not available


func bind_economy(state: SessionEconomy) -> void:
	economy = state
	economy.changed.connect(_refresh)


func open() -> void:
	is_open = true
	set_access_available(false)
	feedback.text = ""
	panel.show()
	_refresh()
	$Backdrop/Center/Panel/Content/Buy.grab_focus()


func close() -> void:
	is_open = false
	panel.hide()
	$FeedbackTimer.stop()
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()


func buy() -> void:
	if not is_open:
		return
	if economy.purchase_storage_crate(storage_crate_price):
		feedback.text = "Purchased Storage Crate."
	elif economy.credits < storage_crate_price:
		feedback.text = "Not enough Credits."
	else:
		feedback.text = "Cannot own another Storage Crate."
	$FeedbackTimer.start()


func _refresh() -> void:
	if not is_open:
		return
	$Backdrop/Center/Panel/Content/Credits.text = "Credits: %d C" % economy.credits
	$Backdrop/Center/Panel/Content/Price.text = "%d C" % storage_crate_price


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action("interact") or event.is_action("inventory_toggle") or event.is_action("furnish_toggle"):
		get_viewport().set_input_as_handled()
