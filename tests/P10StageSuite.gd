extends SceneTree
## Run with tools/p9_verify.py --native --script tests/P10StageSuite.gd.
const STEP := 1.0 / 60.0
const NIGHT_SEED := "验收夜·门裂梁鸣"

var stages: Script
var run_script: Script
var bridge_script: Script
var combat_scene: PackedScene
var snapshot: Script
var output: String
var clock: Node
var data: Node
var combat: Node2D
var simulation: Node2D
var session: Node
var stage: Node2D
var hud: Control
var bridge: RefCounted
var results: Array[Dictionary] = []
var shots: Dictionary = {}
var observations: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else ""
	clock = root.get_node("Clock")
	data = root.get_node("Data")
	var isolated: bool = output.begins_with("/private/tmp/ye-ci-p9-") and data.codex_store.path == output.path_join("state/codex.json")
	if not _check(isolated, "Probe uses the disposable profile before loading any scene"):
		quit(2)
		return
	if not _check(data.errors.is_empty(), "Actual Boot catalogs validate"):
		_finish()
		return
	stages = load("res://src/data/StageOptions.gd")
	run_script = load("res://src/night/NightRun.gd")
	bridge_script = load("res://src/night/NightBattleBridge.gd")
	combat_scene = load("res://scenes/combat/Combat.tscn")
	snapshot = load("res://src/night/BattleSnapshot.gd")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1920, 1080)
	_check(stages.bosses().size() == 3 and stages.modifiers().size() == 3, "Read three authored stage files and three modifier rows")
	_check(not stages.valid("B04", []) and not stages.valid("", ["N01", "N01"]) and not stages.valid("", ["N04"]), "Reject unknown boss and unknown or duplicate modifiers")
	await _acceptance_night()
	await _naming_stage()
	await _modifiers()
	_finish()

func _check(ok: bool, label: String) -> bool:
	results.append({"ok": ok, "label": label})
	print(("PASS " if ok else "FAIL ") + label)
	return ok

