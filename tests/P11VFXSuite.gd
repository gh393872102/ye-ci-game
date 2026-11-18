extends SceneTree
## Native gameplay evidence at the default zoom. Use tools/p9_verify.py --native --script tests/P11VFXSuite.gd.
const STEP := 1.0 / 60.0
const CAMERA_LEFT := 6080.0
const SEED_TEXT := "祠门与梁·远镜头"
const CORE_CHUNKS := ["C01", "C03", "C04"]

var output := ""
var combat_scene: PackedScene
var stages: Script
var clock: Node
var combat: Node2D
var camera: Camera2D
var sim: Node2D
var session: Node
var hud: Control
var results: Array[Dictionary] = []
var shots: Dictionary = {}
var observations: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else ""
	var data := root.get_node("Data")
	if not output.begins_with("/private/tmp/ye-ci-p9-") or data.codex_store.path != output.path_join("state/codex.json"):
		printerr("Use the disposable native verifier")
		quit(2)
		return
	clock = root.get_node("Clock")
	combat_scene = load("res://scenes/combat/Combat.tscn")
	stages = load("res://src/data/StageOptions.gd")
	if not _check(DisplayServer.get_name() != "headless" and data.errors.is_empty(), "Native display and production data"):
		_finish()
		return
	root.size = Vector2i(1920, 1080)
	await _skills()
	await _paper()
	await _breach()
	await _upper()
	await _fusion()
	if is_instance_valid(combat):
		combat.free()
	await process_frame
	_finish()

func _skills() -> void:
	var roster := [["H01", "post_table_hall"], ["H17", "post_hall_door"], ["H04", "post_hall_door"], ["H06", "post_window_1"], ["T02", "post_window_2"]]
	if not _check(_open(CORE_CHUNKS, "shouxiang", roster), "Default camera, real combat scene and five legal cover posts"):
		return
	var prefabs := PackedStringArray()
	for node in sim.vfx.get_children():
		prefabs.append(node.scene_file_path.get_file())
	_check(prefabs == PackedStringArray(["DianCeCircle.tscn", "GreenLantern.tscn", "TalismanSeal.tscn", "IncenseSmoke.tscn", "CrossbowTrail.tscn"]), "Five independent packed scenes are mounted in normal combat")
	var reader := _human("H01")
	var signer := _human("H17")
	var joss := _human("H04")
	var light := _human("H06")
	var crossbow := _human("T02")
	for unit in sim.humans:
		unit.attacks_enabled = false
		unit.motion_enabled = false
	crossbow.attacks_enabled = true
	var elite := _ghost("G09", 0, 94.2, 3)
	_ghost("G01", 0, 86.3, 2)
	var shadows := [_ghost("G04", 2, 90.2, 3), _ghost("G01", 2, 94.0, 3), _ghost("G04", 2, 94.6, 2)]
	var bolt_target := _ghost("G12", 3, 96.5, 3)
	sim._update_units()
	if not _check(session.preview_ritual(reader, elite).reason.is_empty() and _protected(reader), "The hall reader has a legal, indoor reading on a live elite"):
		return
	await _frames()
	var decisions: Node = combat.get_node("Decisions")
	await _click(hud.buttons.REGISTER_ACTION)
	var confirm := decisions.panel.find_child("ritual_confirm", true, false) as Button
	if not _check(confirm != null and not confirm.disabled, "Native mouse opens the real ritual action and its target confirmation"):
		return
	await _click(confirm)
	if not _check(reader.brain.channel.active and reader.brain.channel.target == elite, "The selected confirmation starts the paid channel"):
		return
	var reveal := _cast(light)
	var revealed_count := shadows.filter(func(actor): return actor.growth.statuses.has("revealed")).size()
	_check(reveal and revealed_count == 3, "Cold light reveals three actual actors on the gallery")
	var sealed := _cast(signer)
	_check(sealed and session.growth.state.seals.has("door_hall"), "The real seal applies to the hall doorway")
	var prepaid_before: float = reader.roster.reserve_incense
	var transferred := _cast(joss, reader)
	var incense_credit: float = reader.roster.reserve_incense - prepaid_before
	_check(transferred and incense_credit > 0.0, "The real transfer moves incense to the reader")
	var fired := _cast(crossbow, bolt_target)
	_check(fired and sim.projectiles.size() == 1 and _event("projectile_fired"), "The real crossbow command launches a swept bolt")
	_steps(12)
	var progress: float = reader.brain.channel.progress()
	var same_posts: bool = _protected(reader) and _protected(signer) and _protected(joss) and _protected(light) and _protected(crossbow)
	_check(progress > 0.0 and sim.projectiles.any(func(shot): return shot.kind == "bolt") and same_posts, "All effects operate from cover while the reading and bolt are in flight")
	await _shot("01-k4-five-skills")
	var before_impact: float = bolt_target.hp
	var landed := _until(1.3, func(): return _cue("bolt_hit"))
	_check(landed and bolt_target.hp < before_impact, "The bolt streak ends where the real projectile hits")
	var pause_time: float = sim.simulation_time
	var pause_progress: float = reader.brain.channel.progress()
	await _frames(6)
	_check(clock.paused and is_equal_approx(sim.simulation_time, pause_time) and is_equal_approx(reader.brain.channel.progress(), pause_progress), "Paused rendering keeps the channel and effects still")
	var names_before: float = session.names
	var sent := _until(8.0, func(): return _cue("send_off") or _cue("give_face"))
	_check(sent and _cue("register_relight") and session.names > names_before and _event("channel_complete"), "A completed reading sends the elite off and relights the register only with real names credit")
	observations.k4 = {"prefabs":prefabs, "revealed":revealed_count, "transfer_credit":incense_credit, "channel_progress_in_frame":progress, "protected_posts":same_posts,
		"names_before":names_before, "names_after":session.names, "reader_post":reader.current_post, "reader_room":sim.world.room_at(reader.position, reader.floor_id)}
	if sent:
		_steps(10)
		await _shot("02a-purification-send-off")
		camera.set_left(7680)
		await _shot("02-register-relight")

