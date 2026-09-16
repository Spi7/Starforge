extends CanvasLayer

var player: Player
var storage: InventoryData

@onready var panel: PanelContainer = $Margin/Panel
@onready var player_list: ItemList = $Margin/Panel/Content/Inventories/PlayerColumn/Slots
@onready var storage_column: VBoxContainer = $Margin/Panel/Content/Inventories/StorageColumn
@onready var storage_list: ItemList = $Margin/Panel/Content/Inventories/StorageColumn/Slots
@onready var deposit_button: Button = $Margin/Panel/Content/Inventories/PlayerColumn/Transfer
@onready var withdraw_button: Button = $Margin/Panel/Content/Inventories/StorageColumn/Transfer


func _ready() -> void:
	player = get_parent() as Player
	player.container_access_requested.connect(open_storage)
	player.inventory_feedback.connect(show_feedback)
	player.inventory.changed.connect(_refresh)
	player_list.item_selected.connect(_on_selection_changed)
	storage_list.item_selected.connect(_on_selection_changed)
	deposit_button.pressed.connect(_transfer.bind(true))
	withdraw_button.pressed.connect(_transfer.bind(false))
	$Margin/Panel/Content/Close.pressed.connect(close)
	$FeedbackTimer.timeout.connect(_clear_feedback)
	panel.hide()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_toggle") and not event.is_echo():
		if panel.visible:
			close()
		else:
			_open()
		get_viewport().set_input_as_handled()
	elif panel.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif panel.visible and event.is_action("interact"):
		get_viewport().set_input_as_handled()


func open_storage(container: InventoryData, title: String) -> void:
	close()
	storage = container
	storage.changed.connect(_refresh)
	$Margin/Panel/Content/Inventories/StorageColumn/Title.text = title
	_open()


func _open() -> void:
	player.controls_enabled = false
	player.velocity = Vector2.ZERO
	panel.show()
	storage_column.visible = storage != null
	deposit_button.visible = storage != null
	_refresh()
	player_list.grab_focus()


func close() -> void:
	if storage != null:
		storage.changed.disconnect(_refresh)
		storage = null
	panel.hide()
	player_list.deselect_all()
	storage_list.deselect_all()
	player.controls_enabled = true


func _refresh() -> void:
	if not panel.visible:
		return
	_fill_list(player_list, player.inventory)
	$Margin/Panel/Content/Inventories/PlayerColumn/Capacity.text = _capacity_text(player.inventory)
	if storage != null:
		_fill_list(storage_list, storage)
		$Margin/Panel/Content/Inventories/StorageColumn/Capacity.text = _capacity_text(storage)
	_update_buttons()


func _fill_list(list: ItemList, inventory: InventoryData) -> void:
	var selected: PackedInt32Array = list.get_selected_items()
	list.clear()
	for index in range(inventory.slots.size()):
		var slot: InventorySlot = inventory.slots[index]
		if slot.item == null:
			list.add_item("%02d  — Empty" % [index + 1], null, false)
		else:
			list.add_item("%02d  %s x%d" % [index + 1, slot.item.display_name, slot.quantity], slot.item.icon)
			list.set_item_tooltip(index, slot.item.description)
			if selected.has(index):
				list.select(index)


func _capacity_text(inventory: InventoryData) -> String:
	var occupied: int = 0
	for slot in inventory.slots:
		if slot.item != null:
			occupied += 1
	return "%d / %d slots occupied" % [occupied, inventory.slots.size()]


func _on_selection_changed(_index: int) -> void:
	_update_buttons()


func _update_buttons() -> void:
	deposit_button.disabled = storage == null or player_list.get_selected_items().is_empty()
	withdraw_button.disabled = storage == null or storage_list.get_selected_items().is_empty()


func _transfer(to_storage: bool) -> void:
	if storage == null:
		return
	var source: InventoryData = player.inventory if to_storage else storage
	var destination: InventoryData = storage if to_storage else player.inventory
	var list: ItemList = player_list if to_storage else storage_list
	var selected: PackedInt32Array = list.get_selected_items()
	if selected.is_empty():
		return
	var index: int = selected[0]
	var requested: int = source.slots[index].quantity
	var accepted: int = source.transfer_to(destination, index, requested)
	show_feedback("Transferred %d; %d remain in source." % [accepted, requested - accepted])


func show_feedback(message: String) -> void:
	$Feedback.text = message
	$FeedbackTimer.start()


func _clear_feedback() -> void:
	$Feedback.text = ""