func _acceptance_night() -> void:
	var night: RefCounted = run_script.new()
	if not _check(night.new_p10_run("shouxiang", "example", NIGHT_SEED, "R01", []).ok, "Begin one P10 R01 acceptance night"):
		return
	# Shortened two early battles with authored starting guards. The NightRun, bridge,
	# paid commands, carry, encounters, damage, settlement and transfers are the normal paths.
	for node in night.config.nodes:
		if node.id in ["n01", "n03"]:
			node.boss_id = "B01" if node.id == "n01" else "B02"
			node.chunk_ids = stages.required_chunks(node.boss_id, [])
			night.config.battle_profiles[node.profile_id].duration = 17.0 if node.id == "n01" else 89.0
	night.state.roster.clear()
	for entry in [["H09", "post_hall_door"], ["T01", "post_table_hall"], ["H03", "post_register"], ["H01", "post_register"]]:
		night.state.roster.append(night._unit(entry[0], entry[1]))
	if not _check(night.choose_node("n01").ok and _enter_night_battle(night), "First live combat opens B01 from the NightRun"):
		return
	var gate: Node2D = simulation.world.get_node("door_hall")
	var iron := _actor("H09")
	var interior: Node2D = session._actor(stage.state.boss_actor)
	_check(gate.durability / gate.max_durability <= 0.13 and gate.durability > 0 and not gate.is_open, "B01 starts with a real cracked but closed hall door")
	_check(interior != null and interior.unit_id == "G12" and simulation.world.room_at(interior.position, interior.floor_id) == "hall", "B01 starts a real G12 in the hall")
	await _shot("01-b01-opening")
	var guard_set := _until(8.0, func():
		if iron == null or iron.dead or simulation.simulation_time < 4.5:
			return false
		return iron.roster.statuses.has("gate_guard") or session.roster_command("unit_skill", {"unit_id": iron.instance_id}).ok
	)
	_check(guard_set, "B01 pays for Iron Shoulder while an actual rammer approaches the critical door")
	var raw_ram_damage: float = float(data.get_unit("G12")["攻击"]) * float(data.skills.zhuang_men.structure_multiplier)
	var guarded := _until(10.0, func():
		return _has_effect("guard") and simulation.damage_log.any(func(hit):
			return str(hit.attacker).begins_with("G12_") and hit.target == "door_hall" and hit.before == hit.after
		)
	)
	_check(guarded and not gate.destroyed and raw_ram_damage > gate.durability, "Iron Shoulder intercepts a real ram strike that would otherwise break the door")
	if guarded:
		await _shot("02-k8-iron-shoulder")
	var broken := _until(20.0, func(): return _has_effect("break"))
	_check(broken and gate.destroyed and gate.is_open, "B01 shared structure damage breaks the door after the defense")
	if broken:
		_steps(15)
		await _shot("03-k8-gate-fragments")
	var flood := _until(24.0, func(): return bool(stage.state.gate_flooded))
	_check(flood and _has_event("p10_tide_flood"), "At least two real tide units cross the opened hall door")
	if flood:
		await _shot("04-k8-tide-through-gate")
	observations.b01 = {"boss": interior.unit_id if is_instance_valid(interior) else "G12", "first_breach": session.first_breach.duplicate(), "events": _reading_events(["roster_gate_transferred", "p10_tide_flood"]), "milestones": _milestones(["door_break"]),
		"critical_door_at_start": gate.max_durability * float(stages.bosses().B01.initial_doors.door_hall), "ram_damage": raw_ram_damage}
	_until(18.0, func(): return not session.running)
	var first: Dictionary = bridge.collect(combat, night)
	if not _check(first.outcome == "victory" and night.accept_battle(first).ok and night.state.phase == "reward", "First battle settles through the real NightRun into its three-choice reward"):
		return
	var rewarded := false
	for option in night.reward_options():
		if not bool(option.get("allowed", true)):
			continue
		if night.choose_reward(str(option.id)).ok:
			rewarded = true
			break
	if not _check(rewarded and night.choose_node("n02").ok and night.leave_node().ok and night.choose_node("n03").ok, "The same seeded night accepts one reward and continues through its market"):
		return
	if not _check(_enter_night_battle(night), "The same NightRun opens real B02 with the carried roster"):
		return
	if session.purchase("T01").ok:
		session.deploy_at("post_register")
	var upper_arrival := _until(12.0, func(): return _has_effect("upper"))
	_check(upper_arrival and _milestones(["upper_entry"]).size() > 0, "The B02 G09 reaches the gallery by advancing the actual climb route")
	if upper_arrival:
		await _shot("05-k8-rope-pounce")
	var before_loss: float = session.names
	var upper_lost := _until(25.0, func(): return bool(stage.state.upper_lost))
	_check(upper_lost and session.names < before_loss and _has_event("p10_upper_lost"), "Leaving the gallery unstaffed activates the B02 failure line and drains actual register names")
	if upper_lost:
		await _shot("06-b02-upper-line-lost")
		if session.purchase("T01").ok:
			session.deploy_at("post_stair_head")
	var reader := _actor("H01")
	var landing: Node2D
	while session.running and simulation.simulation_time < 60.0 and landing == null and is_instance_valid(reader) and not reader.dead:
		for ghost in simulation.targets:
			if ghost.unit_id == "G09" and ghost.brain.stage == "rear" and session.preview_ritual(reader, ghost).reason.is_empty():
				landing = ghost
				break
		if landing == null:
			simulation.advance(STEP)
	var started: bool = landing != null and session.start_ritual(reader, landing).ok
	_check(started, "The attacking climber lands on the ground route, and a protected indoor reader starts a paid ritual")
	var reading_start: float = session.names
	var before_credit := reading_start
	var deadline: float = simulation.simulation_time + 6.0
	while started and session.running and simulation.simulation_time < deadline and not _has_effect("rekindle"):
		before_credit = session.names
		simulation.advance(STEP)
	var reading_ledger: Array = session.ledger.filter(func(row): return row.action == "ritual_completed")
	var sent := _has_effect("rekindle") and not reading_ledger.is_empty()
	_check(sent and float(reading_ledger.back().names_delta) > 0.0 and session.names > before_credit and _milestones(["purified"]).size() > 0, "The same B02 combat purifies a real elite and visibly raises names on the completion step")
	if sent:
		_pan_to_register()
		await _shot("07-k8-send-off-register-relit")
	observations.b02 = {"events": _reading_events(["p10_upper_lost", "channel_complete"]), "milestones": _milestones(["upper_entry", "landed", "purified"]), "names_at_reading_start": reading_start,
		"names_before_completion": before_credit, "names_after_completion": session.names, "reading_credit": reading_ledger,
		"reader_status": reader.brain.channel.last_result if is_instance_valid(reader) else "fallen"}
	observations.acceptance_night = {"seed": night.state.seed, "visited": night.state.visited.duplicate(), "profile": "R01", "first_outcome": first.outcome, "carried_human_count": night.state.roster.size(), "scope": "Two real combats in one NightRun with legal starting roster and shortened timers. The second probe ends after the target effects."}

