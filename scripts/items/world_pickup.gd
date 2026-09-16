class_name WorldPickup
extends Node2D

@export var item: ItemDefinition
@export_range(1, 99999) var quantity: int = 1


func _ready() -> void:
	_refresh_label()


func _refresh_label() -> void:
	$QuantityLabel.text = "%s x%d" % [item.display_name if item != null else "Missing item", quantity]


func _on_interacted(actor: Node) -> void:
	if not actor is Player or quantity <= 0 or is_queued_for_deletion():
		return
	var player: Player = actor as Player
	var accepted: int = player.inventory.add_item(item, quantity)
	if accepted == 0:
		player.inventory_feedback.emit("No room for this pickup.")
		return
	quantity -= accepted
	player.inventory_feedback.emit("Picked up %d; %d remain." % [accepted, quantity])
	if quantity == 0:
		queue_free()
	else:
		_refresh_label()
