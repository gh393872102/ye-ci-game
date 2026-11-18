extends "res://src/combat/vfx/EffectCanvas.gd"
## Presentation only. Live pose/cast state draws the five scene prefabs; short impacts follow real events.
const IMPACT := preload("res://assets/vfx/ink/impact.png")
const BONE := Color("d1d0b8")
const DUST := Color("87968a")
const BRICK := Color("ae7559")
const OCHRE := Color("edb477")
const MAX_CUES := 24

var cues: Array[Dictionary] = []
var breached_doors: Dictionary = {}
var painters: Array[Node]
var redraw_needed := true
var last_step := -1

func _ready() -> void:
	painters = get_children()
	for painter in painters:
		painter.simulation = simulation
	if simulation.tide != null:
		simulation.tide.effect_emitted.connect(_on_tide_effect)
	simulation.step_completed.connect(_after_step)
	simulation.event_recorded.connect(_on_event)
	set_process(DisplayServer.get_name() != "headless")

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	var world_frame: Rect2 = (camera.world_rect() if camera != null and camera.has_method("world_rect") else Rect2(0, 0, Rules.REFERENCE_MAP_WIDTH_PX, Rules.HORIZON_Y)).grow(150)
	if not redraw_needed and last_step == simulation.step_index and frame == world_frame:
		return
	last_step = simulation.step_index
	redraw_needed = false
	refresh(world_frame)
	for painter in painters:
		painter.refresh(world_frame)

func invalidate() -> void:
	redraw_needed = true

func reset() -> void:
	cues.clear()
	breached_doors.clear()
	invalidate()

func _after_step(delta: float) -> void:
	for i in range(cues.size() - 1, -1, -1):
		if simulation.simulation_time >= float(cues[i].start) + float(cues[i].duration):
			cues.remove_at(i)
	for id in breached_doors.keys():
		var door: Node2D = simulation.world.get_node_or_null(id)
		if door == null or not door.destroyed:
			breached_doors.erase(id)
			continue
		var threshold := door.position.x + Rules.FOOT_RADIUS_PX
		for actor in simulation.floor_units.get(door.floor_id, []):
			if actor.dead or actor.side != "yegui" or actor.position.x <= threshold or actor.position.x - actor.velocity.x * delta > threshold:
				continue
			var first: String = breached_doors[id]
			if first.is_empty():
				breached_doors[id] = actor.instance_id
			elif first != actor.instance_id:
				_surge(door)
				break

func _on_tide_effect(kind: String, point: Vector2, detail: String) -> void:
	match kind:
		"door_break":
			_add_cue("door_break", point, 1.24, detail)
			breached_doors[detail] = ""
		"upper_entry":
			_add_cue("upper_entry", point, .93, detail)

func _on_event(kind: String, actor: Node2D, detail: String) -> void:
	invalidate()
	match kind:
		"p10_tide_flood":
			# Authored stages already count genuine incursions, including arrivals by scripted formations.
			_surge(simulation.world.get_node(detail))
		"p10_upper_lost":
			if is_instance_valid(actor):
				_add_cue("upper_lost", actor.position, 1.85, detail)

func _surge(door: Node2D) -> void:
	breached_doors.erase(str(door.name))
	if cues.any(func(cue): return cue.kind == "door_surge" and cue.detail == str(door.name)):
		return
	_add_cue("door_surge", door.position, 1.76, str(door.name))

func purification(at: Vector2, recruited: bool, restored_names: bool) -> void:
	_add_cue("give_face" if recruited else "send_off", at, 1.52)
	if restored_names:
		var desk: Node2D = simulation.world.get_node_or_null("register_desk")
		if desk != null:
			_add_cue("register_relight", desk.position, 2.35)

func fusion(at: Vector2, second: Vector2, height: float, recipe: String) -> void:
	_add_cue("fusion", at, 1.64, recipe, {"second":second, "height":height})

func bolt_hit(at: Vector2, direction: Vector2) -> void:
	_add_cue("bolt_hit", at, .24, "", {"direction":direction})

