extends Node2D
## Fixed-direction, finite-range projectile; swept collisions prevent tunneling.
var simulation: Node2D
var owner_unit: Node2D
var direction := Vector2.LEFT
var speed := 0.0
var distance_left := 0.0
var attack := 0.0
var side := "xianghuo"
var kind := "bolt"
var finished := false

func configure(sim: Node2D, shooter: Node2D, aim: Vector2) -> void:
	simulation = sim
	owner_unit = shooter
	position = shooter.aim_point()
	direction = position.direction_to(aim)
	speed = Rules.body_to_px(Rules.PROJECTILE_SPEED)
	distance_left = Rules.body_to_px(shooter.profile.range_body)
	attack = shooter.attack
	side = shooter.side
	kind = shooter.profile.projectile

func advance(delta: float) -> void:
	if finished or delta <= 0:
		return
	var distance := minf(speed * delta, distance_left)
	var destination := position + direction * distance
	var hit: Dictionary = simulation.projectile_hit(position, destination, side)
	if not hit.is_empty():
		position = hit.point
		var shooter: Node2D = owner_unit if is_instance_valid(owner_unit) else null
		if hit.has("unit"):
			simulation.deal_damage(shooter, hit.unit, "projectile", attack)
		else:
			simulation.record_event("projectile_blocked", shooter, hit.object.name)
		if kind == "bolt":
			simulation.vfx.bolt_hit(position, direction)
		finished = true
	else:
		position = destination
	distance_left -= distance
	if distance_left <= 0:
		finished = true
	queue_redraw()

func _draw() -> void:
	if kind == "talisman":
		draw_rect(Rect2(-7,-10,14,20),Color("cab782"))
		draw_line(Vector2(-2,-7),Vector2(2,7),Color("9a5145"),3)
