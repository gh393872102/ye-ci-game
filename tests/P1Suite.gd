extends Node
var checks := 0
var failures := 0
var results: Array[Dictionary] = []
var capture := false
var report_prefix := "p1"
var combat: Node2D
var world: Node2D
var human: Node2D
var camera: Camera2D
var overlay: Node2D
var debugger: CanvasLayer

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
	combat = preload("res://scenes/combat/Combat.tscn").instantiate()
	combat.spatial_only = true
	add_child(combat)
	await get_tree().process_frame
	world = combat.get_node("ReferenceMap")
	human = world.placeholders[0]
	camera = combat.get_node("BattleCamera")
	overlay = combat.get_node("DebugOverlay")
	debugger = combat.get_node("WalkDebugger")
	human.set_physics_process(false)
	check(not debugger.enabled and not debugger.panel.visible, "Developer walking is off on normal startup")
	check(world.floor_y(0) == 700 and world.floor_y(2) == 500 and world.floor_y(3) == 300, "Three 200px indoor stories, horizon unchanged")
	check(Rules.DOOR_HEIGHT_PX >= 96 and Rules.DOOR_HEIGHT_PX <= 112 and Rules.TABLE_HEIGHT_PX == 48, "Door 104px and table 0.6 body; ordinary unit remains 80px")
	check(camera.left() == 6080 and camera.zoom == Vector2.ONE, "P0 default slice and scale preserved")
	check(world.layout.obstacle_slots.size() == 6, "Two obstacle slots each in outer court, inner court and hall")
	for room_name in ["outer_court", "inner_court", "hall"]:
		var count := 0
		for slot in world.layout.obstacle_slots:
			if slot.room_id == room_name and slot.occupied:
				count += 1
		check(count == 1, "One default barrier with rear-lane gap: " + room_name)
	for floor_id in [0, 2, 3]:
		var rooms := 0
		for room in world.layout.rooms:
			if int(room.floor_id) == floor_id and room.tags.has("indoor"):
				rooms += 1
				check(room.end - room.start >= 4, "Room accommodates 3–4 people and facilities: " + room.id)
		check(rooms >= 2, "At least two distinct indoor rooms on floor %d" % floor_id)
	for post in world.posts:
		check(world.can_deploy_at(post.name), "Legal named cover post: " + post.name)
		check(post.has_meta("room_id") and post.has_meta("allowed_roles"), "Post has room and role metadata: " + post.name)
	check(world.is_outside_gate(Rules.BASE_START_X - 1) and not world.is_outside_gate(Rules.BASE_START_X), "Base boundary has correct inclusive inner edge")
	check(world.is_open_court(Vector2(60 * 80, 700)) and world.is_open_court(Vector2(82 * 80, 700)), "Both courts are open-court regions")
	check(not world.is_open_court(Vector2(92 * 80, 700)) and not world.is_open_court(Vector2(60 * 80, 500)), "Hall and unrelated upper coordinates are not open courts")
	check(world.inside_base(Vector2(60 * 80, 700)) and not world.is_cover_post(Vector2(60 * 80, 700)), "Court is passable base space but center is not a deployment post")
	check(not world.can_deploy_at("approach") and not human.request_post("approach"), "Non-post approach destination is rejected")
	check(world.navigation.route(human.position, 0, Vector2(44 * 80, 700), 0).is_empty(), "Human route cannot leave outer gate")
	check(world.navigation.route(human.position, 0, Vector2(30 * 80, 500), 1).is_empty(), "No shortcut through outside raised platform")
	check(world.room_at(Vector2(116 * 80, 700), 0) == "register" and world.room_at(Vector2(119 * 80, 700), 0) == "rear_exit", "Register and rear escape space are distinct")
	var path_time: float = world.ghost_path_length() / Rules.body_to_px(Rules.WALK_SPEED_REF)
	check(path_time >= 45 and path_time <= 70, "Measured unobstructed ghost main path: %.2f bodies / %.2fs" % [world.ghost_path_length() / 80, path_time])
	if capture:
		get_window().size = Vector2i(1920, 1080)
		await _shot("01-default")
		overlay.flags[2] = true
		await _shot("02-scale")
		overlay.flags[2] = false
		camera.set_left(7680)
		await _shot("03-interior")
		camera.set_left(3200)
		await _shot("04-two-courts-outer")
		camera.set_left(1600)
		await _shot("05-approach-platform")
		camera.set_left(6080)
	var hall_door: StaticBody2D = world.get_node("door_hall")
	var origin: Vector2 = human.position
	check(not human.request_post("post_inner_gate") and human.position == origin, "Closed hall door rejects crossing without teleporting")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ray := PhysicsRayQueryParameters2D.create(hall_door.position + Vector2(-60, -40), hall_door.position + Vector2(60, -40), 2)
	check(not world.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(), "Closed door has real physics collision")
	for door in world.doors:
		var original: float = door.durability
		door.set_durability(-10)
		check(door.durability == 0 and not door.is_open, "Durability interface clamps without implementing combat: " + door.door_id)
		door.set_durability(door.max_durability + 10)
		check(door.durability == door.max_durability, "Durability upper bound: " + door.door_id)
		door.set_durability(original)
	world.set_all_doors_open(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(world.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(), "Open door removes its blocking collider")
	for post in world.posts:
		var route: Array[Dictionary] = world.navigation.route(human.position, 0, post.position, int(post.get_meta("floor_id")))
		check(not route.is_empty(), "Every cover post reachable from hall through legal bands: " + post.name)
	# Table footprint must block direct travel; the generated route uses its visible gap.
	var table: StaticBody2D = world.get_node("table_hall")
	check(world.segment_blocked(table.position - Vector2(30, 0), table.position + Vector2(table.width + 30, 0), 0), "Furniture footprint blocks straight-line travel")
	check(not world.segment_blocked(table.position - Vector2(30, 48), table.position + Vector2(table.width + 30, -48), 0), "Rear gap clears furniture with actor radius")
	check(human.request_post("post_table_hall"), "Same-floor move around table is accepted")
	var has_gap := false
	for step in human.route:
		if step.point.y < Rules.HORIZON_Y:
			has_gap = true
	check(has_gap, "Route takes actual rear lane rather than crossing table")
	var walk_result := _walk_until_done()
	check(walk_result.safe and walk_result.smooth and walk_result.finished, "Same-floor movement respects collision and per-step speed")
	check(human.position == world.get_node("post_table_hall").position, "Same-floor arrival at cover position")
	check(human.request_post("post_window_1"), "Upper-floor cover route accepted")
	var contains_stair := false
	for step in human.route:
		if step.stair:
			contains_stair = true
	check(contains_stair, "Upper-floor route must use staircase")
	# Stop partway up the real staircase for rendered evidence.
	for i in 3000:
		if human.route.is_empty() or human.route[0].stair:
			break
		human.advance(1.0 / 60.0)
	var before_stair: Vector2 = human.position
	human.advance(1.0)
	check(is_equal_approx(human.position.distance_to(before_stair), 176 * 0.6), "Stair movement is 60% of 2.2-body horizontal speed")
	check(int(human.get_meta("floor_id")) == 0 and human.position.y < 700 and human.position.y > 500, "Stair transit is continuous; floor_id changes only on landing")
	if capture:
		camera.set_left(7360)
		overlay.flags[6] = true
		await _shot("06-stair-transit")
	walk_result = _walk_until_done()
	check(walk_result.finished and walk_result.smooth, "Stair journey completes without teleporting")
	check(int(human.get_meta("floor_id")) == 2 and human.position == world.get_node("post_window_1").position, "Arrival on floor 2 updates floor_id and reaches window")
	check(human.request_post("post_window_2"), "Beam-floor route accepted through second staircase")
	walk_result = _walk_until_done()
	check(walk_result.finished and int(human.get_meta("floor_id")) == 3, "Second staircase reaches floor 3")
	check(human.request_post("post_gate_inner"), "Return through stairs and both courts is legal")
	walk_result = _walk_until_done()
	check(walk_result.finished and walk_result.safe and human.position.x >= Rules.BASE_START_X, "Return crosses court gaps without exiting base or stopping at center")
	check(human.request_retreat(), "Complete ordered retreat route accepted from gate cover")
	var traversed: Dictionary = {}
	for i in 12000:
		if human.route.is_empty():
			break
		human.advance(1.0 / 60)
		traversed[str(human.get_meta("current_post"))] = true
	check(human.route.is_empty() and human.position == world.get_node("post_rear").position, "Retreat reaches rear escape space via register")
	for post_id in world.layout.retreat_line:
		check(traversed.has(post_id), "Retreat visits prescribed cover: " + post_id)
	var polyline: PackedVector2Array = world.retreat_polyline()
	check(polyline.size() > world.layout.retreat_line.size() and polyline[0] == world.get_node("post_gate_inner").position and polyline[-1] == world.get_node("post_rear").position, "F3 retreat polyline uses actual gap/stair route endpoints")
	# A door closing during movement must stop the actor before the closed leaf.
	check(human.request_post("post_hall_door"), "Return route before door-closing test")
	_walk_until_done()
	check(human.request_post("post_inner_gate"), "Crossing route exists while hall door is open")
	hall_door.set_open(false)
	walk_result = _walk_until_done()
	check(human.last_rejection == "WALK_BLOCKED" and human.position.x > hall_door.position.x + Rules.FOOT_RADIUS_PX, "Closing a door mid-route stops movement on the safe side")
	hall_door.set_open(true)
	check(human.request_post("post_hall_door"), "Blocked actor can request a new legal route after reopening")
	_walk_until_done()
	# Check actual Clock-driven movement and pause, not only manual deterministic stepping.
	check(human.request_post("post_table_hall"), "Live movement route accepted")
	human.set_physics_process(true)
	Clock.set_paused(false)
	var live_before: Vector2 = human.position
	await get_tree().create_timer(0.15).timeout
	check(human.position != live_before, "Actual physics frames move actor using Clock.delta")
	Clock.set_paused(true)
	var frozen: Vector2 = human.position
	await get_tree().create_timer(0.15).timeout
	check(human.position == frozen, "Paused Clock freezes debug traversal")
	Clock.set_paused(false)
	human.set_physics_process(false)
	_walk_until_done()
	await _key(KEY_F8)
	check(debugger.enabled and debugger.panel.visible, "F8 opens developer-only walking UI")
	debugger.select_human()
	check(not debugger.request_world_point(Vector2(44 * 80, 700)) and debugger.status.text == tr("WALK_REJECT_OUTSIDE"), "Debug click outside gate is explicitly rejected")
	if capture:
		camera.set_left(3200)
		await _shot("07-illegal-outside")
	check(not debugger.request_world_point(Vector2(60 * 80, 700)) and debugger.status.text == tr("WALK_REJECT_COURT"), "Court-center click cannot become deployment or stop command")
	if capture:
		await _shot("08-illegal-court")
	await _key(KEY_F8)
	check(not debugger.enabled, "F8 disables manual walk commands again")
	overlay.flags[3] = true
	overlay.flags[6] = false
	if capture:
		camera.set_left(4000)
		await _shot("09-retreat-courts")
		camera.set_left(7680)
		await _shot("10-retreat-interior")
		overlay.flags[3] = false
		overlay.flags[4] = true
		overlay.flags[5] = true
		camera.set_left(6080)
		await _shot("11-minimap-path")
	var data := {"phase": "P1", "engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "capture": capture, "ghost_path_body": world.ghost_path_length() / 80, "ghost_path_seconds": path_time, "results": results}
	var report := FileAccess.open("res://docs/phase-reports/%s-%s-results.json" % [report_prefix, "render" if capture else "test"], FileAccess.WRITE)
	report.store_string(JSON.stringify(data, "\t") + "\n")
	print("P1 RESULT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _walk_until_done() -> Dictionary:
	var safe := true
	var smooth := true
	for i in 12000:
		if human.route.is_empty():
			break
		var old: Vector2 = human.position
		var floor_id := int(human.get_meta("floor_id"))
		var stair: bool = human.route[0].stair
		human.advance(1.0 / 60)
		if old.distance_to(human.position) > 176.0 / 60 + 0.001:
			smooth = false
		if not world.inside_base(human.position):
			safe = false
		if not stair and world.segment_blocked(old, human.position, floor_id):
			safe = false
	return {"safe": safe, "smooth": smooth, "finished": human.route.is_empty() and human.last_rejection.is_empty()}

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

func _shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://docs/phase-reports/%s-shots" % report_prefix
	DirAccess.make_dir_recursive_absolute(directory)
	var error := get_viewport().get_texture().get_image().save_png("%s/%s.png" % [directory, name])
	check(error == OK, "Actual renderer screenshot: " + name)
