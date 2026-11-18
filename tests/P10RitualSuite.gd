extends SceneTree
## Isolated authored positions, with real commands, costs, simulation and settlement.
var rituals: Script
var chunks: Script
var growth_night: Script
var snapshot: Script
var record: Script
const TICK := 1.0/60.0
var data: Node
var rules: Node
var clock: Node
var combat: Node2D
var sim: Node2D
var session: Node
var checks: Array[Dictionary] = []
var captures: Array[String] = []
var failures := 0
var output: String

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	data = root.get_node("Data")
	rules = root.get_node("Rules")
	clock = root.get_node("Clock")
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else ""
	if not (output.begins_with("/private/tmp/ye-ci-p9-") or output.begins_with("/tmp/ye-ci-p9-")) or not is_instance_valid(data.codex_store) or data.codex_store.path != output.path_join("state/codex.json"):
		print("FAIL P10 ritual fixtures require isolated state")
		quit(2)
		return
	rituals = load("res://src/data/RitualCatalog.gd")
	chunks = load("res://src/data/ChunkCatalog.gd")
	growth_night = load("res://src/growth/GrowthNight.gd")
	snapshot = load("res://src/night/BattleSnapshot.gd")
	record = load("res://src/replay/BattleRecord.gd")
	if not _check("catalog",data.errors.is_empty() and data.ritual_rules.size() == 12,"Twelve executable catalog entries load",{"errors":data.errors}):
		_finish()
		return
	_catalog()
	_baseline()
	_water()
	await _fire()
	await _ward()
	_ward_carry()
	_faces()
	_bridge()
	_quiet()
	_naming()
	_cold()
	_upper()
	_borrow()
	_seep()
	_finish()

func _catalog() -> void:
	var config: Dictionary = growth_night.configure(data.night_rules)
	var baseline: Dictionary = rituals.row("example_incense")
	_check("R01",baseline.id == "R01" and baseline.params.is_empty() and baseline.reward_weights.is_empty(),"Legacy example is the unmodified baseline")
	for id in data.ritual_rules:
		if id == "R01": continue
		var rewards: Dictionary = config.rewards.duplicate(true)
		rituals.add_ritual_rewards(rewards,str(id))
		var seen := {}
		for reward in rewards.values():
			var weight: float = rituals.reward_weight(str(id),reward)
			if not is_equal_approx(weight,float(reward.weight)):
				seen[reward.id] = weight / float(reward.weight)
		_check(str(id),not seen.is_empty(),"At least one real reward weight changes",seen)
	_check("R11",is_equal_approx(rituals.event_weight("R11","borrowed_name"),3.0),"Borrowed Name risk/reward event weight is tripled")
	_check("R04",_recruit_weight(config.rewards,"R04","H14") == 3.0,"Gong guard added to the actual recruitment pool")
	_check("R05",_recruit_weight(config.rewards,"R05","G28") == 3.0,"Face thief added to the actual recruitment pool")

func _recruit_weight(source: Dictionary, id: String, unit_id: String) -> float:
	var rewards := source.duplicate(true)
	rituals.add_ritual_rewards(rewards,id)
	var card: Dictionary = rewards.get("p10_recruit_" + unit_id,{})
	return rituals.reward_weight(id,card) / float(card.weight) if not card.is_empty() else 0.0

func _fixture(id: String, extra: Array = [], first := true, ward_hp := -1.0, seed := "P10-fixture") -> bool:
	if is_instance_valid(combat):
		combat.free()
	combat = load("res://scenes/combat/Combat.tscn").instantiate()
	if not extra.is_empty():
		var layout: Array = chunks.CORE.duplicate()
		layout.append_array(extra)
		if not _check(id,combat.configure_chunks(layout),"Authored chunks compose"):
			combat.free()
			return false
	root.add_child(combat)
	sim = combat.get_node("Simulation")
	session = combat.get_node("Session")
	sim.set_physics_process(false)
	sim.tide.config.waves = []
	if not _check(id,session.start_battle("shouxiang").ok,"Real battle session starts"):
		return false
	for actor in sim.humans + sim.targets + sim.corpses + sim.projectiles:
		actor.free()
	sim.humans.clear()
	sim.targets.clear()
	sim.corpses.clear()
	sim.projectiles.clear()
	sim.tide.pending.clear()
	session.configure_dual({"shouxiang":30.0,"duoming":20.0},"shouxiang")
	session.names = 8.0
	session.configure_roster(seed)
	clock.set_paused(true)
	return _check(id,session.configure_ritual(id,seed,first,ward_hp),"Selected ritual configures in the real battle")

