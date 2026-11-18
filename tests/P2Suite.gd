extends Node
const Formula = preload("res://src/combat/Formula.gd")
const Policy = preload("res://src/ai/GuardPolicy.gd")
const Catalog = preload("res://src/data/CombatCatalog.gd")
var checks := 0
var failures := 0
var results: Array[Dictionary] = []
var capture := false
var combat: Node2D
var simulation: Node2D
var world: Node2D
var camera: Camera2D
var inspector: CanvasLayer
var overlay: Node2D
var attack_evidence: Array = []
var retreat_evidence: Array = []

func _ready() -> void:
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
	combat.tide_enabled = false
	combat.decisions_enabled = false
	add_child(combat)
	simulation = combat.get_node("Simulation")
	simulation.set_physics_process(false)
	world = combat.get_node("ReferenceMap")
	camera = combat.get_node("BattleCamera")
	overlay = combat.get_node("DebugOverlay")
	inspector = combat.get_node("BattleInspector")
	Clock.set_paused(true)
	await get_tree().process_frame
	if capture:
		get_window().size = Vector2i(1920,1080)
	check(Data.errors.is_empty(), "CSV and combat ID references load without errors")
	check(simulation.humans.size() == 5 and simulation.targets.size() == 12, "Default G0 preset has three named humans, two troops and 12 source-lane debug targets")
	check(not inspector.enabled and not inspector.panel.visible, "Developer AI panel is closed by default")
	check(not combat.has_node("WalkDebugger"), "Normal P2 scene does not expose P1 manual walk commands")
	for human in simulation.humans:
		var row: Dictionary = Data.get_unit(human.unit_id)
		check(human.max_hp == float(row["生命"]) and human.attack == float(row["攻击"]) and human.defense == float(row["防御"]) and human.speed_stat == int(row["速度"]), "All four stats loaded exactly from CSV: " + human.unit_id)
		check(human.skill_text == row.get("专属技能", "") and human.trait_text == row.get("特性", ""), "Source skill and trait semantics preserved: " + human.unit_id)
		check(world.is_cover_post(human.position) and world.inside_base(human.position), "Default human starts at a named in-base cover post: " + human.unit_id)
		check(not human.may_briefly_leave_base and human.return_after == 0, "Default base exception disabled: " + human.unit_id)
	check(_human("H01").skill_cost == 4 and _human("H09").skill_id == "kang_men" and _human("H17").skill_id == "feng_men_fu", "Required source costs and stable skill IDs")
	check(_human("T02").profile.range_body == 6, "Crossbow uses the source note's six-body range")
	check(Formula.damage(10,16) == 2 and Formula.damage(1,50) == 1 and Formula.damage(10,16,0.5) == 1, "Shared damage formula, minimum and resistance modifier")
	_catalog_failure()
	check(camera.left() == 6080 and camera.zoom == Vector2.ONE and Rules.UNIT_HEIGHT_PX == 80, "Default slice, zoom and 80px unit height preserved")
	var minimap: Control = combat.get_node("CanvasLayer/HUD").minimap
	for left in [0.0,6080.0,7680.0]:
		camera.set_left(left)
		await get_tree().process_frame
		check(is_equal_approx(minimap.camera_rect().size.x / minimap.MAP_RECT.size.x,0.2), "P2 minimap frame remains 20%% at %.0f" % left)
		check(absf((get_viewport().get_canvas_transform().affine_inverse() * Vector2.ZERO).x - left) < 0.01, "P2 actual canvas matches camera at %.0f" % left)
	camera.set_left(6080)
	if capture:
		await _shot("01-default-g0")
		overlay.flags[2] = true
		await _shot("02-scale")
		overlay.flags[2] = false
		camera.set_left(3200)
		overlay.flags[3] = true
		await _shot("03-front-cover")
		overlay.flags[3] = false
		camera.set_left(7680)
		await _shot("04-register-caster")
	simulation.spawn_source_targets(12)
	var unique_positions: Dictionary = {}
	for walker in simulation.targets:
		unique_positions[walker.position] = true
	check(simulation.targets.size() == 20 and unique_positions.size() == 20, "Repeated source spawns respect 20-target cap and never overlap slots")
	_reset("H09")
	var guard: Node2D = _human("H09")
	var target := _target(guard.position + Vector2(60,0))
	_tick(1.0 / 60)
	check(is_equal_approx(target.hp,22 - Formula.damage(10,3)), "Real melee attack goes through shared formula: 10 - 3*0.5 = 8.5")
	check(guard.ai_state == "Engage" and simulation.damage_log.size() == 1, "Guard engages in reach; one attack produces one damage record")
	attack_evidence = simulation.damage_log.duplicate(true)
	simulation.deal_damage(guard,target,"test_lethal",1000)
	check(target.dead and target.ai_state == "Broken", "Zero health immediately enters Broken and disables combat")
	_tick(0.8)
	check(simulation.targets.is_empty() and simulation.corpses.is_empty(), "Fallen actor leaves active battle and corpse expires")
	_reset("H09")
	guard = _human("H09")
	var origin: Vector2 = guard.position
	target = _target(Vector2(Rules.body_to_px(48.9),700))
	_tick(4)
	check(guard.position == origin and guard.brain.route.is_empty(), "Guard never chases a target outside outer gate")
	check(not Policy.can_stop(world,guard,Vector2(3900,700),0) and not Policy.can_stop(world,guard,Vector2(4800,700),0), "Hard policy rejects outside base and open-court center")
	target.position = Vector2(4800,700)
	_tick(3)
	check(guard.position == origin, "Distant court target does not create a new front at court center")
	_place(guard,"post_window_1")
	target.position = guard.position - Vector2(160,0)
	target.floor_id = 2
	simulation._update_units()
	var anchor: Vector2 = guard.position
	var metrics := _tick(1.0)
	check(guard.position.x < anchor.x and metrics.smooth, "Guard can step out to engage, rather than being welded to the post")
	check(absf(guard.position.x-anchor.x) <= Rules.body_to_px(Rules.HUMAN_CHASE_LIMIT), "Limited chase remains within 2.5 bodies of post")
	simulation.clear_targets()
	_tick(2)
	check(guard.position.distance_to(anchor) < 0.01, "Guard returns to cover when target disappears")
	target = _target(anchor + Vector2(160,0),2)
	_tick(1)
	check(guard.position.x > anchor.x and guard.position.x < target.position.x, "Guard approaches a target on the right without overshooting it")
	_reset("T02")
	var archer: Node2D = _human("T02")
	target = _target(archer.position - Vector2(240,0),2)
	_tick(1.0/60)
	check(simulation.projectiles.size() == 1 and target.hp == 22, "Ranged attack spawns a projectile without instant damage")
	var shot: Node2D = simulation.projectiles[0]
	var shot_start: Vector2 = shot.position
	_tick(0.15)
	check(shot.position != shot_start and target.hp == 22, "Projectile has visible finite travel time")
	camera.set_left(6080)
	simulation.debug_rays = true
	if capture:
		await _shot("05-projectile-flight")
	_tick(0.5)
	check(target.hp < 22 and simulation.damage_log[-1].kind == "projectile", "Swept projectile collision applies shared damage on impact")
	attack_evidence.append_array(simulation.damage_log)
	_reset("T02")
	archer = _human("T02")
	target = _target(Vector2(Rules.body_to_px(98),500),2)
	check(not simulation.can_attack(archer,target), "Closed gallery door blocks a shot within six-body range")
	var door: Node2D = world.get_node("door_gallery")
	door.set_open(true)
	check(simulation.can_attack(archer,target), "Opening that door exposes the target")
	_tick(1.0/60)
	check(simulation.projectiles.size() == 1, "Projectile starts through an open doorway")
	door.set_open(false)
	_tick(1)
	check(target.hp == 22 and simulation.projectiles.is_empty(), "Door closed after launch intercepts in-flight projectile")
	check(_has_event("projectile_blocked"), "Blocked projectile has an explicit collision event")
	if capture:
		await _shot("06-door-blocks-shot")
	_place(archer,"post_table_hall")
	target.position = Vector2(90 * 80,700)
	target.floor_id = 0
	check(not simulation.can_attack(archer,target), "Intact table/obstacle silhouette blocks ranged line")
	world.get_node("table_hall").set_occupied(false)
	check(simulation.can_attack(archer,target), "Removing obstacle exposes the same in-range target")
	var column_hit: Dictionary = simulation.world_hit(Vector2(7000,540),Vector2(7080,540))
	check(not column_hit.is_empty() and column_hit.kind == "pillar", "Real room column blocks a segment through its silhouette")
	_place(archer,"post_register")
	target.position = world.get_node("post_gate_inner").position
	archer.attack_left = 0
	check(not simulation.can_attack(archer,target) and not simulation.perform_attack(archer,target), "Register-to-outer-gate shot is rejected at actual attack entry")
	_reset("T02")
	archer = _human("T02")
	world.get_node("door_gallery").set_open(true)
	target = _target(Vector2(98*80,500),2)
	_tick(1.0/60)
	simulation.deal_damage(target,archer,"test_shooter_death",1000)
	_tick(0.7)
	await get_tree().process_frame
	await get_tree().process_frame
	_tick(0.2)
	check(is_equal_approx(target.hp,14.5) and simulation.projectiles.is_empty(), "An in-flight projectile resolves safely after its shooter has been removed")
	_reset("T02")
	archer = _human("T02")
	target = _target(archer.position - Vector2(40,0),2)
	_tick(1.0/60)
	check(archer.ai_state == "StepBack" and archer.brain.target_post == "post_stair_head", "Ranged unit threatened in melee retreats before firing")
	metrics = _tick(6)
	check(archer.current_post == "post_stair_head" and metrics.safe and metrics.smooth, "Ranged fallback reaches next cover through the door without teleporting")
	check(not world.get_node("door_gallery").is_open, "Automatic staff passage closes the intact door after traversal")
	_reset("H09")
	guard = _human("H09")
	guard.hold_lock = true
	door = world.get_node("door_outer")
	door.set_durability(6) # Deterministic one-hit destruction fixture; source/default max stays 240.
	target = _target(Vector2(3920,700))
	target.motion_enabled = true
	target.attacks_enabled = true
	_tick(2.0/60)
	check(door.destroyed and door.is_open and door.durability == 0, "Walking target attacks and destroys the real door via shared damage")
	check(guard.ai_state == "RetreatToNext" and guard.brain.last_reason == "structure", "Destroyed cover overrides hold lock and starts automatic retreat")
	metrics = _tick(1)
	check(is_equal_approx(guard.current_speed,240), "Horizontal retreat speed is 3.0 bodies/s (240px/s)")
	check(guard.current_speed > Rules.body_to_px(2.4), "Retreat exceeds fastest ordinary 2.4-body pursuit")
	camera.set_left(3200)
	overlay.flags[3] = true
	overlay.flags[6] = true
	if capture:
		await _shot("07-retreat-transit")
	metrics = _tick(2.5)
	check(guard.current_post == "post_barricade_outer_court" and target.position.x < guard.position.x, "Retreating human reaches next cover before following ordinary target")
	check(metrics.safe and metrics.smooth, "Retreat passes court but never stops at center or teleports")
	retreat_evidence = simulation.events.duplicate(true)
	if capture:
		await _shot("08-hold-next-cover")
	simulation.clear_targets()
	simulation.deal_damage(guard,world.get_node("outer_a"),"test_structure",1000)
	_tick(1.0/60)
	check(guard.brain.target_post == "post_inner_gate", "Destruction of the section's last obstacle triggers next retreat")
	metrics = _tick(7)
	check(guard.current_post == "post_inner_gate" and metrics.safe and not world.get_node("door_inner").is_open, "Retreat crosses outer court, opens inner door and closes it behind")
	_reset("H09")
	guard = _human("H09")
	for i in 3:
		_target(Vector2((48.7 - i * 0.5) * 80,700))
	_tick(2.4)
	check(guard.ai_state == "IdleAtPost", "3:1 pressure shorter than 2.5 seconds does not trigger retreat")
	_tick(0.2)
	check(guard.ai_state == "RetreatToNext" and guard.brain.last_reason == "pressure", "3:1 sustained pressure triggers automatic retreat at 2.5 seconds")
	_reset("H09")
	guard = _human("H09")
	for i in 3:
		_target(Vector2((48.7 - i * 0.5) * 80,700))
	_tick(2)
	simulation.targets[2].position.x = 0
	simulation._update_units()
	_tick(1)
	simulation.targets[2].position.x = 47.7 * 80
	simulation._update_units()
	_tick(2)
	check(guard.ai_state == "IdleAtPost", "Pressure timer resets when ratio drops below 3:1; separate bursts do not accumulate")
	_reset("H09")
	guard = _human("H09")
	guard.hold_lock = true
	for i in 3:
		_target(Vector2((48.7 - i * 0.5) * 80,700))
	_tick(3)
	check(guard.ai_state == "IdleAtPost" and guard.current_post == "post_gate_inner", "Hold lock suppresses numeric pressure retreat while cover remains")
	guard.hold_lock = false
	_tick(1.0/60)
	check(guard.ai_state == "RetreatToNext", "Releasing hold restores pressure retreat")
	_reset("H09")
	guard = _human("H09")
	for object in world.doors + world.obstacles:
		if object.max_durability > 0:
			simulation.deal_damage(guard,object,"test_clear_defenses",1000)
	metrics = _tick(30)
	check(guard.current_post == "post_stair_head" and guard.floor_id == 2, "Sequential broken fronts retreat through main stairs to floor 2")
	check(metrics.safe and metrics.smooth, "Full multi-front fallback preserves base and per-frame speed constraints")
	guard.attacks_enabled = false # Keep the three pressure fixtures alive for the full threshold.
	for i in 3:
		_target(guard.position - Vector2(120+i*45,0),2)
	_tick(12)
	check(guard.current_post == "post_register" and guard.floor_id == 0, "Next fallback descends rear stairs to final register room")
	check(simulation.next_post("post_register").is_empty(), "Register is final P2 stronghold, not a premature escape/win state")
	for id in ["post_gate_inner","post_barricade_outer_court","post_inner_gate","post_hall_door","post_stair_head","post_register"]:
		check(guard.brain.visited_posts.has(id), "Automatic fallback visited cover: " + id)
	retreat_evidence.append_array(simulation.events)
	simulation.clear_targets()
	guard.attacks_enabled = true
	target = _target(guard.position + Vector2(60,0))
	_tick(1.0/60)
	check(target.hp < 22 and guard.current_post == "post_register", "Defender continues fighting at final register stronghold")
	camera.set_left(7680)
	if capture:
		await _shot("09-register-final-line")
	_reset("H01")
	var caster: Node2D = _human("H01")
	target = _target(Vector2(44*80,700))
	var caster_origin: Vector2 = caster.position
	check(not caster.brain.request_channel(target), "Wan rejects a specified target outside the base")
	_tick(2)
	check(caster.position == caster_origin and not caster.brain.channel.active, "Rejected channel never walks caster out or into court")
	target.position = Vector2(89*80,700)
	check(caster.brain.request_channel(target), "Wan can channel from register on a target already inside hall")
	_tick(1)
	check(caster.ai_state == "Channel" and caster.brain.channel.elapsed > 0 and caster.position == caster_origin, "Channel progresses at safe ritual post without movement")
	if capture:
		await _shot("10-safe-channel")
	_tick(3.1)
	check(caster.brain.channel.completions == 1 and target.hp == 22 and simulation.targets.has(target), "P2 channel completes interface only; no P4 purification/recruitment/resource settlement")
	_place(caster,"post_barricade_outer_court")
	check(not caster.brain.request_channel(target), "Even a named courtyard cover is not a valid ritual casting location")
	simulation.deal_damage(target,caster,"test_human_lethal",1000)
	_tick(0.02)
	check(caster.dead and caster.ai_state == "Broken" and not simulation.humans.has(caster), "Human at zero health falls and is removed from active combat")
	_reset("H09")
	guard = _human("H09")
	world.get_node("door_outer").set_open(true)
	check(not guard.brain.excursion.request(simulation,guard,Vector2(3880,700),true), "Default named human cannot invoke an exception without its trait flag")
	var probe: Node2D = simulation.spawn_exception_probe()
	_tick(0.6)
	check(probe.position.x < Rules.BASE_START_X and probe.brain.excursion.active, "Explicit temporary probe can briefly leave base on a marked task")
	camera.set_left(3200)
	if capture:
		await _shot("11a-exception-probe")
	_tick(2)
	check(probe.brain.excursion.completed and probe.position == world.get_node("post_gate_inner").position, "Exception completion/deadline forces return to original inside cover")
	check(not guard.may_briefly_leave_base, "Probe does not grant exception rights to the named guard")
	probe.return_after = 0.15
	check(not probe.brain.excursion.request(simulation,probe,Vector2(3880,700),false), "Exception still requires an explicitly marked task")
	world.get_node("door_outer").set_open(true)
	check(probe.brain.excursion.request(simulation,probe,Vector2(3880,700),true), "Short-deadline marked probe is accepted")
	_tick(0.2)
	check(probe.brain.excursion.returning and probe.position.x > Rules.BASE_START_X, "Deadline interrupts outbound travel before the requested outside point")
	_tick(1)
	check(probe.brain.excursion.completed and probe.position == world.get_node("post_gate_inner").position, "Expired exception deadline forces return before reaching the outside destination")
	await _pause_and_ui()
	# An actual source-lane run demonstrates the unmodified target/door/AI chain.
	_reset()
	simulation.spawn_source_targets(12)
	metrics = _tick(75)
	check(not simulation.damage_log.is_empty() and _has_event("retreat"), "Default 12 source-lane walkers cause real structure damage and autonomous retreat")
	check(metrics.safe and metrics.smooth, "75-second integrated run keeps all surviving humans within legal base/cover behavior")
	var distinct := true
	for first in simulation.humans:
		for second in simulation.humans:
			if first != second and first.position.distance_to(second.position) < 8:
				distinct = false
	check(distinct, "Defenders sharing a fallback cover do not remain stacked on one pixel")
	var integration := {"duration_seconds":75,"humans":[],"targets":[],"doors":[],"events":simulation.events.duplicate(true)}
	for human in simulation.humans:
		integration.humans.append({"id":human.unit_id,"hp":human.hp,"position":[human.position.x,human.position.y],"post":human.current_post,"state":human.ai_state})
	for walker in simulation.targets:
		integration.targets.append({"hp":walker.hp,"position":[walker.position.x,walker.position.y],"state":walker.ai_state})
	for gate in world.doors:
		integration.doors.append({"id":gate.name,"durability":gate.durability,"destroyed":gate.destroyed})
	camera.set_left(3200)
	if capture:
		await _shot("13-source-run-75s")
	var report := {"phase":"P2","engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"capture":capture,"results":results,"attack_evidence":attack_evidence,"retreat_evidence":retreat_evidence,"integration_evidence":integration}
	var report_prefix := "p2"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report-prefix="):
			report_prefix = argument.trim_prefix("--report-prefix=")
	FileAccess.open("res://docs/phase-reports/%s-%s-results.json" % [report_prefix,("render" if capture else "test")],FileAccess.WRITE).store_string(JSON.stringify(report,"\t") + "\n")
	print("P2 RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)

func _pause_and_ui() -> void:
	_reset()
	var caster: Node2D = _human("H01")
	_target(Vector2(89*80,700))
	_target(Vector2(89*80,500),2)
	simulation.set_physics_process(true)
	Clock.set_speed(1)
	Clock.set_paused(false)
	await get_tree().create_timer(0.2).timeout
	Clock.set_paused(true)
	var snapshot := _snapshot()
	check(caster.brain.channel.active and not simulation.projectiles.is_empty(), "Live Clock frames advance AI, channel and projectiles together")
	await get_tree().create_timer(0.2).timeout
	check(_snapshot() == snapshot, "Pause freezes actors, targets, health, attack clocks, projectiles and channel progress")
	Clock.set_paused(false)
	await get_tree().create_timer(0.1).timeout
	check(_snapshot() != snapshot, "Resume restarts the same simulation")
	simulation.set_physics_process(false)
	Clock.set_paused(true)
	camera.set_left(6080)
	overlay.flags[3] = false
	overlay.flags[6] = false
	await get_tree().process_frame
	var human: Node2D = _human("H17")
	Clock.set_paused(false)
	await _click_world(human.position - Vector2(0,40))
	check(inspector.selected == human and inspector.inspector.visible and Clock.paused, "Real world click selects unit and automatically pauses")
	check(inspector.stats.text.contains("H17") and inspector.stats.text.contains("55") and inspector.stats.text.contains("封门符") and inspector.stats.text.contains("post_hall_door"), "Selected panel shows source stats, skill, post and AI state")
	if capture:
		await _shot("11-unit-inspector")
	await _key(KEY_F7)
	check(inspector.enabled and inspector.panel.visible, "F7 opens developer AI panel")
	if capture:
		await _shot("11b-debug-panel")
	inspector.buttons.hold.emit_signal("pressed")
	check(human.hold_lock, "Developer hold control toggles selected human")
	var rays_before: bool = simulation.debug_rays
	await _key(KEY_F9)
	check(simulation.debug_rays != rays_before, "F9 toggles projectile ray visualization")
	await _key(KEY_F7)
	inspector.clear_selection()
	var before := _snapshot()
	await _click_world(Vector2(82*80,680))
	check(_snapshot() == before and inspector.selected == null, "Clicking open court sends no player movement order")
	if capture:
		get_window().size = Vector2i(1440,900)
		await get_tree().process_frame
		var transform := get_viewport().get_final_transform()
		check(is_equal_approx(transform.x.length(),transform.y.length()), "P2 16:10 window preserves equal-axis scale")
		await _shot("12-paused-resized")
		get_window().size = Vector2i(1920,1080)

func _snapshot() -> String:
	var data: Array = [simulation.simulation_time]
	for unit in simulation.humans + simulation.targets:
		data.append([unit.instance_id,unit.position,unit.hp,unit.ai_state,unit.attack_left])
		if unit.role == "ritual":
			data.append(unit.brain.channel.elapsed)
	for shot in simulation.projectiles:
		data.append([shot.position,shot.distance_left])
	return str(data)

func _reset(keep := "") -> void:
	inspector.clear_selection()
	simulation.auto_targets = false
	simulation.reset_preset()
	simulation.set_physics_process(false)
	if not keep.is_empty():
		for index in range(simulation.humans.size()-1,-1,-1):
			if simulation.humans[index].unit_id != keep:
				simulation.humans[index].free()
				simulation.humans.remove_at(index)
	simulation._update_units()
	Clock.set_paused(true)

func _human(id: String) -> Node2D:
	for human in simulation.humans:
		if human.unit_id == id:
			return human
	return null

func _target(point: Vector2, floor_id := 0) -> Node2D:
	var target: Node2D = simulation.spawn_target(point)
	target.floor_id = floor_id
	target.motion_enabled = false
	target.attacks_enabled = false
	target.sync_meta()
	simulation._update_units()
	return target

func _place(unit: Node2D, post_id: String) -> void:
	unit.position = world.get_node(post_id).position
	unit.current_post = post_id
	unit.floor_id = int(world.get_node(post_id).get_meta("floor_id"))
	unit.brain.route.clear()
	unit.brain.settled_position = unit.position
	unit.brain.target_post = ""
	unit.brain.hold_left = 0
	unit.brain.pressure_elapsed = 0
	unit.brain.channel.cancel("")
	unit.attack_left = 0
	unit.set_state("IdleAtPost")
	simulation._update_units()

func _tick(seconds: float) -> Dictionary:
	var safe := true
	var smooth := true
	for index in ceili(seconds * 60):
		var positions: Dictionary = {}
		for human in simulation.humans:
			positions[human.instance_id] = human.position
		simulation.advance(1.0/60)
		for human in simulation.humans:
			if not world.inside_base(human.position):
				safe = false
			if human.brain.route.is_empty() and world.is_open_court(human.position) and not Policy.can_stop(world,human,human.position,human.floor_id):
				safe = false
			if positions.has(human.instance_id) and human.position.distance_to(positions[human.instance_id]) > Rules.body_to_px(Rules.RETREAT_SPEED)/60 + 0.01:
				smooth = false
	return {"safe":safe,"smooth":smooth}

func _has_event(kind: String) -> bool:
	for event in simulation.events:
		if event.kind == kind:
			return true
	return false

func _catalog_failure() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/p2_combat.json"))
	data.profiles.H09.skill_id = "missing_skill"
	var path := "/tmp/ye-ci-p2-invalid-skill.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data))
	var result: Dictionary = Catalog.read_catalog(path,Data.units)
	check(not result.errors.is_empty() and str(result.errors).contains("Unknown skill_id"), "Missing skill reference is rejected explicitly")
	DirAccess.remove_absolute(path)

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

func _click_world(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = get_viewport().get_canvas_transform() * point
	get_viewport().push_input(event,true)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event,true)
	await get_tree().process_frame

func _shot(id: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png("res://docs/phase-reports/p2-shots/%s.png" % id)
	check(error == OK,"Actual renderer screenshot: " + id)
