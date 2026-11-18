extends Node
## Acceptance fixtures are kept separate from complete nights. Complete nights only call actual NightRun / BattleSession decisions.
var checks := 0
var failures := 0
var results: Array[Dictionary] = []
var nights: Array[Dictionary] = []
var captures: Array[String] = []
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
var fallen_named:Dictionary={}
var recruited_names:Dictionary={}
var named_recruit_violations:Array[String]=[]

func _ready() -> void:
	var archive_dir:="/tmp/ye-ci-p7-night-archives"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-prefix="):archive_dir="/tmp/ye-ci-"+arg.trim_prefix("--report-prefix=")+"-archives"
	archive_dir += "-render" if OS.get_cmdline_user_args().has("--capture") else "-test"
	load("res://src/replay/ReplayArchive.gd").directory=archive_dir
	DirAccess.make_dir_recursive_absolute(archive_dir)
	for file in DirAccess.get_files_at(archive_dir):
		if file.ends_with(".json"):DirAccess.remove_absolute(archive_dir+"/"+file)
	capture=OS.get_cmdline_user_args().has("--capture")
	_run.call_deferred()
func _run() -> void:
	if capture:get_window().size=Vector2i(1920,1080)
	check(Data.errors.is_empty(),"P7 G1 current source validates")
	if not OS.get_cmdline_user_args().has("--duoming-only"):await _complete_night("shouxiang")
	if not OS.get_cmdline_user_args().has("--shouxiang-only"):await _complete_night("duoming")
	_finish()