func _baseline() -> void:
	if not _fixture("R01"): return
	var source := _human("H09",111.0)
	var target := _ghost("G10",112.0)
	var funds: float = session.incense
	session.advance(1.0)
	sim.deal_damage(source,target,"melee",20.0)
	var hit: Dictionary = sim.damage_log.back()
	_check("R01",is_equal_approx(session.incense-funds,float(session.rules.incense_regen)) and hit.multiplier == 1.0 and session.ritual_snapshot().is_empty(),
		"Baseline regeneration, melee and save state use original values",{"regen":session.incense-funds,"attack_factor":hit.multiplier})

func _water() -> void:
	if not _fixture("R02",["C05"]): return
	var caster := _human("H01",116.0)
	var target := _ghost("G10",114.0)
	var before: float = session.names
	var answer: Dictionary = session.start_ritual(caster,target)
	if _check("R02",answer.ok,"Paid reading accepts the real water ghost"):
		caster.brain.channel.advance(sim,caster,5.0)
	_check("R02",is_equal_approx(session.names-before,float(session.rules.ritual.reward_names)+1.0),"Completed reading pays one extra name",{"name_gain":session.names-before})
	var ally := _human("H09",68.0,5,"post_water_sluice")
	var water_ghost := _ghost("G10",70.0,5)
	var original_x := ally.position.x
	var drag: Dictionary = _command(water_ghost,"unit_skill",ally)
	var damage: Dictionary = sim.damage_log.back()
	var body_px: float = rules.body_to_px(float(session.roster.params(water_ghost).drag_body))
	var duration: float = float(session.roster.params(water_ghost).duration)
	_check("R02",drag.ok and is_equal_approx(ally.position.x-original_x,1.3*body_px) and is_equal_approx(damage.multiplier,1.3) and is_equal_approx(float(ally.growth.statuses.get("drag",{}).get("left",0.0)),1.3*duration),
		"Water lane boosts real damage, displacement and drag time",{"chunk":sim.world.chunk_at(water_ghost.position,5),"move_px":ally.position.x-original_x,"attack_factor":damage.multiplier,"drag":ally.growth.statuses.get("drag",{})})
	sim.tide.config.waves = [{"at":0.0,"G01":64}]
	sim.tide.wave_index = 0
	sim.tide._schedule()
	var signature: Array = sim.tide.pending.duplicate()
	_check("R02",signature.count("G10") > 0 and signature.count("G01") > 0,"Actual scheduled wave uses seeded G10 weighting",{"water_ghosts":signature.count("G10"),"total":signature.size()})
	if not _fixture("R02"): return
	sim.tide.config.waves = [{"at":0.0,"G01":64}]
	sim.tide.wave_index = 0
	sim.tide._schedule()
	_check("R02",signature == sim.tide.pending,"Same seed reproduces the scheduled mix")

func _fire() -> void:
	if not _fixture("R03",["C11"]): return
	_human("H01",109.0)
	var caster := _human("H20",93.5,0,"post_stove")
	var ally := _human("T01",94.7)
	var target := _ghost("G12",95.0)
	var funds: float = session.incense
	session.advance(1.0)
	_check("R03",is_equal_approx(session.incense-funds,1.5*float(session.rules.incense_regen)),"Actual resource ticks regenerate fifty percent faster",{"regen":session.incense-funds})
	var answer := _command(caster,"unit_skill",target)
	var fire: Dictionary = _field("fire")
	_check("R03",answer.ok and is_equal_approx(float(fire.get("left",0)),2.0),"Burning petition leaves a two-second ground fire field",fire)
	await _capture("R03","p10-ritual-fire.png",6500.0)
	var hp: float = ally.hp
	var enemy_hp: float = target.hp
	session.growth.advance(0.5)
	_check("R03",is_equal_approx(hp-ally.hp,1.5) and is_equal_approx(enemy_hp-target.hp,1.5),"Real ground fire harms both sides",{"ally_damage":hp-ally.hp,"ghost_damage":enemy_hp-target.hp})
	session.growth.advance(1.5)
	_check("R03",_field("fire").is_empty(),"Ground fire expires after exactly two seconds")
	var hearth: Node2D = sim.world.get_node("stove_hearth")
	sim.deal_damage(target,hearth,"structure",1000.0)
	session.roster.cooldown(caster,0.0)
	var recast := _command(caster,"unit_skill",target)
	var radius: float = _field("fire").get("radius",0.0)
	_check("R03",recast.ok and hearth.durability == 0 and is_equal_approx(float(fire.radius),1.25*radius),
		"An intact Stove Room hearth expands the same fire field, and destroying it removes that bonus",
		{"intact_radius":fire.radius,"broken_radius":radius})
	if not _fixture("R03"): return
	caster = _human("H26",114.0)
	ally = _human("T01",114.7)
	target = _ghost("G12",115.0)
	session.growth.state.inventory.I14 = 1
	var equipped: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":caster.instance_id,"item_id":"I14"},"player")
	answer = _command(caster,"unit_skill",target)
	hp = ally.hp
	enemy_hp = target.hp
	session.growth.advance(0.5)
	_check("R03",equipped.ok and answer.ok and ally.hp == hp and is_equal_approx(enemy_hp-target.hp,1.95),
		"Firecracker field spares Xiaoqing's allies and gains I14's thirty percent",{"ally_damage":hp-ally.hp,"ghost_damage":enemy_hp-target.hp})