func _naming_stage() -> void:
	if not _check(_standalone("B03", [], "p10-listed", [["H09", "post_register"], ["H01", "post_register"], ["H31", "post_register"]]), "B03 loads its actual chunk composition and stage"):
		return
	_pan_to_register()
	var boss: Node2D = session._actor(stage.state.boss_actor)
	var reader := _actor("H01")
	if not _check(boss != null and boss.unit_id == "G32" and boss.max_hp == float(data.get_unit("G32")["生命"]), "B03 spawns G32 with source health and the authored roster ability"):
		return
	await _shot("08-b03-ink-at-the-register")
	var naming_threshold: float = float(session.roster.params(boss).naming_names)
	var starting_names: float = session.names
	var began: bool = session.start_ritual(reader, boss).ok
	_check(began, "Protected B03 reader can start a paid reading at the register")
	var window := began and _until(7.0, func(): return _has_effect("window") or not reader.brain.channel.active)
	window = window and _has_effect("window")
	_check(window and float(boss.roster.ghost.get("naming_left", 0.0)) > 0 and not boss.dead and session.codex.entry("G32").stage == 3, "High names and protected reading open G32's genuine naming window")
	if window:
		await _shot("09-b03-naming-window")
	var again: bool = window and session.start_ritual(reader, boss).ok
	var listed := again and _until(13.0, func(): return _has_effect("listed"))
	_check(listed and bool(stage.state.boss_listed) and session.codex.entry("G32").stage == 3, "Second protected reading actually writes G32 back to the register")
	if listed:
		await _shot("10-b03-returned-to-register")
	observations.b03 = {"events": _reading_events(["channel_complete", "roster_naming_window"]), "milestones": _milestones(["purified"]),
		"naming_threshold": naming_threshold, "starting_names": starting_names,
		"reader_status": reader.brain.channel.last_result, "reader_position_x": reader.position.x,
		"boss_position_x": boss.position.x if is_instance_valid(boss) else 0.0, "boss_hp": boss.hp if is_instance_valid(boss) else 0.0,
		"codex_stage": session.codex.entry("G32").stage}
	if not window and is_instance_valid(boss) and is_instance_valid(reader):
		print("B03 channel stop ", reader.brain.channel.last_result, " at ", simulation.simulation_time,
			": target reason ", reader.brain.channel.target_reason(simulation, reader, boss), ", remaining HP ", boss.hp,
			", positions ", reader.position, " / ", boss.position)

