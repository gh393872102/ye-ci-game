extends Node
var checks := 0
var failures := 0
var results: Array[Dictionary] = []
var timings: Array[Dictionary] = []
var performance: Array[Dictionary] = []
var sim: Node2D
var combat: Node2D
var world: Node2D
var camera: Camera2D
var inspector: CanvasLayer
var capture := false
var performance_mode := false
var shots: Array[String] = []

func _ready() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	performance_mode = OS.get_cmdline_user_args().has("--performance")
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	results.append({"check":message,"passed":condition})
	if not condition:
		failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", message])

func _run() -> void:
	combat = preload("res://scenes/combat/Combat.tscn").instantiate()
	combat.decisions_enabled = false
	add_child(combat)
	sim = combat.get_node("Simulation")
	sim.set_physics_process(false)
	world = combat.get_node("ReferenceMap")
	camera = combat.get_node("BattleCamera")
	inspector = combat.get_node("BattleInspector")
	Clock.set_paused(true)
	await get_tree().process_frame
	if capture or performance_mode:
		get_window().size = Vector2i(1920,1080)
	if performance_mode:
		await _performance()
		_finish()
		return
	check(Data.errors.is_empty(),"P3 boot validates source CSV and skill/trait references")
	check(sim.tide.preset == "preset_hold_g0" and sim.humans.size() == 5,"Boot starts formal G0 hold tide with original five humans")
	for human in sim.humans:
		check(world.is_cover_post(human.position) and world.inside_base(human.position),"Human retains in-base cover: " + human.unit_id)
	check(Rules.REFERENCE_MAP_WIDTH_PX == 9600 and Rules.BODY_PX == 80 and camera.zoom == Vector2.ONE and camera.left() == 6080,"World scale, map length and default camera unchanged")
	check(is_equal_approx(combat.get_node("CanvasLayer/HUD").minimap.camera_rect().size.x / 480.0,0.2),"Minimap camera frame is 20 percent")
	for id in ["G01","G09","G12"]:
		var unit: Node2D = sim.tide.spawn(id,0,200)
		var row: Dictionary = Data.get_unit(id)
		check(unit.max_hp == float(row["生命"]) and unit.attack == float(row["攻击"]) and unit.defense == float(row["防御"]) and unit.speed_stat == int(row["速度"]),"All four stats come unchanged from CSV: " + id)
		check(unit.skill_text == row["专属技能"] and unit.trait_text == row["特性"],"Original skill/trait text: " + id)
	check(Data.traits.wu_mian.fears_light and Data.traits.wu_mian.light_damage_multiplier > 1 and Data.traits.wu_mian.exorcism_resistance_multiplier < 1,"Fear-light / low exorcism resistance data interface has correct direction")
	_isolated_rules()
	await _pause_breaking()
	await _climb_and_pause()
	await _visual()
	# Actual F5 input starts the empty-path trial; F7 opens the reproducible preset panel.
	_key(KEY_F5)
	await get_tree().process_frame
	check(sim.tide.preset == "preset_empty_path" and not Clock.paused,"F5 keyboard starts actual empty trial")
	sim.set_physics_process(false)
	await _trial("preset_empty_path",1.0/60,false)
	_key(KEY_F7)
	await get_tree().process_frame
	check(inspector.enabled and inspector.panel.visible,"F7 opens tide preset controls")
	inspector.buttons.hold_g0.pressed.emit()
	check(sim.tide.preset == "preset_hold_g0" and sim.tide.elapsed == 0,"One-click hold preset restores default defenses and resets timer")
	if capture:
		await _shot("05-debug-presets")
	inspector.enabled = false
	inspector.panel.hide()
	await _trial("preset_hold_g0",1.0/60,true)
	await _trial("preset_hold_g0",1.0/30,false)
	check(absf(timings[1].seconds - timings[2].seconds) < 5,"Hold remains stable at 1x and 2x simulation deltas")
	_finish()

func _fixture() -> void:
	sim.reset_preset("fixture")
	Clock.set_paused(true)
	for human in sim.humans:
		human.attacks_enabled = false

