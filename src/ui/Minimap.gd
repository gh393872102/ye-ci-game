extends Control

const MAP_RECT := Rect2(16, 42, 480, 76)
const PAPER := Color("eee1c8")
const SLATE := Color("b7ad9a")
const GUARD := Color("dabb87")
const TIDE := Color("b1bec7")
var camera: Camera2D
var world: Node2D

func _ready() -> void:
	add_to_group("minimap")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func camera_rect() -> Rect2:
	var slice: Rect2 = camera.world_rect()
	var scale_x := MAP_RECT.size.x / Rules.REFERENCE_MAP_WIDTH_PX
	return Rect2(MAP_RECT.position + Vector2(slice.position.x * scale_x, 0), Vector2(slice.size.x * scale_x, MAP_RECT.size.y))

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null or camera == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("161218"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("755b43"), false, 1)
	draw_rect(Rect2(Vector2(5, 5), size - Vector2(10, 10)), Color("372a26"), false, 1)
	var font := get_theme_default_font()
	draw_string(font, Vector2(16, 29), tr("P9_MINIMAP_TITLE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, PAPER)
	var key_x := 238.0
	for entry in [[GUARD, "P9_MINIMAP_GUARD"], [TIDE, "P9_MINIMAP_TIDE"], [PAPER, "P9_MINIMAP_VIEW"]]:
		var swatch := Rect2(key_x, 17, 12, 11)
		if entry[0] == PAPER:
			draw_rect(swatch, entry[0], false, 1)
		else:
			draw_rect(swatch, entry[0])
		draw_string(font, Vector2(key_x + 19, 28), tr(entry[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, SLATE)
		key_x += 77.0
	draw_rect(MAP_RECT, Color("110f14"))
	var scale_x := MAP_RECT.size.x / Rules.REFERENCE_MAP_WIDTH_PX
	for section in world.layout.sections:
		var x: float = MAP_RECT.position.x + Rules.body_to_px(section.start) * scale_x
		var w: float = Rules.body_to_px(section.end - section.start) * scale_x
		var h := 12.0 if bool(section.base) else 7.0
		var ink := Color("554939") if bool(section.base) else Color("393641")
		draw_rect(Rect2(x, MAP_RECT.end.y - h, w, h), ink)
		draw_line(Vector2(x, MAP_RECT.end.y - h), Vector2(x + w, MAP_RECT.end.y - h), ink.lightened(0.22), 1)
	for floor_band in world.layout.floor_bands:
		if int(floor_band.floor_id) == 0:
			continue
		var y: float = MAP_RECT.end.y - 4 - (Rules.HORIZON_Y - world.floor_y(floor_band.floor_id)) / Rules.HORIZON_Y * MAP_RECT.size.y
		var left: float = MAP_RECT.position.x + Rules.body_to_px(floor_band.start) * scale_x
		var right: float = MAP_RECT.position.x + Rules.body_to_px(floor_band.end) * scale_x
		var beam := Color("6d5f50")
		draw_rect(Rect2(left, y - 13, right - left, 14), Color("3a3330"))
		draw_polyline(PackedVector2Array([Vector2(left, y), Vector2(left, y - 13), Vector2(right, y - 13), Vector2(right, y)]), beam, 1)
		draw_line(Vector2(left, y), Vector2(right, y), beam.lightened(0.17), 1.5)
	for door in world.doors:
		var x: float = MAP_RECT.position.x + door.position.x * scale_x
		draw_line(Vector2(x, MAP_RECT.end.y - 17), Vector2(x, MAP_RECT.end.y - 1),
			Color("c07a62") if door.destroyed else Color("858f80"), 2)
	for unit in world.visible_units():
		var point := Vector2(MAP_RECT.position.x + unit.position.x * scale_x, MAP_RECT.end.y - 3 - (Rules.HORIZON_Y - unit.position.y) / Rules.HORIZON_Y * MAP_RECT.size.y)
		draw_circle(point, 2.5, GUARD if unit.get_meta("side") == "xianghuo" else TIDE)
	var frame := camera_rect()
	draw_rect(frame, Color(0.88, 0.79, 0.64, 0.09))
	draw_rect(frame, PAPER, false, 1.8)
	for x in [frame.position.x, frame.end.x]:
		draw_line(Vector2(x, frame.position.y), Vector2(x, frame.position.y + 8), PAPER, 3)
		draw_line(Vector2(x, frame.end.y - 8), Vector2(x, frame.end.y), PAPER, 3)
