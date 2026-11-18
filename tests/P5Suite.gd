extends Node
## Acceptance fixtures are kept separate from complete nights. Complete nights only call actual NightRun / BattleSession decisions.
var checks := 0
var failures := 0
var results: Array[Dictionary] = []
var nights: Array[Dictionary] = []
var captures: Array[String] = []
var snapshot_evidence: Dictionary = {}
var night_replay_evidence: Array[Dictionary] = []
var capture := false
var host: Node
var combat: Node2D
var sim: Node2D
var session: Node
var camera: Camera2D
var run: RefCounted
var bridge: RefCounted
var choices: Array[Dictionary] = []

func _ready() -> void:
	# P6 replay regression must never write the player's real archive directory.
	load("res://src/replay/ReplayArchive.gd").directory = "/tmp/ye-ci-p6-p5-replay-fixtures"
	capture = OS.get_cmdline_user_args().has("--capture")
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	results.append({"check":message,"passed":condition})
	if not condition:
		failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL",message])

func _run() -> void:
	check(Data.errors.is_empty(),"P5 boot validates existing source tables and new night catalog")
	await _domain_fixtures()
	await _snapshot_roundtrip()
	await _queued_and_fallen_rules()
	await _crowded_home_posts()
	await _ui_flow()
	if OS.get_cmdline_user_args().has("--fixtures-only"):
		_finish()
		return
	await _complete_night("shouxiang")
	await _complete_night("duoming")
	_finish()