func _ward() -> void:
	if not _fixture("R04",[],true,31.0): return
	_human("H01",114.0)
	var ward: Node2D
	for actor in sim.humans:
		if session.is_ritual_ward(actor): ward = actor
	var status: Dictionary = session.ritual_ward_status()
	var hud: Control = combat.get_node("CanvasLayer/HUD")
	hud._update_battle()
	if not _check("R04",is_instance_valid(ward) and status.hp == 31.0 and ward.current_post == "post_register" and hud.ward_status.visible and hud.ward_status.text.contains("31"),
		"Carry HP spawns a unique ward at legal cover and renders the ward's life in HUD",status):
		return
	await _capture("R04","p10-ritual-ward.png")
	var save: Dictionary = snapshot.capture(combat)
	var restored: Dictionary = snapshot.restore(combat,save)
	var wards := 0
	for actor in sim.humans:
		if session.is_ritual_ward(actor):
			ward = actor
			wards += 1
	if not _check("R04",restored.ok and wards == 1 and session.ritual_ward_status().hp == 31.0,"Battle snapshot restores the same ward and HP without a duplicate"):
		return
	var attacker := _ghost("G12",115.0)
	sim.deal_damage(attacker,ward,"melee",300.0)
	sim.advance(TICK)
	hud._update_battle()
	_check("R04",session.result.get("reason") == "P10_END_WARD_LOST" and not session.ritual_ward_status().alive and hud.ward_status.text.contains("阵亡"),
		"A lethal real attack instantly settles the protected life condition and updates the HUD",session.result)

