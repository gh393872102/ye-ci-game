extends "res://src/combat/vfx/EffectCanvas.gd"
## Ruled ground seal with an open ledger and a ring of strokes that fill as the reading advances.
const SEAL := preload("res://assets/vfx/ink/register.png")
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
	var breath := .93 + .07 * sin(simulation.simulation_time * 3.4)
	draw_texture_rect(SEAL, Rect2(origin - Vector2(150, 52), Vector2(300, 96)), false, Color(1, .87, .77, breath))
	# A separate bead travels the full circuit once during the paid reading.
	var phase := TAU * progress - PI / 2
	var cursor := origin + Vector2(cos(phase) * 124, sin(phase) * 25)
	fleck(cursor - Vector2(4, 4), Vector2(8, 8), Color("ffdb90"))
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
	var count := maxi(4, ceili(origin.distance_to(target) / 12.0))
	var previous := origin
	for i in range(1, count + 1):
		var ratio := float(i) / count
		var point := pixel(origin.lerp(target, ratio) - Vector2(0, sin(ratio * PI) * 24))
		draw_line(previous, point, Color(CINNABAR, .84), 3)
		if ratio <= progress:
			draw_line(previous, point, Color(GILT, .93), 3)
		previous = point