func _isolated_rules() -> void:
	_fixture()
	var door: Node2D = world.get_node("door_outer")
	var solo: Node2D = sim.tide.spawn("G01",0,door.position.x - 60)
	var before: float = door.durability
	sim.advance(1.0/60)
	var solo_damage: float = before - door.durability
	check(is_equal_approx(solo_damage,6),"Solo G01 door strike uses shared formula and CSV attack 6")
	_fixture()
	door = world.get_node("door_outer")
	for lane in 4:
		sim.tide.spawn("G01",lane,door.position.x - 60)
	before = door.durability
	sim.advance(1.0/60)
	check(is_equal_approx(before - door.durability,4 * solo_damage * 1.24),"Four synchronized G01 door attacks gain capped 24 percent 拥门")
	_fixture()
	door = world.get_node("door_outer")
	var heavy: Node2D = sim.tide.spawn("G12",3,door.position.x - 60)
	before = door.durability
	sim.advance(1.0/60)
	check(is_equal_approx(before - door.durability,40) and 40 > solo_damage,"G12 breaks structures at 16 x 2.5 = 40 damage")
	check(heavy.height_px == 144 and heavy.height_px >= Rules.LARGE_HEIGHT_MIN_PX and heavy.height_px <= Rules.LARGE_HEIGHT_MAX_PX,"Large ghost 144px silhouette stays in locked 128-176px range")
	door.set_durability(40)
	heavy.attack_left = 0
	sim.advance(1.0/60)
	check(door.destroyed and door.is_open and sim.tide.effects.size() == 1,"Door destruction opens passage and creates visible 0.6s debris")
	var prior: Vector2 = heavy.position
	_tick(1)
	check(heavy.position.x > door.position.x and heavy.position.distance_to(prior) <= 129,"G12 physically walks through broken door, no relocation")
	var retreat_seen := false
	for event in sim.events:
		if event.kind == "state" and event.detail == "RetreatToNext":
			retreat_seen = true
	check(retreat_seen,"Human line-break retreat still responds to destroyed door")
	_fixture()
	for id in ["G01","G12","G09"]:
		var unit: Node2D = sim.tide.spawn(id,sim.targets.size(),0)
		unit.attacks_enabled = false
	_tick(1)
	check(absf(sim.targets[0].position.x - 176) < 0.1,"Ordinary ghost moves 2.2 body/s")
	check(absf(sim.targets[1].position.x - 128) < 0.1,"G12 moves slower at 1.6 body/s")
	check(absf(sim.targets[2].position.x - 192) < 0.1,"G09 horizontal speed maps source speed 12 to 2.4 body/s")
	_fixture()
	for index in 150:
		sim.tide.spawn("G01",index % 4,float(index / 4) * 76)
	check(sim.targets.size() == 150 and sim.tide.spawn("G01",0,0) == null,"Capacity interface supports 150 actors; 151st is rejected")
	sim.tide.before_step(1.0/60)
	check(sim.tide.buckets.size() == 4 and sim.tide.leaders.size() == 146,"Floor/lane buckets compute a single predecessor per follower")

func _pause_breaking() -> void:
	_fixture()
	var door: Node2D = world.get_node("door_outer")
	sim.tide.spawn("G12",3,door.position.x - 60)
	sim.advance(1.0/60)
	var snapshot := _snapshot()
	var durability: float = door.durability
	sim.set_physics_process(true)
	await get_tree().create_timer(0.15).timeout
	check(_snapshot() == snapshot,"Paused real frames freeze an actively attacking G12 and door durability")
	sim.set_physics_process(false)
	_tick(1.2)
	check(door.durability < durability,"Same attacking G12 resumes structure damage when simulation advances")