func _ward_carry() -> void:
	var night_script: Script = load("res://src/night/NightRun.gd")
	var bridge_script: Script = load("res://src/night/NightBattleBridge.gd")
	var night: RefCounted = night_script.new()
	if not _check("R04",night.new_p10_run("shouxiang","fierce","P10 Ward carry","R04",[]).ok and night.choose_node("n01").ok,
		"Normal night domain opens the first battle with the chosen ritual"):
		return
	var bridge: RefCounted = _night_battle(night,bridge_script)
	if bridge == null:
		return
	var ward: Node2D = session.ritual_ward_actor()
	session.growth.state.inventory.I17 = 1
	var upgraded: Dictionary = session.upgrade(ward)
	var equipped: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":ward.instance_id,"item_id":"I17"},"player")
	ward.receive_damage(7.0)
	var expected_hp: float = ward.hp
	var expected_max: float = ward.max_hp
	if not _check("R04",upgraded.ok and equipped.ok and expected_hp > 40.0 and expected_hp < expected_max,
		"Real upgrade and equipped censer create measurable gear and wounds above unupgraded HP",{"hp":expected_hp,"max_hp":expected_max}):
		return
	session.remaining = TICK
	sim.advance(TICK)
	var won: Dictionary = bridge.collect(combat,night)
	if not _check("R04",won.outcome == "victory" and night.accept_battle(won).ok and night.state.ritual_ward.uid == bridge_script.RITUAL_WARD_UID,
		"First settlement keeps a unique ward record and proceeds to reward"):
		return
	_check("R04",not night.state.roster.any(func(actor): return actor.uid == bridge_script.RITUAL_WARD_UID),"The protected ward is absent from the spare party roster slots")
	var path := output.path_join("state/p10-ward-carry.json")
	var resumed: RefCounted = night_script.new()
	var saved: Dictionary = night.save(path)
	if not _check("R04",saved.ok and resumed.load_save(path).ok and resumed.state.ritual_ward.hp == expected_hp,
		"Night save reads back the wound and original ward identity from disk"):
		return
	var bad_copy: Dictionary = resumed.state.duplicate(true)
	bad_copy.ritual_ward.post = "court_center"
	var save_script: Script = load("res://src/night/NightSave.gd")
	var bad_path := output.path_join("state/p10-ward-invalid.json")
	save_script.save(bad_path,bad_copy)
	_check("R04",not night_script.new().load_save(bad_path).ok,"A night save with an altered ward post is rejected")
	var reward_taken := false
	for choice in resumed.reward_options():
		if resumed.choose_reward(str(choice.id)).ok:
			reward_taken = true
			break
	var next: Array = resumed.available_nodes()
	for step in 4:
		if next.is_empty() or not resumed.choose_node(str(next[0].id)).ok:
			break
		if resumed.state.phase == "battle":
			break
		match resumed.state.phase:
			"market": resumed.leave_node()
			"event": resumed.resolve_event(str(resumed.event_options()[0].id))
			"rest": resumed.finish_rest()
		next = resumed.available_nodes()
	if not _check("R04",reward_taken and resumed.state.phase == "battle","Reward and intervening stops lead to the next real battle"):
		return
	bridge = _night_battle(resumed,bridge_script)
	if bridge == null:
		return
	ward = session.ritual_ward_actor()
	var evidence := {"hp":ward.hp,"max_hp":ward.max_hp,"upgrade":ward.upgrade_level,"censer":ward.growth.slots.censer}
	_check("R04",ward.hp == expected_hp and ward.max_hp == expected_max and ward.upgrade_level == 1 and ward.growth.slots.censer == "I17",
		"Next battle restores the same ward's upgraded stats, equipped censer and exact wound",evidence)
	ward.receive_damage(999.0)
	sim.advance(TICK)
	var defeat: Dictionary = bridge.collect(combat,resumed)
	if _check("R04",resumed.accept_battle(defeat).ok and resumed.state.phase == "ended" and resumed.state.reason == "P10_END_WARD_LOST" and resumed.state.ritual_ward.hp == 0.0,
		"Ward death ends the night directly and persists the fallen record"):
		_check("R04",resumed.save(path).ok and night_script.new().load_save(path).ok,"The terminal fallen ward can be saved and reloaded")

func _night_battle(night: RefCounted, bridge_script: Script) -> RefCounted:
	if is_instance_valid(combat):
		combat.free()
	combat = load("res://scenes/combat/Combat.tscn").instantiate()
	if not _check("R04",combat.configure_chunks(night.current_node().chunk_ids),"Night node applies its generated layout"):
		combat.free()
		return null
	root.add_child(combat)
	sim = combat.get_node("Simulation")
	session = combat.get_node("Session")
	sim.set_physics_process(false)
	var bridge: RefCounted = bridge_script.new()
	var result: Dictionary = bridge.start(combat,night)
	clock.set_paused(true)
	if not _check("R04",result.ok and is_instance_valid(session.ritual_ward_actor()),"Shared NightBattleBridge spawns one ward",{"response":result.reason}):
		return null
	return bridge

func _faces() -> void:
	var values: Dictionary = {}
	for id in ["R01","R05"]:
		if not _fixture(id): return
		var caster := _human("H06",114.0)
		var ghost := _ghost("G01",115.0)
		var answer := _command(caster,"unit_skill",ghost)
		values[id] = float(ghost.growth.statuses.get("fear",{}).get("left",0))
		_check(id,answer.ok and values[id] > 0,"Real cold lantern applies fear to a faceless ghost",{"fear_seconds":values[id]})
	_check("R05",is_equal_approx(values.R05,1.5*values.R01),"Cold-lantern fear lasts fifty percent longer in Open Face",values)
	var mask := _human("H32",114.0)
	var ally := _human("H09",115.0)
	session.roster.status(ally,"face_theft",4.0,_ghost("G28",115.0))
	var names: float = session.names
	var ward := _command(mask,"unit_skill",ally)
	_check("R05",ward.ok and ally.roster.face_state == "faced" and session.names > names,
		"Temporary face restores the ally's face and credits names",{"gain":session.names-names})