func _modifiers() -> void:
	var active := ["N01", "N02", "N03"]
	var seed_text := "p10-stack"
	if not _check(_standalone("", active, seed_text, [["H01", "post_register"]]), "All three modifiers can coexist on the same live battle"):
		return
	session.names = 8.0
	var door: Node2D = simulation.world.get_node("door_side")
	var warm_names: float = session.names
	_check(is_equal_approx(door.durability / door.max_durability, float(stages.modifiers().N02.side_durability_ratio)) and not door.is_open and stages.chunk_weights(active).C02 > 1.0, "C02 is required and weighted; its real side door is already cracked but closed")
	_steps(240)
	var ink_loss: float = warm_names - session.names
	_check(absf(ink_loss - 4.0 * float(stages.modifiers().N01.drain_per_second)) < 0.001, "Ink drains the live register against a quiet no-contact control")
	var healer: Node2D = simulation.spawn_human("H02", "post_rear")
	var before_heal: float = session.names
	var restored: bool = session.roster_command("unit_skill", {"unit_id": healer.instance_id}).ok
	var credited: float = session.names - before_heal
	var base: float = float(session.roster.params(healer).names_restore)
	_check(restored and absf(credited - base * float(stages.modifiers().N01.recovery_multiplier)) < 0.001, "Paid H02 recovery uses the real reduced restoration factor")
	var modifiers_text: String = stage.modifiers_text()
	_check(["名册渗墨", "侧门先裂", "超度被盯"].all(func(label): return modifiers_text.contains(label)), "HUD explicitly lists all stacked modifiers")
	await _shot("11-all-three-modifiers")
	var saved: Dictionary = snapshot.capture(combat)
	var exact_stage: Dictionary = stages.capture(session)
	var safe: Dictionary = JSON.parse_string(JSON.stringify(exact_stage))
	_check(stages.valid_snapshot(safe), "Stage snapshot survives ordinary JSON numeric decoding")
	var checksum := JSON.stringify(exact_stage, "", true)
	var recovered: Dictionary = snapshot.restore(combat, saved)
	stage = stages.get_stage(session)
	_check(recovered.ok and stage != null and JSON.stringify(stages.capture(session), "", true) == checksum, "Battle snapshot restores stage, timers, active modifiers and actual door state")
	var reader := _actor("H01")
	var marked := _spawn_fixture("G12", 111.6)
	var watcher := _spawn_fixture("G26", 114.3)
	var began: bool = session.start_ritual(reader, marked).ok
	var watched: bool = watcher.roster.statuses.has("blank_field") and _has_event("p10_reader_watched")
	_check(began and watched, "A seeded N03 paid read causes the nearby actual G26 to cast its blank field on the reader")
	if watched:
		_pan_to_register()
		await _shot("12-watched-reader")
	observations.modifiers = {"active": active, "starting_side_durability": door.durability, "side_max_durability": door.max_durability, "silent_ink_loss_4s": ink_loss, "normal_restore": base, "actual_restore": credited, "watch_events": _reading_events(["p10_reader_watched", "roster_blank_page"])}
	session.enter_debug()
	_check(stages.get_stage(session) == null and is_equal_approx(session.rekindle_multiplier(), 1.0), "Leaving live combat clears the stage overlay and rebases recovery before a new match")

func _enter_night_battle(night: RefCounted) -> bool:
	if not _new_combat(night.current_node().chunk_ids):
		return false
	bridge = bridge_script.new()
	var result: Dictionary = bridge.start(combat, night)
	stage = stages.get_stage(session)
	clock.set_paused(true)
	if not result.ok:
		print("Bridge rejected ", night.current_node().id, " with ", result.reason)
	return result.ok and stage != null

func _standalone(boss_id: String, modifiers: Array, seed_text: String, roster: Array) -> bool:
	var ids: Array[String] = stages.required_chunks(boss_id, modifiers)
	for required in ["C01", "C03", "C04"]:
		if required not in ids:
			ids.append(required)
	if not _new_combat(ids) or not session.start_battle("shouxiang").ok:
		return false
	for actor in simulation.humans:
		actor.free()
	simulation.humans.clear()
	simulation.clear_targets()
	simulation.tide.pending.clear()
	simulation.tide.config.waves.clear()
	session.configure_roster(seed_text)
	session.incense = 32.0
	session.names = 12.0
	for entry in roster:
		var human: Node2D = simulation.spawn_human(entry[0], entry[1])
		if human == null:
			return false
		human.position = simulation.post_destination(human, str(entry[1]))
		human.brain.settled_position = human.position
	simulation._update_units()
	if not stages.start(session, boss_id, modifiers, seed_text):
		return false
	stage = stages.get_stage(session)
	return stage != null

