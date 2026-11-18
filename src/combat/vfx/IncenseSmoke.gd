extends "res://src/combat/vfx/EffectCanvas.gd"
## Coiling ash-coloured ribbons from a lit ember during the real incense transfer / recovery.
const SMOKE := preload("res://assets/vfx/ink/incense.png")
const ASH := Color("c7c6b4")
const SHADE := Color("717d77")

func _draw() -> void:
	if simulation == null:
		return
	var roster: RefCounted = simulation.roster_engine()
	if roster == null:
		return
	for effect in roster.state.effects:
		if effect.kind not in ["incense_transfer", "incense_restored"]:
			continue
		var source := pixel(Vector2(effect.source[0], effect.source[1]))
		var target := pixel(Vector2(effect.point[0], effect.point[1]))
		if frame.has_point(source):
			_plume(source, target, 1.0 - float(effect.left) / float(effect.duration))

func _plume(source: Vector2, target: Vector2, phase: float) -> void:
	var bend := signf(target.x - source.x)
	if bend == 0.0:
		bend = 1.0
	var ember := pixel(source + Vector2(bend * 26, 12))
	var opacity := 1.0 - smoothstep(.62, 1.0, phase)
	var width := 81.0 + 14 * sin(phase * PI)
	var height := 140.0 + 33 * phase
	var drift := bend * (7 * sin(phase * PI) + 3 * sin(simulation.simulation_time * 4.0))
	draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE, drift / height, ember))
	# A soft dark edge keeps the pale rising strand legible against a lit room.
	draw_texture_rect(SMOKE, Rect2(-width * .48 + 3, -height + 3, width, height), false, Color(.19, .22, .27, opacity * .72))
	draw_texture_rect(SMOKE, Rect2(-width * .48, -height, width, height), false, Color(1, .99, .95, opacity))
	draw_set_transform(Vector2.ZERO)