func _bridge() -> void:
	if not _fixture("R01"): return
	_check("R06",not session.configure_ritual("R06","no-bridge"),"Bridge ritual rejects a scene with no bridge")
	if not _fixture("R06",["C07"]): return
	var bridge: Node2D = sim.world.get_node("stone_bridge")
	sim.tide.pending.append("G01")
	sim.tide._spawn_pending()
	var spawned: int = sim.tide.spawn_count
	var attacker: Node2D = sim.targets[-1]
	sim.deal_damage(attacker,bridge,"structure",700.0)
	sim.tide.config.waves = [{"at":0.0,"G01":3}]
	sim.tide.wave_index = 0
	sim.tide.before_step(TICK)
	var funds: float = session.incense_for("duoming")
	var paid: Dictionary = session.execute_for("duoming","reinforce")
	_check("R06",spawned > 0 and sim.tide.bridge_supply_cut() and sim.tide.spawn_count == spawned and paid.reason == "P10_BRIDGE_SUPPLY_CUT" and funds == session.incense_for("duoming"),
		"Destroying the actual bridge cuts scheduled and paid reinforcement on that route without charging",{"spawn_before_cut":spawned,"spawn_after_cut":sim.tide.spawn_count,"durability":bridge.durability})

func _quiet() -> void:
	if not _fixture("R07",["C12"]): return
	var guard := _human("H14",114.0)
	var crier := _ghost("G03",115.0)
	var bell := _ghost("G21",115.3)
	var shadow := _ghost("G04",114.5)
	session.roster.ghosts.advance(shadow,0.1)
	var hidden: bool = session.growth.is_hidden(shadow)
	var cry_hp: float = crier.hp
	var cry := _command(crier,"unit_skill",guard)
	_check("R07",cry.ok and cry_hp > crier.hp and hidden and not session.growth.is_hidden(shadow),
		"Cry backlashes and reveals hidden units within the same sound range",{"hp_loss":cry_hp-crier.hp,"shadow_revealed":not session.growth.is_hidden(shadow)})
	shadow.growth.statuses.erase("revealed")
	var bell_hp: float = bell.hp
	var chime := _command(bell,"unit_skill",guard)
	_check("R07",chime.ok and bell_hp > bell.hp and not session.growth.is_hidden(shadow),"Bell backlashes and retains the detection effect",{"hp_loss":bell_hp-bell.hp})
	shadow.growth.statuses.erase("revealed")
	var gong := _command(guard,"unit_skill",shadow)
	_check("R07",gong.ok and not shadow.growth.statuses.has("stun") and shadow.roster.statuses.has("taunt") and not session.growth.is_hidden(shadow),
		"Gong follows its pure taunt trait and still reveals hidden units")
	guard = _human("H14",99.15,2,"post_silent_window")
	var base_reach: float = session.roster.params(guard).radius_body
	shadow = _ghost("G04",99.15+base_reach*1.2,2)
	session.roster.ghosts.advance(shadow,0.1)
	gong = _command(guard,"unit_skill",shadow)
	_check("R07",gong.ok and shadow.roster.statuses.has("taunt") and not session.growth.is_hidden(shadow),
		"Silence Corridor extends the real sound reach beyond its normal limit",{"normal_radius":base_reach,"observed_at":base_reach*1.2})

func _naming() -> void:
	var times: Dictionary = {}
	for id in ["R01","R08"]:
		if not _fixture(id): return
		var caster := _human("H01",116.0)
		var target := _ghost("G10",114.0)
		var preview: Dictionary = session.preview_ritual(caster,target)
		var read: Dictionary = session.start_ritual(caster,target)
		times[id] = caster.brain.channel.duration
		_check(id,read.ok and is_equal_approx(times[id],float(preview.get("duration",-1))),"Paid channel and preview display the same duration",{"seconds":times[id]})
	_check("R08",is_equal_approx(times.R08,0.75*times.R01),"Actual reading is twenty-five percent faster",times)
	sim.tide.elapsed = 7.99
	sim.tide._schedule()
	var before := _ids(sim.targets)
	sim.tide.before_step(0.02)
	var after := _ids(sim.targets)
	_check("R08","G25" not in before and "G26" not in before and "G25" in after and "G26" in after,
		"Real first-battle source emits Name Clerk and Blank Page at the authored early time",{"before":before,"after":after,"seconds":sim.tide.elapsed})
	if not _fixture("R08",[],false): return
	sim.tide.before_step(9.0)
	_check("R08","G25" not in _ids(sim.targets),"First-battle opening injection does not repeat in later battles")