func _add_cue(kind: String, at: Vector2, duration: float, detail := "", extra := {}) -> void:
	if cues.size() >= MAX_CUES:
		var earliest_hit := cues.find_custom(func(cue): return cue.kind == "bolt_hit")
		if earliest_hit < 0 and kind == "bolt_hit":
			return
		cues.remove_at(maxi(earliest_hit, 0))
	var cue := {"kind":kind, "point":at, "duration":duration, "start":simulation.simulation_time, "detail":detail}
	cue.merge(extra)
	cues.append(cue)
	invalidate()

func _draw() -> void:
	if simulation == null:
		return
	if simulation.growth_engine() != null:
		_draw_marks()
	for cue in cues:
		var at := pixel(cue.point)
		if not frame.has_point(at):
			continue
		var phase := clampf((simulation.simulation_time - float(cue.start)) / float(cue.duration), 0, 1)
		match str(cue.kind):
			"door_break": _splinters(at, phase)
			"door_surge": _surge_dust(at, phase)
			"upper_entry": _pounce(at, phase)
			"upper_lost": _lost_room(at, phase)
			"give_face", "send_off": _face(at, phase, cue.kind == "give_face")
			"register_relight": _relight(at, phase)
			"fusion": _fusion(at, cue.second, cue.height, phase)
			"bolt_hit": _bolt_spark(at, cue.direction, phase)

func _draw_marks() -> void:
	for actor in simulation.humans + simulation.targets:
		if actor.dead or not frame.has_point(actor.position):
			continue
		var statuses: Dictionary = actor.growth.get("statuses", {})
		var head := pixel(actor.position - Vector2(0, actor.height_px - 9.0))
		if statuses.has("revealed"):
			path(head, [Vector2(-24, 1), Vector2(-22, -7), Vector2(-17, -10)], Color(BONE, .56))
			path(head, [Vector2(24, 1), Vector2(22, -7), Vector2(17, -10)], Color(BONE, .56))
		if statuses.has("fear"):
			path(head, [Vector2(26, 20), Vector2(35, 16), Vector2(42, 20)], Color(DUST, .62))
			fleck(head + Vector2(31, 25), Vector2(8, 2), Color(DUST, .45))

func _splinters(at: Vector2, phase: float) -> void:
	var life := 1.0 - phase
	for i in 16:
		var way := -1 if i % 4 == 0 else 1
		var settle := maxf(0, phase - .52)
		var location := pixel(at + Vector2(way * (12 + i % 8 * 18) * phase, -19 - (i * 31 % 95) - (40 + i % 5 * 16) * sin(phase * PI) + settle * 170))
		var tilt := way * (.24 + i % 4 * .28 + phase * 2.5)
		var long := 13.0 + i * 47 % 36
		var edge := Vector2(2, -long).rotated(tilt)
		var corners := PackedVector2Array([location + Vector2(-5, 1).rotated(tilt), location + edge, location + edge * .82 + Vector2(10, 0).rotated(tilt), location + Vector2(2, 4).rotated(tilt)])
		draw_colored_polygon(corners, Color(BRICK.darkened(float(i % 4) * .10), life * .91))
		draw_line(location, pixel(location + edge * .93), Color(OCHRE, life * (.25 + .14 * (i % 4))), 2)
	for i in 20:
		var grain := pixel(at + Vector2((i * 19 % 129 - 31) * phase * 1.8, -7 - (i * 29 % 80) * (1 + .25 * phase)))
		fleck(grain, Vector2(2 + i % 3 * 2, 2), Color(OCHRE, life * .49))
	_surge_dust(at, phase, .46)

func _surge_dust(at: Vector2, phase: float, strength := 1.0) -> void:
	var life := (1.0 - phase * phase) * strength
	for lane in 4:
		var center := at + Vector2(18 + phase * (122 + lane * 26), -6 - lane * 13)
		var width := 48.0 + phase * (50 + lane * 7)
		var height := 5.0 + lane % 2 * 4 + phase * 7.0
		var cloud := PackedVector2Array([center + Vector2(-width, 2), center + Vector2(-width * .48, -height * .5), center + Vector2(-width * .02, -height), center + Vector2(width * .51, -height * .54), center + Vector2(width, -2), center + Vector2(width * .40, 1), center + Vector2(-width * .18, 7)])
		draw_colored_polygon(cloud, Color(DUST, life * (.26 + (lane % 2) * .08)))
		path(center, [Vector2(-width * .62, 0), Vector2(-width * .30, -height + 1), Vector2(width * .22, -height + 1), Vector2(width * .42, -height * .6)], Color(BONE, life * .42))
		for i in 5:
			var crumb := center + Vector2((i * 37 % 52 - 26) * (.9 + phase), -4 - (i * 11 % 30) * phase)
			fleck(crumb, Vector2(4, 2), Color(BONE, life * (.22 + i % 2 * .10)))

