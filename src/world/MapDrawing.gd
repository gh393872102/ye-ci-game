extends RefCounted
## Texture atlas sections and props are painted at the live geometry's world positions.
const FOREST = preload("res://assets/sprites/world/inkshrine/forest-panorama.png")
const MOON = preload("res://assets/sprites/world/inkshrine/moon.png")
const PAVING = preload("res://assets/sprites/world/inkshrine/wet-cobbles.png")
const ROOMS = preload("res://assets/sprites/world/inkshrine/shrine-interiors.png")
const MATERIAL = preload("res://assets/sprites/world/inkshrine/structural-materials.png")
const PROPS = preload("res://assets/sprites/world/inkshrine/shrine-props.png")
const EAVES = preload("res://assets/sprites/world/inkshrine/shrine-eaves.png")

const FLAGS := Rect2(0, 0, 1774, 220)
const SHALE := Rect2(0, 224, 1774, 214)
const LACQUER := Rect2(0, 447, 1774, 210)
const TILES := Rect2(0, 662, 1774, 219)
const EAVES_REGION := Rect2(8, 250, 2156, 285)
const MOON_REGION := Rect2(197, 197, 852, 852)
const COBBLES := Rect2(0, 0, 2172, 724)
const HALL := Rect2(0, 0, 2172, 238)
const UPPER := Rect2(0, 242, 2172, 236)
const ARCHIVE := Rect2(0, 484, 2172, 240)

const GATE := Rect2(35, 48, 322, 342)
const BROKEN_GATE := Rect2(384, 48, 349, 344)
const POST := Rect2(845, 46, 176, 355)
const LANTERN := Rect2(1178, 46, 200, 354)
const ALTAR := Rect2(11, 453, 375, 259)
const TABLE := Rect2(414, 514, 316, 188)
const DESK := Rect2(772, 481, 309, 227)
const BARRICADE := Rect2(1118, 453, 317, 259)
const WELL := Rect2(38, 824, 303, 205)
const CRATE := Rect2(411, 804, 285, 239)
const WINDOW := Rect2(764, 766, 288, 294)
const BELL := Rect2(1138, 752, 262, 301)

const SHADOW := Color(0.025, 0.042, 0.048, .6)
const FOREGROUND_TABLES := ["register", "altar", "table"]
const WALL_VARIATION := {
	"hall": .04, "stair": .67, "gallery": .48, "stair_landing": .88,
	"incense": .20, "rear": .23, "beam": .61, "bell": .08, "attic": .96,
	"register": .0, "rear_exit": .91, "side_hall": .75
}

var world: Node2D
var warm_light: GradientTexture2D
var cool_light: GradientTexture2D

func _init(map: Node2D) -> void:
	world = map
	warm_light = _falloff(Color("e9863d"), .36)
	cool_light = _falloff(Color("8c9db8"), .12)