func _cold() -> void:
	if not _fixture("R09"): return
	var caster := _human("H20",114.0)
	var firework := _human("H26",114.4)
	var target := _ghost("G12",115.0)
	var funds: float = session.incense
	var hp: float = target.hp
	var weld := _command(caster,"unit_skill",target)
	var spark := _command(firework,"unit_skill",target)
	sim.deal_damage(caster,target,"fire",12.0)
	_check("R09",weld.reason == "P10_FIRE_FORBIDDEN" and spark.reason == weld.reason and session.incense == funds and hp == target.hp and _field("fire").is_empty(),
		"Fire skills and direct fire are blocked before costs or field creation")
	session.advance(1.0)
	sim.deal_damage(caster,target,"melee",20.0)
	var attack: Dictionary = sim.damage_log.back()
	_check("R09",is_equal_approx(float(attack.multiplier),1.2) and is_equal_approx(session.incense-funds,0.6*float(session.rules.incense_regen)),
		"Physical attacks are stronger and real incense ticks are sixty percent of normal",{"attack_factor":attack.multiplier,"regen":session.incense-funds})
	var talisman := _human("H17",72.5,0,"post_inner_gate")
	var breaker := _ghost("G12",73.2)
	var seal := _command(talisman,"unit_skill",breaker)
	var sealed: Dictionary = session.growth.state.seals
	var duration := float(sealed.values()[0].left) if not sealed.is_empty() else 0.0
	var door: Node2D = sim.world.get_node("door_inner")
	var durability: float = door.durability
	var breaker_hp: float = breaker.hp
	sim.deal_damage(breaker,door,"structure",28.0)
	_check("R09",seal.ok and is_equal_approx(duration,1.2*float(data.growth_rules.skills.seal_duration)) and door.durability == durability and is_equal_approx(breaker_hp-breaker.hp,7.2),
		"Actual cinnabar seal persists twenty percent longer, protects the door and reflects extra damage",
		{"seal_seconds":duration,"door_damage":durability-door.durability,"reflection":breaker_hp-breaker.hp,"response":seal.reason})

func _upper() -> void:
	if not _fixture("R10",["C05"]): return
	sim.tide.config.waves = [{"at":0.0,"G01":64}]
	sim.tide.wave_index = 0
	sim.tide._schedule()
	var chosen: Array = sim.tide.pending.duplicate()
	_check("R10",chosen.count("G07") > 0 and chosen.count("G09") > 0,"Upper-biased schedule really includes both climber roles",
		{"hanged":chosen.count("G09"),"children":chosen.count("G07")})
	sim.tide.pending.clear()
	_human("H01",116.0)
	_ghost("G10",68.0,5)
	sim.advance(TICK)
	_check("R10",session.ritual.upper_occupation == 0.0,"Water-lane floor index does not count as the upper story")
	var defender := _human("H09",108.0,3)
	_ghost("G09",111.0,3)
	for step in 12: sim.advance(TICK)
	_check("R10",session.ritual.upper_occupation == 0.0 and session.running,"Living defense contests the actual upper layer")
	defender.receive_damage(999.0)
	for step in 380:
		sim.advance(TICK)
		if not session.running: break
	_check("R10",session.result.get("reason") == "P10_END_UPPER_LOST" and "P10_WARN_UPPER_UNHELD" in session.warnings,
		"After the last upper defender falls, real simulation reaches the earlier upper failure line",session.result)

