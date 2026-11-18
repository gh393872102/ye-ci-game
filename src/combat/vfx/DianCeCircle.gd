extends "res://src/combat/vfx/EffectCanvas.gd"
## Ruled ground seal with an open ledger and a ring of strokes that fill as the reading advances.
const GILT := Color("f3bd78")
const CHALK := Color("e1c39a")
const CINNABAR := Color("b6583c")

func _draw() -> void:
	if simulation == null:
		return
	for reader in simulation.humans:
		if reader.dead or reader.role != "ritual" or not reader.brain.channel.active:
			continue
		var channel: RefCounted = reader.brain.channel
		if not is_instance_valid(channel.target):
			continue
		var floor_y: float = simulation.world.floor_y(reader.floor_id)
		var origin := pixel(Vector2(reader.position.x, minf(reader.position.y - 6, floor_y - 35)))
		var target := pixel(channel.target.position)
		if frame.has_point(origin):
			_circle(origin, channel.progress())
		if frame.has_point(target):
			_binding(origin, target, channel.progress())

func _circle(origin: Vector2, progress: float) -> void:
	var rx := 127.0
	var ry := 34.0
	var t: float = simulation.simulation_time
	for ring in 3:
		var ellipse := PackedVector2Array()
		var bounds := Vector2(rx - 9 * ring, ry - 5 * ring)
		for i in 49:
			ellipse.append(pixel(origin + Vector2.from_angle(TAU * i / 48.0) * bounds))
		draw_polyline(ellipse, Color(CINNABAR, .32) if ring != 1 else Color(GILT, .75), 3.0 if ring != 1 else 2.0)
	for i in 36:
		var axis := Vector2.from_angle(TAU * i / 36.0 + PI / 2)
		var a := pixel(origin + axis * Vector2(rx - 14, ry - 9))
		var b := pixel(origin + axis * Vector2(rx - (3 if i % 3 == 0 else 8), ry - 4))
		var lit := float(i) / 36.0 < progress
		draw_line(a, b, Color(CHALK, .95 if lit else .42), 4 if i % 3 == 0 else 2)
	for i in 12:
		var phase := fposmod(t * .53 + float(i) * .279, 1)
		var axis := Vector2.from_angle(i * 2.39996)
		var at := origin + axis * Vector2(rx - 5, ry + 2) - Vector2(0, phase * 26)
		fleck(at, Vector2(4 if i % 4 == 0 else 2, 2), Color(GILT, (1 - phase) * .75))
	var book := origin + Vector2(-64, -31)
	var pages := PackedVector2Array([book + Vector2(-27, -14), book + Vector2(-5, -11), book, book + Vector2(7, -12), book + Vector2(28, -15), book + Vector2(27, 6), book + Vector2(8, 10), book + Vector2(-3, 11), book + Vector2(-27, 5)])
	draw_colored_polygon(pages, Color("472b26"))
	path(book, [Vector2(-27, -14), Vector2(-5, -11), Vector2(0, 0), Vector2(7, -12), Vector2(28, -15)], Color(GILT, .86))
	path(book, [Vector2(-27, 5), Vector2(-3, 11), Vector2(8, 10), Vector2(27, 6)], Color(CINNABAR, .9))
	for line in 3:
		var y := -9 + 5 * line
		path(book, [Vector2(-22, y), Vector2(-9, y + 2)], Color(CHALK, .72))
		path(book, [Vector2(9, y + 1), Vector2(22, y - 2)], Color(CHALK, .72))

func _binding(origin: Vector2, target: Vector2, progress: float) -> void:
	# Hooks by the target's feet and a sparse ink thread avoid covering either unit's body.
	for mirror in [-1, 1]:
		path(target, [Vector2(mirror * 44, -14), Vector2(mirror * 38, -3), Vector2(mirror * 23, 2)], Color(CINNABAR, .92), 4)
		fleck(target + Vector2(mirror * 31, -8), Vector2(4, 4), Color(GILT, .86))
	var count := int(minf(origin.distance_to(target) / 20.0, 15))
	for i in range(1, count):
		var ratio := float(i) / count
		var point := origin.lerp(target, ratio) + Vector2(0, sin(ratio * PI) * 12)
		fleck(point, Vector2(4, 2), Color(GILT, .76 if ratio < progress else .26))
