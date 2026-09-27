class_name MiningOverflow
extends Node

signal changed

const PICKUP_SCENE := preload("res://scenes/items/world_pickup.tscn")
const IRON := preload("res://data/items/iron_ore.tres")
const ID_PREFIX := "mars_mining_overflow_"

var world_objects: Node2D
var next_id: int = 1
var pickups: Dictionary = {}


# Mining publishes its completed transaction after this silent spawn.
func spawn(quantity: int, position: Vector2) -> WorldPickup:
	var id := ID_PREFIX + str(next_id)
	next_id += 1
	return _create(id, quantity, position)


func _create(id: String, quantity: int, position: Vector2) -> WorldPickup:
	var pickup: WorldPickup = PICKUP_SCENE.instantiate()
	pickup.persistent_id = StringName(id)
	pickup.item = IRON
	pickup.quantity = quantity
	pickup.position = position
	pickups[id] = pickup
	pickup.quantity_changed.connect(_quantity_changed.bind(id))
	world_objects.add_child(pickup)
	return pickup


func _quantity_changed(remaining: int, id: String) -> void:
	if remaining == 0:
		pickups.erase(id)
	changed.emit()


func capture() -> Dictionary:
	var entries: Array = []
	for id: String in pickups:
		var pickup: WorldPickup = pickups[id]
		if pickup.quantity > 0:
			entries.append({"persistent_id": id, "item_id": String(IRON.id), "quantity": pickup.quantity,
				"position": {"x": pickup.position.x, "y": pickup.position.y}})
	return {"next_id": next_id, "pickups": entries}


func restore(data: Dictionary) -> void:
	for pickup: WorldPickup in pickups.values():
		pickup.free()
	pickups.clear()
	next_id = int(data.next_id)
	for entry: Dictionary in data.pickups:
		_create(entry.persistent_id, int(entry.quantity), Vector2(entry.position.x, entry.position.y))


static func validate(data: Variant) -> String:
	if not data is Dictionary or not _integer(data.get("next_id"), 1, 9007199254740991):
		return "Invalid mining overflow counter"
	if not data.get("pickups") is Array:
		return "Invalid mining overflow pickups"
	var seen := {}
	for entry: Variant in data.pickups:
		if not entry is Dictionary:
			return "Invalid mining overflow record"
		var id: Variant = entry.get("persistent_id")
		if not id is String or not id.begins_with(ID_PREFIX) or seen.has(id):
			return "Invalid mining overflow identity"
		var sequence := int(id.trim_prefix(ID_PREFIX))
		if sequence < 1 or sequence >= data.next_id or id != ID_PREFIX + str(sequence):
			return "Invalid mining overflow sequence"
		seen[id] = true
		if entry.get("item_id") != String(IRON.id) or not _integer(entry.get("quantity"), 1, 3):
			return "Invalid mining overflow item or quantity"
		var position: Variant = entry.get("position")
		if not position is Dictionary:
			return "Invalid mining overflow position"
		for axis in ["x", "y"]:
			var value: Variant = position.get(axis)
			if not (value is float or value is int):
				return "Invalid mining overflow position"
			if not is_finite(float(value)) or value < 0 or value > (1280 if axis == "x" else 960):
				return "Invalid mining overflow position"
	return ""


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and floor(float(value)) == value