func _borrow() -> void:
	var counts: Dictionary = {}
	for id in ["R01","R11"]:
		if not _fixture(id): return
		var caster := _human("H23",116.0)
		var failures_in_sample := 0
		var fulfilled := 0
		var all_costs_match := true
		var expected := 7.0 if id == "R11" else 12.0
		for trial in 48:
			session.growth.rng.seed = ("P10 paired borrow %d" % trial).hash()
			session.names = 8.0
			session.incense = 30.0
			var paid := _command(caster,"borrow_god")
			all_costs_match = all_costs_match and paid.ok and session.incense == 30.0-expected and session.names == 7.0
			session.growth.advance(3.01)
			if "G30" in _ids(sim.targets): failures_in_sample += 1
			if "G11" in _ids(sim.humans): fulfilled += 1
			for unit in sim.humans.duplicate() + sim.targets.duplicate():
				if unit == caster: continue
				sim.humans.erase(unit)
				sim.targets.erase(unit)
				unit.free()
			sim._update_units()
		counts[id] = {"false_gods":failures_in_sample,"true_gods":fulfilled,"trials":48,"cost":expected}
		_check(id,all_costs_match and fulfilled+failures_in_sample == 48,"Forty-eight paid casts consume incense and names, then really spawn the outcome",counts[id])
	_check("R11",counts.R11.false_gods > counts.R01.false_gods,"The same forty-eight fixed seeds show increased false gods",counts)

func _seep() -> void:
	if not _fixture("R12",["C02","C10"]): return
	_human("H01",116.0)
	var before: float = session.names
	for step in 60: sim.advance(TICK)
	var loss: float = before-session.names
	_check("R12",is_equal_approx(loss,0.025) and "P10_WARN_NAME_SEEP" in session.warnings,
		"Nameless seep drains the real register from the opening second",{"name_loss":loss,"elapsed":sim.simulation_time})
	var plan: Dictionary = load("res://src/night/P10NightPlan.gd").generate_map("p10-nameless-stage","R12","B03",[])
	var boss_id: String = rituals.row("R12").boss_id
	var stage: Script = load("res://src/data/StageOptions.gd")
	_check("R12",boss_id == "B03" and not plan.is_empty() and stage.start(session,boss_id,[],"p10-nameless-stage") and "G32" in _ids(sim.targets),
		"The forced B03 stage opens with the real G32 nameless boss",{"chunks":plan.get("chunk_ids",[]),"boss_id":boss_id,"on_field":_ids(sim.targets)})

func _human(id: String,x: float,floor := 0,post := "post_register") -> Node2D:
	var unit: Node2D = sim.spawn_human(id,post)
	return _position(unit,x,floor)

func _ghost(id: String,x: float,floor := 0) -> Node2D:
	var unit: Node2D = sim.tide.spawn(id,3,rules.body_to_px(x))
	return _position(unit,x,floor)

func _position(unit: Node2D,x: float,floor: int) -> Node2D:
	unit.position = Vector2(rules.body_to_px(x),sim.world.floor_y(floor))
	unit.floor_id = floor
	unit.attacks_enabled = false
	unit.motion_enabled = false
	unit.sync_meta()
	return unit

func _command(unit: Node2D, action: String, target: Node2D = null) -> Dictionary:
	var seat := "duoming" if unit.side == "yegui" else "shouxiang"
	var args := {"unit_id":str(unit.instance_id)}
	if is_instance_valid(target): args.target_id = target.instance_id
	return session.execute_for(seat,action,args,"player" if seat == "shouxiang" else "ai")

func _field(kind: String) -> Dictionary:
	for field in session.growth.state.fields:
		if field.kind == kind: return field
	return {}

func _ids(units: Array) -> Array:
	return units.map(func(unit): return str(unit.unit_id))

func _capture(id: String, filename: String, camera_left := 7680.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	combat.get_node("BattleCamera").set_left(camera_left)
	sim.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var saved := capture.save_png(output.path_join(filename)) == OK
	if _check(id,saved,"Native frame captured",{"file":filename,"width":capture.get_width(),"height":capture.get_height()}):
		captures.append(filename)

func _check(id: String, passed: bool, label: String, evidence := {}) -> bool:
	checks.append({"ritual_id":id,"label":label,"passed":passed,"evidence":evidence.duplicate(true)})
	if not passed:
		failures += 1
		print("FAIL ",id," ",label," ",JSON.stringify(evidence))
	return passed

func _finish() -> void:
	var report := {"scope":"isolated fixed-step combat fixtures","engine":Engine.get_version_info().string,
		"checks":checks.size(),"failures":failures,"details":checks,"screenshots":captures,"rules_hash":record.rules_hash()}
	var file := FileAccess.open(output.path_join("p10-ritual-results.json"),FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(report,"\t")+"\n")
	file.close()
	print("P10 RITUALS ",checks.size()," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
