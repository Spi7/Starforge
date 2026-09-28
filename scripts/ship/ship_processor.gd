class_name ShipProcessor
extends StaticBody2D

signal changed

const PERSISTENT_ID := "starter_ship_processor_01"
const INPUT := preload("res://data/items/iron_ore.tres")
const OUTPUT := preload("res://data/items/iron_plate.tres")
const INPUT_QUANTITY := 10
const OUTPUT_QUANTITY := 1
const DURATION_SECONDS := 30.0
const MAX_INPUT_ORE := 100
const MAX_BATCH_UNITS := MAX_INPUT_ORE / INPUT_QUANTITY

@export var persistent_id: String = PERSISTENT_ID
var units_remaining := 0
var next_unit_deadline := 0.0
var held_output := 0


func is_idle() -> bool:
	return units_remaining == 0 and held_output == 0


func max_affordable_units(inventory: InventoryData) -> int:
	return mini(MAX_BATCH_UNITS, inventory.count_item(INPUT) / INPUT_QUANTITY) if inventory != null else 0


func start_job(inventory: InventoryData, quantity: int = 1) -> bool:
	if not is_idle() or inventory == null or quantity < 1 or quantity > MAX_BATCH_UNITS:
		return false
	if not inventory._remove_item(INPUT, quantity * INPUT_QUANTITY):
		return false
	next_unit_deadline = Time.get_unix_time_from_system() + DURATION_SECONDS
	units_remaining = quantity
	# Both objects are final before observers can save or repeat the action.
	inventory.changed.emit()
	changed.emit()
	return true


func refresh_completion(now: float = Time.get_unix_time_from_system()) -> bool:
	if units_remaining == 0 or now < next_unit_deadline:
		return false
	# Advance from the old deadline, preserving progress within the next interval.
	var completed := mini(units_remaining, 1 + int(floor((now - next_unit_deadline) / DURATION_SECONDS)))
	units_remaining -= completed
	held_output += completed * OUTPUT_QUANTITY
	next_unit_deadline = next_unit_deadline + completed * DURATION_SECONDS if units_remaining > 0 else 0.0
	changed.emit()
	return true


func collect(inventory: InventoryData) -> int:
	refresh_completion()
	if held_output == 0 or inventory == null:
		return 0
	var accepted := inventory._add_item(OUTPUT, held_output)
	if accepted == 0:
		return 0
	held_output -= accepted
	inventory.changed.emit()
	changed.emit()
	return accepted


func capture() -> Dictionary:
	return {"units_remaining": units_remaining, "next_unit_deadline": next_unit_deadline, "held_output": held_output}


func restore(data: Dictionary) -> bool:
	units_remaining = int(data.units_remaining)
	next_unit_deadline = float(data.next_unit_deadline)
	held_output = int(data.held_output)
	return refresh_completion()


static func idle_snapshot() -> Dictionary:
	return {"units_remaining": 0, "next_unit_deadline": 0.0, "held_output": 0}
