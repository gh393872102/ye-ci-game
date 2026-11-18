extends Node2D
var flags := {1: false, 2: false, 3: false, 4: false, 5: false, 6: false, 10: false}
var world: Node2D
var camera: Camera2D
var font := SystemFont.new()
var retreat_preview := PackedVector2Array()

func _ready() -> void:
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC"])

func _unhandled_input(event: InputEvent) -> void:
	for key in flags:
		if event.is_action_pressed("debug_f%d" % key):
			flags[key] = not flags[key]
			queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null:
		return
	var start: float = camera.left()
	var end: float = start + Rules.CAMERA_WIDTH_PX
	if flags[1]:
		for x in range(int(start / Rules.BODY_PX) * Rules.BODY_PX, int(end) + Rules.BODY_PX, Rules.BODY_PX):
			draw_line(Vector2(x, Rules.TOP_BAR_HEIGHT), Vector2(x, Rules.HORIZON_Y), Color(0.4, 0.7, 0.7, 0.3))
		for y in range(Rules.HORIZON_Y, Rules.TOP_BAR_HEIGHT, -Rules.BODY_PX):
			draw_line(Vector2(start, y), Vector2(end, y), Color(0.4, 0.7, 0.7, 0.3))
	if flags[2]:
		for unit in world.visible_units():
			var p: Vector2 = unit.position
			var height: float = unit.height_px if unit.get("height_px") != null else Rules.UNIT_HEIGHT_PX
			_ruler(p + Vector2(45, 0), height, "%d px" % height)
			_ruler(p + Vector2(135, 0), Rules.DOOR_HEIGHT_PX, "104 px")
		_ruler(Vector2(Rules.HALL_X + 330, Rules.HORIZON_Y), Rules.STORY_HEIGHT_PX, "200 px")
		_ruler(Vector2(Rules.HALL_X + 480, Rules.HORIZON_Y), Rules.TABLE_HEIGHT_PX, "48 px")
	if flags[3]:
		var base := Rect2(Rules.BASE_START_X, Rules.TOP_BAR_HEIGHT, Rules.REFERENCE_MAP_WIDTH_PX - Rules.BASE_START_X, Rules.HORIZON_Y - Rules.TOP_BAR_HEIGHT)
		draw_rect(base, Color(0.25, 0.7, 0.6, 0.04))
		draw_rect(base, Color("5cafa1"), false, 2)
		for post in world.posts:
			draw_circle(post.position + Vector2(0, -8), 8, Color("91c7ae"))
			draw_string(font, post.position + Vector2(-20, -110), post.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("a9dcc1"))
		for interval in world.layout.base_region.court_intervals:
			draw_rect(Rect2(Rules.body_to_px(interval[0]), Rules.HORIZON_Y - Rules.WALK_BAND_DEPTH_PX, Rules.body_to_px(interval[1] - interval[0]), Rules.WALK_BAND_DEPTH_PX), Color(0.6, 0.25, 0.18, 0.18))
		if retreat_preview.is_empty():
			retreat_preview = world.retreat_polyline()
		for index in range(1, retreat_preview.size()):
			draw_dashed_line(retreat_preview[index - 1], retreat_preview[index], Color("c4d69f"), 3, 12)
	if flags[4]:
		draw_rect(Rect2(start + 3, Rules.TOP_BAR_HEIGHT + 3, Rules.CAMERA_WIDTH_PX - 6, Rules.HORIZON_Y - Rules.TOP_BAR_HEIGHT - 6), Color("d6bf79"), false, 3)
	if flags[6]:
		var unit_index := 0
		for unit in world.visible_units():
			var rise := 150 + (unit_index % 3) * 72
			unit_index += 1
			var info := "%s floor_id=%d %.1f px/s\n%s\n%s" % [unit.get_meta("unit_id"), unit.get_meta("floor_id"), unit.current_speed, unit.get_meta("current_post"), unit.get_meta("ai_state")]
			for index in info.split("\n").size():
				draw_string(font, unit.position + Vector2(-20, -rise + index * 20), info.split("\n")[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("dfd7bc"))

func _ruler(foot: Vector2, height: float, label: String) -> void:
	var top := foot - Vector2(0, height)
	draw_line(top, foot, Color("dfd7bc"), 2)
	draw_line(top - Vector2(5, 0), top + Vector2(5, 0), Color("dfd7bc"), 2)
	draw_line(foot - Vector2(5, 0), foot + Vector2(5, 0), Color("dfd7bc"), 2)
	draw_string(font, top + Vector2(8, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("dfd7bc"))
