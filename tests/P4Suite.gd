extends Node
## Rule fixtures may position actors or set resources. The two full runs below may only issue public decisions.
var checks := 0
var failures := 0
var results: Array[Dictionary] = []
var runs: Array[Dictionary] = []
var shots: Array[String] = []
var combat: Node2D
var sim: Node2D
var session: Node
var world: Node2D
var camera: Camera2D
var inspector: CanvasLayer
var hud: Control
var panel: CanvasLayer
var capture := false
var command_script: Array[Dictionary] = []

func _ready() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	results.append({"check":message,"passed":condition})
	if not condition:
		failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL",message])

func _run() -> void:
	combat = preload("res://scenes/combat/Combat.tscn").instantiate()
	add_child(combat)
	sim = combat.get_node("Simulation")
	sim.set_physics_process(false)
	session = combat.get_node("Session")
	world = combat.get_node("ReferenceMap")
	camera = combat.get_node("BattleCamera")
	inspector = combat.get_node("BattleInspector")
	hud = combat.get_node("CanvasLayer/HUD")
	panel = combat.get_node("Decisions")
	Clock.set_paused(true)
	await get_tree().process_frame
	if capture:
		get_window().size = Vector2i(1920,1080)
	check(Data.errors.is_empty(),"P4 boot validates tables and profiles")
	check(sim.session == session and session.simulation == sim,"K8 Both seats bind the existing shared CombatSimulation")
	check(not session.running and session.result.is_empty(),"K8 Prebattle seat selection does not advance or settle battle")
	check(Rules.REFERENCE_MAP_WIDTH_PX == 9600 and Rules.BODY_PX == 80 and camera.zoom == Vector2.ONE,"G0 Map length, body scale and far camera remain locked")
	check(is_equal_approx(hud.minimap.camera_rect().size.x / 480.0,0.2),"G0 Minimap viewport remains one fifth of full map")
	if OS.get_cmdline_user_args().has("--evidence-refresh"):
		await _ritual_rules()
		await _repair_rules()
		_start("duoming")
		session.mutate(_ghost(),"G09")
		camera.set_left(0)
		await _shot("06-mutation-source-flow")
		await _ui_inputs()
		_finish()
		return
	await _command_rules()
	await _ritual_rules()
	await _repair_rules()
	await _attack_commands()
	await _ending_rules()
	await _ui_inputs()
	await _complete_battle("shouxiang")
	await _complete_battle("duoming")
	await _restart_ui_regression()
	_finish()

func _start(mode := "shouxiang") -> void:
	inspector.clear_selection()
	session.enter_debug()
	panel.start_battle(mode)
	sim.set_physics_process(false)
	Clock.set_speed(1)
	Clock.set_paused(true)
	camera.set_left(6080)

func _tick(seconds: float) -> void:
	for index in ceili(seconds * 60):
		sim.advance(1.0/60)

func _human(id: String) -> Node2D:
	for human in sim.humans:
		if human.unit_id == id:
			return human
	return null

func _ghost(id := "G01") -> Node2D:
	for ghost in sim.targets:
		if ghost.unit_id == id and not ghost.dead:
			return ghost
	return null

func _snapshot() -> String:
	var data: Array = [sim.simulation_time,session.remaining,session.incense,session.names,session.result]
	for unit in sim.humans + sim.targets:
		data.append([unit.instance_id,unit.position,unit.hp,unit.ai_state,unit.attack_left])
		if unit.role == "ritual":
			data.append(unit.brain.channel.elapsed)
	for shot in sim.projectiles:
		data.append([shot.position,shot.distance_left])
	return str(data)

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

func _click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = point
	get_viewport().push_input(event,true)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event,true)
	await get_tree().process_frame

func _click_world(point: Vector2) -> void:
	await _click(get_viewport().get_canvas_transform() * point)

func _button(button: BaseButton) -> void:
	await _click(button.get_global_rect().get_center())