func _climb_and_pause() -> void:
	_fixture()
	for human in sim.humans:
		human.free()
	sim.humans.clear()
	sim._update_units()
	world.set_all_doors_open(true)
	for obstacle in world.obstacles:
		obstacle.set_occupied(false)
	var ghost: Node2D = sim.tide.spawn("G09",1,Rules.body_to_px(sim.tide.config.climb.from_x) - 5)
	_tick(0.1)
	check(ghost.ai_state == "Climb" and ghost.floor_id == 0,"G09 selects visible wall-rope route before hall")
	_tick(0.8)
	check(ghost.position.y < 664 and ghost.position.y > 464 and ghost.floor_id == 0,"G09 traverses intermediate coordinates before changing floor")
	check(absf(ghost.current_speed - 192 * 0.6) < 0.1,"Climbing speed is 60 percent of source-derived horizontal speed")
	if capture:
		await _shot("03-climb-midway")
	var snapshot := _snapshot()
	sim.set_physics_process(true)
	Clock.set_paused(true)
	await get_tree().create_timer(0.15).timeout
	check(_snapshot() == snapshot,"Real paused engine frames freeze tide/climb, attack timers, structures and simulation time")
	sim.set_physics_process(false)
	_tick(2.5)
	check(ghost.floor_id == 2 and ghost.brain.stage == "upper","G09 reaches second floor continuously and updates floor_id")
	if capture:
		await _shot("04-upper-entry")
	_tick(15)
	check(ghost.floor_id == 0 and ghost.brain.stage == "rear" and sim.tide.arrival > 0,"Unopposed G09 traverses upper rooms and real rear stair into register")
	var climbed := false
	var landed := false
	for event in sim.tide.milestones:
		climbed = climbed or event.kind == "upper_entry"
		landed = landed or event.kind == "landed"
	check(climbed and landed,"Upper entry and landing emit visible event feedback")

func _visual() -> void:
	for count in [40,80]:
		_fixture()
		sim.tide.preset = "preset_visual_tide"
		sim.tide.visual(count)
		check(sim.targets.size() == count,"Visual fixture contains %d tide units" % count)
		var visible := 0
		var lanes: Dictionary = {}
		var positions: Dictionary = {}
		for unit in sim.targets:
			visible += int(unit.position.x >= camera.left() and unit.position.x < camera.left() + 1920)
			lanes[unit.lane_index] = true
			positions[unit.position] = true
		check(visible == count and lanes.size() == 4 and positions.size() == count,"All %d visible at unchanged default camera, four rows, unique positions" % count)
		_tick(1)
		if capture:
			await _shot("01-visual-%d" % count)
		check(camera.zoom == Vector2.ONE and camera.left() == 6080,"Visual %d never changes camera scale or slice" % count)
	_fixture()
	var barrier: Node2D = world.get_node("door_hall")
	barrier.set_durability(40)
	var heavy: Node2D = sim.tide.spawn("G12",3,barrier.position.x - 60)
	sim.advance(1.0/60)
	if capture:
		await _shot("02-door-shatter")
	_tick(0.7)
	check(sim.tide.effects.is_empty() and camera.zoom == Vector2.ONE,"Impact feedback ends before 0.8s; camera never zooms")
	check(not heavy.dead,"Door-impact fixture actor remains in simulation")

