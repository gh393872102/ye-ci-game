extends StaticBody2D
## P1 spatial gate. Durability is an interface only; no attack/damage implementation.
signal state_changed
var door_id := ""
var floor_id := 0
var connected_rooms: Array = []
var is_open := false
var starts_open := false
var max_durability := 0.0
var durability := 0.0
var collision: CollisionShape2D
var destroyed := false
var defense := 0.0

func configure(spec: Dictionary, floor_y: float) -> void:
	name = spec.id
	door_id = spec.id
	floor_id = int(spec.floor_id)
	connected_rooms = spec.rooms
	position = Vector2(Rules.body_to_px(spec.x), floor_y)
	max_durability = spec.max_durability
	durability = max_durability
	is_open = spec.open
	starts_open = is_open
	collision_layer = 2
	collision_mask = 0
	collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, Rules.DOOR_HEIGHT_PX)
	collision.shape = shape
	collision.position.y = -Rules.DOOR_HEIGHT_PX / 2.0
	collision.disabled = is_open
	add_child(collision)
	add_to_group("doors")

func set_open(value: bool) -> void:
	is_open = value
	collision.set_deferred("disabled", value)
	state_changed.emit()

func set_durability(value: float) -> void:
	durability = clampf(value, 0.0, max_durability)
	# P2/P3 own destruction/repair transitions. P1 does not silently open the door.
	state_changed.emit()

func blocking_rect() -> Rect2:
	return Rect2(position - Vector2(8, Rules.DOOR_HEIGHT_PX), Vector2(16, Rules.DOOR_HEIGHT_PX))

func receive_damage(amount: float) -> void:
	if destroyed:
		return
	set_durability(durability - amount)
	if durability <= 0:
		destroyed = true
		set_open(true)
