class_name ShipStorage
extends StaticBody2D

@export_range(1, 200) var slot_capacity: int = 40
@export var persistent_id: String = ""
@export var display_title: String = "Ship Storage"
var inventory: InventoryData


func _ready() -> void:
	ensure_inventory()


func ensure_inventory() -> void:
	if inventory == null:
		inventory = InventoryData.new(slot_capacity)


func _on_interacted(actor: Node) -> void:
	if actor is Player:
		(actor as Player).container_access_requested.emit(inventory, display_title)
