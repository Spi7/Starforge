class_name ItemDefinition
extends Resource

enum Category { RESOURCE, CONSUMABLE, TOOL, WEAPON, SUIT, MODULE, QUEST }

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export_range(1, 9999) var max_stack: int = 99
@export var category: Category = Category.RESOURCE
