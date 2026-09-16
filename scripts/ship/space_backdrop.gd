extends Control

@export var star_spacing: int = 72
@export var star_seed: int = 350


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("080e19"))
	var random := RandomNumberGenerator.new()
	random.seed = star_seed
	var spacing: int = maxi(star_spacing, 16)
	for y in range(0, ceili(size.y), spacing):
		for x in range(0, ceili(size.x), spacing):
			var point := Vector2(x + random.randi_range(0, spacing - 1), y + random.randi_range(0, spacing - 1))
			var brightness: float = random.randf_range(0.25, 0.65)
			var extent: int = 2 if random.randf() < 0.08 else 1
			draw_rect(Rect2(point, Vector2(extent, extent)), Color(brightness * 0.7, brightness * 0.85, brightness))
