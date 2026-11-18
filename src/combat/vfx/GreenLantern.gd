extends "res://src/combat/vfx/EffectCanvas.gd"
## A cold lantern throws a narrow pool along the actual floor and lights the revealed footsteps in it.
const LANTERN := preload("res://assets/vfx/ink/lantern.png")
const PALE := Color("b1e7d5")
const TEAL := Color("64ac9c")
const DEEP := Color("3b766f")
var pool := GradientTexture2D.new()

func _ready() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	gradient.colors = PackedColorArray([Color("80e0cb80"), Color("50aaa74a"), Color("43939300")])
	pool.gradient = gradient
	pool.fill = GradientTexture2D.FILL_RADIAL
	pool.fill_from = Vector2(.5, .5)
	pool.fill_to = Vector2(1, .5)
	pool.width = 192
	pool.height = 64

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
	var sway := sin(t * 2.4) * 3.0
	var center := pixel(feet + Vector2(30 + sway, -66))
	var ray_length := minf(radius, 243.0)
	var ground := feet + Vector2(0, -4)
	draw_texture_rect(pool, Rect2(ground - Vector2(ray_length, 29), Vector2(ray_length + 82, 45)), false, Color(1, 1, 1, strength))
	draw_texture_rect(pool, Rect2(center - Vector2(79, 72), Vector2(158, 144)), false, Color(1, 1, 1, strength * .65))
	var size := Vector2(73, 111) if bone else Vector2(68, 103)
	draw_texture_rect(LANTERN, Rect2(center - size / 2, size), false, Color(1, 1, 1, .7 + strength * .3))
	for i in 5:
		var phase := fposmod(t * .54 + i * .317, 1)
		fleck(center + Vector2((i-2) * 8.5, -21 - phase * 38), Vector2(3, 3), Color(PALE, .62 * (1-phase)))
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