func _finish() -> void:
	var report_prefix := "p5"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report-prefix="):
			report_prefix = argument.trim_prefix("--report-prefix=")
	var report := {"phase":"P5","engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"capture":capture,"results":results,"nights":nights,"snapshot_evidence":snapshot_evidence,"night_replay_evidence":night_replay_evidence,"screenshots":captures,"fixture_policy":"Rule/save fixtures may alter isolated run state and battle positions. Complete example nights use actual NightRun and shared BattleSession commands, source waves and fixed simulation steps; no direct HP, position, structures, resources, rules or timer edits."}
	FileAccess.open("res://docs/phase-reports/%s-%s-results.json" % [report_prefix,"render" if capture else "test"],FileAccess.WRITE).store_string(JSON.stringify(report,"\t") + "\n")
	for filename in DirAccess.get_files_at("/tmp/ye-ci-p6-p5-replay-fixtures"):
		if filename.ends_with(".json"):
			DirAccess.remove_absolute("/tmp/ye-ci-p6-p5-replay-fixtures/" + filename)
	print("P5 RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)

func _shot(id: String, fixture := false) -> void:
	if not capture:
		return
	DirAccess.make_dir_recursive_absolute("res://docs/phase-reports/p5-shots")
	var layer: CanvasLayer
	if fixture:
		layer = CanvasLayer.new()
		layer.layer = 100
		var label := Label.new()
		label.text = "规则夹具 / 预置状态 / 非完整夜程"
		label.position = Vector2(24,1044)
		label.add_theme_font_size_override("font_size",22)
		layer.add_child(label)
		add_child(layer)
	await get_tree().process_frame
	RenderingServer.force_draw(true)
	var path := "res://docs/phase-reports/p5-shots/%s.png" % id
	check(get_viewport().get_texture().get_image().save_png(path) == OK,"Actual renderer screenshot: " + id)
	captures.append(path)
	if layer != null:
		layer.queue_free()

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

func _all_text(node: Node) -> String:
	var text := ""
	if node is Label or node is BaseButton:
		text += str(node.text) + "\n"
	for child in node.get_children():
		text += _all_text(child)
	return text

func _new_run(mode := "shouxiang", seed_text := "P5-ACCEPTANCE-01") -> RefCounted:
	var value: RefCounted = load("res://src/night/NightRun.gd").new()
	var result: Dictionary = value.new_run(mode,"example",seed_text)
	check(result.ok,"NightRun creates deterministic example seat: " + mode)
	return value

func _first_target(value: RefCounted, offer: Dictionary) -> String:
	if not offer.get("requires_target",false):
		return ""
	var options: Array = value.target_options(str(offer.id))
	if options.is_empty():
		return ""
	return str(options[0].get("uid", "")) if options[0] is Dictionary else str(options[0])

func _fixture_summary(value: RefCounted, outcome := "victory") -> Dictionary:
	return {"outcome":outcome,"reason":"fixture_victory" if outcome == "victory" else "P4_END_REGISTER_EXTINGUISHED","incense":7.5,"names":2.25,"roster":value.state.roster.duplicate(true),"fallen":[],"elapsed":180.0,"encountered":["G01","G09","G12"],"first_breach":{"door":"door_outer","time":120.0}}

func _choose_fixture_reward(value: RefCounted) -> Dictionary:
	var offers: Array = value.reward_options()
	for offer in offers:
		if offer.get("allowed",true):
			var target := _first_target(value,offer)
			if not offer.get("requires_target",false) or not target.is_empty():
				return value.choose_reward(str(offer.id),target)
	return {"ok":false,"reason":"No applicable fixture reward"}

func _domain_fixtures() -> void:
	var value := _new_run()
	check(value.state.phase == "map" and value.state.ritual == "example_incense" and value.state.mode == "shouxiang","K7 Example starts on map with the only implemented ritual")
	check(value.state.incense == 20 and value.state.names == 8,"Night starts with correct two resources")
	check(value.state.roster.size() == 5 and value.state.roster[0].id == "H01","K7 Guard example starts with Wan and declared night-watch support")
	check(not value.choose_node("n10").ok and value.state.phase == "map","Unreachable boss cannot be selected early")
	check(not value.choose_reward("missing").ok and not value.buy_offer("missing").ok and not value.resolve_event("missing").ok and not value.finish_rest().ok,"Wrong-phase actions are rejected without advancing night")
	var choices_before: Array = value.available_nodes()
	check(choices_before.size() == 1 and choices_before[0].id == "n01","K1 Initial map exposes the opening battle only")
	check(value.choose_node("n01").ok and value.state.phase == "battle","K1 Choosing reachable node enters actual battle phase")
	var state_before := JSON.stringify(value.state)
	check(not value.choose_node("n02").ok and JSON.stringify(value.state) == state_before,"Battle cannot be skipped by selecting the next node")
	var summary := _fixture_summary(value)
	summary.roster[0].hp = 31.0
	summary.roster[0].upgrade_level = 1
	summary.roster[0].max_hp += 15
	summary.roster[0].defense += 2
	check(value.accept_battle(summary).ok and value.state.phase == "reward","K3 A victory requires a reward choice before returning to map")
	check(is_equal_approx(value.state.incense,15.5) and is_equal_approx(value.state.names,6.25),"K5 Actual remaining resources carry with visible eight-incense/four-name victory reward")
	check(value.state.roster[0].hp == 31 and value.state.roster[0].upgrade_level == 1,"K5 Surviving upgraded roster keeps actual HP instead of silently resurrecting")
	state_before = JSON.stringify(value.state)
	check(not value.accept_battle(summary).ok and not value.leave_node().ok and not value.choose_node("n02").ok and JSON.stringify(value.state) == state_before,"K3 Mandatory reward gate rejects duplicate battle settlement and node skipping")
	var offers: Array = value.reward_options()
	check(offers.size() == 3,"K3 Exactly three weighted cards are generated")
	var ids: Array[String] = []
	var survival := 0
	for offer in offers:
		ids.append(str(offer.id))
		if offer.category == "survival":
			survival += 1
		check(not str(offer.title).is_empty() and not str(offer.description).is_empty() and offer.has("effect"),"K3 Reward explains its actual effect: " + str(offer.id))
	check(ids.size() == 3 and ids[0] != ids[1] and ids[0] != ids[2] and ids[1] != ids[2] and survival <= 1,"K3 Rewards are distinct and cannot all be survival cards")
	var save_path := "/tmp/ye-ci-p5-reward-fixture.json"
	check(value.save(save_path).ok,"S1 Reward phase saves to isolated acceptance path")
	var loaded: RefCounted = load("res://src/night/NightRun.gd").new()
	check(loaded.load_save(save_path).ok and loaded.state.phase == "reward" and JSON.stringify(loaded.reward_options()) == JSON.stringify(offers) and loaded.state.rng_state == value.state.rng_state,"S1 Loading pending reward preserves exact cards and RNG state")
	check(_choose_fixture_reward(value).ok and value.state.phase == "map","K3 Selecting one applicable reward returns to map")
	var chosen_state := JSON.stringify(value.state)
	check(not value.choose_reward(ids[0]).ok and JSON.stringify(value.state) == chosen_state,"K3 Second reward confirmation cannot obtain a second card")
	check(_choose_fixture_reward(loaded).ok and _equivalent(loaded.state,value.state),"Saved reward choice has identical effects and deterministic future RNG")
	check(value.choose_node("n02").ok and value.state.phase == "market","K4 Route reaches real market after opening battle reward")
	var market: Array = value.market_options()
	check(not market.is_empty(),"K4 Market exposes priced seat-appropriate offers")
	check(value.save(save_path).ok and loaded.load_save(save_path).ok and JSON.stringify(loaded.market_options()) == JSON.stringify(market),"S1 Market stock and prices survive save/load without reroll")
	var bought := false
	for offer in market:
		if offer.get("allowed",false):
			var target := _first_target(value,offer)
			if offer.get("requires_target",false) and target.is_empty():
				continue
			var funds: float = value.state.incense
			var response: Dictionary = value.buy_offer(str(offer.id),target)
			check(response.ok and is_equal_approx(value.state.incense,funds - float(offer.cost)),"K4 Market purchase charges its displayed incense price")
			funds = value.state.incense
			check(not value.buy_offer(str(offer.id),target).ok and value.state.incense == funds,"Sold market stock cannot be purchased twice")
			value.save(save_path)
			loaded.load_save(save_path)
			check(JSON.stringify(loaded.market_options()) == JSON.stringify(value.market_options()),"S1 Loading sold stock does not replenish it")
			bought = true
			break
	check(bought,"K4 At least one real market offer is affordable after first victory")
	check(value.leave_node().ok and value.state.phase == "map","K4 Leaving market returns to reachable route")
	DirAccess.remove_absolute(save_path)
	await _weighted_pool_rules()
	await _mercy_fixtures()
	await _route_fixture()

func _mercy_fixtures() -> void:
	var value := _new_run("shouxiang","P5-MERCY-FIXTURE")
	value.choose_node("n01")
	var summary := _fixture_summary(value,"defeat")
	summary.roster = []
	summary.incense = 0
	summary.names = 0
	check(value.accept_battle(summary).ok and value.state.phase == "mercy","K7 First example failure exposes an explicit mercy choice")
	check(value.use_mercy().ok and value.state.phase == "battle" and value.state.current_node_id == "n01" and value.state.incense >= 16 and value.state.names >= 4 and not value.state.roster.is_empty(),"K7 One free mercy visibly restores battle-before roster and retries same node")
	check(not value.use_mercy().ok,"Mercy cannot be consumed repeatedly during its retry")
	check(value.accept_battle(summary).ok and value.state.phase == "ended","K7 Second defeat ends night instead of granting unlimited mercy")
	var ending: Dictionary = value.summary()
	check(ending.outcome == "defeat" and not str(ending.reason).is_empty() and ending.seed == "P5-MERCY-FIXTURE","K6 Failure summary exposes actual failure line and copyable seed")
	check(not ending.unlocks.is_empty(),"S3 Failed example records encountered codex unlocks")

func _route_fixture() -> void:
	var value := _new_run("duoming","P5-ROUTE-FIXTURE")
	var visited: Array[String] = []
	var types: Array[String] = []
	var profile_ids: Array[String] = []
	for iteration in 40:
		if value.state.phase == "ended":
			break
		match value.state.phase:
			"map":
				var options: Array = value.available_nodes()
				var next: Dictionary = options[0]
				for option in options:
					if option.id == "n06":
						next = option
				check(value.choose_node(str(next.id)).ok,"K1 Reachable route node: " + str(next.id))
				visited.append(str(next.id))
				types.append(str(next.type))
			"battle":
				profile_ids.append(str(value.current_node().profile_id))
				check(value.accept_battle(_fixture_summary(value)).ok,"Fixture route accepts isolated battle summary")
			"reward":
				check(_choose_fixture_reward(value).ok,"Mandatory fixture reward is selectable")
			"market":
				value.leave_node()
			"event":
				var options: Array = value.event_options()
				var selected: Dictionary = options[0]
				for option in options:
					if option.allowed:
						selected = option
						break
				check(value.resolve_event(str(selected.id)).ok,"K4 Event applies an explicit priced or risky decision")
			"rest":
				check(value.finish_rest().ok,"K4 Limited rest node resolves once")
			_:
				check(false,"Unexpected fixture route phase: " + str(value.state.phase))
				break
	check(value.state.phase == "ended" and visited.size() >= 8 and visited.size() <= 12,"K1 External example route visits eight to twelve meaningful nodes and ends")
	check(types.has("market") and types.has("event") and types.has("rest") and (types.has("boss") or visited.has("n10")),"K1 Route contains market, event, rest and boss")
	check(profile_ids.size() >= 4 and profile_ids[0] != profile_ids[2],"K8 Route uses distinct battle profile identifiers")

func _create_combat(value: RefCounted) -> Node2D:
	var scene: Node2D = preload("res://scenes/combat/Combat.tscn").instantiate()
	add_child(scene)
	var adapter: RefCounted = load("res://src/night/NightBattleBridge.gd").new()
	scene.set_meta("acceptance_bridge",adapter)
	var answer: Dictionary = adapter.start(scene,value)
	check(answer.ok,"K2 Night adapter starts the existing shared G0 combat scene")
	scene.get_node("Simulation").set_physics_process(false)
	Clock.set_paused(true)
	return scene

func _unit(scene: Node2D, id: String) -> Node2D:
	for unit in scene.get_node("Simulation").humans + scene.get_node("Simulation").targets:
		if unit.unit_id == id:
			return unit
	return null

func _snapshot_roundtrip() -> void:
	var value := _new_run("shouxiang","P5-SNAPSHOT-FIXTURE")
	value.choose_node("n01")
	var original := _create_combat(value)
	var original_sim: Node2D = original.get_node("Simulation")
	var original_session: Node = original.get_node("Session")
	var adapter: RefCounted = original.get_meta("acceptance_bridge")
	var caster := _unit(original,"H01")
	var target: Node2D = original_sim.tide.spawn("G01",0,caster.position.x - 100)
	target.motion_enabled = false
	target.attacks_enabled = false
	var archer := _unit(original,"T02")
	var ranged_target: Node2D = original_sim.tide.spawn("G01",1,archer.position.x + 200)
	ranged_target.position.y = archer.position.y
	ranged_target.floor_id = archer.floor_id
	ranged_target.motion_enabled = false
	ranged_target.attacks_enabled = false
	original_sim._update_units()
	original_sim.world.get_node("door_inner").receive_damage(400)
	check(original_session.start_ritual(caster,target).ok and original_session.repair("door_inner").ok,"Snapshot fixture has paid ritual and genuine repair job together")
	for step in 6:
		original_sim.advance(1.0/60)
	var home_probe := _unit(original,"H09")
	home_probe.set_meta("night_home_post","post_gate_inner")
	home_probe.current_post = "post_hall_door" # Isolated carry-home metadata fixture, not a full night.
	var before: Dictionary = adapter.snapshot(original)
	check(caster.brain.channel.active and not original_session.repair_jobs.is_empty() and not original_sim.projectiles.is_empty(),"S1 Snapshot includes active channel, moving repairer and in-flight projectile")
	check(not before.tide.pending.is_empty() and not before.actors.is_empty() and not before.structures.is_empty(),"S1 Snapshot includes source queue, live actors and physical structures")
	value.state.battle_snapshot = before
	var save_path := "/tmp/ye-ci-p5-live-battle-fixture.json"
	check(value.save(save_path).ok,"S1 A live battle snapshot serializes to local night save")
	var loaded: RefCounted = load("res://src/night/NightRun.gd").new()
	check(loaded.load_save(save_path).ok and loaded.state.phase == "battle" and loaded.state.current_node_id == value.state.current_node_id and loaded.state.rng_state == value.state.rng_state,"S1 Continue loads same battle node and RNG rather than a fresh night")
	var restored := _create_combat(loaded)
	var restored_adapter: RefCounted = restored.get_meta("acceptance_bridge")
	check(restored_adapter.restore(restored,loaded,loaded.state.battle_snapshot).ok,"S1 Adapter restores saved live battle into new combat instance")
	check(str(_unit(restored,"H09").get_meta("night_home_post","")) == "post_gate_inner" and _unit(restored,"H09").current_post == "post_hall_door","S1 Restoring retreating unit keeps original next-node deployment post")
	var after: Dictionary = restored_adapter.snapshot(restored)
	check(_equivalent(before,after),"S1 Restored semantic snapshot equals saved actors, AI, channel, repairs, projectiles, doors, queue, resources and clocks")
	var restored_sim: Node2D = restored.get_node("Simulation")
	for step in 180:
		original_sim.advance(1.0/60)
	for step in 180:
		restored_sim.advance(1.0/60)
	var expected: Dictionary = adapter.snapshot(original)
	var continued: Dictionary = restored_adapter.snapshot(restored)
	check(_equivalent(expected,continued),"S1 Restored battle's next three seconds match uninterrupted actual combat")
	var invalid: Dictionary = continued.duplicate(true)
	invalid.actors[0].position = {"_vector2":[1,"invalid"]}
	check(not restored_adapter.restore(restored,loaded,invalid).ok and _equivalent(restored_adapter.snapshot(restored),continued),"Malformed saved vector is rejected before changing live battle")
	invalid = continued.duplicate(true)
	invalid.actors[0].erase("brain")
	check(not restored_adapter.restore(restored,loaded,invalid).ok and _equivalent(restored_adapter.snapshot(restored),continued),"Missing saved brain is rejected atomically without freeing live actors")

	snapshot_evidence = {"at_seconds":0.1,"same_node":loaded.state.current_node_id,"before":before,"after":after,"continued":continued,"equivalent_at_restore":_equivalent(before,after),"equivalent_after_three_seconds":_equivalent(expected,continued)}
	await _shot("10-midbattle-resume-fixture",true)
	original.queue_free()
	restored.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(save_path)

func _equivalent(left: Variant, right: Variant) -> bool:
	if (left is float or left is int) and (right is float or right is int):
		return absf(float(left) - float(right)) < 0.0001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _equivalent(left[key],right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _equivalent(left[index],right[index]):
				return false
		return true
	return left == right

func _new_host(save_suffix: String) -> Node:
	if is_instance_valid(host):
		remove_child(host)
		host.queue_free()
	var scene: Node = load("res://scenes/night/Night.tscn").instantiate()
	scene.save_path = "/tmp/ye-ci-p5-%s.json" % save_suffix
	add_child(scene)
	host = scene
	return scene

func _ui_flow() -> void:
	_new_host("ui-fixture")
	await get_tree().process_frame
	if capture:
		get_window().size = Vector2i(1920,1080)
	check(host.panel.buttons.has("start_shouxiang") and host.panel.buttons.has("start_duoming"),"K1 Entrance offers both player seats")
	await _shot("01-night-entry")
	host.panel.seed_input.text = "P5-UI-FIXTURE"
	await _button(host.panel.buttons.start_shouxiang)
	check(host.run.state.phase == "map" and not host.panel.show_intro and host.run.state.seed == "P5-UI-FIXTURE","K1 Actual entrance click starts seeded example and displays map")
	check(host.panel.buttons.has("node_n01") and not host.panel.buttons.node_n01.disabled and host.panel.buttons.node_n10.disabled,"K1 Map visibly allows reachable node and disables locked boss")
	await _shot("02-night-map")
	if capture:
		get_window().size = Vector2i(1280,720)
		await _shot("02b-night-map-720p")
		get_window().size = Vector2i(1920,1080)
	await _button(host.panel.buttons.node_n01)
	check(host.run.state.phase == "battle" and is_instance_valid(host.combat) and not host.panel.visible,"K2 Actual node click enters shared battle and hides map")
	host.combat.get_node("Simulation").set_physics_process(false)
	Clock.set_paused(true)
	await _key(KEY_SPACE)
	check(not Clock.paused,"K2 Existing Space battle resume remains usable from night host")
	await _key(KEY_SPACE)
	check(Clock.paused,"K2 Existing Space battle pause remains usable from night host")
	for step in 120:
		host.combat.get_node("Simulation").advance(1.0/60)
	var saved_time: float = host.combat.get_node("Simulation").simulation_time
	await _button(host.buttons.save_exit)
	check(host.combat == null and host.panel.show_intro and FileAccess.file_exists(host.save_path),"S1 Real save-and-exit button leaves resumable local night")
	await _button(host.panel.buttons.continue)
	check(is_instance_valid(host.combat) and host.run.state.current_node_id == "n01" and is_equal_approx(host.combat.get_node("Simulation").simulation_time,saved_time) and Clock.paused,"S1 Real continue resumes exact live node and combat time paused")
	host.combat.get_node("Simulation").set_physics_process(false)
	await _shot("03-live-node-continued",true)
	# UI rendering fixtures use explicit synthetic summaries, separate from both full nights below.
	host._dispose_battle()
	host.run.accept_battle(_fixture_summary(host.run))
	host.refresh()
	await get_tree().process_frame
	check(host.run.state.phase == "reward" and _all_text(host.panel).contains(tr("P5_REWARD_TITLE")),"K3 Battle reward screen visibly requires one of three cards")
	await _shot("04-three-rewards",true)
	var offers: Array = host.run.reward_options()
	for offer in offers:
		if offer.get("allowed",true) and host.panel.buttons.has("reward_" + str(offer.id)) and not host.panel.buttons["reward_" + str(offer.id)].disabled:
			await _button(host.panel.buttons["reward_" + str(offer.id)])
			break
	check(host.run.state.phase == "map","K3 Actual reward card click takes exactly one and returns to route")
	await _button(host.panel.buttons.node_n02)
	check(host.run.state.phase == "market","K4 Actual map click opens night market")
	await _shot("05-night-market",true)
	await _button(host.panel.buttons.leave)
	check(host.run.state.phase == "map","K4 Market leave button returns to current route")
	_fast_fixture_phase(host.run,"event")
	host.refresh()
	await get_tree().process_frame
	await _shot("06-night-event",true)
	var events: Array = host.run.event_options()
	for event in events:
		if event.allowed:
			await _button(host.panel.buttons["event_" + str(event.id)])
			break
	check(host.run.state.phase == "map","K4 Event button resolves its visible decision")
	_fast_fixture_phase(host.run,"rest")
	host.refresh()
	await get_tree().process_frame
	await _shot("07-night-rest",true)
	await _button(host.panel.buttons.rest)
	check(host.run.state.phase == "map","K4 Rest button applies limited recovery and returns to route")
	_fast_fixture_phase(host.run,"ended")
	if not host.run.state.roster.is_empty():
		var casualty: Dictionary = host.run.state.roster.pop_back()
		casualty.hp = 0.0
		host.run.state.fallen.append(casualty)
	host.refresh()
	await get_tree().process_frame
	var summary: Dictionary = host.run.summary()
	var outcome_reason: String = str(summary.battles[-1].reason) if summary.outcome == "victory" and not summary.battles.is_empty() else str(summary.reason)
	var expected := [tr("P9_NIGHT_INCENSE"), tr("P9_NIGHT_NAMES"), tr("P9_NIGHT_STILL_LISTED"), tr("P5_DEAD"),
		tr("P5_SEED") % summary.seed, tr(outcome_reason), "\n%.1f\n" % float(summary.incense), "\n%.1f\n" % float(summary.names)]
	for record in summary.roster + summary.fallen:
		var source: Dictionary = Data.get_unit(str(record.id))
		expected.append(str(source.get("姓名",source.get("名称",record.id))))
	var ending := _all_text(host.panel)
	check(host.run.state.phase == "ended" and not summary.roster.is_empty() and not summary.fallen.is_empty() and not outcome_reason.is_empty() and expected.all(func(text): return ending.contains(text)),"K6 Night ending shows translated headings, exact incense/names, survivor and casualty names, reason and seed")
	await _shot("08-night-summary",true)
	if capture:
		get_window().size = Vector2i(1280,720)
		await _shot("08b-night-summary-720p",true)
		get_window().size = Vector2i(1920,1080)
	remove_child(host)
	host.queue_free()
	host = null
	await get_tree().process_frame
	DirAccess.remove_absolute("/tmp/ye-ci-p5-ui-fixture.json")

func _fast_fixture_phase(value: RefCounted, phase: String) -> void:
	for iteration in 40:
		if value.state.phase == phase:
			return
		match value.state.phase:
			"map":
				var options: Array = value.available_nodes()
				if options.is_empty(): return
				var next: Dictionary = options[0]
				for option in options:
					if option.id == "n06": next = option
				value.choose_node(str(next.id))
			"battle": value.accept_battle(_fixture_summary(value))
			"reward": _choose_fixture_reward(value)
			"market": value.leave_node()
			"event":
				for option in value.event_options():
					if option.allowed:
						value.resolve_event(str(option.id))
						break
			"rest": value.finish_rest()
			_: return

func _pick_reward(value: RefCounted) -> Dictionary:
	var scored: Array[Dictionary] = []
	for offer in value.reward_options():
		if not offer.get("allowed",true): continue
		var target := _first_target(value,offer)
		if offer.get("requires_target",false) and target.is_empty(): continue
		var score := 0
		match str(offer.id):
			"r_joinery": score = 100
			"r_slow_incense": score = 90
			"r_incense_gear": score = 80
			"r_thick_name": score = 70
			"r_sharp_name": score = 60
			"r_breaker": score = 100
			"r_hanging": score = 85
			_: score = 30 if offer.category == "build" else 20
		scored.append({"offer":offer,"target":target,"score":score})
	scored.sort_custom(func(a,b): return a.score > b.score)
	return scored[0] if not scored.is_empty() else {}

func _record_choice(action: String, args: Dictionary, ok := true, reason := "") -> void:
	choices.append({"node":str(host.run.state.get("current_node_id","")),"phase":str(host.run.state.phase),"battle_seconds":sim.simulation_time if is_instance_valid(sim) and is_instance_valid(host.combat) else 0,"action":action,"args":args,"ok":ok,"reason":reason,"incense":session.incense if is_instance_valid(session) and is_instance_valid(host.combat) else host.run.state.incense,"names":session.names if is_instance_valid(session) and is_instance_valid(host.combat) else host.run.state.names})

func _complete_night(mode: String) -> void:
	_new_host("full-" + mode)
	host.start_run(mode,"example","P5-FULL-" + mode)
	choices = []
	var battles: Array[Dictionary] = []
	var visited: Array[String] = []
	var phases: Array[String] = []
	var mercy_used := false
	for iteration in 60:
		var phase: String = host.run.state.phase
		phases.append(phase)
		if phase == "ended": break
		match phase:
			"map":
				var options: Array = host.run.available_nodes()
				if options.is_empty():
					check(false,"Full night has reachable next node")
					break
				var next: Dictionary = options[0]
				for option in options:
					if option.id == "n06": next = option
				visited.append(str(next.id))
				host.choose_node(str(next.id))
				if is_instance_valid(host.combat):
					host.combat.get_node("Simulation").set_physics_process(false)
					Clock.set_paused(true)
				_record_choice("choose_node",{"id":next.id})
				await get_tree().process_frame
				if host.run.state.phase == "map": break
			"battle":
				battles.append(await _drive_battle(mode))
			"reward":
				var picked := _pick_reward(host.run)
				if picked.is_empty():
					check(false,"Full night has applicable mandatory reward")
					break
				host.select_reward(str(picked.offer.id),str(picked.target))
				_record_choice("choose_reward",{"id":picked.offer.id,"target":picked.target},host.run.state.phase != "reward")
				await get_tree().process_frame
			"market":
				# One deliberate affordable construct purchase; all validation/payment remains NightRun-owned.
				for offer in host.run.market_options():
					if offer.get("allowed",false) and offer.category == "build" and host.run.state.incense >= float(offer.cost) + 6:
						var target := _first_target(host.run,offer)
						if offer.get("requires_target",false) and target.is_empty(): continue
						host.buy_offer(str(offer.id),target)
						_record_choice("buy_offer",{"id":offer.id,"target":target})
						break
				host.leave_node()
				_record_choice("leave_market",{})
			"event":
				var selected: Dictionary = {}
				for option in host.run.event_options():
					if option.allowed:
						selected = option
						if option.id == "listen" or option.id == "return": break
				if selected.is_empty():
					check(false,"Full night has applicable event choice")
					break
				host.resolve_event(str(selected.id))
				_record_choice("resolve_event",{"id":selected.id})
			"rest":
				host.finish_rest()
				_record_choice("finish_rest",{})
			"mercy":
				if mercy_used:
					check(false,"Full night avoids repeated mercy")
					break
				host.use_mercy()
				mercy_used = true
				_record_choice("use_mercy",{})
			_:
				check(false,"Unexpected full-night phase: " + phase)
				break
		await get_tree().process_frame
	var summary: Dictionary = host.run.summary()
	check(host.run.state.phase == "ended" and summary.outcome == "victory","K1 Complete unmodified %s example reaches successful night ending" % mode)
	check(visited.size() >= 8 and visited.size() <= 12 and visited.has("n02") and visited.has("n04") and visited.has("n06") and visited.has("n10"),"K1 %s complete night traverses meaningful market/event/rest/boss route" % mode)
	check(battles.size() >= 5,"K2 %s night plays at least five actual shared-simulation battles" % mode)
	var elapsed := 0.0
	var too_short := 0
	var too_long := 0
	for battle in battles:
		elapsed += battle.seconds
		if battle.seconds < 120: too_short += 1
		if battle.seconds > 600: too_long += 1
	check(too_short <= 1 and too_long == 0,"K10 %s ordinary battles are not repeatedly below two minutes or above ten" % mode)
	check(absf(elapsed - float(summary.elapsed)) < 0.1,"K10 %s night duration equals recorded actual battle durations" % mode)
	check(summary.ritual == "example_incense" if summary.has("ritual") else host.run.state.ritual == "example_incense","K7 Complete night uses only implemented example incense ritual")
	check(not summary.seed.is_empty() and not summary.unlocks.is_empty(),"K6/S3 %s ending retains seed and encounter unlocks" % mode)
	host.refresh()
	await get_tree().process_frame
	check(_all_text(host.panel).contains(summary.seed) and _all_text(host.panel).contains(tr("P4_SEAT_" + mode.to_upper())),"K6 %s actual final UI matches this night seat and seed" % mode)
	await _shot("12-%s-full-night-end" % mode)
	await _verify_night_seed_replay(mode,summary.seed)
	nights.append({"mode":mode,"seed":summary.seed,"visited":visited,"phases":phases,"summary":summary,"battles":battles,"choices":choices.duplicate(true),"actual_battle_seconds":elapsed,"minutes":elapsed / 60.0,"mercy_used":mercy_used,"too_short_battles":too_short,"too_long_battles":too_long,"cheat_mutations":[]})
	var path: String = host.save_path
	remove_child(host)
	host.queue_free()
	host = null
	await get_tree().process_frame
	DirAccess.remove_absolute(path)

func _drive_battle(mode: String) -> Dictionary:
	combat = host.combat
	sim = combat.get_node("Simulation")
	session = combat.get_node("Session")
	camera = combat.get_node("BattleCamera")
	sim.set_physics_process(false)
	Clock.set_paused(true)
	var node: Dictionary = host.run.current_node()
	var node_id: String = node.id
	var before_roster: Array = host.run.state.roster.duplicate(true)
	check(is_equal_approx(session.incense,host.run.state.incense) and is_equal_approx(session.names,host.run.state.names),"K5 %s %s enters with carried night resources" % [mode,node_id])
	check(Rules.REFERENCE_MAP_WIDTH_PX == 9600 and camera.zoom == Vector2.ONE and Rules.UNIT_HEIGHT_PX == 80,"K9 Shared battle keeps G0 geometry and unit scale")
	var carry_by_uid: Dictionary = {}
	for owned in before_roster: carry_by_uid[str(owned.uid)] = owned
	var validated: Dictionary = {}
	var persistence_ok := true
	var safe := true
	var smooth := true
	var upgraded := false
	var mutation_done := false
	var next_decision := 0.0
	var samples: Array[Dictionary] = []
	var next_sample := 0.0
	var sampled_shot := false
	var observed_ghost_ids: Dictionary = {}
	if mode == "shouxiang" and node_id == "n01":
		for human in sim.humans:
			if human.unit_id == "H09":
				var answer: Dictionary = session.upgrade(human)
				_record_choice("upgrade",{"uid":human.get_meta("night_uid","")},answer.ok,answer.reason)
				upgraded = answer.ok
			if human.unit_id == "H01":
				var answer: Dictionary = session.equip(human)
				_record_choice("equip",{"uid":human.get_meta("night_uid","")},answer.ok,answer.reason)
	if mode == "duoming":
		var has_breaker := false
		for owned in before_roster:
			if owned.id == "G12": has_breaker = true
		if not has_breaker:
			for ghost in sim.targets:
				if ghost.unit_id == "G01":
					var answer: Dictionary = session.mutate(ghost,"G12")
					_record_choice("mutate",{"uid":ghost.get_meta("night_uid",""),"form":"G12"},answer.ok,answer.reason)
					mutation_done = answer.ok
					break
	Clock.set_paused(false)
	for step in 36600:
		if not session.result.is_empty(): break
		for unit in sim.humans + sim.targets:
			if unit.side == "yegui": observed_ghost_ids[unit.unit_id] = true
			var uid: String = unit.get_meta("night_uid","")
			if carry_by_uid.has(uid) and not validated.has(uid):
				var expected: Dictionary = carry_by_uid[uid]
				# First-node decisions deliberately change the chosen unit; all other carry fields must agree at spawn.
				if not (node_id == "n01" and ((mode == "shouxiang" and unit.unit_id in ["H09","H01"]) or (mode == "duoming" and unit.mutation_count > 0))):
					persistence_ok = persistence_ok and unit.unit_id == expected.id and is_equal_approx(unit.max_hp,float(expected.max_hp)) and is_equal_approx(unit.defense,float(expected.defense)) and is_equal_approx(unit.attack,float(expected.attack)) and unit.upgrade_level == int(expected.upgrade_level) and unit.equipment_id == expected.equipment_id and unit.mutation_count == int(expected.mutation_count)
				validated[uid] = true
		if sim.simulation_time >= next_decision:
			Clock.set_paused(true)
			next_decision += 1
			if mode == "shouxiang":
				if session.repair_jobs.is_empty() and session.incense >= float(session.rules.repair.cost):
					for door_id in ["door_outer","door_inner","door_hall","door_gallery"]:
						var door: Node2D = sim.world.get_node(door_id)
						if not door.destroyed and door.max_durability - door.durability >= float(session.rules.repair.heal):
							var answer: Dictionary = session.repair(door_id)
							_record_choice("repair",{"door":door_id},answer.ok,answer.reason)
							if answer.ok: break
				for caster in sim.humans:
					if caster.role == "ritual" and not caster.brain.channel.active and session.incense >= float(session.rules.ritual.cost):
						for target in sim.targets:
							if caster.brain.channel.valid_target(sim,caster,target):
								var answer: Dictionary = session.start_ritual(caster,target)
								_record_choice("start_ritual",{"caster":caster.instance_id,"target":target.instance_id},answer.ok,answer.reason)
								break
			else:
				var has_hanging := false
				for ghost in sim.targets:
					if ghost.unit_id == "G09": has_hanging = true
				if not has_hanging and session.incense >= float(session.rules.mutations.G09):
					var candidate: Node2D = null
					for ghost in sim.targets:
						if ghost.unit_id == "G01" and not ghost.dead and (candidate == null or ghost.position.x < candidate.position.x): candidate = ghost
					if candidate != null:
						var answer: Dictionary = session.mutate(candidate,"G09")
						_record_choice("mutate",{"uid":candidate.get_meta("night_uid",""),"form":"G09"},answer.ok,answer.reason)
				if session.incense >= float(session.rules.reinforce.cost) and session.reinforce_left <= 0 and session.reinforce_count < int(session.rules.reinforce.limit):
					var answer: Dictionary = session.reinforce()
					_record_choice("reinforce",{},answer.ok,answer.reason)
		Clock.set_paused(false)
		var previous: Dictionary = {}
		for human in sim.humans: previous[human.instance_id] = human.position
		sim.advance(1.0/60)
		for human in sim.humans:
			safe = safe and sim.world.inside_base(human.position)
			if previous.has(human.instance_id): smooth = smooth and human.position.distance_to(previous[human.instance_id]) <= Rules.body_to_px(Rules.RETREAT_SPEED)/60 + 0.1
		if sim.simulation_time >= next_sample:
			next_sample += 30
			samples.append({"seconds":sim.simulation_time,"incense":session.incense,"names":session.names,"humans":sim.humans.size(),"ghosts":sim.targets.size(),"pending":sim.tide.pending.size()})
		if capture and not sampled_shot and sim.simulation_time >= 120:
			sampled_shot = true
			camera.set_left(6080)
			await _shot("11-%s-%s-live" % [mode,node_id])
	var result: Dictionary = session.result.duplicate(true)
	var events: Array = sim.events.duplicate(true)
	var milestones: Array = sim.tide.milestones.duplicate(true)
	var summary: Dictionary = host.bridge.collect(combat,host.run)
	check(not result.is_empty() and result.outcome == "victory","K2 %s %s reaches actual battle victory" % [mode,node_id])
	check(persistence_ok and not validated.is_empty(),"K5 %s %s carried unit identities, stats, upgrades, equipment and mutations enter real combat" % [mode,node_id])
	check(safe and smooth,"K9 %s %s humans remain in-base with continuous AI movement" % [mode,node_id])
	await get_tree().process_frame
	check(host.run.state.phase in ["reward","mercy","ended"] and host.combat == null,"K2 Actual Night host collects battle and returns to night phase")
	return {"node":node_id,"profile":str(node.profile_id),"seconds":summary.elapsed,"result":result,"starting_roster":before_roster,"surviving_roster":summary.roster,"fallen":summary.fallen,"samples":samples,"events":events,"milestones":milestones,"persistence_ok":persistence_ok,"validated_carried_units":validated.size(),"human_base_safe":safe,"continuous_movement":smooth,"upgraded_in_first_battle":upgraded,"mutation_in_battle":mutation_done,"observed_ghost_ids":observed_ghost_ids.keys(),"battle_profile":host.run.config.battle_profiles[str(node.profile_id)].duplicate(true)}

func _weighted_pool_rules() -> void:
	for mode in ["shouxiang","duoming"]:
		var seen: Dictionary = {}
		var valid := true
		for index in 48:
			var value: RefCounted = load("res://src/night/NightRun.gd").new()
			value.new_run(mode,"example","P5-POOL-%s-%d" % [mode,index])
			value.choose_node("n01")
			value.accept_battle(_fixture_summary(value))
			var offers: Array = value.reward_options()
			var survival := 0
			for offer in offers:
				seen[str(offer.category)] = true
				if offer.category == "survival": survival += 1
			valid = valid and offers.size() == 3 and survival <= 1
		check(valid and seen.has("roster") and seen.has("build") and seen.has("survival"),"K3 Across 48 deterministic %s seeds all three reward categories can occur, with at most one survival card" % mode)
	var profiles: Dictionary = Data.night_rules.battle_profiles
	check(JSON.stringify(profiles.gate.waves) != JSON.stringify(profiles.upper.waves) and profiles.gate.layout != profiles.upper.layout,"K8 Gate pressure and upper-floor pressure use genuinely distinct wave profiles")
	check(profiles.boss.phases.size() >= 3 and profiles.boss.phase_waves.size() >= 3 and profiles.boss.phase_waves[2].get("G09",0) > 0 and profiles.boss.phase_waves[4].get("G12",0) > 0,"K8 Boss changes to upper pressure then mixed pressure by scheduled mechanism, beyond health inflation")
	var unsupported: RefCounted = load("res://src/night/NightRun.gd").new()
	check(not unsupported.new_run("shouxiang","fierce","P5-NO-SKIN-RITUAL").ok and unsupported.state.is_empty(),"S2 Unimplemented fierce night is explicitly rejected rather than reskinning an unsupported ritual")

func _queued_and_fallen_rules() -> void:
	var value := _new_run("duoming","P5-QUEUE-FALLEN-FIXTURE")
	value.choose_node("n01")
	var scene := _create_combat(value)
	var adapter: RefCounted = scene.get_meta("acceptance_bridge")
	var engine: Node2D = scene.get_node("Simulation")
	var decisions: Node = scene.get_node("Session")
	var ghost := _unit(scene,"G01")
	check(decisions.mutate(ghost,"G12").ok,"Fallen-form fixture mutates owned white robe through actual decision")
	engine.tide.config.waves = [] # Isolated queue fixture holds off unrelated scheduled reinforcement.
	engine.deal_damage(_unit(scene,"H09"),ghost,"p5_fallen_fixture",1000)
	engine.advance(1.0/60) # Real cleanup emits unit_fallen before collection.
	var collected: Dictionary = adapter.collect(scene,value)
	var correct_fallen := false
	for fallen in collected.fallen:
		if fallen.id == "G12" and fallen.mutation_count == 1: correct_fallen = true
	check(correct_fallen,"K5 Fallen roster records actual mutated form at death, not original white-robed spawn")
	decisions.incense = 30 # Isolated queue-payment fixture, never used in either complete night.
	check(decisions.reinforce().ok,"Queued reinforcement fixture pays real incense")
	var saved: Dictionary = adapter.snapshot(scene)
	collected = adapter.collect(scene,value)
	check(collected.roster.size() == 23,"K5 Sixteen initial ghosts minus one fallen plus eight paid queued reinforcements survive collection")
	var ids: Dictionary = {}
	for owned in collected.roster: ids[str(owned.uid)] = true
	check(ids.size() == 23,"Carried and unspawned reinforcement roster UIDs are unique")
	var restored := _create_combat(value)
	var loaded_adapter: RefCounted = restored.get_meta("acceptance_bridge")
	check(loaded_adapter.restore(restored,value,saved).ok,"S1 Paid unspawned queue can be restored into a new combat")
	var after: Dictionary = loaded_adapter.collect(restored,value)
	check(_equivalent(collected.roster,after.roster) and _equivalent(collected.fallen,after.fallen),"S1 Save/restore preserves paid unspawned roster, latest fallen form and stable identities")
	scene.queue_free()
	restored.queue_free()
	await get_tree().process_frame

func _crowded_home_posts() -> void:
	var value := _new_run("shouxiang","P5-CROWDED-POST-FIXTURE")
	var villager: Dictionary = {}
	for owned in value.state.roster:
		if owned.id == "T01":
			owned.post = "post_gate_inner"
			villager = owned.duplicate(true)
	for index in 2:
		var added: Dictionary = villager.duplicate(true)
		added.uid = "fixture-extra-villager-%d" % index
		value.state.roster.append(added)
	value.choose_node("n01")
	var funds: float = value.state.incense
	var scene := _create_combat(value)
	var engine: Node2D = scene.get_node("Simulation")
	var decisions: Node = scene.get_node("Session")
	var posts: Dictionary = {}
	var legal := true
	var preferred := 0
	for unit in engine.humans:
		posts[unit.current_post] = int(posts.get(unit.current_post,0)) + 1
		legal = legal and engine.world.can_deploy_at(unit.current_post) and engine.world.inside_base(unit.position) and unit.position.distance_to(engine.world.get_node(unit.current_post).position) <= 80
		if unit.get_meta("night_home_post","") == "post_gate_inner": preferred += 1
	var bounded := true
	for count in posts.values():
		bounded = bounded and count <= 3
	check(engine.humans.size() == 7 and preferred == 4 and legal and bounded,"K5 Four carried units preferring same gate redistribute to legal cover with at most three per post")
	check(decisions.incense == funds and decisions.ledger.any(func(entry): return entry.action == "night_redeploy" and entry.incense_delta == 0),"Automatic carried-roster redeployment logs its decision without charging incense again")
	scene.queue_free()
	await get_tree().process_frame

func _verify_night_seed_replay(mode: String, seed: String) -> void:
	# P6: actual night archives include both the opening and a later node with carried damage/upgrades/mutations.
	var storage = load("res://src/replay/ReplayArchive.gd")
	var options: Array = storage.list_seed(seed)
	for node_id in ["n01","n03"]:
		var selected: Dictionary = {}
		for option in options:
			if str(option.node_id) == node_id and bool(option.complete): selected = option; break
		check(not selected.is_empty(),"P6 K7 Actual %s night seed resolves completed %s input archive" % [mode,node_id])
		if selected.is_empty(): continue
		var loaded: Dictionary = storage.load_record(str(selected.id))
		check(loaded.ok and loaded.record.metadata.seed == seed and loaded.record.metadata.node_id == node_id,"P6 K7 Archive lookup retains actual night seed and node identity")
		if not loaded.ok: continue
		var replay_scene: Node2D = preload("res://scenes/combat/Combat.tscn").instantiate()
		add_child(replay_scene)
		replay_scene.get_node("Simulation").set_physics_process(false)
		var player: RefCounted = load("res://src/replay/ReplayPlayer.gd").new()
		var answer: Dictionary = player.start(replay_scene,loaded.record)
		check(answer.ok,"P6 K7 Actual %s %s night archive starts shared-simulation playback" % [mode,node_id])
		if answer.ok:
			for step in loaded.record.steps.size() + 120:
				if player.done: break
				player.advance(1.0/60)
			check(player.done and player.verified and player.error.is_empty(),"P6 K7 Recorded %s %s reproduces carried state, commands, key events and terminal fingerprint" % [mode,node_id])
			night_replay_evidence.append({"mode":mode,"seed":seed,"node_id":node_id,"archive_id":selected.id,"status":player.status(),"recorded_commands":loaded.record.actions.size(),"recorded_steps":loaded.record.steps.size(),"actual_result":replay_scene.get_node("Session").result.duplicate(true)})
		replay_scene.queue_free()
		await get_tree().process_frame
