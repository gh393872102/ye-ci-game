extends Node
## Service rule fixtures are separate from watch, duel and archive playback evidence.
var checks := 0
var failures := 0
var results: Array[Dictionary] = []
var watches: Array[Dictionary] = []
var duels: Array[Dictionary] = []
var replays: Array[Dictionary] = []
var ferocity_trials: Array[Dictionary] = []
var shots: Array[String] = []
var capture := false
var host: Node
var scene: Node2D
var controller: RefCounted
var archive: Dictionary = {}

func _ready() -> void:
	load("res://src/replay/ReplayArchive.gd").directory = "/tmp/ye-ci-p6-replay-fixtures"
	capture = OS.get_cmdline_user_args().has("--capture")
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	results.append({"check":message,"passed":condition})
	if not condition: failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL",message])

func _run() -> void:
	if capture: get_window().size = Vector2i(1920,1080)
	check(Data.errors.is_empty(),"P6 boot validates source tables, night objectives and mode catalog")
	await _configuration_rules()
	await _dual_wallet_rules()
	await _canonical_command_rules()
	await _director_rules()
	await _ferocity_rules()
	await _watch_battle()
	await _duel_battles()
	await _replay_rules()
	await _ui_flow()
	_finish()

func _finish() -> void:
	var prefix := "p6"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report-prefix="): prefix = argument.trim_prefix("--report-prefix=")
	var report := {"phase":"P6","engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"capture":capture,"results":results,"watches":watches,"duels":duels,"replays":replays,"ferocity_trials":ferocity_trials,"screenshots":shots,"fixture_policy":"Isolated wallet, director and malformed-record fixtures may set actor positions or damaged structures. Actual watch, duel and battle replays use shared Simulation/Session with validated inputs and fixed steps; no direct HP, position, resource, rule or timer rewrites. Whole-night success is additionally verified by the same-tree P5 regression under p6-p5-regression prefix.","whole_night_replay":"S1 deferred; battle-level archive replay is required and tested."}
	FileAccess.open("res://docs/phase-reports/%s-%s-results.json" % [prefix,"render" if capture else "test"],FileAccess.WRITE).store_string(JSON.stringify(report,"\t") + "\n")
	for filename in DirAccess.get_files_at("/tmp/ye-ci-p6-replay-fixtures"):
		if filename.ends_with(".json"):
			DirAccess.remove_absolute("/tmp/ye-ci-p6-replay-fixtures/" + filename)
	print("P6 RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)

func _fresh_combat() -> Node2D:
	var value: Node2D = preload("res://scenes/combat/Combat.tscn").instantiate()
	add_child(value)
	value.get_node("Simulation").set_physics_process(false)
	Clock.set_paused(true)
	return value

func _configured(config: Dictionary) -> Dictionary:
	var value := _fresh_combat()
	var service: RefCounted = load("res://src/modes/ObservationSession.gd").new()
	var answer: Dictionary = service.start(value,config)
	return {"combat":value,"controller":service,"answer":answer}

func _unit(combat: Node2D, id: String) -> Node2D:
	for unit in combat.get_node("Simulation").humans + combat.get_node("Simulation").targets:
		if unit.unit_id == id and not unit.dead: return unit
	return null

func _dispose(value: Node2D) -> void:
	remove_child(value)
	value.queue_free()

func _shot(id: String, fixture := false) -> void:
	if not capture: return
	DirAccess.make_dir_recursive_absolute("res://docs/phase-reports/p6-shots")
	var layer: CanvasLayer
	if fixture:
		layer = CanvasLayer.new()
		layer.layer = 100
		var badge := Label.new()
		badge.text = "规则夹具 / 预置状态 / 非完整观祭"
		badge.position = Vector2(24,1044)
		badge.add_theme_font_size_override("font_size",21)
		layer.add_child(badge)
		add_child(layer)
	await get_tree().process_frame
	RenderingServer.force_draw(true)
	var path := "res://docs/phase-reports/p6-shots/%s.png" % id
	check(get_viewport().get_texture().get_image().save_png(path) == OK,"Actual renderer screenshot: " + id)
	shots.append(path)
	if layer != null: layer.queue_free()

func _all_text(node: Node) -> String:
	var text := ""
	if node is Label or node is BaseButton: text += str(node.text) + "\n"
	for child in node.get_children(): text += _all_text(child)
	return text

func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	get_viewport().push_input(event,true)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event,true)
	await get_tree().process_frame

func _button(button: BaseButton) -> void:
	await _click(button.get_global_rect().get_center())

func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _equivalent(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float): return absf(float(left) - float(right)) < 0.0001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for key in left:
			if not right.has(key) or not _equivalent(left[key],right[key]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index in left.size():
			if not _equivalent(left[index],right[index]): return false
		return true
	return left == right

func _config(seed := "P6-ACCEPTANCE") -> Dictionary:
	var value: Dictionary = Data.mode_rules.defaults.duplicate(true)
	value.seed = seed
	return value

func _configuration_rules() -> void:
	var config := _config("P6-CONFIG-FIXTURE")
	var valid := _configured(config)
	check(valid.answer.ok,"K3 Valid default watch starts on shared Combat scene")
	var original: Node2D = valid.combat
	check(original.get_node("Simulation").session == original.get_node("Session") and original.get_node("Session").mode == "shouxiang","K2 Watch uses shared simulator with fixed defensive result reference")
	check(original.get_node("BattleCamera").zoom == Vector2.ONE and Rules.REFERENCE_MAP_WIDTH_PX == 9600 and Rules.BODY_PX == 80,"K9 Observer retains G0 world length, camera scale and body height")
	for human in original.get_node("Simulation").humans:
		var row: Dictionary = Data.get_unit(human.unit_id)
		check(human.max_hp == float(row["生命"]) and human.attack == float(row["攻击"]) and human.defense == float(row["防御"]),"K2 Initial observer human values remain source CSV: " + human.unit_id)
	_dispose(original)
	var bads: Array[Dictionary] = []
	var bad := config.duplicate(true); bad.profile_id = "future_map"; bads.append(bad)
	bad = config.duplicate(true); bad.ritual = "unimplemented_ritual"; bads.append(bad)
	bad = config.duplicate(true); bad.ferocity = "stat_buff"; bads.append(bad)
	bad = config.duplicate(true); bad.duration = 30; bads.append(bad)
	bad = config.duplicate(true); bad.incense.shouxiang = -1; bads.append(bad)
	bad = config.duplicate(true); bad.names = 100; bads.append(bad)
	bad = config.duplicate(true); bad.humans[0].post = "court_center"; bads.append(bad)
	bad = config.duplicate(true); bad.ghosts = [{"id":"G99","count":1}]; bads.append(bad)
	bad = config.duplicate(true); bad.ghosts = [{"id":"G01","count":121}]; bads.append(bad)
	bad = config.duplicate(true)
	for human in bad.humans:
		if str(human.id).begins_with("H"): human.count = 2; break
	bads.append(bad)
	for index in bads.size():
		var value := _fresh_combat()
		var before: Dictionary = load("res://src/night/BattleSnapshot.gd").capture(value)
		var service: RefCounted = load("res://src/modes/ObservationSession.gd").new()
		var answer: Dictionary = service.start(value,bads[index])
		check(not answer.ok and not str(answer.reason).is_empty() and _equivalent(before,load("res://src/night/BattleSnapshot.gd").capture(value)),"K3 Invalid observation config is rejected before scene mutation: " + str(index))
		_dispose(value)
	var objectives_ok := true
	for node in Data.night_rules.nodes:
		if node.type not in ["battle","boss"]: continue
		objectives_ok = objectives_ok and load("res://src/modes/Seat.gd").valid_objectives(node.get("objectives",{})) and node.objectives.duoming.primary in ["register_capture","names_drained"] and node.objectives.duoming.primary != node.objectives.shouxiang.primary
	check(objectives_ok,"K1 Every actual night battle exposes attack-specific primary and secondary objectives")
	await get_tree().process_frame

func _dual_wallet_rules() -> void:
	var setup := _configured(_config("P6-WALLETS-FIXTURE"))
	var value: Node2D = setup.combat
	var sim: Node2D = value.get_node("Simulation")
	var session: Node = value.get_node("Session")
	check(session.incense_for("shouxiang") == 20 and session.incense_for("duoming") == 16,"Dual seats initialize independent incense balances from same currency")
	check(not session.purchase("T01").ok and not session.reinforce().ok,"Watch mode rejects raw player purchase and reinforcement")
	check(session.execute_for("shouxiang","purchase",{"id":"T01"},"ai").ok and session.incense_for("shouxiang") == 15 and session.incense_for("duoming") == 16,"AI defender purchase reserves only defender incense")
	var ghost := _unit(value,"G01")
	check(session.execute_for("duoming","mutate",{"unit_id":ghost.instance_id,"form_id":"G09"},"ai").ok and session.incense_for("duoming") == 4 and session.incense_for("shouxiang") == 15,"Interleaved attacker mutation charges only attacker balance")
	var count: int = sim.humans.size()
	check(not session.execute_for("shouxiang","deploy_at",{"post_id":"court_center"},"ai").ok and session.incense_for("shouxiang") == 15,"Illegal AI deployment keeps purchase reservation and resources")
	check(session.execute_for("shouxiang","deploy_at",{"post_id":"post_inner_gate"},"ai").ok and sim.humans.size() == count + 1 and session.incense_for("shouxiang") == 15,"Interleaved AI purchase completes once at legal cover without second charge")
	check(not session.execute_for("shouxiang","deploy_at",{"post_id":"post_inner_gate"},"ai").ok and sim.humans.size() == count + 1,"Repeated AI deploy confirmation cannot create an extra unit")
	check(session.execute_for("shouxiang","purchase",{"id":"T01"},"ai").ok and session.execute_for("shouxiang","cancel_purchase",{},"ai").ok and session.incense_for("shouxiang") == 15,"Cancel refunds the correct wallet after dual-seat interleaving")
	var human := _unit(value,"H09")
	check(not session.execute_for("duoming","upgrade",{"unit_id":human.instance_id},"ai").ok and not session.execute_for("duoming","repair",{"door_id":"door_outer"},"ai").ok and not session.execute_for("shouxiang","mutate",{"unit_id":ghost.instance_id,"form_id":"G12"},"ai").ok,"Dual dispatcher cannot issue wrong-seat commands")
	check(not session.execute_for("shouxiang","set_stats",{"hp":99999},"director").ok and not session.execute_for("shouxiang","enter_debug",{},"ai").ok,"Whitelisted dispatch rejects direct stat writes and debug takeover")
	_dispose(value)
	setup = _configured(_config("P6-RITUAL-WALLET-FIXTURE"))
	value = setup.combat
	sim = value.get_node("Simulation")
	session = value.get_node("Session")
	var caster := _unit(value,"H01")
	var target: Node2D = sim.tide.spawn("G01",0,caster.position.x - 100)
	target.motion_enabled = false
	target.attacks_enabled = false
	sim._update_units()
	check(session.execute_for("shouxiang","start_ritual",{"caster_id":caster.instance_id,"target_id":target.instance_id},"ai").ok and session.incense_for("shouxiang") == 16,"AI ritual pays four from defender wallet")
	ghost = _unit(value,"G01")
	check(session.execute_for("duoming","mutate",{"unit_id":ghost.instance_id,"form_id":"G12"},"ai").ok and session.incense_for("duoming") == 1,"Attacker can pay mutation during defender's asynchronous ritual")
	for step in 246: sim.advance(1.0/60)
	check(target.dead and absf(session.incense_for("shouxiang") - 19.492) < 0.01 and absf(session.incense_for("duoming") - 1.492) < 0.01 and session.names == 9,"Dual natural regen credits both wallets and ritual completion returns three only to defender")
	await _shot("08-dual-wallet-ritual-fixture",true)
	_dispose(value)
	await get_tree().process_frame

func _director_rules() -> void:
	var config := _config("P6-DIRECTOR-FIXTURE")
	config.director_enabled = true
	config.incense = {"shouxiang":40.0,"duoming":40.0}
	var setup := _configured(config)
	var value: Node2D = setup.combat
	var service: RefCounted = setup.controller
	var session: Node = value.get_node("Session")
	var before: int = service.director_used
	check(not service.director("repair",{"door_id":"door_outer"}).ok and service.director_used == before,"K8 Invalid full-health door repair does not consume director charge")
	check(not service.director("set_stats",{"hp":99999}).ok and service.director_used == before,"K8 Director cannot rewrite stats or bypass whitelist")
	check(service.director("reinforce",{}).ok and service.director_used == 1 and session.incense_for("duoming") == 30,"K8 Director reinforcement spends real attacker incense and one charge")
	value.get_node("ReferenceMap/door_inner").receive_damage(400) # Isolated damaged-door fixture.
	check(service.director("repair",{"door_id":"door_inner"}).ok and service.director_used == 2 and session.incense_for("shouxiang") == 34 and not session.repair_jobs.is_empty(),"K8 Director repair pays defender fee and creates actual worker job")
	Clock.set_paused(false)
	check(service.director("pause",{}).ok and service.director_used == 3 and Clock.paused,"K8 Director pause uses third successful charge")
	var shou: float = session.incense_for("shouxiang")
	var duo: float = session.incense_for("duoming")
	Clock.set_paused(false)
	check(not service.director("pause",{}).ok and service.director_used == 3 and not Clock.paused and session.incense_for("shouxiang") == shou and session.incense_for("duoming") == duo,"K8 Fourth otherwise-valid director command is denied without effect or resource change")
	_dispose(value)
	config.director_enabled = false
	setup = _configured(config)
	check(not setup.controller.director("pause",{}).ok and setup.controller.director_used == 0,"Disabled director has no administrative powers")
	_dispose(setup.combat)
	await get_tree().process_frame

func _initial_stats(value: Node2D) -> Array:
	var stats: Array = []
	for unit in value.get_node("Simulation").humans + value.get_node("Simulation").targets:
		stats.append([unit.unit_id,unit.hp,unit.max_hp,unit.attack,unit.defense,unit.speed_stat])
	return stats

func _brain_trace(service: RefCounted) -> Array:
	var trace: Array = []
	for action in service.recording.actions:
		if action.origin == "ai": trace.append(action.duplicate(true))
	return trace

func _ferocity_rules() -> void:
	var first_stats: Array = []
	var traces: Array = []
	for level in ["calm","fierce"]:
		var config := _config("P6-FEROCITY-SAME-SEED")
		config.ferocity = level
		var setup := _configured(config)
		check(setup.answer.ok,"K6 Configured AI ferocity starts: " + level)
		var value: Node2D = setup.combat
		var initial := _initial_stats(value)
		if first_stats.is_empty(): first_stats = initial
		else: check(initial == first_stats,"K6 Calm and fierce have identical initial source HP, attack, defense and speed")
		Clock.set_paused(false)
		for step in 3600: setup.controller.advance(1.0/60)
		var trace := _brain_trace(setup.controller)
		traces.append(trace)
		ferocity_trials.append({"level":level,"seed":config.seed,"initial_stats":initial,"actions":trace,"seconds":value.get_node("Simulation").simulation_time})
		_dispose(value)
	check(not traces[0].is_empty() and not traces[1].is_empty() and not _equivalent(traces[0],traces[1]),"K6 Same-seed calm and fierce change actual decision timing/preferences instead of initial stats")
	var config := _config("P6-FEROCITY-DIFFERENT-SEED")
	config.ferocity = "fierce"
	var setup := _configured(config)
	Clock.set_paused(false)
	for step in 3600: setup.controller.advance(1.0/60)
	check(not _equivalent(_brain_trace(setup.controller),traces[1]),"K7 A changed seed changes configured AI decision stream")
	_dispose(setup.combat)
	await get_tree().process_frame

func _run_observation(service: RefCounted, value: Node2D, seconds: float, shot_id := "") -> Dictionary:
	var sim: Node2D = value.get_node("Simulation")
	var session: Node = value.get_node("Session")
	var safe := true
	var cover := true
	var smooth := true
	var floors: Dictionary = {}
	var samples: Array[Dictionary] = []
	var next_sample := 0.0
	var captured := false
	Clock.set_paused(false)
	for step in ceili(seconds * 60):
		if not session.result.is_empty(): break
		var previous: Dictionary = {}
		for human in sim.humans: previous[human.instance_id] = human.position
		service.advance(1.0/60)
		for human in sim.humans:
			floors[str(human.floor_id)] = true
			safe = safe and sim.world.inside_base(human.position)
			if previous.has(human.instance_id): smooth = smooth and human.position.distance_to(previous[human.instance_id]) <= Rules.body_to_px(Rules.RETREAT_SPEED)/60 + 0.1
			if human.brain.route.is_empty() and not human.brain.excursion.active and human.brain.repair_door == null:
				cover = cover and load("res://src/ai/GuardPolicy.gd").can_stop(sim.world,human,human.position,human.floor_id)
		if sim.simulation_time >= next_sample:
			next_sample += 20
			samples.append({"seconds":sim.simulation_time,"humans":sim.humans.size(),"ghosts":sim.targets.size(),"wallet_shouxiang":session.incense_for("shouxiang"),"wallet_duoming":session.incense_for("duoming"),"names":session.names,"ai_actions":_brain_trace(service).size()})
		if capture and not captured and sim.simulation_time >= 120 and not shot_id.is_empty():
			captured = true
			value.get_node("BattleCamera").set_left(6080)
			await _shot(shot_id)
	return {"seconds":sim.simulation_time,"result":session.result.duplicate(true),"safe":safe,"cover":cover,"smooth":smooth,"floors":floors.keys(),"samples":samples,"actions":service.recording.actions.duplicate(true),"events":load("res://src/replay/BattleRecord.gd").key_events(value),"fingerprint":load("res://src/replay/BattleRecord.gd").fingerprint(value)}

func _watch_battle() -> void:
	var config := _config("P6-WATCH-ACTUAL-120S")
	config.profile_id = "upper"
	var setup := _configured(config)
	check(setup.answer.ok,"K3 Custom upper-pressure watch starts")
	var value: Node2D = setup.combat
	var service: RefCounted = setup.controller
	var evidence := await _run_observation(service,value,240,"03-watch-two-ai-120s")
	var defender := 0
	var attacker := 0
	for action in evidence.actions:
		if action.origin != "ai": continue
		if action.seat == "shouxiang": defender += 1
		if action.seat == "duoming": attacker += 1
	check(evidence.seconds >= 120 and defender >= 2 and attacker >= 1,"K4 Actual two-minute watch includes successful decisions from both paid AI seats")
	var defender_paid := false
	var attacker_paid := false
	for entry in value.get_node("Session").ledger:
		if float(entry.get("incense_delta",0)) >= 0: continue
		if entry.get("seat","") == "shouxiang": defender_paid = true
		if entry.get("seat","") == "duoming": attacker_paid = true
	check(defender_paid and attacker_paid,"K4 Both AI sides actually pay decision costs, beyond autonomous walking")
	check(evidence.safe and evidence.cover and evidence.smooth and evidence.floors.has("0") and evidence.floors.has("2"),"K5 Watch humans keep legal multi-floor base/cover behavior and continuous movement")
	check(not evidence.result.is_empty() and evidence.result.has("winner"),"Watch reaches common-rule result with a winning seat")
	evidence.config = config
	evidence.ai_counts = {"shouxiang":defender,"duoming":attacker}
	watches.append(evidence)
	_dispose(value)
	await get_tree().process_frame

func _duel_battles() -> void:
	for seat in ["shouxiang","duoming"]:
		var config := _config("P6-DUEL-ACTUAL-" + seat)
		config.kind = "duel"
		config.player_seat = seat
		config.director_enabled = true
		var setup := _configured(config)
		check(setup.answer.ok,"K3 Duel starts with player seat: " + seat)
		var value: Node2D = setup.combat
		var service: RefCounted = setup.controller
		var session: Node = value.get_node("Session")
		Clock.set_paused(true)
		var command: Dictionary
		if seat == "shouxiang":
			command = session.execute_for(seat,"purchase",{"id":"T04"},"player")
			check(command.ok and session.execute_for(seat,"deploy_at",{"post_id":"post_inner_gate"},"player").ok,"Duel guard player purchases and deploys through validated shared commands")
			command = session.execute_for(seat,"upgrade",{"unit_id":_unit(value,"H09").instance_id},"player")
		else:
			command = session.execute_for(seat,"mutate",{"unit_id":_unit(value,"G01").instance_id,"form_id":"G12"},"player")
		check(command.ok,"Duel player's actual paid command succeeds: " + seat)
		var opposite := "duoming" if seat == "shouxiang" else "shouxiang"
		var wrong_action := "reinforce" if opposite == "duoming" else "purchase"
		check(not session.execute_for(opposite,wrong_action,{"id":"T01"},"player").ok,"Duel player cannot issue commands for opposing AI seat")
		var director_added := false
		if seat == "shouxiang":
			var directed: Dictionary = service.director("reinforce",{})
			director_added = directed.ok
			check(directed.ok,"Recorded duel includes an actual paid director intervention")
		var evidence := await _run_observation(service,value,360,"04-duel-%s-120s" % seat)
		check(not evidence.result.is_empty() and evidence.actions.any(func(item): return item.origin == "player" and item.seat == seat),"K3 Duel %s records actual player input and settles" % seat)
		check(evidence.actions.any(func(item): return item.origin == "ai" and item.seat == opposite),"K3 Duel %s opposing seat makes actual AI decisions" % seat)
		check(evidence.safe and evidence.cover and evidence.smooth,"K5 Duel %s preserves human base, cover and movement rules" % seat)
		var saved: Dictionary = service.finish_recording()
		check(saved.ok,"K7 Actual duel is saved as local battle archive")
		if seat == "shouxiang":
			archive = saved.get("record",service.recording.finish()).duplicate(true)
			archive["_acceptance_archive_id"] = str(saved.get("archive_id",saved.get("id","")))
			evidence.director_added = director_added
		evidence.config = config
		evidence.archive_id = saved.get("archive_id",saved.get("id",""))
		duels.append(evidence)
		_dispose(value)
	await get_tree().process_frame

func _replay_rules() -> void:
	var storage = load("res://src/replay/ReplayArchive.gd")
	var record_api = load("res://src/replay/BattleRecord.gd")
	check(not archive.is_empty(),"K7 A real duel recording is available for playback")
	if archive.is_empty(): return
	var archive_id: String = archive.get("_acceptance_archive_id","")
	archive.erase("_acceptance_archive_id")
	var from_disk: Dictionary = storage.load_record(archive_id)
	check(from_disk.ok,"K7 Replay proof loads the actual persisted archive file, beyond an in-memory recording")
	if not from_disk.ok: return
	archive = from_disk.record.duplicate(true)
	check(storage.validate(archive).ok and archive.complete and not archive.actions.is_empty() and not archive.steps.is_empty(),"K7 Archive contains actual initial snapshot, successful inputs, exact steps and terminal state")
	check(archive.actions.any(func(item): return item.origin == "player") and archive.actions.any(func(item): return item.origin == "ai") and archive.actions.any(func(item): return item.origin == "director"),"K7 Archive includes actual player, AI and director inputs")
	check(not storage.list_seed(str(archive.metadata.seed)).is_empty() and storage.load_record(archive_id).ok,"K7 Seed lookup resolves the saved local battle rather than inventing past input")
	check(storage.list_seed("P6-MISSING-SEED-NO-ACTIONS").is_empty() and not storage.load_record("../outside-archive").ok,"K7 Missing seed and unsafe archive identifiers are explicitly unavailable")
	var export_prefix := "p6"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report-prefix="): export_prefix = argument.trim_prefix("--report-prefix=")
	check(storage.export_record(archive_id,"res://docs/phase-reports/%s-acceptance-battle-record.json" % export_prefix).ok,"Acceptance archive exports exact machine-readable replay record")
	var fingerprints: Array = []
	var event_hashes: Array[String] = []
	var command_hashes: Array[String] = []
	for iteration in 2:
		var value := _fresh_combat()
		var service: RefCounted = load("res://src/modes/ObservationSession.gd").new()
		check(service.start_replay(value,archive).ok,"K7 Saved-seed battle replay starts: " + str(iteration + 1))
		check(not value.get_node("Session").purchase("T01").ok and not value.get_node("Session").reinforce().ok,"S2 Replay rejects raw player mutations")
		Clock.set_paused(false)
		for step in archive.steps.size() + 120:
			if service.playback.done: break
			service.advance(1.0/60)
		var state: Dictionary = service.playback.status()
		check(state.done and state.verified and str(state.error).is_empty(),"K7 Replay %d validates exact event, input-count and terminal fingerprints" % (iteration + 1))
		var fingerprint: Dictionary = record_api.fingerprint(value)
		var events: Array = record_api.key_events(value)
		var fingerprint_hash: String = record_api.digest(fingerprint)
		var event_hash: String = record_api.digest(events)
		var command_hash: String = record_api.digest(service.playback.applied)
		check(fingerprint_hash == record_api.digest(archive.final) and event_hash == archive.event_hash and command_hash == record_api.digest(archive.actions),"K7 Replay %d reexecutes identical successful commands and actual combat" % (iteration + 1))
		fingerprints.append(fingerprint_hash)
		event_hashes.append(event_hash)
		command_hashes.append(command_hash)
		replays.append({"run":iteration + 1,"seed":archive.metadata.seed,"archive_id":archive_id,"status":state,"fingerprint_hash":fingerprint_hash,"event_hash":event_hash,"command_hash":command_hash,"fingerprint":fingerprint,"events":events,"applied":service.playback.applied.duplicate(true),"result":value.get_node("Session").result.duplicate(true)})
		await _shot("05-replay-%d-terminal" % (iteration + 1))
		_dispose(value)
	check(fingerprints[0] == fingerprints[1] and event_hashes[0] == event_hashes[1] and command_hashes[0] == command_hashes[1],"K7 Two independent replays of same local seed archive have identical commands, key events and final state")
	var bad: Dictionary = archive.duplicate(true)
	bad.engine = "incompatible-engine"
	check(not storage.validate(bad).ok,"K7 Incompatible engine archive is rejected")
	bad = archive.duplicate(true); bad.rules_hash = "changed-rules"
	check(not storage.validate(bad).ok,"K7 Changed rules archive is rejected")
	bad = archive.duplicate(true); bad.steps[0] = -1
	check(not storage.validate(bad).ok,"K7 Malformed negative simulation step is rejected")
	bad = archive.duplicate(true); bad.actions[0].action = "set_stats"
	check(not storage.validate(bad).ok,"K7 Archive cannot replay arbitrary stat-writing actions")

	bad = archive.duplicate(true); bad.steps[0] = "not-a-step"
	check(not storage.validate(bad).ok,"K7 Non-numeric step is rejected")
	bad = archive.duplicate(true); bad.duration = -1
	check(not storage.validate(bad).ok,"K7 Negative archive duration is rejected")
	bad = archive.duplicate(true); bad.director_used = 4
	check(not storage.validate(bad).ok,"K7 Forged director count beyond three is rejected")
	bad = archive.duplicate(true); bad.metadata.director_limit = 99
	check(not storage.validate(bad).ok,"K7 Archive cannot grant itself extra director powers")
	bad = archive.duplicate(true); bad.actions[0].step = -1
	check(not storage.validate(bad).ok,"K7 Negative command step index is rejected")
	bad = archive.duplicate(true); bad.actions[0].arguments.id = {"not":"a string"}
	check(not storage.validate(bad).ok,"K7 Command argument type corruption is rejected")

	bad = archive.duplicate(true); bad.initial_exact = Marshalls.raw_to_base64(var_to_bytes({"not":"the initial state"}))
	check(not storage.validate(bad).ok,"K7 Exact initial state must match readable mirror")
	bad = archive.duplicate(true); bad.steps_exact = Marshalls.raw_to_base64(var_to_bytes([0.03]))
	check(not storage.validate(bad).ok,"K7 Exact step stream length and values must match recorded step mirror")
	bad = archive.duplicate(true); bad.steps_exact = Marshalls.raw_to_base64(var_to_bytes({"not":"a step array"}))
	check(not storage.validate(bad).ok,"K7 Safe-decoded exact payload with wrong type is rejected")

	bad = archive.duplicate(true); bad.metadata.config = ["not a configuration dictionary"]
	check(not storage.validate(bad).ok,"K7 Malformed metadata configuration is rejected before UI playback")
	bad = archive.duplicate(true); bad.actions[0].origin = "director"; bad.director_used += 1
	check(not storage.validate(bad).ok,"K7 Forged director purchase is rejected even within the numeric director quota")
	bad = archive.duplicate(true); bad.initial.session.names += 1
	check(not storage.validate(bad).ok,"K7 Edited readable initial snapshot is rejected when exact state disagrees")
	bad = archive.duplicate(true); bad.steps[0] = 0.03
	check(not storage.validate(bad).ok,"K7 Edited readable step is rejected even when individually within legal delta range")
	bad = archive.duplicate(true); bad.key_events.append({"forged":true})
	check(not storage.validate(bad).ok,"K7 Corrupt key-event hash is rejected")
	var value := _fresh_combat()
	var before: Dictionary = load("res://src/night/BattleSnapshot.gd").capture(value)
	var service: RefCounted = load("res://src/modes/ObservationSession.gd").new()
	check(not service.start_replay(value,bad).ok and _equivalent(before,load("res://src/night/BattleSnapshot.gd").capture(value)),"Invalid replay is rejected before modifying current battle state")
	_dispose(value)
	await get_tree().process_frame

func _ui_flow() -> void:
	host = load("res://scenes/modes/Observatory.tscn").instantiate()
	add_child(host)
	host.set_physics_process(false)
	await get_tree().process_frame
	if capture: get_window().size = Vector2i(1920,1080)
	var panel: Control = host.panel
	check(panel.buttons.has("start_watch") and panel.buttons.has("start_duel_shouxiang") and panel.buttons.has("start_duel_duoming"),"K3 Actual Observatory offers watch and both duel seats")
	panel.seed_input.text = "P6-UI-CONFIG"
	panel.profile.select(1)
	panel.ferocity.select(2)
	panel.duration.value = 180
	panel.incense_shouxiang.value = 30
	panel.incense_duoming.value = 24
	panel.names.value = 9
	panel.director_enabled.button_pressed = true
	await _shot("01-observation-setup")
	if capture:
		get_window().size = Vector2i(1280,720)
		await _shot("01b-observation-setup-720p")
		get_window().size = Vector2i(1920,1080)
	await _button(panel.buttons.start_watch)
	check(is_instance_valid(host.combat) and host.controller.config.kind == "watch" and host.controller.config.profile_id == "upper" and host.controller.config.ferocity == "fierce" and host.controller.config.duration == 180,"K3 Real setup button starts selected profile, AI behavior and duration")
	check(host.combat.get_node("Session").incense_for("shouxiang") == 30 and host.combat.get_node("Session").incense_for("duoming") == 24 and host.combat.get_node("Session").names == 9,"K3 Real setup applies both resource balances and names")
	Clock.set_paused(false)
	var combat: Node2D = host.combat
	var human := _unit(combat,"H17")
	combat.get_node("BattleCamera").set_left(6080)
	await _click(get_viewport().get_canvas_transform() * (human.position - Vector2(0,40)))
	var inspector: CanvasLayer = combat.get_node("Decisions")
	check(Clock.paused and inspector.selected == human,"S2 Watch click opens existing unit inspector and pauses")
	var text: String = inspector.details.text
	check(text.contains(human.display_name) and text.contains("攻击") and text.contains("防御") and text.contains("速度") and text.contains("特性") and text.contains("香器") and text.contains("技艺") and text.contains("名帖") and inspector.portrait.texture != null,"S2 Watch inspector retains complete data, empty slots and independent portrait")
	var before: Dictionary = load("res://src/replay/BattleRecord.gd").fingerprint(combat)
	for key in [KEY_Q,KEY_E,KEY_R,KEY_F]: await _key(key)
	check(_equivalent(before,load("res://src/replay/BattleRecord.gd").fingerprint(combat)),"S2 Watch keyboard commands cannot mutate inspected battle")
	check(not inspector.buttons.has("card_upgrade") or not is_instance_valid(inspector.buttons.card_upgrade) or not inspector.buttons.card_upgrade.visible,"S2 Watch card exposes no paid gameplay action buttons")
	await _shot("02-readonly-full-unit-card")
	if capture:
		get_window().size = Vector2i(1280,720)
		await _shot("02b-readonly-unit-card-720p")
		get_window().size = Vector2i(1920,1080)
	inspector.close_panel()
	host.return_setup()
	await get_tree().process_frame
	for seat in ["shouxiang","duoming"]:
		await _button(panel.buttons["start_duel_" + seat])
		check(is_instance_valid(host.combat) and host.combat.get_node("Session").player_seat == seat,"K3 Real Observatory button selects player duel seat: " + seat)
		host.return_setup()
		await get_tree().process_frame
	panel.replay_seed.text = str(archive.metadata.seed)
	await _button(panel.buttons.find_replays)
	var replay_id: String = replays[0].archive_id
	check(panel.buttons.has("replay_" + replay_id),"K7 Real seed lookup lists recorded local battle")
	await _shot("06-local-seed-records")
	await _button(panel.buttons["replay_" + replay_id])
	check(host.is_replay and host.controller.playback != null,"K7 Actual replay selection starts recorded battle playback")
	Clock.set_paused(false)
	combat = host.combat
	human = _unit(combat,"H17")
	combat.get_node("BattleCamera").set_left(6080)
	await _click(get_viewport().get_canvas_transform() * (human.position - Vector2(0,40)))
	check(combat.get_node("Decisions").selected == human and Clock.paused,"S2 Replay retains read-only full unit inspection")
	before = load("res://src/replay/BattleRecord.gd").fingerprint(combat)
	for key in [KEY_Q,KEY_E,KEY_R,KEY_F]: await _key(key)
	check(_equivalent(before,load("res://src/replay/BattleRecord.gd").fingerprint(combat)) and not host.controller.director("reinforce",{}).ok,"S2 Replay blocks gameplay hotkeys and director intervention")
	await _shot("07-replay-readonly-inspection")
	remove_child(host)
	host.queue_free()
	host = null
	await get_tree().process_frame

func _canonical_command_rules() -> void:
	var setup := _configured(_config("P6-CANONICAL-SIGNAL-FIXTURE"))
	var value: Node2D = setup.combat
	var session: Node = value.get_node("Session")
	var emitted: Array[Dictionary] = []
	session.command_applied.connect(func(seat: String, action: String, args: Dictionary, origin: String): emitted.append({"seat":seat,"action":action,"arguments":args.duplicate(true),"origin":origin}))
	var query: Dictionary = session.execute_for("shouxiang","purchase_options",{},"ai")
	check(query.ok and query.data is Array and emitted.is_empty(),"AI previews use dictionary envelope without recording a mutation")
	check(not session.execute_for("shouxiang","purchase",{"id":"unknown"},"ai").ok and emitted.is_empty(),"Rejected commands emit no canonical replay action")
	check(session.execute_for("shouxiang","purchase",{"id":"T01"},"ai").ok and emitted.size() == 1 and emitted[0].seat == "shouxiang" and emitted[0].action == "purchase" and emitted[0].arguments == {"id":"T01"} and emitted[0].origin == "ai","Successful external mutation emits exactly one canonical seat/action/arguments/origin event")
	var before: int = emitted.size()
	session._finish("victory","P6_FIXTURE_FINISH")
	check(emitted.size() == before and session.incense_for("shouxiang") == 20 and session.pending_purchase.is_empty(),"Internal settlement refund restores defender wallet without emitting replayable cancellation")
	_dispose(value)
	var config := _config("P6-INPUT-LOCK-FIXTURE")
	config.kind = "duel"
	config.player_seat = "duoming"
	setup = _configured(config)
	value = setup.combat
	session = value.get_node("Session")
	var ghost := _unit(value,"G01")
	query = session.execute_for("duoming","preview_mutation",{"unit_id":ghost.instance_id,"form_id":"G12"},"player")
	check(query.ok and query.data.allowed,"Controlled attacker receives actual mutation preview under its own wallet")
	session.input_locked = true
	check(not session.reinforce().ok and not session.execute_for("duoming","reinforce",{},"player").ok,"Replay-style input lock blocks raw and wrapped player commands")
	check(session.execute_for("duoming","mutate",{"unit_id":ghost.instance_id,"form_id":"G09"},"replay").ok,"Input lock permits only trusted replay transport to reexecute valid recorded command")
	var funds: float = session.incense_for("duoming")
	check(not session.configure_dual({"shouxiang":-1,"duoming":16},"").ok and session.incense_for("duoming") == funds,"Invalid dual reconfiguration rejects before touching existing wallets")
	_dispose(value)
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/modes/p6_modes.json"))
	rules.ai_levels.fierce.attack = 999
	var path := "/tmp/ye-ci-p6-illegal-ai-stats.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(rules))
	var loaded: Dictionary = load("res://src/data/ModeCatalog.gd").read_config(path,Data.combat_profiles)
	check(not loaded.errors.is_empty(),"K6 Mode catalog rejects AI ferocity fields that try to modify unit attack")
	DirAccess.remove_absolute(path)
	await get_tree().process_frame
