extends "res://src/combat/vfx/EffectCanvas.gd"
## Draw along the swept projectile's actual travel, ending its streak at the collision.
const BOLT := preload("res://assets/vfx/ink/bolt.png")

func _draw() -> void:
	if simulation == null:
		return
	for shot in simulation.projectiles:
		if shot.kind != "bolt" or shot.direction.is_zero_approx() or not frame.has_point(shot.position):
			continue
		var length := 153.0
		if is_instance_valid(shot.owner_unit):
			length = clampf(Rules.body_to_px(shot.owner_unit.profile.range_body) - shot.distance_left, 0, length)
		_streak(shot.position, shot.direction, length)

func _streak(position_now: Vector2, direction: Vector2, length: float) -> void:
	var span := clampf(length + 16.0, 25.0, 169.0)
	var height := minf(49, span * .31)
	draw_set_transform(pixel(position_now), direction.angle(), Vector2.ONE)
	draw_texture_rect(BOLT, Rect2(-span + 9, -height * .5, span, height), false)
	draw_set_transform(Vector2.ZERO)