func _pounce(at: Vector2, phase: float) -> void:
	var life := 1.0 - phase
	# The folds point from the climbing route through the sill, then break into dust.
	for i in 5:
		var offset := Vector2(i * 11 - 8, -(i * 17 % 55))
		var tip := at + offset + Vector2(phase * 30, -12)
		path(tip, [Vector2(-116 + 22 * i, 35), Vector2(-52 + 2 * i, -12), Vector2(-23, -30), Vector2(-9, -5), Vector2(8, 0)], Color(BONE, life * (.31 + i % 2 * .17)), float(2 + i % 2 * 2))
	for i in 12:
		fleck(at + Vector2((i * 43 % 90 - 42) * (1 + phase), -3 - (i * 11 % 38) * sin(phase * PI)), Vector2(4, 2), Color(DUST, life * .62))

func _lost_room(at: Vector2, phase: float) -> void:
	var life := 1.0 - phase * phase
	var y := -153.0
	for edge in [-1, 1]:
		var origin := at + Vector2(edge * 72, y)
		path(origin, [Vector2(-edge * 25, 2), Vector2(0, 2), Vector2(0, 37), Vector2(-edge * 9, 48), Vector2(0, 65), Vector2(0, 87)], Color(BRICK, life * .75), 3)
		for i in 3:
			fleck(origin + Vector2(-edge * (15 + i * 10), 97 + i * 9), Vector2(2, 6), Color(BRICK, life * .58))
	var cap := at + Vector2(0, y + 12)
	path(cap, [Vector2(-17, -10), Vector2(0, 4), Vector2(17, -10)], Color(OCHRE, life * .8), 3)
	path(cap + Vector2(0, 13), [Vector2(-11, -8), Vector2(0, 2), Vector2(11, -8)], Color(BRICK, life * .86), 3)

func _face(at: Vector2, phase: float, recruited: bool) -> void:
	var life := 1.0 - phase * phase
	var crest := pixel(at + Vector2(0, -70 - (18.0 if recruited else 78.0) * phase))
	var mask := PackedVector2Array()
	for offset in [Vector2(-19, -10), Vector2(-13, -23), Vector2(0, -27), Vector2(14, -23), Vector2(19, -10), Vector2(14, 13), Vector2(2, 21), Vector2(-11, 15)]:
		mask.append(crest + offset)
	draw_colored_polygon(mask, Color("9e957a", life * .91))
	path(crest, [Vector2(-19, -10), Vector2(-13, -23), Vector2(0, -27), Vector2(14, -23), Vector2(19, -10)], Color(BONE, life), 3)
	for x in [-9, 6]:
		fleck(crest + Vector2(x, -7), Vector2(5, 4), Color("293632", life))
	path(crest, [Vector2(-5, 12), Vector2(3, 11), Vector2(7, 8)], Color("4b3f31", life))
	for i in 12:
		var dust := crest + Vector2((i * 17 % 57 - 28) * (.5 + phase), 13 + i * 11 % 62 - phase * 16)
		fleck(dust, Vector2(3, 4), Color(BONE, life * (.33 + i % 3 * .14)))