func _breach() -> void:
	if not _check(_boss("B01", [["T01", "post_table_hall"], ["H01", "post_register"]]), "Authored B01 loads the real rammer and gate pressure"):
		return
	# Start a live follow-up wave along the four approach lanes. The authored lead rammer still breaks the gate.
	for column in 7:
		for lane in 4:
			sim.tide.spawn("G01", lane, 6090.0 - 84 * column - 16 * lane)
	var door: Node2D = sim.world.get_node("door_hall")
	var broken := _until(12, func(): return _cue("door_break", "door_hall"))
	var damage: Array = sim.damage_log.filter(func(hit): return hit.target == "door_hall" and str(hit.attacker).begins_with("G12_") and hit.after <= 0.0)
	if _check(broken and door.destroyed and door.is_open and door.durability == 0 and not damage.is_empty(), "A real G12 hit opens the hall gate and triggers the wood splinters"):
		_steps(11)
		await _shot("03-k5-gate-splinters")
	var flooded := _until(22, func(): return _cue("door_surge", "door_hall") and bool(stages.get_stage(session).state.gate_flooded))
	var entrants: Array = sim.targets.filter(func(actor): return not actor.dead and actor.floor_id == door.floor_id and actor.position.x > door.position.x + 18 and actor.instance_id in stages.get_stage(session).state.gate_entrants)
	_check(flooded and _event("p10_tide_flood") and entrants.size() >= 2, "At least two actual attackers cross past the opened gate and trigger the moving dust")
	observations.breach = {"damage":damage, "first_breach":session.first_breach, "entered":entrants.map(func(actor): return actor.instance_id), "held_posts":_protected(_human("T01")), "approach_lanes":4, "live_follow_up_ghosts":28}
	if flooded:
		_steps(12)
		await _shot("04-k5-tide-enters")

func _paper() -> void:
	if not _check(_open(CORE_CHUNKS, "shouxiang", [["H18", "post_table_hall"], ["H22", "post_window_1"], ["H01", "post_register"]]), "Mirror and dispel have legal starting posts"):
		return
	var mirror := _human("H18")
	var dispeller := _human("H22")
	_ghost("G12", 0, 94.3, 3)
	var target := _ghost("G30", 2, 94.0, 3)
	sim._update_units()
	var mirrored := _cast(mirror)
	var hp_before: float = target.hp
	var dispelled := _cast(dispeller, target)
	_check(mirrored and mirror.roster.statuses.has("mirror") and dispelled and target.hp < hp_before and _event("roster_false_god_unmasked"), "Mirror and dispel create real ward and unmasking events using the shared paper preset")
	if mirrored and dispelled:
		_steps(12)
		await _shot("08-k4-mirror-and-dispel")