func _finish() -> void:
	var prefix:="p7-night"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-prefix="):prefix=arg.trim_prefix("--report-prefix=")
	FileAccess.open("res://docs/phase-reports/"+prefix+("-render" if capture else "-test")+"-results.json",FileAccess.WRITE).store_string(JSON.stringify({"phase":"P7Night","rules_hash":load("res://src/replay/BattleRecord.gd").rules_hash(),"archive_directory":load("res://src/replay/ReplayArchive.gd").directory,"checks":checks,"failures":failures,"results":results,"nights":nights,"replays":night_replay_evidence,"screenshots":captures,"fixture_policy":"Both complete growth-enabled nights use new_growth_run, real source waves, actual night choices and paid Session commands only. No resources, HP, position, structures, timers or rules are rewritten."},"\t")+"\n")
	print("P7Night RESULT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	results.append({"check":message,"passed":condition})
	if not condition:
		failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL",message])

func _shot(id: String, fixture := false) -> void:
	if not capture:
		return
	DirAccess.make_dir_recursive_absolute("res://docs/phase-reports/p7-night-shots")
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
	var path := "res://docs/phase-reports/p7-night-shots/%s.png" % id
	check(get_viewport().get_texture().get_image().save_png(path) == OK,"Actual renderer screenshot: " + id)
	captures.append(path)
	if layer != null:
		layer.queue_free()

func _all_text(node: Node) -> String:
	var text := ""
	if node is Label or node is BaseButton:
		text += str(node.text) + "\n"
	for child in node.get_children():
		text += _all_text(child)
	return text

func _first_target(value: RefCounted, offer: Dictionary) -> String:
	if not offer.get("requires_target",false):
		return ""
	var options: Array = value.target_options(str(offer.id))
	if options.is_empty():
		return ""
	return str(options[0].get("uid", "")) if options[0] is Dictionary else str(options[0])

func _unit(scene: Node2D, id: String) -> Node2D:
	for unit in scene.get_node("Simulation").humans + scene.get_node("Simulation").targets:
		if unit.unit_id == id:
			return unit
	return null

func _new_host(save_suffix: String) -> Node:
	if is_instance_valid(host):
		remove_child(host)
		host.queue_free()
	var scene: Node = load("res://scenes/night/Night.tscn").instantiate()
	scene.save_path = "/tmp/ye-ci-p7-night-%d-%s.json" % [OS.get_process_id(),save_suffix]
	add_child(scene)
	host = scene
	return scene

func _offer_score(offer:Dictionary)->int:
	if offer.category=="survival":return 60
	if offer.effect.kind=="recruit":
		var id:String=offer.effect.unit_id
		if id in ["H11","H25","H21","T02"]:return 90
		return 45
	if offer.effect.kind=="growth_item":
		var id:String=offer.effect.id
		if id in ["J01","J02","I03","I09","I13","N01","N04","N05","Y09","Y14"]:return 70
		if id in ["I20","I19"]:return 1
		return 30
	return 20
func _pick_reward(value:RefCounted)->Dictionary:
	var scored:Array[Dictionary]=[]
	for offer in value.reward_options():
		if not offer.get("allowed",true):continue
		if offer.effect.kind=="recruit" and _named_dead(str(offer.effect.unit_id)):continue
		var target:=_first_target(value,offer)
		if offer.get("requires_target",false) and target.is_empty():continue
		scored.append({"offer":offer,"target":target,"score":_offer_score(offer)})
	scored.sort_custom(func(a,b):return a.score>b.score)
	return scored[0] if not scored.is_empty() else {}
func _record_choice(action: String, args: Dictionary, ok := true, reason := "") -> void:
	choices.append({"node":str(host.run.state.get("current_node_id","")),"phase":str(host.run.state.phase),"battle_seconds":sim.simulation_time if is_instance_valid(sim) and is_instance_valid(host.combat) else 0,"action":action,"args":args,"ok":ok,"reason":reason,"incense":session.incense if is_instance_valid(session) and is_instance_valid(host.combat) else host.run.state.incense,"names":session.names if is_instance_valid(session) and is_instance_valid(host.combat) else host.run.state.names})

func _complete_night(mode: String) -> void:
	_new_host("full-" + mode)
	# The public growth button now starts a P8 full-roster night. Historical P7
	# regression keeps its original rules explicitly and never opens player codex IO.
	var legacy=load("res://src/night/NightRun.gd").new()
	var started:Dictionary=legacy.new_growth_run(mode,"P7-G1-FULL-" + mode)
	check(started.ok and not legacy.state.get("roster_enabled",false),"P7 regression explicitly starts legacy growth rules without the P8 roster")
	host._dispose_battle()
	host.run=legacy
	host.panel.show_intro=false
	check(host._save_state().ok,"P7 legacy host saves only its PID-isolated temporary checkpoint")
	host.refresh()
	fallen_named.clear();recruited_names.clear();named_recruit_violations.clear()
	check(host.run.state.get("growth_enabled",false) or host.run.state.has("growth"),"G1 New ordinary night explicitly enables real growth: "+mode)
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
				var offers:Array=host.run.market_options()
				offers.sort_custom(func(a,b):return _offer_score(a)>_offer_score(b))
				for offer in offers:
					if offer.get("allowed",false) and not (offer.effect.kind=="recruit" and _named_dead(str(offer.effect.unit_id))) and _offer_score(offer)>=60 and host.run.state.incense>=float(offer.cost)+4:
						var target:=_first_target(host.run,offer)
						if offer.get("requires_target",false) and target.is_empty():continue
						host.buy_offer(str(offer.id),target);_record_choice("buy_offer",{"id":offer.id,"target":target});break
				host.leave_node();_record_choice("leave_market",{})
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
				if is_instance_valid(host.combat):host.combat.get_node("Simulation").set_physics_process(false)
				Clock.set_paused(true)
				mercy_used = true
				_record_choice("use_mercy",{})
			_:
				check(false,"Unexpected full-night phase: " + phase)
				break
		await get_tree().process_frame
	var summary: Dictionary = host.run.summary()
	check(named_recruit_violations.is_empty(),"G1 No named character is purchased again after death or repeatedly recruited")
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
	nights.append({"mode":mode,"seed":summary.seed,"visited":visited,"phases":phases,"summary":summary,"battles":battles,"choices":choices.duplicate(true),"actual_battle_seconds":elapsed,"minutes":elapsed / 60.0,"mercy_used":mercy_used,"named_recruit_violations":named_recruit_violations.duplicate(),"recruited_names":recruited_names.keys(),"too_short_battles":too_short,"too_long_battles":too_long,"cheat_mutations":[]})
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
	for fallen in host.run.state.fallen:
		if str(fallen.id).begins_with("H"):fallen_named[str(fallen.id)]=true
	sim.unit_fallen.connect(func(unit):
		if unit.unit_id.begins_with("H"):fallen_named[unit.unit_id]=true)
	var before_roster: Array = host.run.state.roster.duplicate(true)
	check(is_equal_approx(session.incense,host.run.state.incense) and is_equal_approx(session.names,host.run.state.names),"K5 %s %s enters with carried night resources" % [mode,node_id])
	check(is_equal_approx(session.rules.incense_regen,.24) and host.run.config.battle_profiles[str(node.profile_id)].victory_incense==12,"G1 Ordinary growth node uses public 0.24/s and +12-victory curve")
	check(Rules.REFERENCE_MAP_WIDTH_PX == 9600 and camera.zoom == Vector2.ONE and Rules.UNIT_HEIGHT_PX == 80,"K9 Shared battle keeps G0 geometry and unit scale")
	var carry_by_uid: Dictionary = {}
	for owned in before_roster: carry_by_uid[str(owned.uid)] = owned
	var validated: Dictionary = {}
	for unit in sim.humans+sim.targets:
		var carry_uid:String=unit.get_meta("night_uid","")
		if carry_by_uid.has(carry_uid):
			var prior:Dictionary=carry_by_uid[carry_uid]
			check(unit.unit_id==prior.id and is_equal_approx(unit.hp,float(prior.hp)) and is_equal_approx(unit.max_hp,float(prior.max_hp)) and is_equal_approx(unit.attack,float(prior.attack)) and is_equal_approx(unit.defense,float(prior.defense)) and unit.upgrade_level==int(prior.upgrade_level) and unit.mutation_count==int(prior.mutation_count) and unit.growth.get("slots",{})==prior.get("growth",{}).get("slots",{}) and unit.growth.get("job_tags",[])==prior.get("growth",{}).get("job_tags",[]),"G1 Actual carried actor retains injury, stats, four slots and job tags before new inputs")
			validated[carry_uid]=true
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
			if human.unit_id == "H01":
				var answer: Dictionary = session.upgrade(human)
				_record_choice("upgrade",{"uid":human.get_meta("night_uid","")},answer.ok,answer.reason)
				upgraded = answer.ok
			if human.unit_id == "H01":
				var answer: Dictionary = session.execute_for(mode,"equip_item",{"unit_id":human.instance_id,"item_id":"I17"},"player")
				session.execute_for(mode,"equip_item",{"unit_id":human.instance_id,"item_id":"Y01","slot_index":0},"player")
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
					if answer.ok:
						session.execute_for(mode,"equip_item",{"unit_id":ghost.instance_id,"item_id":"I10"},"player")
						session.execute_for(mode,"equip_item",{"unit_id":ghost.instance_id,"item_id":"Y11","slot_index":0},"player")
					break
	if mode=="shouxiang":
		for unit in sim.humans:
			if unit.unit_id=="H01":
				while unit.upgrade_level<3 and session.incense>=float(session.rules.upgrade.cost):
					var answer:Dictionary=session.upgrade(unit);_record_choice("upgrade_ritual_line",{"unit":unit.instance_id},answer.ok,answer.reason)
		var desired:Array=[{"id":"H03","post":"post_rear"}] if node.type=="boss" else [{"id":"H25","post":"post_register"},{"id":"H01","post":"post_register"},{"id":"H11","post":"post_register"},{"id":"H21","post":"post_stair_head"}]
		for recruit in desired:
			var present:=false
			for unit in sim.humans:
				if unit.unit_id==recruit.id:present=true
			if present or _named_dead(str(recruit.id)) or session.incense<float(session.rules.purchases[recruit.id])+4:continue
			var bought:Dictionary=session.purchase(recruit.id)
			if bought.ok:
				var deployed:Dictionary=session.deploy_at(recruit.post)
				_record_choice("purchase_deploy",recruit,deployed.ok,deployed.reason)
				if not deployed.ok:session.cancel_purchase()
				else:
					if recruited_names.has(str(recruit.id)):named_recruit_violations.append(str(recruit.id))
					recruited_names[str(recruit.id)]=true
			break
	if node.type!="boss" or mode!="shouxiang":_apply_inventory(mode)
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
				if session.repair_jobs.is_empty() and session.incense >= 3.8:
					for door in sim.world.doors:
						var door_id:String=str(door.name)
						var useful_threshold:float=minf(float(session.rules.repair.heal),door.max_durability*.5)
						if not door.destroyed and door.max_durability-door.durability>=useful_threshold:
							var answer: Dictionary = session.repair(door_id)
							_record_choice("repair",{"door":door_id},answer.ok,answer.reason)
							if answer.ok: break
				var reading:Dictionary={}
				for caster in sim.humans:
					if caster.role=="ritual" and caster.brain.channel.active and is_instance_valid(caster.brain.channel.target):reading[caster.brain.channel.target.instance_id]=true
				for caster in sim.humans:
					var ritual_cost:float=session.growth.ritual_cost(caster,float(session.rules.ritual.cost))
					if caster.role == "ritual" and not caster.brain.channel.active and session.incense >= ritual_cost:
						var ritual_targets:Array=sim.targets.duplicate()
						ritual_targets.sort_custom(func(a,b):return a.unit_id in ["G12","G09"] and b.unit_id not in ["G12","G09"])
						for target in ritual_targets:
							if not reading.has(target.instance_id) and caster.brain.channel.valid_target(sim,caster,target):
								var answer: Dictionary = session.start_ritual(caster,target)
								_record_choice("start_ritual",{"caster":caster.instance_id,"target":target.instance_id},answer.ok,answer.reason)
								if answer.ok:reading[target.instance_id]=true
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
			var focus_x:float=0
			for ghost in sim.targets:
				if not ghost.dead:focus_x=maxf(focus_x,ghost.position.x)
			camera.set_left(clampf(focus_x-960,0,7680))
			await _shot("11-%s-%s-live" % [mode,node_id])
	var actual_regen:float=session.rules.incense_regen
	var terminal_actors:Array=[]
	for unit in sim.humans+sim.targets+sim.corpses:
		terminal_actors.append({"id":unit.unit_id,"uid":unit.instance_id,"side":unit.side,"hp":unit.hp,"max_hp":unit.max_hp,"floor":unit.floor_id,"post":unit.current_post,"position":[unit.position.x,unit.position.y],"dead":unit.dead,"state":unit.ai_state})
	var budget_ledger:Array=session.ledger.duplicate(true)
	var growth_events:Array=session.growth.state.events.duplicate(true)
	var result: Dictionary = session.result.duplicate(true)
	var events: Array = sim.events.duplicate(true)
	var milestones: Array = sim.tide.milestones.duplicate(true)
	var summary: Dictionary = host.bridge.collect(combat,host.run)
	check(not result.is_empty() and result.outcome == "victory","K2 %s %s reaches actual battle victory" % [mode,node_id])
	check(persistence_ok and not validated.is_empty(),"K5 %s %s carried unit identities, stats, upgrades, equipment and mutations enter real combat" % [mode,node_id])
	check(safe and smooth,"K9 %s %s humans remain in-base with continuous AI movement" % [mode,node_id])
	await get_tree().process_frame
	check(host.run.state.phase in ["reward","mercy","ended"] and host.combat == null,"K2 Actual Night host collects battle and returns to night phase")
	return {"terminal_actors":terminal_actors,"budget_ledger":budget_ledger,"growth_events":growth_events,"node":node_id,"profile":str(node.profile_id),"seconds":summary.elapsed,"result":result,"starting_roster":before_roster,"surviving_roster":summary.roster,"fallen":summary.fallen,"samples":samples,"events":events,"milestones":milestones,"persistence_ok":persistence_ok,"validated_carried_units":validated.size(),"human_base_safe":safe,"continuous_movement":smooth,"upgraded_in_first_battle":upgraded,"mutation_in_battle":mutation_done,"observed_ghost_ids":observed_ghost_ids.keys(),"battle_profile":host.run.config.battle_profiles[str(node.profile_id)].duplicate(true),"actual_incense_regen":actual_regen,"victory_incense_reward":host.run.config.battle_profiles[str(node.profile_id)].victory_incense}

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

func _apply_inventory(mode:String)->void:
	var engine=session.growth
	if mode=="shouxiang":
		var priest:Node2D=null;var guard:Node2D=null
		for unit in sim.humans:
			if unit.unit_id=="H01":priest=unit
			if unit.unit_id=="H25":guard=unit
		if priest!=null:
			_move_item_to("N05",priest)
			if not engine.has(priest,"N05"):_move_item_to("N01",priest)
		if guard!=null:
			for id in ["I09","I13","I01"]:
				if guard.growth.get("slots",{}).get("censer","")=="":_move_item_to(id,guard)
	for unit in sim.humans:
		for job in ["J01","J02"]:
			if Data.growth_rules.jobs[job].source_id==unit.unit_id and int(engine.state.inventory.get(job,0))>0 and job not in unit.growth.get("job_tags",[]):
				var answer:Dictionary=session.execute_for(mode,"stamp_job",{"unit_id":unit.instance_id,"job_id":job},"player")
				_record_choice("stamp_job",{"unit":unit.instance_id,"job":job},answer.ok,answer.reason)
	for id in engine.state.inventory.keys():
		if not Data.growth_rules.items.has(id) or id in ["I19","I20"]:continue
		var slot:String=Data.growth_rules.items[id].slot
		var candidates:Array=(sim.humans if mode=="shouxiang" else sim.targets).duplicate()
		if id in ["I17","I11","Y01","Y03","Y13","N05"] or (id=="I10" and mode=="shouxiang"):
			candidates.sort_custom(func(a,b):return a.role=="ritual" and b.role!="ritual")
		elif id=="I03":candidates.sort_custom(func(a,b):return a.unit_id=="H17" and b.unit_id!="H17")
		elif id in ["N01","N04","Y02","Y09","Y11"]:candidates.sort_custom(func(a,b):return a.unit_id=="H09" and b.unit_id!="H09")
		for unit in candidates:
			if int(engine.state.inventory.get(id,0))<=0:break
			if unit.dead or not engine.eligible(unit):continue
			if id=="I10" and mode=="shouxiang" and unit.role!="ritual":continue
			engine.ensure(unit)
			var index:=0
			if slot=="art":
				if id in unit.growth.slots.arts:continue
				index=unit.growth.slots.arts.find("")
				if index<0:continue
			elif str(unit.growth.slots[slot])!="":continue
			var answer:Dictionary=session.execute_for(mode,"equip_item",{"unit_id":unit.instance_id,"item_id":id,"slot_index":index},"player")
			_record_choice("equip_growth_inventory",{"unit":unit.instance_id,"item":id,"slot_index":index},answer.ok,answer.reason)

func _move_item_to(id:String,target:Node2D)->void:
	var engine=session.growth
	engine.ensure(target)
	if engine.has(target,id):return
	var slot:String=Data.growth_rules.items[id].slot
	if int(engine.state.inventory.get(id,0))<=0:
		for holder in sim.humans:
			if holder!=target and engine.has(holder,id):
				var removed:Dictionary=session.execute_for("shouxiang","unequip_item",{"unit_id":holder.instance_id,"slot":slot},"player")
				_record_choice("transfer_unequip",{"unit":holder.instance_id,"item":id},removed.ok,removed.reason);break
	if int(engine.state.inventory.get(id,0))>0:
		var applied:Dictionary=session.execute_for("shouxiang","equip_item",{"unit_id":target.instance_id,"item_id":id},"player")
		_record_choice("transfer_equip",{"unit":target.instance_id,"item":id},applied.ok,applied.reason)

func _named_dead(id:String)->bool:
	if not id.begins_with("H"):return false
	if fallen_named.has(id):return true
	for unit in host.run.state.fallen:
		if unit.id==id:return true
	return false