func _new_combat(ids: Array) -> bool:
	if bridge != null and bridge.recording != null:
		bridge.recording.stop()
	bridge = null
	if is_instance_valid(combat):
		combat.free()
	combat = combat_scene.instantiate()
	if not combat.configure_chunks(ids):
		combat.free()
		combat = null
		return false
	root.add_child(combat)
	combat.get_node("BattleCamera").make_current()
	simulation = combat.get_node("Simulation")
	simulation.set_physics_process(false)
	session = combat.get_node("Session")
	hud = combat.get_node("CanvasLayer/HUD")
	var decisions: Node = combat.get_node("Decisions")
	decisions.managed_by_night = true
	decisions.prebattle.hide()
	clock.set_paused(true)
	return true

func _actor(id: String) -> Node2D:
	for unit in simulation.humans:
		if not unit.dead and unit.unit_id == id:
			return unit
	return null

func _spawn_fixture(id: String, x: float) -> Node2D:
	return simulation.tide.spawn(id, 2, root.get_node("Rules").body_to_px(x))

func _has_effect(kind: String) -> bool:
	return stage.state.effects.any(func(effect): return effect.kind == kind)

func _has_event(kind: String) -> bool:
	return simulation.events.any(func(event): return event.kind == kind)

func _reading_events(kinds: Array) -> Array:
	return simulation.events.filter(func(event): return event.kind in kinds).duplicate(true)

func _milestones(kinds: Array) -> Array:
	return simulation.tide.milestones.filter(func(event): return event.kind in kinds).duplicate(true)

func _until(time_limit: float, predicate: Callable) -> bool:
	while session.running and simulation.simulation_time < time_limit:
		if predicate.call():
			return true
		simulation.advance(STEP)
	return predicate.call()

func _steps(count: int) -> void:
	for _index in count:
		simulation.advance(STEP)

func _pan_to_register() -> void:
	combat.get_node("BattleCamera").set_left(root.get_node("Rules").body_to_px(96.0))

func _shot(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	RenderingServer.force_draw(true)
	var image := root.get_texture().get_image()
	var path := output.path_join(id + ".png")
	if _check(image != null and not image.is_empty() and image.save_png(path) == OK, "Native frame written for " + id):
		var camera: Camera2D = combat.get_node("BattleCamera")
		shots[id] = {"file":path.get_file(),"sha256":FileAccess.get_sha256(path),
			"width":image.get_width(),"height":image.get_height(),"time":simulation.simulation_time,
			"camera_left":camera.left(),"camera_zoom":camera.zoom.x,
			"hud_title":hud.stage_title.text,"hud_pressure":hud.stage_pressure.text,
			"hud_modifiers":hud.stage_modifiers.text,"hud_event":hud.stage_event.text}
		_check(camera.zoom.is_equal_approx(Vector2.ONE), "Actual camera remains unit scale at " + id)

func _finish() -> void:
	var count := results.filter(func(item): return not item.ok).size()
	var sources := {}
	for path in ["src/combat/P10Stage.gd", "src/data/StageOptions.gd", "src/ui/CombatHUD.gd", "data/levels/bosses/B01.json",
		"data/levels/bosses/B02.json", "data/levels/bosses/B03.json", "data/rituals/nameless_modifiers.csv", "tests/P10StageSuite.gd"]:
		sources[path] = FileAccess.get_sha256("res://" + path)
	var file := FileAccess.open(output.path_join("p10-stage-results.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,
			"display":DisplayServer.get_name(),"checks":results.size(),"failures":count,
			"results":results,"observations":observations,"screenshots":shots,
			"source_sha256":sources}, "\t") + "\n")
	quit(1 if count else 0)