func _relight(at: Vector2, phase: float) -> void:
	var base := at + Vector2(0, -50)
	var bright := (1.0 - phase * phase) * smoothstep(0.0, .14, phase + .10)
	var light := PackedVector2Array([base + Vector2(-40, 3), base + Vector2(-74, -57), base + Vector2(-50, -105), base + Vector2(51, -105), base + Vector2(74, -57), base + Vector2(42, 3)])
	draw_colored_polygon(light, Color(OCHRE, bright * .091))
	path(base, [Vector2(-38, -13), Vector2(-11, -19), Vector2(0, -11), Vector2(11, -19), Vector2(38, -13)], Color(OCHRE, bright * .91), 4)
	path(base, [Vector2(-38, -7), Vector2(-11, -13), Vector2(0, -5), Vector2(11, -13), Vector2(38, -7)], Color(BRICK, bright * .76), 3)
	for side in [-1, 1]:
		var flame := base + Vector2(side * 32, -17)
		var lift := 17 + absf(sin(simulation.simulation_time * 16.0 + side)) * 12
		draw_colored_polygon(PackedVector2Array([flame + Vector2(-6, 1), flame + Vector2(-4, -10), flame + Vector2(2, -lift), flame + Vector2(6, -8), flame + Vector2(4, 1)]), Color(OCHRE, bright))
	for i in 16:
		var pos := base + Vector2((i * 23 % 94 - 48) * (.5 + phase), -15 - fmod(phase * 124 + (i * 13 % 100), 104))
		fleck(pos, Vector2(2 + i % 3 * 2, 3), Color(OCHRE, bright * (.23 + i % 3 * .18)))

func _fusion(at: Vector2, other: Vector2, height: float, phase: float) -> void:
	var lift := maxf(80.0, height)
	var life := 1.0 - phase * phase
	var source := other - Vector2(0, 42)
	var meeting := at - Vector2(0, lift * .42)
	if phase < .46 and source.distance_to(meeting) < 480.0:
		for i in 10:
			var span := clampf((i * .064) + phase * 2.1, 0, 1)
			var speck := source.lerp(meeting, span) + Vector2(0, sin(span * PI) * (i * 11 % 55 - 29))
			fleck(speck, Vector2(4, 4), Color(DUST, life * (1.0 - span) * .82))
	var landing := smoothstep(0, .20, phase)
	var span := lerpf(80, 315, landing) + 30 * phase
	var plume_height := (29 + 64 * landing) * (1.0 - phase * .33)
	draw_texture_rect(IMPACT, Rect2(at.x-span*.5, at.y-plume_height+8, span, plume_height), false, Color(1, 1, 1, life))
	var spread := 54.0 + phase * 106
	var ground := PackedVector2Array([at + Vector2(-spread, -2), at + Vector2(-spread * .55, -14), at + Vector2(spread * .41, -19), at + Vector2(spread, -4), at + Vector2(spread * .52, 2), at + Vector2(-spread * .43, 3)])
	draw_colored_polygon(ground, Color("1f302d", life * .72))
	for edge in [-1, 1]:
		path(at, [Vector2(edge * spread, -2), Vector2(edge * (spread * .61), -9), Vector2(edge * (spread * .42), -6), Vector2(edge * (spread * .26), -18), Vector2(edge * 10, -10)], Color(BONE, life * .67), 3)
		path(at, [Vector2(edge * spread * .61, -9), Vector2(edge * spread * .78, -20), Vector2(edge * spread * .86, -18)], Color(DUST, life * .72))
		var shroud := PackedVector2Array([at + Vector2(edge * 42, 0), at + Vector2(edge * 24, -lift * .68), at + Vector2(edge * (51 + 27 * phase), -lift * .68 + 8), at + Vector2(edge * (55 + 60 * phase), -20)])
		draw_colored_polygon(shroud, Color("506360", life * .13))
		path(at, [Vector2(edge * (36 + phase * 57), -7), Vector2(edge * (32 + phase * 12), -lift * .32), Vector2(edge * 27, -lift * .54), Vector2(edge * 34, -lift * .72)], Color(DUST, life * .62), 3)
	_surge_dust(at - Vector2(48, 0), phase, .40)

func _bolt_spark(at: Vector2, direction: Vector2, phase: float) -> void:
	var angle := direction.angle()
	for i in 6:
		var streak := Vector2.from_angle(angle + (i - 2.5) * .45) * (10 + (i % 3) * 9)
		var tip := pixel(at + streak * (.45 + phase))
		draw_line(pixel(tip - streak * .24), tip, Color(BONE, (1.0 - phase) * .87), 2)
