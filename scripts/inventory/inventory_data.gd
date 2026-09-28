class_name InventoryData
extends RefCounted

signal changed

var slots: Array[InventorySlot] = []


func count_item(item: ItemDefinition) -> int:
	var count := 0
	for slot in slots:
		if item != null and slot.item != null and slot.item.id == item.id:
			count += slot.quantity
	return count


func remove_item(item: ItemDefinition, quantity: int) -> bool:
	if not _remove_item(item, quantity):
		return false
	changed.emit()
	return true


# Silent mutation allows callers to publish a completed multi-object transaction.
func _remove_item(item: ItemDefinition, quantity: int) -> bool:
	if item == null or quantity <= 0 or count_item(item) < quantity:
		return false
	var remaining := quantity
	for slot in slots:
		if slot.item != null and slot.item.id == item.id:
			var amount := mini(remaining, slot.quantity)
			slot.quantity -= amount
			remaining -= amount
			if slot.quantity == 0:
				slot.item = null
			if remaining == 0:
				break
	return true


func _init(capacity: int = 20) -> void:
	for index in range(maxi(capacity, 0)):
		slots.append(InventorySlot.new())


func add_item(item: ItemDefinition, requested_quantity: int) -> int:
	var accepted: int = _add_item(item, requested_quantity)
	if accepted > 0:
		changed.emit()
	return accepted


func _add_item(item: ItemDefinition, requested_quantity: int) -> int:
	if item == null or item.id == &"" or item.max_stack < 1 or requested_quantity <= 0:
		return 0
	var remaining: int = requested_quantity
	for slot in slots:
		if slot.item != null and slot.item.id == item.id:
			var amount: int = mini(remaining, maxi(slot.item.max_stack - slot.quantity, 0))
			slot.quantity += amount
			remaining -= amount
			if remaining == 0:
				return requested_quantity
	for slot in slots:
		if slot.item == null:
			var amount: int = mini(remaining, item.max_stack)
			slot.item = item
			slot.quantity = amount
			remaining -= amount
			if remaining == 0:
				break
	return requested_quantity - remaining


func transfer_to(destination: InventoryData, source_slot_index: int, requested_quantity: int) -> int:
	if destination == null or destination == self or requested_quantity <= 0:
		return 0
	if source_slot_index < 0 or source_slot_index >= slots.size():
		return 0
	var source: InventorySlot = slots[source_slot_index]
	if source.item == null:
		return 0
	# Notify observers only after both sides contain their final quantities.
	var accepted: int = destination._add_item(source.item, mini(requested_quantity, source.quantity))
	if accepted > 0:
		source.quantity -= accepted
		if source.quantity == 0:
			source.item = null
		changed.emit()
		destination.changed.emit()
	return accepted
