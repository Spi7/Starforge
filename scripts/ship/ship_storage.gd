class_name ShipStorage
extends StaticBody2D

@export_range(1, 200) var slot_capacity: int = 40
var inventory: InventoryData


func _ready() -> void:
	ensure_inventory()


func ensure_inventory() -> void:
	if inventory == null:
		inventory = InventoryData.new(slot_capacity)


func _on_interacted(actor: Node) -> void:
	if actor is Player:
		(actor as Player).container_access_requested.emit(inventory, "Ship Storage")
