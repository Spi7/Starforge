class_name ShipFurnishings
extends Node

signal changed

const CRATE_SCENE := preload("res://scenes/ship/ship_storage.tscn")
const CRATE_CAPACITY := 40
# JSON numbers must remain exact. The final value is an exhausted-counter sentinel.
const MAX_NEXT_ID: int = 9007199254740991
const GRID_SIZE := 32

@export var reserved_cells: Array[Vector2i] = []
var next_placed_object_id: int = 1
# Each record owns a cell and a ShipStorage, including crates awaiting recovery.
var crates: Dictionary = {}
var economy: SessionEconomy
var player: Player
var pending_validation := false


static func object_id(sequence: int) -> String:
	return "placed_object_%06d" % sequence


static func id_sequence(id: String) -> int:
	if not id.begins_with("placed_object_"):
		return 0
	var digits := id.trim_prefix("placed_object_")
	if digits.is_empty() or digits.length() > 16:
		return 0
	for character in digits:
		if character < "0" or character > "9":
			return 0
	var sequence := digits.to_int()
	if sequence < 1 or sequence >= MAX_NEXT_ID or object_id(sequence) != id:
		return 0
	return sequence


func floor_layer() -> TileMapLayer:
	return get_parent().get_node("Floor")


func cell_at(global_point: Vector2) -> Vector2i:
	return floor_layer().local_to_map(floor_layer().to_local(global_point))


func cell_center(cell: Vector2i) -> Vector2:
	return floor_layer().to_global(floor_layer().map_to_local(cell))


func crate_at(cell: Vector2i) -> String:
	for id: String in crates:
		if not crates[id].recovery and crates[id].cell == cell:
			return id
	return ""


func placement_error(cell: Vector2i, moving_id: String = "", restoring: bool = false) -> String:
	if not is_inside_tree():
		return "Ship is not active."
	if floor_layer().get_cell_source_id(cell) == -1:
		return "Place on ship floor."
	if reserved_cells.has(cell):
		return "Keep this access space clear."
	var occupied := crate_at(cell)
	if not occupied.is_empty() and occupied != moving_id:
		return "Another crate occupies this cell."
	var center := cell_center(cell)
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE * (GRID_SIZE - 0.2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, center)
	query.collision_mask = 1
	# Occupancy is authoritative for dynamic crates, even before physics refreshes.
	var excluded: Array[RID] = []
	for record: Dictionary in crates.values():
		excluded.append(record.node.get_rid())
	if restoring and is_instance_valid(player):
		excluded.append(player.get_rid())
	query.exclude = excluded
	if not floor_layer().get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return "Blocked by player, wall, or fixed object."
	var footprint := Rect2(center - shape.size / 2, shape.size)
	for child in get_parent().get_node("WorldObjects").get_children():
		if child is WorldPickup and child.quantity > 0 and not child.is_queued_for_deletion():
			if footprint.intersects(Rect2(child.global_position - Vector2(7, 7), Vector2(14, 14))):
				return "Collect the pickup first."
	return ""


func create_crate(cell: Vector2i, rotation_quarters: int = 0) -> String:
	if economy == null or economy.owned_storage_crates() <= 0:
		return ""
	if rotation_quarters < 0 or rotation_quarters > 3:
		return ""
	if not placement_error(cell).is_empty() or next_placed_object_id >= MAX_NEXT_ID:
		return ""
	var id := object_id(next_placed_object_id)
	if crates.has(id):
		return ""
	var crate := add_restored_crate(id, cell, rotation_quarters)
	_activate_crate(id)
	next_placed_object_id += 1
	economy.consume_storage_crate()
	changed.emit()
	return crate.persistent_id


func add_restored_crate(id: String, cell: Vector2i, rotation_quarters: int = 0) -> ShipStorage:
	var crate: ShipStorage = CRATE_SCENE.instantiate()
	crate.persistent_id = id
	crate.display_title = "Storage Crate"
	crate.rotation = rotation_quarters * PI / 2.0
	crate.ensure_inventory()
	crate.visible = false
	crate.collision_layer = 0
	crate.get_node("Interactable").collision_layer = 0
	# Recovery nodes are owned here but have neither visible nor collidable presence.
	add_child(crate)
	crates[id] = {"cell": cell, "node": crate, "recovery": true, "rotation_quarters": rotation_quarters}
	crate.inventory.changed.connect(_inventory_changed)
	return crate


func _inventory_changed() -> void:
	changed.emit()


func validate_restored() -> void:
	if not pending_validation:
		return
	var ids := crates.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return id_sequence(a) < id_sequence(b))
	for id: String in ids:
		if placement_error(crates[id].cell, id, true).is_empty():
			_activate_crate(id)
	pending_validation = false


func _activate_crate(id: String) -> void:
	var record: Dictionary = crates[id]
	var crate: ShipStorage = record.node
	var objects := get_parent().get_node("WorldObjects")
	if crate.get_parent() != objects:
		crate.reparent(objects, false)
	crate.global_position = cell_center(record.cell)
	crate.visible = true
	crate.collision_layer = 1
	crate.get_node("Interactable").collision_layer = 2
	record.recovery = false


func move_crate(id: String, cell: Vector2i, rotation_quarters: int = -1) -> bool:
	if not crates.has(id) or not placement_error(cell, id).is_empty():
		return false
	var record: Dictionary = crates[id]
	if rotation_quarters == -1:
		rotation_quarters = record.rotation_quarters
	if rotation_quarters < 0 or rotation_quarters > 3:
		return false
	if record.cell == cell and record.rotation_quarters == rotation_quarters and not record.recovery:
		return true
	record.cell = cell
	record.rotation_quarters = rotation_quarters
	record.node.rotation = rotation_quarters * PI / 2.0
	_activate_crate(id)
	changed.emit()
	return true


func rotate_crate(id: String) -> bool:
	if not crates.has(id):
		return false
	var record: Dictionary = crates[id]
	record.rotation_quarters = (record.rotation_quarters + 1) % 4
	record.node.rotation = record.rotation_quarters * PI / 2.0
	changed.emit()
	return true


func remove_crate(id: String) -> bool:
	if economy == null or not economy.can_return_storage_crate():
		return false
	if not crates.has(id):
		return false
	var crate: ShipStorage = crates[id].node
	for slot in crate.inventory.slots:
		if slot.item != null or slot.quantity != 0:
			return false
	crate.inventory.changed.disconnect(_inventory_changed)
	crates.erase(id)
	crate.get_parent().remove_child(crate)
	crate.queue_free()
	economy.return_storage_crate()
	changed.emit()
	return true
