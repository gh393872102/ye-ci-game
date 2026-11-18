extends "res://src/combat/vfx/EffectCanvas.gd"
## Coiling ash-coloured ribbons from a lit ember during the real incense transfer / recovery.
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
	var length := minf(absf(target.x - source.x) * .27 + 15, 75)
	var ember := source + Vector2(bend * 26, 12)
	var opacity := 1.0 - clampf(phase, 0, 1) ** 2.0
	path(ember, [Vector2(-14, 2), Vector2(-9, 9), Vector2(9, 9), Vector2(14, 2)], Color("a07f61", opacity), 4)
	path(ember, [Vector2(-12, 1), Vector2(13, 1)], Color("bd9173", opacity), 4)
	fleck(ember + Vector2(-4, -5), Vector2(8, 5), Color(Color("efac62"), opacity))
	for ribbon in 3:
		var older := .2 * ribbon
		var previous := ember
		for i in range(1, 16):
			var weight := float(i) / 15.0
			var wave := sin(weight * 7.0 + phase * 3.4 + ribbon * .8)
			var width := (6 + 14 * sin(weight * PI)) * (1.0 - .22 * ribbon)
			var drift := Vector2(bend * (length * weight * weight + wave * width), -weight * (79 + 41 * phase) - 9 * ribbon)
			var at := pixel(ember + drift, 3)
			var alpha := opacity * (1.0 - weight * .80) * (1.0 - older)
			draw_line(previous, at, Color(SHADE, .31 * alpha), 9 - ribbon * 2)
			draw_line(previous, at, Color(ASH, .66 * alpha), 3)
			if i % 3 == ribbon:
				fleck(at + Vector2(3 + ribbon * 3, -4), Vector2(3, 3), Color(ASH, .38 * alpha))
			previous = at