func _falloff(color: Color, strength: float) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, .14, .34, .67, 1])
	gradient.colors = PackedColorArray([Color(color, strength), Color(color, strength * .64), Color(color, strength * .29), Color(color, strength * .07), Color(color, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 192
	texture.height = 192
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(.5, .5)
	texture.fill_to = Vector2(1, .5)
	return texture

func draw_sky(canvas: Node2D) -> void:
	var night := Color("c4c3c3")
	_region(canvas, FOREST, Rect2(0, 0, 2172, 355), Rect2(0, 0, 3020, 246), night)
	_region(canvas, FOREST, Rect2(0, 355, 2172, 369), Rect2(0, 246, 3020, 347), night)
	var at := Vector2(1510, 128)
	_light(canvas, at, Vector2(214, 186), cool_light, .55)
	_region(canvas, MOON, MOON_REGION, Rect2(at - Vector2(29, 29), Vector2(58, 58)), Color("cdbfb9", .94))

func draw_architecture(canvas: Node2D) -> void:
	var horizon := float(Rules.HORIZON_Y)
	var width := float(Rules.REFERENCE_MAP_WIDTH_PX)
	var outer: Node2D = world.get_node("door_outer")
	var wall_left := outer.position.x + 55.0
	var wall_end := Rules.HALL_X - 10.0
	_distant_eaves(canvas, world.get_node("door_inner").position.x + 272)
	_strip(canvas, MATERIAL, SHALE, Rect2(wall_left, 426, wall_end - wall_left, 188), 810, Color("727a7a"))
	_strip(canvas, MATERIAL, TILES, Rect2(wall_left - 30, 397, wall_end - wall_left + 45, 49), 520, Color("838b8e"))
	canvas.draw_rect(Rect2(wall_left, 600, wall_end - wall_left, 15), Color(0.02, 0.028, 0.03, .48))
	_strip(canvas, PAVING, COBBLES, Rect2(0, horizon - 112, width, 112), 610, Color("9a897e"))
	var edge := Color(.035, .039, .04, .26)
	canvas.draw_rect(Rect2(0, horizon - 112, width, 8), edge)
	_strip(canvas, MATERIAL, SHALE, Rect2(0, horizon, width, 23), 1110, Color("51595a"))
	_approach(canvas)
	for gate in world.doors:
		if gate.door_id in ["door_outer", "door_inner"]:
			_outer_gate(canvas, gate.position)
	for room in world.layout.rooms:
		if room.start >= 88.0 or room.id == "side_hall":
			_room(canvas, room)
	_window_posts(canvas)
	var top := _top_of_hall()
	_roof(canvas, Rect2(Rules.HALL_X - 46, top - 59, width - Rules.HALL_X + 78, 74), Color("a2a3a0"))
	for spec in world.layout.get("pieces", []):
		draw_chunk(canvas, spec, world.floor_y(int(spec.visual.floor_id)))
	for facility in world.obstacles:
		if facility.kind == "register":
			var at: Vector2 = facility.position + Vector2(facility.width * .55, -62)
			_light(canvas, at, Vector2(190, 150), warm_light, .9)

func _distant_eaves(canvas: Node2D, x: float) -> void:
	# Only the unlit upper outbuilding can be seen behind the court enclosure.
	var weathered := Color("525862")
	_region(canvas, MATERIAL, SHALE, Rect2(x - 132, 251, 264, 169), Color("4c5359"))
	for side in [-1, 1]:
		_prop(canvas, POST, Vector2(x + side * 113, 417), Vector2(29, 142), weathered)
	_roof(canvas, Rect2(x - 211, 187, 422, 83), weathered)
	_roof(canvas, Rect2(x - 161, 304, 322, 52), Color("464c51"))

func _top_of_hall() -> float:
	var highest := Rules.HORIZON_Y - float(Rules.STORY_HEIGHT_PX)
	for room in world.layout.rooms:
		if room.start >= 88:
			highest = minf(highest, world.floor_y(int(room.floor_id)) - Rules.STORY_HEIGHT_PX)
	return highest

func _approach(canvas: Node2D) -> void:
	for band in world.layout.floor_bands:
		if int(band.floor_id) != 1:
			continue
		var at := Vector2(Rules.body_to_px(band.start), world.floor_y(1))
		var width := Rules.body_to_px(band.end - band.start)
		canvas.draw_rect(Rect2(at + Vector2(-6, 4), Vector2(width + 12, 108)), Color("0b1012"))
		_strip(canvas, MATERIAL, SHALE, Rect2(at.x, at.y + 11, width, 114), 560, Color("687275"))
		_strip(canvas, MATERIAL, FLAGS, Rect2(at.x - 12, at.y - 8, width + 24, 25), 400, Color("9cabae"))
		for interval in 4:
			var end := at + Vector2(width * (.13 + .24 * interval), 102)
			_prop(canvas, POST, end, Vector2(34, 115), Color("6d7675"))
	for site in [430.0, 1350.0, 3420.0]:
		var at := Vector2(site, Rules.HORIZON_Y - 102)
		_prop(canvas, CRATE, at, Vector2(57, 42), Color("737777"))
		_prop(canvas, WELL, at + Vector2(-65, 5), Vector2(83, 44), Color("606a6d"))

func _outer_gate(canvas: Node2D, at: Vector2) -> void:
	var dark_wood := Color("a0a4a0")
	_region(canvas, MATERIAL, SHALE, Rect2(at.x - 101, at.y - 215, 202, 97), Color("969795"))
	_region(canvas, MATERIAL, SHALE, Rect2(at.x - 104, at.y - 123, 47, 121), Color("7c8587"))
	_region(canvas, MATERIAL, SHALE, Rect2(at.x + 57, at.y - 123, 47, 121), Color("7c8587"))
	_prop(canvas, POST, at + Vector2(-82, 0), Vector2(37, 188), dark_wood)
	_prop(canvas, POST, at + Vector2(82, 0), Vector2(37, 188), dark_wood)
	_roof(canvas, Rect2(at.x - 146, at.y - 280, 292, 79), dark_wood)
	_hanging_lamp(canvas, at + Vector2(-64, -164), 45, .8)
	_hanging_lamp(canvas, at + Vector2(64, -164), 45, .8)

func _room(canvas: Node2D, room: Dictionary) -> void:
	var left := Rules.body_to_px(room.start)
	var width := Rules.body_to_px(room.end - room.start)
	var level := int(room.floor_id)
	var floor_y: float = world.floor_y(level)
	var ceiling := floor_y - Rules.STORY_HEIGHT_PX
	var use_archive: bool = room.id in ["register", "attic", "rear"]
	var wall := ARCHIVE if use_archive else HALL if level == 0 else UPPER
	var source_width := minf(wall.size.x, width * 1.61)
	var source_offset := (wall.size.x - source_width) * float(WALL_VARIATION.get(room.id, .5))
	var detail := Rect2(Vector2(source_offset, wall.position.y), Vector2(source_width, wall.size.y))
	var tint := Color("c4ac99") if use_archive else Color("b9ad9f") if level == 0 else Color("b2b6b6")
	_region(canvas, ROOMS, detail, Rect2(left, ceiling + 8, width, 144), tint)
	_strip(canvas, MATERIAL, LACQUER, Rect2(left, floor_y - 52, width, 51), 685, Color("aaada5"))
	_strip(canvas, MATERIAL, SHALE, Rect2(left - 3, floor_y - 1, width + 6, 13 if level == 0 else 14), 685, Color("6d716b"))
	_beam(canvas, Vector2(left, ceiling + 5), Vector2(left + width, ceiling + 5), 13, Color("a8a29a"))
	# Columns behind the walk lane mark boundaries while the true door openings stay on their own layer.
	_prop(canvas, POST, Vector2(left + 12, floor_y - 4), Vector2(35, 189), Color("acaaa1"))
	if width > 280:
		_lamp_row(canvas, left, floor_y, width, level, use_archive)
	if str(room.id) in ["attic", "rear", "beam"]:
		_storage(canvas, Vector2(left + width * .78, floor_y - 38), room.id != "beam")
	if room.tags.has("exit"):
		var rear := Vector2(left + width - 72, floor_y)
		canvas.draw_rect(Rect2(rear - Vector2(40, 109), Vector2(80, 109)), Color("081015"))
		_gate_frame(canvas, rear, 88, 112, Color("717878"))
		_light(canvas, rear + Vector2(0, -47), Vector2(110, 160), cool_light, .7)

func _lamp_row(canvas: Node2D, left: float, floor_y: float, width: float, level: int, archive: bool) -> void:
	var lamps := clampi(int(ceil(width / 350.0)), 1, 4)
	for index in lamps:
		var x := left + width * (float(index) + .54) / lamps
		var toward := -5 if index % 2 else 5
		var light := Vector2(x + toward * 2, floor_y - 124 - (index % 2) * 7)
		_hanging_lamp(canvas, light - Vector2(0, 24), 57 if level == 0 else 50, 1.12 if archive else .92)
		var sheen := Rect2(light.x - 78, floor_y - 21, 156, 23)
		canvas.draw_texture_rect(warm_light, sheen, false, Color(1, 1, 1, .38))
		if level > 0 and index % 2 == 1:
			var end := Vector2(x + 84, floor_y - 23)
			_prop(canvas, CRATE, end, Vector2(37, 31), Color("7b7771"))

func _window_posts(canvas: Node2D) -> void:
	for post in world.posts:
		if post.get_meta("cover_kind") != "window":
			continue
		var at: Vector2 = post.position - Vector2(0, 66)
		_prop(canvas, WINDOW, at, Vector2(74, 82), Color("7a7d7d"))
		_light(canvas, at - Vector2(0, 35), Vector2(125, 125), cool_light, .72)

func _storage(canvas: Node2D, at: Vector2, stacked: bool) -> void:
	_prop(canvas, CRATE, at + Vector2(0, 3), Vector2(69, 47), Color("746f65"))
	_prop(canvas, CRATE, at + Vector2(-46, 0), Vector2(51, 38), Color("8b7b69"))
	if stacked:
		_prop(canvas, CRATE, at - Vector2(-7, 44), Vector2(48, 32), Color("908170"))

func draw_chunk(canvas: Node2D, spec: Dictionary, y: float) -> void:
	var art: Dictionary = spec.visual
	var left := Rules.body_to_px(art.start)
	var width := Rules.body_to_px(art.end - art.start)
	var at := Vector2(left, y)
	match str(art.motif):
		"gate_court":
			for offset in range(64, int(width), 335):
				_court_lamp(canvas, at + Vector2(offset, -29))
		"alley":
			_strip(canvas, MATERIAL, SHALE, Rect2(left, y - 113, width, 99), 575, Color("758187"))
			_strip(canvas, MATERIAL, LACQUER, Rect2(left, y - 19, width, 22), 600, Color("788587"))
			_court_lamp(canvas, at + Vector2(width * .30, -10))
			_court_lamp(canvas, at + Vector2(width * .76, -10))
		"beam":
			# The gallery floor is painted by the room cutaway. The repairable span is painted with live obstacles.
			pass
		"register":
			pass
		"water":
			_water(canvas, Rect2(left, y - 17, width, 28))
			_strip(canvas, MATERIAL, SHALE, Rect2(left, y + 10, width, 16), 720, Color("6e8488"))
		"well":
			var center := at + Vector2(width * .68, -23)
			_prop(canvas, WELL, center, Vector2(109, 71), Color("929590"))
			_light(canvas, center - Vector2(0, 20), Vector2(206, 94), cool_light)
		"bridge":
			# The stone span is drawn in pieces around the destructible bridge at its live x position.
			_bridge(canvas, at, width)
		"stage":
			_stage(canvas, at, width)
		"side_hall":
			_roof(canvas, Rect2(left - 26, y - 249, width + 52, 65), Color("889297"))
		"fissure":
			_fissure(canvas, at + Vector2(width * .66, -44))
		"hearth":
			pass
		"silence":
			for offset in range(116, int(width) - 30, 197):
				var bell := at + Vector2(offset, -101)
				_beam(canvas, bell - Vector2(0, 73), bell - Vector2(0, 26), 3, Color("8d887b"))
				_prop(canvas, BELL, bell, Vector2(19, 27), Color("838588"))

func _water(canvas: Node2D, water: Rect2) -> void:
	_strip(canvas, MATERIAL, FLAGS, water, 440, Color("647c87"))
	canvas.draw_rect(water, Color(.05, .13, .17, .60))
	for i in int(water.size.x / 19):
		var p := water.position + Vector2(i * 19 + (i * 13 % 15), i * 29 % int(water.size.y - 4))
		canvas.draw_rect(Rect2(p, Vector2((10 + i * 11 % 22), 1)), Color("5f7d85", .29 if i % 2 else .4))

func _bridge(canvas: Node2D, at: Vector2, width: float) -> void:
	var gap: Node2D = world.get_node_or_null("stone_bridge")
	if gap == null:
		_strip(canvas, MATERIAL, SHALE, Rect2(at.x, at.y - 19, width, 32), 720, Color("a4a6a0"))
		return
	var gap_start: float = gap.position.x
	var gap_end: float = gap_start + gap.width
	_strip(canvas, MATERIAL, SHALE, Rect2(at.x, at.y - 11, gap_start - at.x, 38), 720, Color("a5aaa8"))
	_strip(canvas, MATERIAL, SHALE, Rect2(gap_end, at.y - 11, at.x + width - gap_end, 38), 720, Color("a5aaa8"))
	for post in [at.x + 71, gap_start - 62, gap_end + 55, at.x + width - 60]:
		_prop(canvas, POST, Vector2(post, at.y + 85), Vector2(46, 125), Color("878e91"))

func _stage(canvas: Node2D, at: Vector2, width: float) -> void:
	var offset := at + Vector2(width * .27, -62)
	var breadth := width * .52
	_strip(canvas, MATERIAL, LACQUER, Rect2(offset.x, offset.y, breadth, 22), 450, Color("929293"))
	_strip(canvas, ROOMS, HALL, Rect2(offset.x, offset.y - 143, breadth, 148), 700, Color("77726f"))
	_roof(canvas, Rect2(offset.x - 43, offset.y - 207, breadth + 86, 72), Color("888a87"))
	for side in [15.0, breadth - 15.0]:
		_prop(canvas, POST, offset + Vector2(side, 20), Vector2(39, 157), Color("9e9892"))
		_hanging_lamp(canvas, offset + Vector2(side * .89 + 18, -114), 46, .82)

func _fissure(canvas: Node2D, at: Vector2) -> void:
	_region(canvas, MATERIAL, Rect2(180, 271, 410, 142), Rect2(at - Vector2(70, 37), Vector2(140, 46)), Color("8d8279"))
	var seam := PackedVector2Array([at + Vector2(-70, 7), at + Vector2(-45, -13), at + Vector2(-18, -8), at + Vector2(-7, -22), at + Vector2(32, -15), at + Vector2(65, 2)])
	canvas.draw_polyline(seam, Color("0d1115"), 7)
	canvas.draw_polyline(seam, Color(.43, .35, .35, .56), 1)

func draw_fixtures(canvas: Node2D) -> void:
	for stair in world.layout.stairs:
		_stair(canvas, stair)
	for object in world.obstacles:
		if object.kind not in FOREGROUND_TABLES:
			_facility(canvas, object)
	for door in world.doors:
		_door(canvas, door)

func draw_cover(canvas: Node2D) -> void:
	for post in world.posts:
		if post.get_meta("cover_kind") == "window":
			_window_sill(canvas, post.position)
	for object in world.obstacles:
		if object.kind in FOREGROUND_TABLES:
			_facility(canvas, object, _table_front(object))

func _window_sill(canvas: Node2D, foot: Vector2) -> void:
	var left := foot.x - 68
	var sill := Rect2(left, foot.y - 37, 136, 9)
	var lattice := Rect2(WINDOW.position + Vector2(4, 120), Vector2(279, 170))
	_region(canvas, PROPS, lattice, Rect2(left + 5, foot.y - 31, 126, 29), Color("a99b90"))
	_region(canvas, MATERIAL, LACQUER, sill, Color("bdac96"))
	for side in [-1, 1]:
		_prop(canvas, POST, foot + Vector2(side * 66, 0), Vector2(13, 40), Color("938477"))
	canvas.draw_rect(Rect2(left, foot.y - 2, 136, 3), Color("271b17"))

func _table_front(object: StaticBody2D) -> Vector2:
	var left: float = object.position.x
	var right: float = left + object.width
	# The visible overhang meets the assigned cover post; the physics footprint stays on the object.
	for post in world.posts:
		if post.get_meta("cover_kind") != object.kind or int(post.get_meta("floor_id")) != object.floor_id:
			continue
		var x: float = post.position.x
		if x >= left - 24 and x <= right + 44:
			left = minf(left, x - 24)
			right = maxf(right, x + 33)
	return Vector2(left, right)

func _stair(canvas: Node2D, stair: Dictionary) -> void:
	var a := Vector2(Rules.body_to_px(stair.from_x), world.floor_y(int(stair.from_floor)))
	var b := Vector2(Rules.body_to_px(stair.to_x), world.floor_y(int(stair.to_floor)))
	if not world.path_is_open(str(stair.id)):
		for side in [a, b]:
			_prop(canvas, BARRICADE, side, Vector2(57, 37), Color("9e6a60"))
		return
	var steps := maxi(1, roundi(absf(b.y - a.y) / 12.0))
	_beam(canvas, a + Vector2(0, 11), b + Vector2(0, 11), 22, Color("747879"))
	for index in steps:
		var p := a.lerp(b, float(index) / steps)
		var q := a.lerp(b, (index + 1.0) / steps)
		var low := maxf(p.y, q.y)
		var high := minf(p.y, q.y)
		var top := Rect2(minf(p.x, q.x), high, maxf(1, absf(q.x - p.x)), low - high + 5)
		_region(canvas, MATERIAL, LACQUER, top, Color("b5a99b"))
		canvas.draw_line(top.position + Vector2(0, 1), top.position + Vector2(top.size.x, 1), Color(0.61, 0.51, 0.39, .57), 1)
		if index % 4 == 0:
			_prop(canvas, POST, p + Vector2(0, 1), Vector2(10, 47), Color("ab9c8e"))
	_beam(canvas, a - Vector2(0, 44), b - Vector2(0, 44), 8, Color("a8a29d"))

func _facility(canvas: Node2D, object: StaticBody2D, front := Vector2.ZERO) -> void:
	var at: Vector2 = object.position + Vector2(object.width * .5, 0)
	var w: float = object.width
	if front != Vector2.ZERO:
		at.x = (front.x + front.y) / 2
		w = front.y - front.x
	if not object.occupied:
		if object.max_durability > 0 and object.durability <= 0 and object.kind in ["beam_span", "stone_bridge", "barricade", "palisade", "stove"]:
			_debris(canvas, at, minf(w, 132.0), object.kind == "stone_bridge")
		return
	var profile: Rect2 = TABLE
	var h := float(Rules.TABLE_HEIGHT_PX)
	var tint := Color.WHITE
	match str(object.kind):
		"register":
			profile = DESK
			h = 61
			tint = Color("f0e0c5")
		"altar":
			profile = ALTAR
			h = 75
		"bell":
			_prop(canvas, TABLE, at, Vector2(w, 43), Color("787573"))
			_prop(canvas, BELL, at - Vector2(0, 46), Vector2(w * .68, 83), Color("a5a39d"))
			return
		"barricade", "palisade", "well_rail", "side_wall", "stove_partition":
			profile = BARRICADE
			h = 53 if object.kind == "barricade" else 45
			tint = Color("b6a795")
		"silent_screen", "stage_curtain":
			profile = WINDOW
			h = 80
			tint = Color("8b8079")
		"stove":
			_prop(canvas, WELL, at, Vector2(w, 55), Color("a09687"))
			_light(canvas, at - Vector2(0, 48), Vector2(165, 130), warm_light, 1.35)
			_pocket_flame(canvas, at - Vector2(0, 47), 25)
			return
		"stone_bridge":
			_strip(canvas, MATERIAL, SHALE, Rect2(object.position.x, at.y - 11, w, 38), 450, Color("a5aaa8"))
			return
		"beam_span", "water_plank":
			_beam(canvas, at - Vector2(w / 2, 5), at + Vector2(w / 2, -5), 20, Color("b8aa9b"))
			return
	canvas.draw_rect(Rect2(at - Vector2(w * .48, 4), Vector2(w * .96, 7)), SHADOW)
	_prop(canvas, profile, at, Vector2(w, h), tint)
	if object.kind == "register":
		_pocket_flame(canvas, at + Vector2(w * .31, -49), 15)

func _debris(canvas: Node2D, at: Vector2, width: float, stone: bool) -> void:
	for index in 6:
		var start := at + Vector2(-width * .4 + index * width * .15, -3 - index % 2 * 4)
		var end := start + Vector2(width * .17, -4 - index * 11 % 18)
		if stone:
			_region(canvas, MATERIAL, SHALE, Rect2(start, Vector2(width * .16, 11)), Color("778485"))
		else:
			_beam(canvas, start, end, 3 + index % 3 * 2, Color("897a6d"))

func _door(canvas: Node2D, gate: StaticBody2D) -> void:
	var at: Vector2 = gate.position
	var hall_gate: bool = gate.door_id in ["door_hall", "door_outer", "door_inner"]
	var h := Rules.DOOR_HEIGHT_PX + 9.0
	var w := 104.0 if hall_gate else 76.0
	var tint := Color("d0c2af") if hall_gate else Color("a7a9a5")
	canvas.draw_rect(Rect2(at - Vector2(w * .44, h - 8), Vector2(w * .88, h - 8)), Color("080d11"))
	if gate.destroyed:
		_prop(canvas, BROKEN_GATE, at, Vector2(w * 1.12, h + 4), tint)
		_debris(canvas, at, w, false)
	elif gate.is_open:
		_gate_frame(canvas, at, w, h, tint)
	else:
		_prop(canvas, GATE, at, Vector2(w, h), tint)
		if gate.durability <= gate.max_durability * .21:
			_door_crack(canvas, at - Vector2(0, 68))
	if gate.door_id == "door_hall":
		for side in [-1, 1]:
			var base := at + Vector2(side * (w * .59 + 2), -115)
			_hanging_lamp(canvas, base, 43, 1.18)

func _door_crack(canvas: Node2D, at: Vector2) -> void:
	var points := PackedVector2Array([at + Vector2(-13, -35), at + Vector2(-6, -13), at + Vector2(1, -20), at + Vector2(7, -3), at + Vector2(-1, 6), at + Vector2(11, 29)])
	canvas.draw_polyline(points, Color("1e1210"), 5)
	canvas.draw_polyline(points, Color("b07358"), 2)

func _gate_frame(canvas: Node2D, at: Vector2, w: float, h: float, tint: Color) -> void:
	var left := at.x - w / 2
	var height := h * .9
	var post_w := w * .20
	var top := GATE.position
	_region(canvas, PROPS, Rect2(top.x, top.y, GATE.size.x, 40), Rect2(left, at.y - h, w, h - height), tint)
	_region(canvas, PROPS, Rect2(top.x, top.y + 37, 63, GATE.size.y - 37), Rect2(left, at.y - height, post_w, height), tint)
	_region(canvas, PROPS, Rect2(GATE.end.x - 63, top.y + 37, 63, GATE.size.y - 37), Rect2(at.x + w / 2 - post_w, at.y - height, post_w, height), tint)

func _court_lamp(canvas: Node2D, at: Vector2) -> void:
	_beam(canvas, at, at - Vector2(0, 79), 8, Color("817870"))
	_hanging_lamp(canvas, at - Vector2(0, 109), 44, .71)

func _hanging_lamp(canvas: Node2D, attachment: Vector2, height: float, strength: float) -> void:
	var at := attachment + Vector2(0, height * .68)
	_light(canvas, at, Vector2(228, 212) * (.8 + strength * .2), warm_light, strength)
	_prop(canvas, LANTERN, attachment + Vector2(0, height), Vector2(height * .56, height), Color("ffe7ce"))

func _pocket_flame(canvas: Node2D, tip: Vector2, h: float) -> void:
	canvas.draw_rect(Rect2(tip + Vector2(-7, 0), Vector2(14, 3)), Color("ba885e"))
	canvas.draw_rect(Rect2(tip + Vector2(-2, -6), Vector2(4, 6)), Color("53372a"))
	var outline := PackedVector2Array([tip - Vector2(4, 6), tip - Vector2(4, h * .65), tip + Vector2(1, -h), tip + Vector2(4, -h * .5), tip + Vector2(3, -6)])
	canvas.draw_colored_polygon(outline, Color("e8a769"))
	canvas.draw_rect(Rect2(tip + Vector2(-1, -h * .61), Vector2(2, h * .26)), Color("ffe0a8"))

func _light(canvas: Node2D, at: Vector2, size: Vector2, tint: Texture2D, weight := 1.0) -> void:
	canvas.draw_texture_rect(tint, Rect2(at - size * .5, size), false, Color(1, 1, 1, weight))

func _roof(canvas: Node2D, destination: Rect2, tint: Color) -> void:
	_region(canvas, EAVES, EAVES_REGION, destination, tint)

func _prop(canvas: Node2D, source: Rect2, foot: Vector2, size: Vector2, tint := Color.WHITE) -> void:
	_region(canvas, PROPS, source, Rect2(foot - Vector2(size.x * .5, size.y), size), tint)

func _beam(canvas: Node2D, a: Vector2, b: Vector2, width: float, tint: Color) -> void:
	var span := a.distance_to(b)
	if span < 1:
		return
	canvas.draw_set_transform(a, a.angle_to_point(b))
	_region(canvas, MATERIAL, Rect2(0, 563, 870, 68), Rect2(0, -width * .5, span, width), tint)
	canvas.draw_line(Vector2(0, -width * .35), Vector2(span, -width * .35), Color(.61, .47, .35, .20))
	canvas.draw_set_transform(Vector2.ZERO)

func _strip(canvas: Node2D, texture: Texture2D, source: Rect2, target: Rect2, tile_width: float, tint: Color) -> void:
	for i in ceili(target.size.x / tile_width):
		var px := i * tile_width
		var span := minf(tile_width, target.size.x - px)
		var region := Rect2(source.position, Vector2(source.size.x * span / tile_width, source.size.y))
		var size := Vector2(span, target.size.y)
		if i % 2 == 1:
			canvas.draw_set_transform(target.position + Vector2(px + span, 0), 0, Vector2(-1, 1))
			_region(canvas, texture, region, Rect2(Vector2.ZERO, size), tint)
			canvas.draw_set_transform(Vector2.ZERO)
		else:
			_region(canvas, texture, region, Rect2(target.position + Vector2(px, 0), size), tint)

func _region(canvas: Node2D, texture: Texture2D, source: Rect2, target: Rect2, tint: Color) -> void:
	canvas.draw_texture_rect_region(texture, target, source, tint, false, true)
