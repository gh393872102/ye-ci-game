extends SceneTree
## See the default production camera, cover line and panning in a pre-seeded formation.
var output := ""
var combat: Node2D
var camera: Camera2D
var world: Node2D
var sim: Node2D
var results: Array[Dictionary] = []
var screenshots: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	output = args[0]
	if not output.begins_with("/private/tmp/ye-ci-p9-") or root.get_node("Data").codex_store.path != output.path_join("state/codex.json"):
		quit(2)
		return
	root.size = Vector2i(1920,1080)
	combat = load("res://scenes/combat/Combat.tscn").instantiate()
	_check(combat.configure_chunks(["C01", "C03", "C04"]), "Authored three-core-chunk scene")
	root.add_child(combat)
	world = combat.get_node("ReferenceMap")
	camera = combat.get_node("BattleCamera")
	sim = combat.get_node("Simulation")
	camera.make_current()
	sim.set_physics_process(false)
	root.get_node("Clock").set_paused(true)
	var decisions: Node = combat.get_node("Decisions")
	decisions.managed_by_night = true
	decisions.prebattle.hide()
	var session: Node = combat.get_node("Session")
	session.start_battle("shouxiang")
	session.configure_roster("井雾照祠")
	for old in sim.humans:
		old.free()
	sim.humans.clear()
	sim.clear_targets()
	var roster := [
		["H09", "post_hall_door"], ["H17", "post_table_hall"], ["T02", "post_window_1"],
		["H06", "post_window_2"], ["H01", "post_register"], ["T01", "post_stair_head"]
	]
	for entry in roster:
		var unit: Node2D = sim.spawn_human(entry[0], entry[1])
		unit.position = sim.post_destination(unit, entry[1])
		unit.brain.settled_position = unit.position
	# Seed 44 common ghosts in the simulator's real four lanes, from the gate back through the approach.
	for column in 11:
		for lane in 4:
			var front := 6901.0 - 35 * lane
			sim.tide.spawn("G01", lane, front - column * 72.0 - (column * 7 + lane * 11) % 31)
	var ram: Node2D = sim.tide.spawn("G12", 2, 6951.0)
	var climber: Node2D = sim.tide.spawn("G09", 1, 6988.0)
	climber.position.y = world.floor_y(0) - 148
	climber.brain.stage = "climb"
	climber.set_state("Climb")
	sim._update_units()
	var camera_left: float = camera.left()
	var actor_count := 0
	for actor in sim.humans + sim.targets:
		if camera.world_rect().has_point(actor.position - Vector2(0, 1)):
			actor_count += 1
	_check(actor_count >= 40 and actor_count <= 80, "Default slice contains the regular battle density")
	_check(sim.humans.all(func(actor): return world.can_deploy_at(actor.current_post) and world.inside_base(actor.position) and not world.is_open_court(actor.position)), "Defenders occupy legal covered posts inside the base")
	_check(camera_left == 6080.0 and camera.zoom == Vector2.ONE and camera.world_rect().size.x == 1920.0, "Original default camera and complete map sizes")
	_check(world.floor_y(0) == 700 and world.floor_y(2) == 500 and world.floor_y(3) == 300, "Visual floors remain anchored to authored elevations")
	_check(not world._show_room_names and is_instance_valid(world.get_node("ShrineArchitecture")), "Normal battle has no persistent room labels")
	_check(world.get_node("door_hall").blocking_rect().size.y == 104.0 and is_instance_valid(ram), "Real 104 px hall door and rammer are present")
	await _shot("01-default-13-cover-25")
	var sky_before: float = world.get_node("ForestAndSky").position.x
	camera.set_left(4330)
	await _shot("02-court-scroll")
	var sky_after: float = world.get_node("ForestAndSky").position.x
	_check(absf(sky_after - sky_before) > 0 and absf(sky_after - sky_before) < absf(camera.left() - camera_left), "Sky moves more slowly than the map during lateral scrolling")
	await _debug()
	_check(world._show_room_names, "F6 reveals room labels for inspection")
	await _debug()
	_check(not world._show_room_names, "F6 returns to clean production view")
	camera.set_left(7680)
	await _shot("03-rear-register")
	var hall := world.get_node("door_hall")
	hall.receive_damage(hall.durability)
	camera.set_left(camera_left)
	await _shot("04-broken-door")
	_check(hall.destroyed and hall.is_open, "Broken gate sprite follows the real opening state")
	var sources := {}
	for path: String in ["src/world/MapDrawing.gd","src/world/ReferenceMap.gd","src/world/ShrineScenery.gd","src/world/ChunkPiece.gd","tests/P11WorldArtSuite.gd"]:
		sources[path] = FileAccess.get_sha256("res://" + path)
	var assets := {}
	for file: String in DirAccess.get_files_at("res://assets/sprites/world/inkshrine"):
		if file.get_extension() == "png":
			assets[file] = FileAccess.get_sha256("res://assets/sprites/world/inkshrine/" + file)
	var failures := results.filter(func(result): return not result.passed).size()
	var report := {"checks":results.size(),"failures":failures,"results":results,"screenshots":screenshots,
		"renderer":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,
		"actor_count_in_default_slice":actor_count,"front_door_screen_x":hall.position.x - camera_left,
		"source_sha256":sources,"asset_sha256":assets,
		"method":"Godot native fixed-frame inspection of a seeded formation on the shared C01, C03, C04 map. F6 is injected using real keyboard events. Gate destruction is a direct state fixture."}
	FileAccess.open(output.path_join("p11-revision-world-results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	combat.free()
	await process_frame
	quit(1 if failures else 0)

func _debug() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.pressed = pressed
		event.keycode = KEY_F6
		event.physical_keycode = KEY_F6
		root.push_input(event, true)
		await process_frame

func _shot(id: String) -> void:
	for i in 3:
		await process_frame
	RenderingServer.force_draw(true)
	var image := root.get_texture().get_image()
	var file := output.path_join(id + ".png")
	if _check(image != null and image.get_size() == Vector2i(1920,1080) and image.save_png(file) == OK, "Native 1080p " + id):
		screenshots[id] = {"file":file.get_file(),"camera_left":camera.left(),"zoom":camera.zoom.x,"sha256":FileAccess.get_sha256(file)}

func _check(ok: bool, label: String) -> bool:
	results.append({"check":label,"passed":ok})
	print(("PASS " if ok else "FAIL ") + label)
	return ok