func _trial(name: String, delta: float, take_shots: bool) -> void:
	sim.reset_preset(name)
	Clock.set_paused(true)
	var unique := true
	var base_safe := true
	var continuous := true
	var normal_floor := true
	var climb_seen := false
	var broken_shot := false
	for frame in ceili(600.0 / delta):
		var before: Dictionary = {}
		for unit in sim.targets:
			before[unit.instance_id] = unit.position
		sim.advance(delta)
		for unit in sim.targets:
			if before.has(unit.instance_id):
				continuous = continuous and unit.position.distance_to(before[unit.instance_id]) <= 192 * delta + 0.1
			if unit.unit_id == "G01":
				normal_floor = normal_floor and unit.floor_id == 0
			climb_seen = climb_seen or unit.ai_state == "Climb"
		for human in sim.humans:
			base_safe = base_safe and world.inside_base(human.position)
		if frame % 60 == 0:
			var positions: Dictionary = {}
			for unit in sim.targets:
				positions[unit.position] = true
			unique = unique and positions.size() == sim.targets.size()
		if take_shots and capture and not broken_shot and world.get_node("door_hall").destroyed:
			broken_shot = true
			await _shot("06-hold-hall-breach")
		if frame % 600 == 0:
			await get_tree().process_frame
		if sim.tide.arrival >= 0:
			break
	var seconds: float = sim.tide.arrival
	var record := {"preset":name,"delta":delta,"seconds":seconds,"arrived_by":sim.tide.arrived_by,"milestones":sim.tide.milestones.duplicate(true),"spawned":sim.tide.spawn_count,"surviving":sim.targets.size()}
	timings.append(record)
	print("MEASURED ",name," delta=",delta," arrival=",seconds)
	if name == "preset_empty_path":
		check(seconds >= 45 and seconds <= 70,"Measured empty path is within 45-70s: %.3f" % seconds)
		check(sim.tide.spawn_count == 1 and sim.damage_log.is_empty(),"Empty trial has one 2.2-speed G01, no attacks and no blocking structures")
	else:
		check(seconds >= 120 and seconds < 600,"Hold first body enters room at >=120s and before 10min: %.3f" % seconds)
		check(climb_seen,"Hold waves include actual G09 climbing before first entry")
		check(sim.tide.spawn_count >= 40 and sim.tide.spawn_count <= 80,"Formal waves create 40-80 source-origin tide units")
	check(unique,"No exact-position stacking during " + name)
	check(continuous,"No ghost teleports during " + name)
	check(base_safe,"Humans remain inside base throughout " + name)
	check(normal_floor,"Normal G01 never climbs during " + name)
	if capture and take_shots:
		camera.set_left(7680)
		await _shot("07-register-first-entry")
		camera.set_left(6080)

func _performance() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for count in [40,80]:
		_fixture()
		sim.tide.preset = "preset_visual_tide"
		sim.tide.visual(count)
		# Keep the full active tide on screen while measuring real attacks, queues and rendering.
		for door in world.doors:
			if not door.destroyed:
				door.max_durability = 100000
				door.set_durability(100000)
		for human in sim.humans:
			human.attacks_enabled = true
		var frames: Array[float] = []
		var steps: Array[float] = []
		for frame in 660:
			var start := Time.get_ticks_usec()
			sim.advance(1.0/60)
			var stepped := Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			if frame >= 60:
				steps.append((stepped - start) / 1000.0)
				frames.append((Time.get_ticks_usec() - start) / 1000.0)
		frames.sort()
		steps.sort()
		var total := 0.0
		for value in frames:
			total += value
		var record := {"tide_requested":count,"humans":sim.humans.size(),"tide_alive":sim.targets.size(),"samples":frames.size(),"average_fps":1000.0/(total/frames.size()),"frame_p50_ms":frames[300],"frame_p95_ms":frames[570],"simulation_p95_ms":steps[570],"viewport":[1920,1080],"renderer":RenderingServer.get_current_rendering_method(),"vsync":"disabled","fixture":"active visual tide, durable hall gate"}
		performance.append(record)
		print("PERFORMANCE ",record)
		check(record.average_fps >= 60,"%d tide active rendering average >=60 FPS: %.1f" % [count,record.average_fps])
		if capture:
			await _shot("perf-%d" % count)

func _snapshot() -> String:
	var values: Array = [sim.simulation_time,sim.tide.elapsed]
	for unit in sim.humans + sim.targets:
		values.append([unit.position,unit.hp,unit.attack_left,unit.floor_id])
	for object in world.doors + world.obstacles:
		values.append(object.durability)
	return str(values)

func _tick(seconds: float) -> void:
	for frame in roundi(seconds * 60):
		sim.advance(1.0/60)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)

func _shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://docs/phase-reports/p3-shots/%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	shots.append(path)

func _finish() -> void:
	var suffix := "performance" if performance_mode else ("render" if capture else "test")
	var report_prefix := "p3"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report-prefix="):
			report_prefix = argument.trim_prefix("--report-prefix=")
	var report := {"phase":"P3","checks":checks,"failures":failures,"results":results,"timings":timings,"performance":performance,"screenshots":shots,"engine":Engine.get_version_info().string,"os":OS.get_name(),"date":Time.get_datetime_string_from_system()}
	var file := FileAccess.open("res://docs/phase-reports/%s-%s-results.json" % [report_prefix,suffix],FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ") + "\n")
	print("P3 RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures > 0 else 0)
