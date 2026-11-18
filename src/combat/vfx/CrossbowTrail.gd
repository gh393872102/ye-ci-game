extends "res://src/combat/vfx/EffectCanvas.gd"
## Draw along the swept projectile's actual travel, ending its streak at the collision.
const EDGE := Color("cdddc9")
const METAL := Color("78a39b")

func _draw() -> void:
	if simulation == null:
		return
	for shot in simulation.projectiles:
		if shot.kind != "bolt" or shot.direction.is_zero_approx() or not frame.has_point(shot.position):
			continue
		var length := 84.0
		if is_instance_valid(shot.owner_unit):
			length = clampf(Rules.body_to_px(shot.owner_unit.profile.range_body) - shot.distance_left, 0, length)
		_streak(shot.position, shot.direction, length)

func _streak(position_now: Vector2, direction: Vector2, length: float) -> void:
	var nose := pixel(position_now + direction * 8)
	var rear := pixel(position_now - direction * minf(length, 32))
	var perpendicular := direction.orthogonal()
	if length > 34.0:
		var start := pixel(position_now - direction * length)
		draw_line(start, rear, Color(METAL, .38), 3)
		for i in 3:
			fleck(start.lerp(rear, .33 * i), Vector2(4, 2), Color(METAL, .45 + .13 * i))
	draw_line(rear, nose, Color("2d4e4e"), 7)
	draw_line(rear, nose, EDGE, 3)
	draw_colored_polygon(PackedVector2Array([nose, pixel(nose - direction * 15 + perpendicular * 5), pixel(nose - direction * 11), pixel(nose - direction * 15 - perpendicular * 5)]), EDGE)
	if length > 18.0:
		for side in [-1, 1]:
			draw_line(pixel(rear - direction * 12 + perpendicular * (side * 5)), rear, METAL, 3)
