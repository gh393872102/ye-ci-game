extends RefCounted
## P1 geometric cutaway, not final art; all functional positions come from spatial data.
var world: Node2D
var font: Font

func _init(map: Node2D) -> void:
	world = map
	font = world.font

func rect(x: float, y: float, w: float, h: float, color: String) -> void:
	world.draw_rect(Rect2(x, y, w, h), Color(color))

func line(a: Vector2, b: Vector2, color: String, width := 2.0) -> void:
	world.draw_line(a, b, Color(color), width)

func label(text: String, p: Vector2, size := 20, color := "a5b3b0") -> void:
	world.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color))

func draw_map() -> void:
	for band in 10:
		world.draw_rect(Rect2(0, band * 70, Rules.REFERENCE_MAP_WIDTH_PX, 70), Color("101722").lerp(Color("24373e"), band / 10.0))
	for index in 180:
		rect((index * 337 + 97) % Rules.REFERENCE_MAP_WIDTH_PX, (index * 83 + 71) % 320 + 65, 2, 2, "69787d")
	for index in 90:
		var x := float(index * 115)
		var top := float(330 + (index * 47) % 160)
		world.draw_colored_polygon(PackedVector2Array([Vector2(x - 90, 620), Vector2(x, top), Vector2(x + 100, 620)]), Color("17252b"))
	for section in world.layout.sections:
		var x := Rules.body_to_px(section.start)
		var width := Rules.body_to_px(section.end - section.start)
		rect(x, 636, width, 64, section.color)
		label(tr(section.label), Vector2(x + 20, 600), 22)
		# Long wet-stone path, cut at the camera edges.
		for brick_x in range(int(x), int(x + width), 160):
			line(Vector2(brick_x, 666), Vector2(brick_x + 150, 666), "4d6267", 1)
			line(Vector2(brick_x + 60, 640), Vector2(brick_x + 60, 664), "40545b", 1)
			line(Vector2(brick_x + 110, 670), Vector2(brick_x + 110, 697), "40545b", 1)
	# Approach platform; no human route goes outside the base to reach it.
	var platform_x := Rules.body_to_px(24)
	rect(platform_x, world.floor_y(1), Rules.body_to_px(16), 16, "43585c")
	for x in range(int(platform_x), int(Rules.body_to_px(40)), 240):
		rect(x, world.floor_y(1) + 16, 30, Rules.HORIZON_Y - world.floor_y(1) - 16, "24353b")
	for body in [48, 70]:
		_gate(Rules.body_to_px(body))
	for room in world.layout.rooms:
		if room.start >= 88:
			_room(room)
	_roof(Rules.HALL_X - 40, Rules.REFERENCE_MAP_WIDTH_PX, 100)
	for stair in world.layout.stairs:
		_stair(stair)
	for object in world.obstacles:
		_facility(object)
	for door in world.doors:
		_door(door)
	# Visible back-lane openings in every obstacle slot, plus empty placement slots.
	for slot in world.layout.obstacle_slots:
		var p := Vector2(Rules.body_to_px(slot.x), world.floor_y(int(slot.floor_id)))
		world.draw_dashed_line(p + Vector2(-20, -Rules.GAP_LANE_OFFSET_PX), p + Vector2(Rules.body_to_px(slot.width) + 20, -Rules.GAP_LANE_OFFSET_PX), Color("718f88"), 2, 8)
		if not slot.occupied:
			world.draw_rect(Rect2(p.x, p.y - 14, Rules.body_to_px(slot.width), 14), Color("4c6662"), false, 1)
	line(Vector2(0, Rules.HORIZON_Y), Vector2(Rules.REFERENCE_MAP_WIDTH_PX, Rules.HORIZON_Y), "7c8986")

func _roof(start: float, end: float, y: float) -> void:
	var inset := minf(160, (end - start) * 0.3)
	world.draw_colored_polygon(PackedVector2Array([Vector2(start - 16, y - 15), Vector2(start + 24, y), Vector2(start + inset, y - 34), Vector2(end - inset, y - 34), Vector2(end - 24, y), Vector2(end + 16, y - 15), Vector2(end, y + 10), Vector2(start, y + 10)]), Color("10191d"))
	line(Vector2(start, y + 10), Vector2(end, y + 10), "6d7465", 4)
	for x in range(int(start + inset), int(end - inset), 26):
		line(Vector2(x, y - 28), Vector2(x - 14, y + 3), "334445", 2)

func _gate(x: float) -> void:
	rect(x, 508, 160, 192, "223239")
	rect(x + 16, 550, 128, 150, "15242b")
	_roof(x - 24, x + 184, 508)
	rect(x + 8, 532, 16, 168, "58615a")
	rect(x + 136, 532, 16, 168, "58615a")