func _upper() -> void:
	if not _check(_boss("B02", [["T01", "post_table_hall"], ["H01", "post_register"]]), "Authored B02 loads the real climb route and empty upper defense line"):
		return
	var stage: Node = stages.get_stage(session)
	var climber: Node2D = session._actor(stage.state.boss_actor)
	var arrived := _until(9, func(): return _cue("upper_entry", climber.instance_id))
	var room: String = sim.world.room_at(climber.position, climber.floor_id) if is_instance_valid(climber) else ""
	_check(arrived and climber.unit_id == "G09" and climber.floor_id == 2 and room == "gallery" and climber.brain.stage == "upper", "Real G09 reaches the gallery along the wall route and leaves a pounce trail")
	if arrived:
		_steps(6)
		await _shot("05-k5-gallery-pounce")
	var names_before: float = session.names
	var lost := _until(16, func(): return _cue("upper_lost"))
	_check(lost and stage.state.upper_lost and _event("p10_upper_lost") and session.names < names_before, "The unstaffed gallery trips the real failure line and drains names")
	if lost:
		_steps(6)
		await _shot("06-k5-gallery-lost")
		_check("失守" in hud.stage_pressure.text and "失守" in hud.upper_status.text, "Room loss stays visible on the non-modal stage warning and top status")
	observations.upper = {"actor":climber.instance_id if is_instance_valid(climber) else "", "entry_room":room, "entry_floor":2 if arrived else -1,
		"names_before_loss":names_before, "names_after_loss":session.names, "held_posts":_protected(_human("T01"))}

func _fusion() -> void:
	if not _check(_open(CORE_CHUNKS, "duoming", [["T01", "post_table_hall"], ["H01", "post_register"]]), "Normal attacker combat for the paid fusion"):
		return
	var first := _ghost("G12", 0, 86.1, 3)
	var second := _ghost("G20", 0, 84.4, 1)
	var gate: Node2D = sim.world.get_node("door_hall")
	var gate_before: float = gate.durability
	var before: float = session.incense
	var answer: Dictionary = session.execute_for("duoming", "fuse", {"first_id":first.instance_id, "second_id":second.instance_id, "recipe_id":"F02"}, "player")
	_check(answer.ok and first.display_name == "门骑" and first.growth.fusion_id == "F02" and second.dead and session.incense < before and _cue("fusion", "F02"), "The actual F02 command consumes the second unit and incense and reveals the heavy fusion")
	observations.fusion = {"recipe":"F02", "height":first.height_px, "name":first.display_name, "incense_cost":before - session.incense, "source_consumed":second.dead}
	if answer.ok:
		first.motion_enabled = true
		_steps(10)
		await _shot("07-fusion-arrival")
		var charged := _until(3, func(): return sim.damage_log.any(func(hit): return hit.kind == "charge_structure" and hit.attacker == first.instance_id and hit.target == "door_hall"))
		_check(charged and gate.durability < gate_before, "Fused Door Rider's real charge damages the next gate")
		observations.fusion.gate_damage = gate_before - gate.durability

func _open(chunks: Array, mode: String, roster: Array) -> bool:
	if is_instance_valid(combat):
		combat.free()
	combat = combat_scene.instantiate()
	if not combat.configure_chunks(chunks):
		return false
	root.add_child(combat)
	camera = combat.get_node("BattleCamera")
	camera.make_current()
	sim = combat.get_node("Simulation")
	sim.set_physics_process(false)
	session = combat.get_node("Session")
	hud = combat.get_node("CanvasLayer/HUD")
	var decisions: Node = combat.get_node("Decisions")
	decisions.managed_by_night = true
	decisions.prebattle.hide()
	clock.set_paused(true)
	if not session.start_battle(mode).ok:
		return false
	for unit in sim.humans:
		unit.free()
	sim.humans.clear()
	sim.clear_targets()
	sim.tide.pending.clear()
	sim.tide.config.waves.clear()
	session.configure_roster(SEED_TEXT)
	session.incense = 60.0
	session.names = 9.0
	var data := root.get_node("Data")
	for entry in roster:
		# The full formation uses the legal starting posts available to the observer. Some named actors are not sold in the legacy shop.
		var role: String = data.combat_profiles[entry[0]].role
		var post: Node2D = sim.world.get_node_or_null(entry[1])
		var legal: String = session.deployment_reason(entry[1], "")
		if not legal.is_empty() or (role if role != "talisman" else "crossbow") not in post.get_meta("allowed_roles"):
			print("Starting post rejected: ", entry, " ", legal, " ", role)
			return false
		var unit: Node2D = sim.spawn_human(entry[0], entry[1])
		if unit == null:
			return false
		unit.position = sim.post_destination(unit, str(entry[1]))
		unit.brain.settled_position = unit.position
	sim._update_units()
	return is_equal_approx(camera.left(), CAMERA_LEFT)

