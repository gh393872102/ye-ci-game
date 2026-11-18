extends "res://src/combat/vfx/EffectCanvas.gd"
## A cold lantern throws a narrow pool along the actual floor and lights the revealed footsteps in it.
const PALE := Color("b1e7d5")
const TEAL := Color("64ac9c")
const DEEP := Color("3b766f")

func _draw() -> void:
	if simulation == null:
		return
	var growth: RefCounted = simulation.growth_engine()
	if growth == null:
		return
	for field in growth.state.fields:
		var bone: bool = field.kind == "bone_lantern"
		if field.kind != "light" and not bone:
			continue
		var feet := pixel(Vector2(field.point[0], field.point[1]))
		var radius := Rules.body_to_px(float(Data.roster_rules.abilities.G11.radius) if bone else float(field.radius))
		if frame.grow(radius).has_point(feet):
			_lamp(feet, int(field.floor_id), radius, bone, clampf(float(field.left) * 4.2, .36, 1))

func _lamp(feet: Vector2, floor_id: int, radius: float, bone: bool, strength: float) -> void:
	var t: float = simulation.simulation_time
	var base := feet + Vector2(27, -26)
	var height := 33.0 if bone else 29.0
	var core := pixel(base - Vector2(0, height / 2))
	var ray_length := minf(radius, 278.0)
	draw_colored_polygon(PackedVector2Array([core, feet + Vector2(-ray_length, 6), feet + Vector2(-ray_length * .67, 14), feet + Vector2(128, 9)]), Color(DEEP, .092 * strength))
	for edge in 4:
		var offset := float(edge) * 5.0
		var glint := .4 + .6 * absf(sin(t * 3.1 + edge * 2.4))
		path(feet, [Vector2(-ray_length + 11 * edge, 6 + offset), Vector2(-ray_length * .5 - 4 * edge, -3 + offset), Vector2(120 - 10 * edge, 2 + offset)], Color(TEAL, .18 * glint * strength))
	for ring in 3:
		var size := Vector2(28 + ring * 16, height + ring * 14)
		draw_rect(Rect2(pixel(core - size / 2), size), Color(DEEP, .08 * strength))
	var mantle := PackedVector2Array([base + Vector2(-13, -height), base + Vector2(13, -height), base + Vector2(17, -height + 6), base + Vector2(13, -4), base + Vector2(7, 1), base + Vector2(-8, 1), base + Vector2(-14, -4), base + Vector2(-17, -height + 6)])
	draw_colored_polygon(mantle, Color("273936"))
	path(base, [Vector2(-17, -height + 6), Vector2(-12, -height), Vector2(13, -height), Vector2(17, -height + 6), Vector2(13, -4), Vector2(-14, -4), Vector2(-17, -height + 6)], Color(TEAL, .91 * strength), 3)
	path(base, [Vector2(-14, -height), Vector2(-6, -height - 7), Vector2(6, -height - 7), Vector2(14, -height)], Color(PALE, .67 * strength), 3)
	for rail in [-6, 5]:
		path(base, [Vector2(rail, -height + 4), Vector2(rail + 1, -5)], Color(PALE, .75 * strength))
	var flame := 9.0 + 5.0 * absf(sin(t * 11.0))
	draw_colored_polygon(PackedVector2Array([base + Vector2(-5, -7), base + Vector2(-4, -14), base + Vector2(2, -11 - flame), base + Vector2(6, -13), base + Vector2(4, -7)]), Color(PALE, .94 * strength))
	path(base, [Vector2(0, 2), Vector2(-1, 11), Vector2(3, 18)], Color(TEAL, .68 * strength))
	for i in 9:
		var phase := fposmod(t * .59 + i * .317, 1)
		fleck(base + Vector2((i - 4) * (4 + 5 * phase), -height - phase * 42), Vector2(2, 2), Color(PALE, .55 * (1.0 - phase) * strength))
	_steps(feet, floor_id, radius, strength)

func _steps(feet: Vector2, floor_id: int, radius: float, strength: float) -> void:
	var marked := 0
	for unit in simulation.floor_units.get(floor_id, []):
		if unit.dead or unit.position.distance_squared_to(feet) > radius * radius or not frame.has_point(unit.position):
			continue
		if not unit.roster.get("statuses", {}).has("revealed") and not unit.growth.get("statuses", {}).has("revealed"):
			continue
		for i in range(2):
			var at := pixel(unit.position + Vector2(-13 + i * 20, 2 + i * 5))
			path(at, [Vector2(-6, 0), Vector2(0, -4), Vector2(8, -2), Vector2(4, 2), Vector2(-4, 3)], Color(PALE, (.67 - .17 * i) * strength), 3)
		marked += 1
		if marked >= 8:
			return
