extends SceneTree

var failures: int = 0
var checks: int = 0
var iron: ItemDefinition = load("res://data/items/iron_ore.tres")
var copper: ItemDefinition = load("res://data/items/copper_ore.tres")
var nutrient: ItemDefinition = load("res://data/items/nutrient_pack.tres")
var tool: ItemDefinition = load("res://data/items/basic_mining_tool.tres")


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)


func run() -> void:
	test_definitions()
	test_stacking()
	test_transfers()
	await test_pickups()
	await test_ship_and_ui()
	await test_existing_interaction()
	print("M3 tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_definitions() -> void:
	var ids: Array[StringName] = []
	for item in [iron, copper, nutrient, tool]:
		check(item != null and item.id != &"" and item.max_stack >= 1, "Valid item definition")
		check(not ids.has(item.id), "Unique canonical item ID")
		ids.append(item.id)
	check(tool.max_stack == 1, "Tool is non-stackable")
	check(ItemDefinition.Category.size() == 7, "Exactly seven item categories")


func test_stacking() -> void:
	var inventory := InventoryData.new(2)
	check(inventory.add_item(iron, 40) == 40, "Initial addition")
	check(inventory.add_item(iron, 20) == 20 and inventory.slots[0].quantity == 60, "Normal stacking")
	check(inventory.add_item(iron, 60) == 60, "Overflow accepted")
	check(inventory.slots[0].quantity == 99 and inventory.slots[1].quantity == 21, "Overflow uses empty slot")
	var signals: Array[int] = [0]
	inventory.changed.connect(func() -> void: signals[0] += 1)
	check(inventory.add_item(copper, 1) == 0, "Full inventory rejects different item")
	check(signals[0] == 0 and inventory.slots[1].quantity == 21, "Failed add changes nothing")
	check(inventory.add_item(iron, 100) == 78, "Partial acceptance into remaining stack")
	check(signals[0] == 1, "One change notification for successful add")
	check(inventory.add_item(null, 1) == 0, "Null item rejected")
	check(inventory.add_item(iron, 0) == 0 and inventory.add_item(iron, -1) == 0, "Nonpositive additions rejected")
	var tools := InventoryData.new(2)
	check(tools.add_item(tool, 3) == 2, "Non-stackable partial acceptance")
	check(tools.slots[0].quantity == 1 and tools.slots[1].quantity == 1, "One tool per slot")
	check(InventoryData.new(0).add_item(iron, 1) == 0, "Zero-capacity inventory")
	var other := InventoryData.new(2)
	check(other.slots[0].item == null, "Inventory instances are independent")
	check(other.slots[0] != other.slots[1], "Slots are independent objects")
	var holes := InventoryData.new(2)
	holes.add_item(tool, 1)
	holes.add_item(iron, 90)
	holes.transfer_to(other, 0, 1)
	check(holes.add_item(iron, 20) == 20, "Addition with earlier empty slot")
	check(holes.slots[1].quantity == 99 and holes.slots[0].quantity == 11, "Existing stacks filled before earlier holes")


func test_transfers() -> void:
	var source := InventoryData.new(20)
	var destination := InventoryData.new(40)
	source.add_item(iron, 90)
	destination.add_item(iron, 20)
	check(source.transfer_to(destination, 0, 90) == 90, "Player to storage")
	check(source.slots[0].item == null and source.slots[0].quantity == 0, "Emptied source normalized")
	check(destination.slots[0].quantity == 99 and destination.slots[1].quantity == 11, "Transfer stacks correctly")
	check(destination.transfer_to(source, 1, 999) == 11, "Storage to player bounded by source")
	var small := InventoryData.new(1)
	small.add_item(iron, 90)
	var observed: Array[int] = []
	var observe_transfer: Callable = func() -> void: observed.append(source.slots[0].quantity + small.slots[0].quantity)
	source.changed.connect(observe_transfer)
	check(source.transfer_to(small, 0, 11) == 9, "Partial transfer")
	check(source.slots[0].quantity == 2 and small.slots[0].quantity == 99, "Partial transfer conserves quantities")
	check(observed == [101], "Observers see completed source and destination")
	check(source.transfer_to(small, 0, 2) == 0 and source.slots[0].quantity == 2, "Full target preserves source")
	check(source.transfer_to(source, 0, 2) == 0, "Self transfer rejected")
	check(source.transfer_to(small, -1, 1) == 0, "Invalid slot rejected")
	check(source.transfer_to(null, 0, 1) == 0, "Null destination rejected")
	check(source.transfer_to(destination, 0, -1) == 0, "Negative transfer rejected")
	source.changed.disconnect(observe_transfer)


func test_pickups() -> void:
	for scenario in range(4):
		var player: Player = load("res://scenes/characters/player.tscn").instantiate()
		root.add_child(player)
		var pickup: WorldPickup = load("res://scenes/items/world_pickup.tscn").instantiate()
		pickup.item = tool if scenario == 2 else iron
		pickup.quantity = 120 if scenario == 1 else (1 if scenario == 2 else 20)
		if scenario == 0 or scenario == 1:
			player.inventory.add_item(iron, 90)
			player.inventory.add_item(tool, 18 if scenario == 1 else 19)
		elif scenario == 2:
			player.inventory.add_item(tool, 20)
		root.add_child(pickup)
		(pickup.get_node("Interactable") as Interactable).interact(player)
		if scenario == 0:
			check(pickup.quantity == 11 and not pickup.is_queued_for_deletion(), "World partial pickup leaves 11")
			check(player.inventory.slots[0].quantity == 99, "Partial pickup fills existing stack")
		elif scenario == 1:
			check(pickup.quantity == 12 and not pickup.is_queued_for_deletion(), "World partial pickup leaves 12")
			check(player.inventory.slots[0].quantity == 99 and player.inventory.slots[19].quantity == 99, "Partial pickup accepts 108")
		elif scenario == 2:
			check(pickup.quantity == 1 and not pickup.is_queued_for_deletion(), "Zero acceptance leaves world tool unchanged")
		else:
			check(pickup.quantity == 0 and pickup.is_queued_for_deletion(), "Complete pickup removes world object")
			(pickup.get_node("Interactable") as Interactable).interact(player)
			check(player.inventory.slots[0].quantity == 20, "Queued pickup cannot be collected twice")
		if not pickup.is_queued_for_deletion():
			pickup.queue_free()
		player.queue_free()
		await process_frame


func test_ship_and_ui() -> void:
	var ship: Node2D = load("res://scenes/ship/starter_ship.tscn").instantiate()
	root.add_child(ship)
	await process_frame
	var player: Player = ship.get_node("WorldObjects/Player")
	var storage: ShipStorage = ship.get_node("WorldObjects/Crate")
	var ui = player.get_node("InventoryUI")
	check(player.inventory.slots.size() == 20 and storage.inventory.slots.size() == 40, "Configured player and ship capacities")
	var console: Interactable = ship.get_node("WorldObjects/ShipConsole/Interactable")
	var console_calls: Array[int] = [0]
	console.interacted.connect(func(actor: Node) -> void: console_calls[0] += 1 if actor == player else 0)
	player.global_position = console.global_position + Vector2(0, 28)
	await physics_frame
	await physics_frame
	player.interact_with_nearest()
	check(console_calls[0] == 1, "Nearest interaction reaches existing console with actor")
	var crate_area: Interactable = storage.get_node("Interactable")
	player.global_position = crate_area.global_position + Vector2(0, 24)
	await physics_frame
	await physics_frame
	player.interact_with_nearest()
	check(ui.panel.visible and ui.storage == storage.inventory, "Nearest crate interaction opens storage UI")
	check(not player.controls_enabled, "UI blocks player controls")
	player.inventory.add_item(iron, 20)
	ui.player_list.select(0)
	ui.player_list.item_selected.emit(0)
	check(not ui.deposit_button.disabled, "Selecting occupied slot enables transfer")
	ui.deposit_button.pressed.emit()
	check(storage.inventory.slots[0].quantity == 20 and player.inventory.slots[0].item == null, "UI deposit stack")
	ui.storage_list.select(0)
	ui.storage_list.item_selected.emit(0)
	ui.withdraw_button.pressed.emit()
	check(player.inventory.slots[0].quantity == 20 and storage.inventory.slots[0].item == null, "UI withdraw stack")
	storage.inventory.add_item(iron, 90)
	storage.inventory.add_item(tool, 39)
	ui.player_list.select(0)
	ui.deposit_button.pressed.emit()
	check(player.inventory.slots[0].quantity == 11 and storage.inventory.slots[0].quantity == 99, "UI partial whole-stack transfer")
	ui.deposit_button.pressed.emit()
	check(player.inventory.slots[0].quantity == 11, "UI full destination preserves source")
	player.inventory.add_item(tool, 19)
	ui.storage_list.select(0)
	ui.withdraw_button.pressed.emit()
	check(player.inventory.slots[0].quantity == 99 and storage.inventory.slots[0].quantity == 11, "UI partial withdrawal preserves storage remainder")
	ui.withdraw_button.pressed.emit()
	check(storage.inventory.slots[0].quantity == 11, "UI full player preserves storage source")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	ui._input(cancel)
	check(not ui.panel.visible and player.controls_enabled and ui.storage == null, "Cancel closes UI and releases controls")
	var toggle := InputEventAction.new()
	toggle.action = &"inventory_toggle"
	toggle.pressed = true
	ui._input(toggle)
	check(ui.panel.visible and not ui.storage_column.visible, "Inventory action opens player-only UI")
	ui._input(toggle)
	check(not ui.panel.visible and player.controls_enabled, "Inventory action toggles closed")
	ship.queue_free()
	await process_frame


func test_existing_interaction() -> void:
	var scene: Node2D = load("res://scenes/test/movement_test.tscn").instantiate()
	root.add_child(scene)
	var player: Player = scene.get_node("Player")
	var target: Interactable = scene.get_node("TestInteractable/Interactable")
	var calls: Array[int] = [0]
	target.interacted.connect(func(actor: Node) -> void: calls[0] += 1 if actor == player else 0)
	player.global_position = target.global_position + Vector2(0, 24)
	await physics_frame
	await physics_frame
	player.interact_with_nearest()
	check(calls[0] == 1, "Existing test object still interacts")
	scene.queue_free()
	await process_frame