func _boss(id: String, roster: Array) -> bool:
	return _open(stages.required_chunks(id, []), "shouxiang", roster) and stages.start(session, id, [], SEED_TEXT)

func _human(id: String) -> Node2D:
	for unit in sim.humans:
		if unit.unit_id == id and not unit.dead:
			return unit
	return null

func _ghost(id: String, floor_id: int, body_x: float, lane: int) -> Node2D:
	var unit: Node2D = sim.tide.spawn(id, lane, body_x * 80.0)
	unit.floor_id = floor_id
	unit.position.y = sim.world.floor_y(floor_id) + float(sim.tide.config.lane_offsets[lane])
	unit.motion_enabled = false
	unit.attacks_enabled = false
	unit.sync_meta()
	return unit

func _protected(unit: Node2D) -> bool:
	return is_instance_valid(unit) and not unit.dead and sim.world.inside_base(unit.position) and not sim.world.is_open_court(unit.position) and sim.world.can_deploy_at(unit.current_post)

func _cast(unit: Node2D, target: Node2D = null) -> bool:
	var args := {"unit_id":unit.instance_id}
	if target != null:
		args.target_id = target.instance_id
	return session.roster_command("unit_skill", args).ok

func _cue(kind: String, detail := "") -> bool:
	return sim.vfx.cues.any(func(cue): return cue.kind == kind and (detail.is_empty() or cue.detail == detail))

func _event(kind: String) -> bool:
	return sim.events.any(func(event): return event.kind == kind)

func _steps(count: int) -> void:
	for i in count:
		sim.advance(STEP)

func _until(limit: float, predicate: Callable) -> bool:
	while session.running and sim.simulation_time < limit:
		if predicate.call():
			return true
		sim.advance(STEP)
	return predicate.call()

func _frames(count := 3) -> void:
	for i in count:
		await process_frame

func _click(control: Control) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = control.get_global_rect().get_center()
		root.push_input(ev, true)
		await _frames(2)

func _shot(id: String) -> void:
	await _frames()
	RenderingServer.force_draw(true)
	var image := root.get_texture().get_image()
	var file := output.path_join(id + ".png")
	var actual_size := Vector2i(image.get_width(), image.get_height()) if image != null else Vector2i.ZERO
	if _check(actual_size == Vector2i(1920, 1080) and camera.zoom.is_equal_approx(Vector2.ONE) and image.save_png(file) == OK, "Native 1080p frame at production zoom " + id):
		shots[id] = {"file":file.get_file(), "sha256":FileAccess.get_sha256(file), "width":actual_size.x, "height":actual_size.y,
			"camera_left":camera.left(), "camera_zoom":camera.zoom.x, "battle_seconds":sim.simulation_time, "stage_status":hud.stage_pressure.text, "stage_event":hud.stage_event.text}

func _check(ok: bool, label: String) -> bool:
	results.append({"ok":ok, "check":label})
	print(("PASS " if ok else "FAIL ") + label)
	return ok

func _finish() -> void:
	var failures := results.filter(func(result): return not result.ok).size()
	var sources := {}
	for folder: String in ["src/combat/vfx", "scenes/combat/vfx"]:
		for file in DirAccess.get_files_at("res://" + folder):
			if file.get_extension() in ["gd", "tscn"]:
				var path := folder.path_join(file)
				sources[path] = FileAccess.get_sha256("res://" + path)
	for path in ["tests/P11VFXSuite.gd", "src/combat/CombatSimulation.gd", "src/combat/BattleSession.gd", "src/combat/P10Stage.gd", "src/combat/Projectile.gd", "src/growth/GrowthEngine.gd", "src/roster/HumanAbilities.gd", "src/roster/GhostAbilities.gd", "src/camera/BattleCamera.gd"]:
		sources[path] = FileAccess.get_sha256("res://" + path)
	var report := {"engine":Engine.get_version_info().string, "display":DisplayServer.get_name(), "checks":results.size(), "failures":failures,
		"results":results, "screenshots":shots, "observations":observations, "source_sha256":sources, "reference":[13, 24, 25],
		"method":"Native viewport capture of normal combat with manual fixed-step fixtures. Real mouse confirmation for DianCe, shared commands for skills and fusion, authored AI stage behaviors for B01 and B02."}
	FileAccess.open(output.path_join("p11-vfx-results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	quit(1 if failures else 0)
