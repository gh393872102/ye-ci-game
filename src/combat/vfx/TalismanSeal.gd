extends "res://src/combat/vfx/EffectCanvas.gd"
## Ragged paper, fold, stamp and ink strokes shared by the door seal, mirror and exorcism.
const PAPER := preload("res://assets/vfx/ink/seal.png")
const AMBER := Color("e4ad76")
const INK := Color("5c2a26")
const RED := Color("cb6b48")

func _draw() -> void:
	if simulation == null:
		return
	var growth: RefCounted = simulation.growth_engine()
	if growth == null:
		return
	for id in growth.state.seals:
		var door: Node2D = simulation.world.get_node_or_null(id)
		if door == null or not frame.has_point(door.position):
			continue
		var foot := pixel(door.position)
		var pulse := .7 + .3 * absf(sin(simulation.simulation_time * 4.0))
		path(foot, [Vector2(-25, 0), Vector2(-25, -102), Vector2(-17, -115), Vector2(17, -115), Vector2(25, -102), Vector2(25, 0)], Color(RED, .58 * pulse), 4)
		_paper(foot + Vector2(0, -56), 1.0, pulse, false)
		fleck(foot + Vector2(-28, -8), Vector2(56, 4), Color(AMBER, .37 * pulse))
	for field in growth.state.fields:
		if field.kind == "paper_brace":
			var center := pixel(Vector2(field.point[0],field.point[1]-112))
			if frame.has_point(center): _broken_stamp(center,clampf(1.0-float(field.left)/0.65,0,1))
	var roster: RefCounted = simulation.roster_engine()
	if roster != null:
		for effect in roster.state.effects:
			_draw_cast(effect)

## The two sides of the vermilion stamp follow the combat layer's torn paper halves.
func _broken_stamp(center: Vector2,phase: float) -> void:
	var ink := Color("b23829",1.0-phase)
	for side in [-1,1]:
		var origin := center+Vector2(side*(9+24*phase),-20*phase)
		path(origin,[Vector2(-4*side,-11),Vector2(5*side,-11),Vector2(5*side,8),Vector2(-4*side,8)],ink,2)
		if phase<0.70:
			var flash := Color(AMBER,0.86*(1-phase/0.7))
			var tip := origin+Vector2(side*(17+34*phase),-8-18*phase)
			path(tip,[Vector2(-9*side,6),Vector2(0,0),Vector2(5*side,-6)],flash,3)
		for i in 3:
			var ash := origin+Vector2(side*(8+i*4+phase*12),12+i*6+20*phase*phase)
			fleck(ash,Vector2(3,2+i),Color(AMBER,(1-phase)*0.7))

func _draw_cast(effect: Dictionary) -> void:
	var kind: String = effect.kind
	if kind not in ["gold_mirror", "false_god_unmasked", "dispel", "misname"]:
		return
	var at := pixel(Vector2(effect.point[0], effect.point[1] - 40.0))
	if not frame.has_point(at):
		return
	var phase := clampf(1.0 - float(effect.left) / float(effect.duration), 0, 1)
	var alpha := 1.0 - phase * phase
	if kind == "gold_mirror":
		var outline := PackedVector2Array()
		for i in 9:
			outline.append(pixel(at + Vector2.from_angle(TAU * i / 8.0 + PI / 8) * Vector2(37, 42)))
		draw_colored_polygon(outline.slice(0, 8), Color("473737", .57 * alpha))
		draw_polyline(outline, Color(AMBER, .68 * alpha), 4)
		path(at, [Vector2(-19, 18), Vector2(-6, -18), Vector2(17, -25)], Color(AMBER, .58 * alpha))
		for side in [-1, 1]:
			_paper(at + Vector2(side * (37 + phase * 14), 12), .66, alpha, side > 0)
	elif kind == "misname":
		_paper(at, .78, alpha, false)
	else:
		for i in 3:
			var offset := Vector2((i - 1) * (25 + 36 * phase), -phase * (38 + 10 * i))
			_paper(at + offset, .64 - .15 * absf(i - 1), alpha, i % 2 == 0)
		for i in 7:
			var crumb := at + Vector2.from_angle(i * 2.39996) * (8.0 + phase * 60.0)
			fleck(crumb, Vector2(4, 3), Color(AMBER, alpha * .65))

func _paper(at: Vector2, size: float, alpha: float, reverse: bool) -> void:
	var paper_size := Vector2(53, 107) * size
	draw_set_transform(pixel(at), -.10 if reverse else .07, Vector2.ONE)
	draw_texture_rect(PAPER, Rect2(-paper_size / 2, paper_size), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO)
