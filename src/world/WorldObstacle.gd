extends StaticBody2D
## Side-view footprint; rear-lane gap remains inside the same FloorBand.
var object_id := ""
var floor_id := 0
var kind := ""
var blocks_walk := true
var width := 0.0
var occupied := true
var max_durability := 0.0
var durability := 0.0
var collision: CollisionShape2D
var defense := 0.0

func configure(spec: Dictionary, floor_y: float) -> void:
	name = spec.id
	object_id = spec.id
	floor_id = int(spec.floor_id)
	kind = spec.kind
	blocks_walk = bool(spec.get("blocks_walk", true))
	position = Vector2(Rules.body_to_px(spec.x), floor_y)
	width = Rules.body_to_px(spec.width)
	occupied = spec.get("occupied", true)
	max_durability = spec.get("max_durability", 0.0)
	if spec.has("tide_max_durability"):
		set_meta("tide_max_durability", float(spec.tide_max_durability))
	durability = max_durability
	collision_layer = 4
	collision_mask = 0
	collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, 16)
	collision.shape = shape
	collision.position = Vector2(width / 2.0, -8)
	collision.disabled = not occupied or not blocks_walk
	add_child(collision)
	add_to_group("obstacles")

func set_occupied(value: bool) -> void:
	occupied = value
	collision.set_deferred("disabled", not value or not blocks_walk)
	get_parent().redraw_geometry()

func set_durability(value: float) -> void:
	durability = clampf(value, 0, max_durability)

func blocking_rect() -> Rect2:
	return Rect2(position - Vector2(0, 16), Vector2(width, 16))

func receive_damage(amount: float) -> void:
	if max_durability <= 0 or not occupied:
		return
	set_durability(durability - amount)
	if durability <= 0:
		set_occupied(false)
