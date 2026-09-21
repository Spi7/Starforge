class_name SessionEconomy
extends RefCounted

signal changed

const STARTING_CREDITS := 1000
const MAX_BALANCE := 2147483647

var credits: int:
	get:
		return _credits
var _credits: int = STARTING_CREDITS
var _storage_crates: int = 0


func owned_storage_crates() -> int:
	return _storage_crates


func purchase_storage_crate(price: int) -> bool:
	if price <= 0 or price > credits or not can_return_storage_crate():
		return false
	_credits -= price
	_storage_crates += 1
	changed.emit()
	return true


func can_return_storage_crate() -> bool:
	return _storage_crates < MAX_BALANCE


# ShipFurnishings calls these only after committing the related world change.
func consume_storage_crate() -> bool:
	if _storage_crates <= 0:
		return false
	_storage_crates -= 1
	changed.emit()
	return true


func return_storage_crate() -> bool:
	if not can_return_storage_crate():
		return false
	_storage_crates += 1
	changed.emit()
	return true


func restore(balance: int, crates: int) -> bool:
	if balance < 0 or balance > MAX_BALANCE or crates < 0 or crates > MAX_BALANCE:
		return false
	_credits = balance
	_storage_crates = crates
	changed.emit()
	return true
