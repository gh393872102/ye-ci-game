extends Node
## Run with: Godot --headless --path . tests/P0Suite.tscn
## Add -- --capture without --headless to exercise rendering and record evidence.
const Csv = preload("res://src/data/CsvTable.gd")
var failures := 0
var checks := 0
var results: Array[Dictionary] = []
var capture := false
var report_prefix := "p0"
var combat: Node2D
var camera: Camera2D
var world: Node2D
var hud: Control
var debug: Node2D

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report-prefix="):
			report_prefix = argument.trim_prefix("--report-prefix=")
	capture = OS.get_cmdline_user_args().has("--capture")
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	results.append({"check": message, "passed": condition})
	if not condition:
		failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", message])

func _run() -> void:
	check(Data.errors.is_empty(), "All source tables load without errors")
	check(Data.units.size() == 68, "32 humans + 32 ghosts + 4 troops")
	check(Data.units.is_read_only(), "Unit cache is read only")
	var expected := {"H01": ["晚", "70", "点册"], "H09": ["铁肩", "110", "扛门"], "H17": ["朱砂", "55", "封门符"], "G01": ["白衣无面", "22", "拥门"], "G09": ["缢鬼", "36", "上梁"], "G12": ["力士尸", "70", "撞门"]}
	for id in expected:
		var row := Data.get_unit(id)
		check(row.get("姓名", row.get("名称")) == expected[id][0] and row["生命"] == expected[id][1] and str(row["专属技能"]).begins_with(expected[id][2]), "CSV identity, health and skill: " + id)
		check(row.is_read_only(), "Read-only row: " + id)
	check(str(Data.get_unit("T03")["备注"]).contains("初稿占位"), "Troop draft status is explicit")
	_csv_failures()
	check(Rules.body_to_px(24) == 1920, "24 bodies = 1920 world pixels")
	check(Rules.UNIT_HEIGHT_PX == 80 and Rules.REFERENCE_MAP_WIDTH_PX == 9600, "Locked body and world dimensions")
	check(Rules.empty_path_seconds() >= 45 and Rules.empty_path_seconds() <= 70, "Empty-path estimate = %.5f seconds" % Rules.empty_path_seconds())
	check(Rules.REGISTER_X - Rules.BASE_START_X > Rules.LONG_RANGE.y * Rules.BODY_PX, "Register to outer gate exceeds maximum 8-body range")
	check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items" and ProjectSettings.get_setting("display/window/stretch/aspect") == "keep", "Stretch canvas_items + keep")
	check(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter") == 0, "Nearest texture filter")
	check(ProjectSettings.get_setting("physics/common/physics_ticks_per_second") == 60, "60 Hz physics")
	for bus in ["SFX", "Music", "Ritual"]:
		check(AudioServer.get_bus_index(bus) >= 0, "Audio bus: " + bus)
	for action in ["pause", "speed_one", "speed_two", "camera_left", "camera_right", "select", "cancel", "buy", "deploy", "upgrade", "mutate", "fusion", "reinforce", "register", "repair", "recall", "codex", "select_next", "select_previous", "command_wheel"]:
		check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "Declared input: " + action)
	for pair in [["camera_left", KEY_LEFT], ["camera_right", KEY_RIGHT], ["speed_one", KEY_KP_DIVIDE], ["codex", KEY_TAB]]:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = pair[1]
		check(InputMap.action_has_event(pair[0], key_event), "Native key constant matches action: " + pair[0])
	_test_clock_math()
	combat = preload("res://scenes/combat/Combat.tscn").instantiate()
	combat.spatial_only = true
	add_child(combat)
	await get_tree().process_frame
	camera = combat.get_node("BattleCamera")
	world = combat.get_node("ReferenceMap")
	hud = combat.get_node("CanvasLayer/HUD")
	debug = combat.get_node("DebugOverlay")
	check(camera.zoom == Vector2.ONE and camera.left() == Rules.DEFAULT_CAMERA_LEFT, "Default view is a 1:1 slice at 76–100 bodies")
	check(world.posts.size() == 10, "All 10 named cover posts exist")
	check(world.placeholders.size() == 2, "Exactly two static scale placeholders")
	var human: Node2D = world.placeholders[0]
	var ghost: Node2D = world.placeholders[1]
	check(human.position == world.get_node("post_hall_door").position and human.position.x >= Rules.HALL_X, "Human is at hall-door cover, outside courtyard center")
	check(ghost.position.x < Rules.body_to_px(48), "Ghost is outside outer gate on approach")
	for group in ["units", "cover_posts", "doors", "obstacles", "floors", "camera", "hud", "minimap"]:
		check(not get_tree().get_nodes_in_group(group).is_empty(), "Stable scene group: " + group)
	for left_pos in [0.0, 6080.0, 7680.0]:
		camera.set_left(left_pos)
		camera.force_update_scroll()
		await get_tree().process_frame
		var frame: Rect2 = hud.minimap.camera_rect()
		check(is_equal_approx(frame.size.x / hud.minimap.MAP_RECT.size.x, 0.2), "Minimap frame width 20%% at %.0f" % left_pos)
		check(is_equal_approx((frame.position.x - hud.minimap.MAP_RECT.position.x) / hud.minimap.MAP_RECT.size.x, left_pos / Rules.REFERENCE_MAP_WIDTH_PX), "Minimap position matches camera at %.0f" % left_pos)
		var screen_left: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * Vector2.ZERO
		check(absf(screen_left.x - left_pos) < 0.01, "Actual rendered canvas agrees with camera at %.0f" % left_pos)
	camera.set_left(-500)
	check(camera.left() == 0, "Left edge clamps to world")
	camera.set_left(99999)
	check(camera.left() == 7680, "Right edge clamps to world")
	camera.set_left(Rules.DEFAULT_CAMERA_LEFT)
	Clock.set_paused(false)
	Clock.set_speed(1)
	if capture:
		get_window().size = Vector2i(1920, 1080)
		await get_tree().process_frame
		await _shot("01-default")
		camera.set_left(0)
		await _shot("02-source")
		camera.set_left(7680)
		await _shot("03-register")
		camera.set_left(Rules.DEFAULT_CAMERA_LEFT)
	for key in [1, 2, 3, 4, 5, 6, 10]:
		await _key(KEY_F1 + key - 1)
		check(debug.flags[key], "F%d turns its debug layer on" % key)
		await _key(KEY_F1 + key - 1)
		check(not debug.flags[key], "F%d turns its debug layer off" % key)
	await _key(KEY_F2)
	if capture:
		await _shot("04-height-human")
		camera.set_left(Rules.body_to_px(30))
		await _shot("05-height-ghost")
		camera.set_left(Rules.DEFAULT_CAMERA_LEFT)
	await _key(KEY_F2)
	await _key(KEY_F3)
	if capture:
		await _shot("06-cover")
	await _key(KEY_F3)
	await _key(KEY_F4)
	await _key(KEY_F5)
	if capture:
		await _shot("07-minimap-path")
	await _key(KEY_F4)
	await _key(KEY_F5)
	await _key(KEY_F6)
	if capture:
		await _shot("08-csv")
	await _key(KEY_F6)
	await _key(KEY_SPACE)
	check(Clock.paused and Clock.time_scale == 0, "Space pauses simulation")
	var paused_time := Clock.combat_time
	var wall_before := Clock.wall_time
	await get_tree().create_timer(0.2).timeout
	check(Clock.combat_time == paused_time and Clock.wall_time > wall_before, "Real frames: paused combat freezes while wall clock advances")
	var before: float = camera.left()
	Input.action_press("camera_left")
	await get_tree().create_timer(0.12).timeout
	Input.action_release("camera_left")
	check(camera.left() < before and Clock.combat_time == paused_time, "Keyboard camera pan works during pause")
	before = camera.left()
	await _key(KEY_RIGHT)
	check(camera.left() > before, "Physical right arrow pans right during pause")
	before = camera.left()
	await _key(KEY_LEFT)
	check(camera.left() < before, "Physical left arrow pans left during pause")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	mouse.pressed = true
	get_viewport().push_input(mouse, true)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 0)
	before = camera.left()
	get_viewport().push_input(motion, true)
	mouse = mouse.duplicate()
	mouse.pressed = false
	get_viewport().push_input(mouse, true)
	check(is_equal_approx(camera.left(), before - 100), "Middle drag pans exactly 100 logical pixels while paused")
	await _key(KEY_EQUAL)
	check(Clock.paused and Clock.time_scale == 0 and Clock.resume_scale == 2, "Speed shortcut keeps paused state and selects resume speed")
	# UI callback plus real mouse delivery exercise both layers.
	hud.buttons["BUY"].emit_signal("pressed")
	check(hud.feedback.text == tr("P4_PENDING"), "Empty command provides P4 feedback while paused")
	if capture:
		await _shot("09-paused")
	await _key(KEY_SPACE)
	check(not Clock.paused and Clock.time_scale == 2, "Space resumes at selected 2x")
	await _key(KEY_MINUS)
	check(Clock.time_scale == 1, "Minus restores 1x")
	Clock.set_speed(2)
	await _key(KEY_KP_DIVIDE)
	check(Clock.time_scale == 1, "Keypad divide restores 1x")
	await _click_button("two")
	check(Clock.time_scale == 2, "Actual HUD mouse click selects 2x")
	await _click_button("pause")
	check(Clock.paused, "Actual HUD mouse click pauses")
	await _click_button("one")
	check(Clock.paused and Clock.resume_scale == 1, "HUD 1x still usable while paused")
	await _key(KEY_SPACE)
	check(not Clock.paused, "Space still works after mouse focus on HUD")
	camera.set_left(Rules.DEFAULT_CAMERA_LEFT)
	check(human.position == world.get_node("post_hall_door").position and ghost.position.x == Rules.body_to_px(44), "All inputs leave both placeholders stationary")
	if capture:
		get_window().size = Vector2i(1440, 900)
		await get_tree().process_frame
		await _shot("10-resized-16-10")
		var transform := get_viewport().get_final_transform()
		check(is_equal_approx(transform.x.length(), transform.y.length()), "16:10 window preserves equal-axis 16:9 content scaling")
	var evidence := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "capture": capture, "results": results}
	var report := FileAccess.open("res://docs/phase-reports/%s-%s-results.json" % [report_prefix, "render" if capture else "test"], FileAccess.WRITE)
	report.store_string(JSON.stringify(evidence, "\t") + "\n")
	print("P0 RESULT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _test_clock_math() -> void:
	var clock := preload("res://src/autoload/Clock.gd").new()
	clock.advance(1)
	check(clock.combat_time == 1 and clock.cooldown_delta == 1, "1x advances world and unscaled cooldown equally")
	clock.set_speed(2)
	clock.advance(1)
	check(clock.combat_time == 3 and clock.delta == 2 and clock.cooldown_delta == 1, "2x doubles world delta but exposes unscaled cooldown delta")
	clock.set_paused(true)
	for index in 120:
		clock.advance(1.0 / 60.0)
	check(clock.combat_time == 3 and clock.delta == 0 and clock.cooldown_delta == 0, "120 paused steps do not advance combat or cooldown")
	clock.free()

func _csv_failures() -> void:
	for fixture in ["missing_column", "duplicate_id", "invalid_number", "short_row", "missing_file"]:
		var result: Dictionary = Csv.read_table("res://tests/fixtures/%s.csv" % fixture, ["id", "姓名", "生命"])
		check(not result.errors.is_empty(), "CSV rejects " + fixture)

func _key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _click_button(id: String) -> void:
	var button: Button = hud.buttons[id]
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.pressed = true
	# push_input uses logical viewport coordinates, independent of OS window scale.
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _shot(filename: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://docs/phase-reports/%s-shots" % report_prefix
	DirAccess.make_dir_recursive_absolute(directory)
	var error := get_viewport().get_texture().get_image().save_png("%s/%s.png" % [directory, filename])
	check(error == OK, "Rendered screenshot: " + filename)