func _room(room: Dictionary) -> void:
	var x := Rules.body_to_px(room.start)
	var w := Rules.body_to_px(room.end - room.start)
	var y: float = world.floor_y(int(room.floor_id))
	var top := y - Rules.STORY_HEIGHT_PX
	var color := "202c31" if int(room.floor_id) == 0 else ("253237" if int(room.floor_id) == 2 else "29353a")
	rect(x, top, w, Rules.STORY_HEIGHT_PX, color)
	rect(x, y - Rules.WALK_BAND_DEPTH_PX, w, Rules.WALK_BAND_DEPTH_PX, "34454a")
	for px in range(int(x), int(x + w), 100):
		line(Vector2(px, y - 30), Vector2(px + 90, y - 30), "45595b", 1)
		line(Vector2(px + 40, y - 58), Vector2(px + 40, y - 32), "45595b", 1)
	# Structural post leaves a 104 px doorway beneath its lintel.
	rect(x, top + 8, 16, Rules.STORY_HEIGHT_PX - Rules.DOOR_HEIGHT_PX - 8, "121c21")
	rect(x + 16, top + 8, 8, Rules.STORY_HEIGHT_PX - Rules.DOOR_HEIGHT_PX - 12, "53615d")
	rect(x, top, w, 12, "111b20")
	line(Vector2(x, y), Vector2(x + w, y), "71807b", 5)
	label(tr(room.label), Vector2(x + 32, top + 43), 21, "a2afa2")
	if room.tags.has("indoor"):
		for px in range(int(x + 110), int(x + w - 80), 260):
			rect(px, top + 60, 72, 66, "101c24")
			world.draw_rect(Rect2(px, top + 60, 72, 66), Color("58726f"), false, 2)
			for bar in 3:
				line(Vector2(px + 18 + bar * 18, top + 62), Vector2(px + 18 + bar * 18, top + 125), "354f53", 2)
			line(Vector2(px, top + 92), Vector2(px + 72, top + 92), "354f53", 2)
		_lamp(Vector2(x + 60, top + 86))
	if room.tags.has("exit"):
		rect(x + w - 90, y - Rules.DOOR_HEIGHT_PX, 60, Rules.DOOR_HEIGHT_PX, "0c1b22")
		line(Vector2(x + w - 90, y - Rules.DOOR_HEIGHT_PX), Vector2(x + w - 90, y), "648679", 3)

func _lamp(p: Vector2) -> void:
	line(p - Vector2(0, 26), p, "827b62", 2)
	rect(p.x - 8, p.y, 16, 24, "766e50")
	rect(p.x - 4, p.y + 3, 8, 16, "c1b17c")

func _stair(stair: Dictionary) -> void:
	var a := Vector2(Rules.body_to_px(stair.from_x), world.floor_y(int(stair.from_floor)))
	var b := Vector2(Rules.body_to_px(stair.to_x), world.floor_y(int(stair.to_floor)))
	if not world.path_is_open(str(stair.id)):
		world.draw_dashed_line(a, b, Color("95605a"), 4, 14)
		return
	var steps := int(absf(b.y - a.y) / 12.5)
	line(a + Vector2(0, 8), b + Vector2(0, 8), "17262b", 18)
	for i in steps:
		var p := a.lerp(b, i / float(steps))
		var q := a.lerp(b, (i + 1) / float(steps))
		line(p, Vector2(q.x, p.y), "92a29a", 4)
		line(Vector2(q.x, p.y), q, "4c655f", 3)
		if i % 3 == 0:
			line(p, p - Vector2(0, 48), "536d66", 4)
	line(a - Vector2(0, 48), b - Vector2(0, 48), "7b8b79", 4)

func _facility(object: StaticBody2D) -> void:
	if not object.occupied or not object.blocks_walk:
		return
	var p: Vector2 = object.position
	var w: float = object.width
	var h := Rules.TABLE_HEIGHT_PX
	if object.kind in ["palisade", "barricade", "well_rail", "water_plank", "stage_curtain", "side_wall", "stove_partition", "silent_screen", "beam_span"]:
		for x in range(int(p.x + 8), int(p.x + w), 20):
			if object.kind == "barricade":
				line(Vector2(x - 12, p.y), Vector2(x + 12, p.y - h), "8f9079", 6)
				line(Vector2(x + 12, p.y), Vector2(x - 12, p.y - h), "5f796f", 6)
			else:
				rect(x, p.y - h, 7, h, "718477")
		line(p - Vector2(0, 24), p + Vector2(w, -24), "9b987d", 4)
	else:
		rect(p.x, p.y - h, w, 10, "9a9275")
		rect(p.x + 12, p.y - h + 10, 10, h - 10, "586e64")
		rect(p.x + w - 22, p.y - h + 10, 10, h - 10, "586e64")
		if object.kind == "register":
			rect(p.x + 24, p.y - h - 18, 44, 18, "c8c0a1")
			line(p + Vector2(46, -h - 16), p + Vector2(46, -h), "78745e", 2)
			_flame(p + Vector2(w - 20, -h))
			label(tr("REGISTER"), p + Vector2(8, -h - 28), 21, "d0c39a")
		elif object.kind == "altar":
			rect(p.x + w / 2 - 20, p.y - h - 14, 40, 14, "8d9a85")
			for i in 3:
				line(p + Vector2(w / 2 - 10 + i * 10, -h - 14), p + Vector2(w / 2 - 10 + i * 10, -h - 36), "b9ae7c", 2)
		elif object.kind == "bell":
			world.draw_colored_polygon(PackedVector2Array([p + Vector2(25, -h - 65), p + Vector2(w - 25, -h - 65), p + Vector2(w - 12, -h - 12), p + Vector2(12, -h - 12)]), Color("778a7c"))

func _flame(p: Vector2) -> void:
	line(p, p - Vector2(0, 18), "799b96", 4)
	world.draw_colored_polygon(PackedVector2Array([p - Vector2(0, 34), p + Vector2(5, -23), p - Vector2(0, 18), p + Vector2(-5, -23)]), Color("c6bd8a"))

func _door(door: StaticBody2D) -> void:
	var p: Vector2 = door.position
	var h := float(Rules.DOOR_HEIGHT_PX)
	rect(p.x - 28, p.y - h - 10, 56, 10, "879180")
	if not door.is_open:
		rect(p.x - 10, p.y - h, 20, h, "704f49")
		line(p + Vector2(0, -h + 5), p + Vector2(0, -5), "ac8d69", 2)
		rect(p.x - 14, p.y - 54, 28, 8, "a59a77")
	else:
		rect(p.x - 28, p.y - h, 6, h, "536a61")
	label(tr("DOOR_OPEN" if door.is_open else "DOOR_CLOSED"), p + Vector2(-10, -h - 18), 16, "9ca88b")