func _shot(id: String) -> void:
	if not capture:
		return
	DirAccess.make_dir_recursive_absolute("res://docs/phase-reports/p4-shots")
	var fixture_layer: CanvasLayer
	if id.begins_with("04-") or id.begins_with("05-repair-completed") or id.begins_with("06-"):
		fixture_layer = CanvasLayer.new()
		fixture_layer.layer = 100
		var tag := Label.new()
		tag.text = "规则夹具 / 预置目标或资源 / 非完整战局"
		tag.position = Vector2(26,1046)
		tag.add_theme_font_override("font",world.font)
		tag.add_theme_font_size_override("font_size",20)
		tag.add_theme_color_override("font_color",Color("e4bd7b"))
		fixture_layer.add_child(tag)
		add_child(fixture_layer)
	await get_tree().process_frame
	RenderingServer.force_draw(true)
	var path := "res://docs/phase-reports/p4-shots/%s.png" % id
	check(get_viewport().get_texture().get_image().save_png(path) == OK,"Actual renderer screenshot: " + id)
	shots.append(path)
	if fixture_layer != null:
		fixture_layer.queue_free()

func _finish() -> void:
	var report_prefix := "p4"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report-prefix="):
			report_prefix = argument.trim_prefix("--report-prefix=")
	var report := {"phase":"P4","engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"capture":capture,"results":results,"full_battles":runs,"screenshots":shots,"fixture_policy":"Only isolated rule fixtures modify actor state/resources. Full battles use start_battle plus public decisions and fixed-step shared advance; no HP, position, durability, rules or timer rewrites."}
	FileAccess.open("res://docs/phase-reports/%s-%s-results.json" % [report_prefix,"render" if capture else "test"],FileAccess.WRITE).store_string(JSON.stringify(report,"\t") + "\n")
	print("P4 RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)

func _command_rules() -> void:
	_start()
	check(session.incense == 20 and session.names == 8,"K2 Guard seat opens with 20 incense and configured names")
	check(session.rules.purchases.T01 == 5 and session.rules.purchases.T02 == 8 and session.rules.purchases.T04 == 6,"K2 Source troop prices are 5 / 8 / 6")
	var before: float = session.incense
	check(session.purchase("T01").ok and session.incense == before - 5 and session.pending_purchase == "T01","K2 Purchase reserves and debits exactly once")
	check(not session.purchase("T02").ok and session.incense == before - 5,"Pending purchase rejects a second purchase without charging again")
	for invalid in ["outside_gate","court_center","door_outer",""]:
		var rejected: Dictionary = session.deploy_at(invalid)
		check(not rejected.ok and not rejected.reason.is_empty() and session.pending_purchase == "T01" and session.incense == before - 5,"K3 Invalid deployment preserves reservation and funds: " + invalid)
	check(session.cancel_purchase().ok and session.pending_purchase.is_empty() and session.incense == before,"Right cancel refunds reserved incense exactly")
	session.cancel_purchase()
	check(session.incense == before,"Repeating cancel cannot manufacture incense")
	check(session.purchase("T02").ok,"Crossbow can be purchased while paused")
	var count: int = sim.humans.size()
	var deploy: Dictionary = session.deploy_at("post_window_1")
	check(deploy.ok and sim.humans.size() == count + 1 and session.pending_purchase.is_empty(),"K3 Legal inner window deploys one actor and clears reservation")
	check(not session.deploy_at("post_window_1").ok and sim.humans.size() == count + 1 and session.incense == before - 8,"Repeated deployment confirmation neither spawns nor charges again")
	if deploy.ok:
		var unit: Node2D = deploy.unit
		check(world.inside_base(unit.position) and world.can_deploy_at(unit.current_post) and unit.position.distance_to(world.get_node(unit.current_post).position) <= 80,"Deployed actor occupies genuine in-base CoverPost")
		check(unit.max_hp == 38 and unit.attack == 9 and unit.defense == 4 and unit.profile.range_body == 6,"Purchase unit has source stats and six-body crossbow range")
	session.incense = 0 # Isolated affordability fixture.
	check(not session.purchase("T01").ok and session.pending_purchase.is_empty() and session.incense == 0,"K2 Insufficient incense rejects purchase without debt")
	_start()
	var guard := _human("H09")
	var preview: Dictionary = session.preview_upgrade(guard)
	var hp: float = guard.max_hp
	var defense: float = guard.defense
	var funds: float = session.incense
	check(preview.get("allowed",false) and preview.current_hp == hp and preview.next_hp == hp + 15 and preview.current_defense == defense and preview.next_defense == defense + 2,"K4 Upgrade preview current and next values agree with actual unit")
	check(session.upgrade(guard).ok and guard.max_hp == hp + 15 and guard.defense == defense + 2 and session.incense == funds - 8,"K4 Upgrade actual HP, defense and charge match configured preview delta")
	check(guard.upgrade_level == 1,"Upgrade records per-unit level")
	session.incense = 1000 # Isolated bounded-growth fixture.
	for index in 4:
		session.upgrade(guard)
	check(guard.upgrade_level == 3 and guard.max_hp == hp + 45 and guard.defense == defense + 6,"Upgrade cap prevents repeated unbounded stat growth")
	funds = session.incense
	check(not session.upgrade(guard).ok and session.incense == funds,"Max-level upgrade is rejected without another charge")
	check(session.equip(guard).ok and guard.equipment_id == "ritual_incense","Placeholder equipment occupies its declared slot")
	funds = session.incense
	check(not session.equip(guard).ok and session.incense == funds,"Occupied equipment slot rejects duplicate equip and cost")
	check(not session.mutate(guard,"G12").ok,"Guard seat cannot issue ghost mutations")
	# Troop cap is tested through ordinary commands; only funds are fixture setup.
	for index in 12:
		if session.purchase("T01").ok:
			session.deploy_at(session.legal_posts("T01")[0])
	var troop_count := 0
	for human in sim.humans:
		if human.unit_id.begins_with("T"):
			troop_count += 1
	check(troop_count <= 4 and not session.purchase("T01").ok,"S3 Troop field cap rejects unlimited paid purchases")


func _ritual_target() -> Node2D:
	var target: Node2D = sim.tide.spawn("G01",0,_human("H01").position.x - 100)
	target.motion_enabled = false
	target.attacks_enabled = false
	sim._update_units()
	return target

func _ritual_rules() -> void:
	_start()
	# Position-controlled fixture. This is separate from the full source-lane battle runs.
	sim.clear_targets()
	sim.tide.pending.clear()
	sim.tide.preset = "fixture"
	var caster := _human("H01")
	var target := _ritual_target()
	var funds: float = session.incense
	var names: float = session.names
	check(session.start_ritual(caster,target).ok and session.incense == funds - 4,"K5 Player-triggered ritual spends exactly four incense at start")
	check(caster.brain.channel.active and caster.brain.channel.duration == 4,"K5 Ritual has a four-second real channel")
	funds = session.incense
	check(not session.start_ritual(caster,target).ok and session.incense == funds,"Repeated ritual confirmation cannot debit twice")
	var origin: Vector2 = caster.position
	_tick(3.9)
	check(not target.dead and caster.brain.channel.active and caster.position == origin,"K5 Target remains until full read; caster stays at safe ritual cover")
	_tick(0.2)
	var expected: float = 20 - 4 + 3 + 4.1 * 0.12
	check(target.dead and not caster.brain.channel.active and session.names == names + 1 and absf(session.incense - expected) < 0.02,"K5 Completing channel removes ghost and pays three incense plus one name, including documented natural regen")
	_start()
	sim.clear_targets()
	sim.tide.pending.clear()
	sim.tide.preset = "fixture"
	caster = _human("H01")
	target = _ritual_target()
	check(session.start_ritual(caster,target).ok,"Interrupted ritual starts normally")
	_tick(1)
	sim.deal_damage(target,caster,"p4_interrupt_fixture",1)
	_tick(0.05)
	check(not caster.brain.channel.active and session.incense < 17 and session.names == 8 and not target.dead,"K5 Actual damage interrupts ritual without refund or reward")
	var outside: Node2D = sim.tide.spawn("G01",1,44 * 80)
	funds = session.incense
	check(not session.start_ritual(caster,outside).ok and session.incense == funds,"K5 Outside-base target is rejected without spending")
	target.position = Vector2(104 * 80,500)
	target.floor_id = 2
	sim._update_units()
	check(not session.start_ritual(caster,target).ok,"K5 Ritual rejects a target on another floor")
	caster.position = world.get_node("post_barricade_outer_court").position
	check(not session.start_ritual(caster,outside).ok,"K5 Courtyard ritual caster is rejected")
	_start()
	sim.clear_targets()
	sim.tide.pending.clear()
	sim.tide.preset = "fixture"
	caster = _human("H01")
	target = _ritual_target()
	var guard := _human("H09")
	var enemy: Node2D = sim.tide.spawn("G01",1,guard.position.x - 50)
	enemy.motion_enabled = false
	enemy.attacks_enabled = false
	sim._update_units()
	check(session.start_ritual(caster,target).ok,"Parallel combat ritual fixture starts")
	var enemy_hp: float = enemy.hp
	_tick(0.5)
	check(caster.brain.channel.active and enemy.hp < enemy_hp,"K5 Other defenders continue actual shared combat during ritual")
	camera.set_left(7680)
	await _shot("04-ritual-channel")

func _repair_rules() -> void:
	_start()
	sim.clear_targets()
	sim.tide.pending.clear()
	sim.tide.preset = "fixture"
	var door: Node2D = world.get_node("door_inner")
	door.receive_damage(400) # Isolated damaged structure fixture, never part of full runs.
	var damaged: float = door.durability
	var funds: float = session.incense
	var preview: Dictionary = session.preview_repair("door_inner")
	check(preview.ok and preview.cost==6 and session.incense==funds and session.repair_jobs.is_empty(),"K6 Repair quote reserves neither worker nor incense")
	var command: Dictionary = session.repair("door_inner")
	check(command.ok and session.incense == funds - 6 and session.repair_jobs.size() == 1,"K6 Repair pays six incense and creates real repairer job")
	if command.ok:
		var worker: Node2D = session.repair_jobs[0].unit
		check(worker==preview.unit and session.preview_repair("door_inner").reason=="P4_REPAIR_BUSY","K6 Payment dispatches the quoted guard and blocks a duplicate repair")
		var origin: Vector2 = worker.position
		_tick(0.1)
		check(worker.position != origin and door.durability == damaged,"K6 Repairer walks first; a distant damaged door does not instantly heal")
		var safe := true
		var maximum_step := 0.0
		for index in 2400:
			var previous: Vector2 = worker.position
			sim.advance(1.0/60)
			safe = safe and world.inside_base(worker.position)
			maximum_step = maxf(maximum_step,worker.position.distance_to(previous))
			if session.repair_jobs.is_empty():
				break
		check(session.repair_jobs.is_empty() and door.durability > damaged,"K6 Real job arrives, spends work time and restores actual door durability")
		check(safe and maximum_step <= Rules.body_to_px(Rules.RETREAT_SPEED)/60 + 0.1,"K6 Repairer remains inside base and traverses without teleporting")
	await _shot("05-repair-completed")

func _attack_commands() -> void:
	_start("duoming")
	check(session.incense == 16,"K7 Attack seat opens with sixteen incense")
	var ghost := _ghost()
	var funds: float = session.incense
	check(session.mutate(ghost,"G09").ok and ghost.unit_id == "G09" and session.incense == funds - 12,"K7 Eligible white robe mutates to hanging ghost for twelve incense")
	check(ghost.mutation_count == 1 and ghost.profile.skill_id == "shang_liang","Mutation applies genuine climber profile and records count")
	session.incense = 100 # Isolated source/count validation fixture.
	funds = session.incense
	check(not session.mutate(ghost,"G12").ok and session.incense == funds,"Mutation source/count rules reject chaining elite into breaker without spending")
	var white := _ghost()
	check(session.mutate(white,"G12").ok and white.unit_id == "G12" and session.incense == funds - 15,"K7 Eligible white robe mutates to real breaker for fifteen incense")
	check(not session.mutate(_human("H09"),"G09").ok,"Human unit is never a valid mutation source")
	check(not session.mutate(_ghost(),"G02").ok,"S1 Unsupported lantern form is rejected explicitly")
	var count: int = sim.targets.size()
	funds = session.incense
	check(session.reinforce().ok and session.incense == funds - 10,"K7 Reinforcement charges ten incense")
	check(sim.targets.size() + sim.tide.pending.size() >= count + 8 and session.reinforce_count == 1,"K7 Reinforcement appends eight source-spawn ghosts")
	funds = session.incense
	check(not session.reinforce().ok and session.incense == funds,"K7 Cooldown blocks immediate reinforcement without spending")
	_tick(30.1)
	session.incense = 100
	check(session.reinforce().ok,"Reinforcement becomes available after real cooldown")
	_tick(30.1)
	session.incense = 100
	check(session.reinforce().ok and session.reinforce_count == 3,"Third reinforcement is available at declared limit")
	_tick(30.1)
	funds = session.incense
	check(not session.reinforce().ok and session.incense == funds,"K7 Per-battle reinforcement limit prevents unlimited ghost farming")
	await _shot("06-mutation-source-flow")

func _ui_inputs() -> void:
	panel = combat.get_node("Decisions")
	session.enter_debug()
	panel.start_battle("shouxiang")
	sim.set_physics_process(false)
	Clock.set_paused(true)
	await get_tree().process_frame
	check(not panel.prebattle.visible and session.running,"K8 Prebattle guard seat starts through the actual UI")
	await _key(KEY_SPACE)
	check(not Clock.paused,"K1 Space resumes battle")
	await _key(KEY_Q)
	check(Clock.paused and panel.panel.visible,"K1 Opening purchase with Q during combat automatically pauses")
	check(panel.buttons.has("buy_T01") and panel.buttons.has("buy_T02") and panel.buttons.has("buy_T04"),"K2 Purchase UI exposes the three costed troop cards")
	var labels := _all_text(panel.content)
	check(labels.contains("45") and labels.contains("7") and labels.contains("38") and labels.contains("射程"),"K2 Purchase cards display source HP, attack, defense and ranged range")
	panel.buttons.buy_T01.grab_focus()
	await _key(KEY_SPACE)
	check(not Clock.paused,"K1 Focused purchase button does not swallow Space pause shortcut")
	await _key(KEY_SPACE)
	check(Clock.paused,"K1 Focused purchase button Space pauses again")
	panel.open_purchase()
	await get_tree().process_frame
	var funds: float = session.incense
	await _button(panel.buttons.buy_T01)
	check(session.pending_purchase == "T01" and session.incense == funds - 5,"K1 Mouse purchase button invokes paid reservation while paused")
	await _click(Vector2(1000,690),MOUSE_BUTTON_RIGHT)
	check(session.pending_purchase.is_empty() and session.incense == funds,"K3 Right mouse cancels placement and refunds")
	panel.open_purchase()
	await get_tree().process_frame
	await _shot("01-purchase-cards")
	if capture:
		get_window().size = Vector2i(1280,720)
		await _shot("01b-purchase-720p")
		get_window().size = Vector2i(1920,1080)
	panel.close_panel()
	camera.set_left(6080)
	var human := _human("H17")
	Clock.set_paused(false)
	await _click_world(human.position - Vector2(0,40))
	check(Clock.paused and panel.selected == human,"K1 Real world unit click pauses and selects complete card")
	var info: String = panel.details.text
	check(info.contains(human.display_name) and info.contains(str(int(human.max_hp))) and info.contains("攻击") and info.contains("防御") and info.contains("速度") and info.contains("特性") and info.contains("香器") and info.contains("技艺") and info.contains("名帖"),"K10 Unit card has identity, four stats, skill cost, traits, tags and empty equipment slots")
	check(panel.portrait.texture != null,"K10 Selected card loads separate portrait asset")
	await _shot("03-complete-unit-card")
	await _key(KEY_E)
	check(panel.panel.visible and panel.buttons.has("upgrade_confirm"),"K4 E opens actual upgrade preview")
	labels = _all_text(panel.content)
	check(labels.contains(str(int(human.max_hp))) and labels.contains(str(int(human.max_hp + 15))) and labels.contains(str(int(human.defense + 2))) and not labels.contains("变异"),"K4 Guard upgrade preview shows stat changes without mutation main command")
	await _shot("03b-upgrade-preview")
	panel.buttons.upgrade_confirm.grab_focus()
	await _key(KEY_SPACE)
	check(not Clock.paused,"K1 Focused upgrade button still permits Space resume")
	await _key(KEY_SPACE)
	await _button(panel.buttons.upgrade_confirm)
	check(human.upgrade_level == 1,"K1 Mouse confirms previewed upgrade while paused")
	panel.close_panel()
	panel.select_unit(_human("H01"))
	await _key(KEY_R)
	check(panel.current_panel == "ritual" and Clock.paused,"K1 R opens paid ritual decision list while paused")
	panel.close_panel()
	await _key(KEY_F)
	check(panel.current_panel == "repair" and Clock.paused,"K1 F opens real door repair decision list while paused")
	await _shot("05b-repair-menu")
	panel.close_panel()
	await _pad(6)
	check(not Clock.paused,"S4 Controller pause button resumes battle")
	await _pad(6)
	check(Clock.paused,"S4 Controller pause button pauses battle")
	await _pad(8)
	check(Clock.resume_scale == 2,"S4 Controller selects 2x")
	await _pad(7)
	check(Clock.resume_scale == 1,"S4 Controller selects 1x")
	await _pad(10)
	check(panel.selected != null and Clock.paused,"S4 Controller cycles to next unit and opens its card")
	await _pad(2)
	check(panel.current_panel == "commands" and panel.buttons.command_BUY.has_focus(),"S4 Controller opens the battle command list with keyboard-free focus")
	await _pad(0)
	check(panel.current_panel == "purchase" and panel.buttons.buy_T01.has_focus(),"S4 Controller confirms purchase from the command list")
	panel.close_panel()
	await _button(hud.buttons.two)
	check(Clock.resume_scale == 2 and Clock.paused,"K1 Mouse 2x changes chosen speed without advancing paused time")
	await _button(hud.buttons.one)
	check(Clock.resume_scale == 1,"K1 Mouse 1x restores speed")
	var snapshot := _snapshot()
	sim.set_physics_process(true)
	await get_tree().create_timer(0.15).timeout
	check(_snapshot() == snapshot,"K1 Paused clock freezes resource regen, countdown, AI, HP, projectiles and channel")
	await _button(hud.buttons.pause)
	await get_tree().create_timer(0.15).timeout
	check(_snapshot() != snapshot,"K1 Mouse resume restarts same shared battle")
	Clock.set_paused(true)
	sim.set_physics_process(false)
	# Explicit debug handoff is tested from an active session, in addition to P3 regression's opt-out.
	await _key(KEY_F5)
	check(not session.active and sim.tide.preset == "preset_empty_path","K11 F5 exits active decisions and starts genuine P3 empty-path debug")
	var before: float = sim.simulation_time
	_tick(1)
	check(sim.simulation_time > before,"K11 Debug handoff does not leave P3 simulation frozen by session gate")
	session.enter_debug()
	panel.start_battle("duoming")
	sim.set_physics_process(false)
	Clock.set_paused(true)
	panel.select_unit(_ghost())
	panel.open_mutation()
	await get_tree().process_frame
	check(panel.buttons.has("mutate_G09") and panel.buttons.has("mutate_G12"),"K7 Attacker panel offers upper and breaker mutations")
	await _shot("07-attacker-commands")

func _all_text(node: Node) -> String:
	var text := ""
	if node is Label or node is BaseButton:
		text += str(node.text) + "\n"
	for child in node.get_children():
		text += _all_text(child)
	return text

func _decision(action: String, payload: Dictionary, response: Dictionary) -> void:
	command_script.append({"at":snappedf(sim.simulation_time,0.001),"action":action,"args":payload,"ok":response.ok,"reason":response.reason,"incense":snappedf(session.incense,0.001),"names":session.names})

func _complete_battle(mode: String) -> void:
	panel.close_panel()
	_start(mode)
	command_script = []
	var samples: Array[Dictionary] = []
	var next_sample := 0.0
	var next_decision := 0.0
	var safe := true
	var smooth := true
	var second_mutation := false
	var replay_frame := 0
	var next_replay := 0.0
	if capture:
		DirAccess.make_dir_recursive_absolute("res://exports/p4-replays/" + mode)
		for filename in DirAccess.get_files_at("res://exports/p4-replays/" + mode):
			if filename.begins_with("frame-") and filename.ends_with(".png"):
				DirAccess.remove_absolute("res://exports/p4-replays/%s/%s" % [mode,filename])
	await _shot("08-%s-start" % mode)
	# No actor/HP/structure/resource/rule edits from this start to result. All choices go through public session commands.
	if mode == "duoming":
		var candidate := _ghost()
		_decision("mutate",{"unit":candidate.instance_id,"form":"G12"},session.mutate(candidate,"G12"))
	Clock.set_paused(false)
	for battle_step in 21660:
		if not session.result.is_empty():
			break
		if sim.simulation_time >= next_decision:
			Clock.set_paused(true)
			next_decision += 1
			if mode == "shouxiang":
				# Mend the current pressure line when it has lost at least one repair's worth.
				if session.repair_jobs.is_empty() and session.incense >= 6:
					for door_id in ["door_outer","door_inner","door_hall","door_gallery"]:
						var door: Node2D = world.get_node(door_id)
						if not door.destroyed and door.max_durability - door.durability >= 300:
							_decision("repair",{"door":door_id},session.repair(door_id))
							break
				var caster := _human("H01")
				if caster != null and not caster.brain.channel.active and session.incense >= 4:
					for candidate in sim.targets:
						if caster.brain.channel.valid_target(sim,caster,candidate):
							_decision("start_ritual",{"caster":caster.instance_id,"target":candidate.instance_id},session.start_ritual(caster,candidate))
							break
			else:
				if not second_mutation and session.incense >= 12:
					var white: Node2D = null
					for candidate in sim.targets:
						if candidate.unit_id == "G01" and not candidate.dead and (white == null or candidate.position.x < white.position.x):
							white = candidate
					if white != null:
						var response: Dictionary = session.mutate(white,"G09")
						_decision("mutate",{"unit":white.instance_id,"form":"G09"},response)
						second_mutation = response.ok
				if second_mutation and session.incense >= 10 and session.reinforce_left <= 0 and session.reinforce_count < 3:
					_decision("reinforce",{},session.reinforce())
		Clock.set_paused(false)
		var previous: Dictionary = {}
		for human in sim.humans:
			previous[human.instance_id] = human.position
		sim.advance(1.0/60)
		for human in sim.humans:
			safe = safe and world.inside_base(human.position)
			if previous.has(human.instance_id):
				smooth = smooth and human.position.distance_to(previous[human.instance_id]) <= Rules.body_to_px(Rules.RETREAT_SPEED)/60 + 0.1
		if sim.simulation_time >= next_sample:
			next_sample += 10
			samples.append({"at":snappedf(sim.simulation_time,0.01),"humans":sim.humans.size(),"ghosts":sim.targets.size(),"incense":snappedf(session.incense,0.01),"names":session.names,"doors":_doors()})
		if capture and sim.simulation_time >= next_replay:
			next_replay += 2
			camera.set_left(6080)
			await get_tree().process_frame
			RenderingServer.force_draw(true)
			get_viewport().get_texture().get_image().save_png("res://exports/p4-replays/%s/frame-%04d.png" % [mode,replay_frame])
			replay_frame += 1
		if capture and sim.simulation_time >= 120 and sim.simulation_time < 120.02:
			camera.set_left(6080)
			await _shot("08-%s-120s" % mode)
	check(not session.result.is_empty(),"K9 Complete unmodified %s battle reaches settlement" % mode)
	check(session.result.get("outcome","") == "victory","G0 %s designated roster wins using only public decisions" % mode)
	check(not session.result.get("reason","").is_empty(),"K9 %s result explains winning or losing line" % mode)
	check(safe and smooth,"G0 %s full run preserves inside-base humans and continuous movement" % mode)
	var result: Dictionary = session.result.duplicate(true)
	var funds: float = session.incense
	var actor_count: int = sim.humans.size() + sim.targets.size()
	check(not session.purchase("T01").ok and not session.reinforce().ok and session.incense == funds and sim.humans.size() + sim.targets.size() == actor_count,"Ended %s battle rejects further commands without state changes" % mode)
	await get_tree().process_frame
	if capture:
		# The ending panel pauses Clock after HUD's process callback; render the next
		# frame so the final movie sample includes the settled pause indicator too.
		await get_tree().process_frame
		RenderingServer.force_draw(true)
		get_viewport().get_texture().get_image().save_png("res://exports/p4-replays/%s/frame-%04d.png" % [mode,replay_frame])
		replay_frame += 1
	var ending_text := _all_text(panel.ending)
	var expected_details: String = tr("P4_END_DETAILS") % [tr("P4_SEAT_" + mode.to_upper()),tr(str(result.get("reason",""))),session.incense,session.names,session.remaining]
	var expected_outcome: String = tr("P4_END_VICTORY" if result.get("outcome","") == "victory" else "P4_END_DEFEAT")
	check(panel.ending.visible and ending_text.contains(expected_details) and ending_text.contains(expected_outcome) and hud.goal_label.text.contains(expected_outcome),"S2 %s visible ending and HUD match this battle mode, outcome, reason and exact resource summary" % mode)
	runs.append({"mode":mode,"result":result,"seconds":sim.simulation_time,"script":command_script.duplicate(true),"samples":samples,"human_base_safe":safe,"continuous_movement":smooth,"doors":_doors(),"events":sim.events.duplicate(true),"tide_milestones":sim.tide.milestones.duplicate(true),"cheat_mutations":[],"replay_frames":replay_frame,"replay_sample_sim_seconds":2,"ending_text":ending_text})
	await get_tree().process_frame
	await _shot("09-%s-result" % mode)

func _doors() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for door in world.doors:
		values.append({"id":str(door.name),"hp":door.durability,"max":door.max_durability,"destroyed":door.destroyed})
	return values

func _ending_rules() -> void:
	_start()
	session.names = 0 # Isolated defeat-line fixture; not one of the two full battles.
	_tick(9.9)
	check(session.result.is_empty() and session.extinguish_left > 0 and session.warnings.has("P4_WARN_REGISTER_EXTINGUISHING"),"Name depletion enters visible ten-second recovery window before defeat")
	session.names = 1
	_tick(0.1)
	check(session.extinguish_left == 10 and session.result.is_empty(),"Recovering one name resets the extinction window")
	session.names = 0
	_tick(10.1)
	check(session.result.get("reason","") == "P4_END_REGISTER_EXTINGUISHED" and session.result.get("outcome","") == "defeat","S2 Exhausted name window produces explicit extinction defeat")
	var funds: float = session.incense
	var caster := _human("H01")
	var ghost := _ghost()
	check(not session.purchase("T01").ok and not session.deploy_at("post_gate_inner").ok and not session.upgrade(caster).ok and not session.equip(caster).ok and not session.start_ritual(caster,ghost).ok and not session.repair("door_outer").ok and not session.mutate(ghost,"G12").ok and not session.reinforce().ok and session.incense == funds,"All decision APIs reject commands after settlement without cost")
	_start()
	sim.clear_targets()
	sim.tide.pending.clear()
	sim.tide.preset = "fixture"
	caster = _human("H01")
	ghost = _ritual_target()
	funds = session.incense
	var accepted: bool = caster.brain.request_channel(ghost)
	check((accepted and session.incense == funds - 4) or (not accepted and session.incense == funds),"Legacy developer channel entry cannot bypass active P4 ritual payment")
	caster.brain.channel.cancel("fixture_reset")
	_start()
	sim.clear_targets()
	sim.tide.pending.clear()
	sim.tide.preset = "fixture"
	caster = _human("H01")
	ghost = _ritual_target()
	check(session.start_ritual(caster,ghost).ok,"Movement-interruption fixture pays for valid ritual")
	caster.position.x += 3
	_tick(0.1)
	check(not caster.brain.channel.active and session.incense < 17,"Ritual movement interrupts without returning its paid cost")
	_start()
	sim.clear_targets()
	sim.tide.pending.clear()
	sim.tide.preset = "fixture"
	caster = _human("H01")
	ghost = _ritual_target()
	session.start_ritual(caster,ghost)
	ghost.position.x -= 9 * 80
	_tick(0.1)
	check(not caster.brain.channel.active and session.incense < 17,"Ritual target leaving range interrupts without refund")

func _pad(index: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _restart_ui_regression() -> void:
	check(panel.ending.visible,"Direct-restart regression begins with a visible previous battle ending")
	var response: Dictionary = session.start_battle("shouxiang")
	await get_tree().process_frame
	check(response.ok and not panel.ending.visible and panel.last_result.is_empty(),"Direct session restart clears previous ending and its result signature")
	sim.set_physics_process(false)
	Clock.set_paused(true)
	session.names = 0 # Isolated UI restart fixture after both full runs.
	_tick(10.1)
	await get_tree().process_frame
	check(panel.ending.visible and _all_text(panel.ending).contains(tr("P4_END_REGISTER_EXTINGUISHED")),"Next direct-started battle can show its own fresh ending")
