extends RefCounted
## Applies one night's owned roster and data profiles to the existing G0 simulator.
# The shipped P10 source at 10d8719. Its actions cannot be replayed under P11.
const PRE_CAMP_BRACE_RULES := "004f1b12a973af60eaa01012ad9adacd534a4970ee06fadcd4665ab5207e4237"
const PILOT_TRIAL_RULES := "8f8e0dc25f49973a78a9f6885d50cc3344c040d798c60955a52ba5050ecc0b6a"
const P11_REVIEW_RULES := "1f94085406a4fd4ca08507962d8998ba590faa5d11bcdd2db02a57ce89ae9b9c"
const P10_RULES := "8554a9e4eed596d0f7db6b2e434f17b7800ad5a9fc9e708edb53e1aa9a5f4671"
const GROWTH_CARRY_FIELDS := ["roster","growth","side","tags","skill_id","trait_id","skill_cost","skill_text","trait_text","display_name","role","profile","speed_stat"]
const RITUAL_WARD_UID := "ritual_ward"
const Snapshot = preload("res://src/night/BattleSnapshot.gd")
const Record = preload("res://src/replay/BattleRecord.gd")
const Archive = preload("res://src/replay/ReplayArchive.gd")
const Story = preload("res://src/night/NightStory.gd")
var recording: RefCounted
var replay_receipt: Dictionary = {}
var active_run: RefCounted
var active_combat: Node
var carry_queue: Array[Dictionary] = []
var tracked: Dictionary = {}
var departed: Array[Dictionary] = []
var encountered: Array[String] = []
var battle_profile: Dictionary = {}
var starting_roster: Array[Dictionary] = []
var _renown_peak := 0.0
var _story_attempt := 0
var _story_node := ""

func start(combat: Node, run: RefCounted) -> Dictionary:
	if run.state.get("phase","") != "battle":
		return {"ok":false,"reason":"P5_NOT_BATTLE"}
	if recording != null: recording.stop()
	replay_receipt.clear()
	active_run = run
	active_combat = combat
	var node: Dictionary = run.current_node()
	_story_attempt = run.state.stats.battles.size()
	_story_node = str(node.id)
	battle_profile = run.config.battle_profiles.get(node.get("profile_id",""),{}).duplicate(true)
	if battle_profile.is_empty():
		return {"ok":false,"reason":"P5_INVALID_PROFILE"}
	var sim: Node = combat.get_node("Simulation")
	var session: Node = combat.get_node("Session")
	var panel: Node = combat.get_node("Decisions")
	tracked.clear()
	departed.clear()
	encountered.clear()
	carry_queue.clear()
	starting_roster.assign(run.state.roster.duplicate(true))
	for spec in starting_roster:
		tracked[str(spec.uid)] = spec.duplicate(true)
	var callback := Callable(self,"_spawned")
	if sim.unit_spawned.is_connected(callback):
		sim.unit_spawned.disconnect(callback)
	sim.tide.config = Data.tide_rules.duplicate(true)
	sim.tide.config.waves = battle_profile.get("phase_waves",battle_profile.get("waves",[])).duplicate(true)
	if battle_profile.has("door_durability"):
		for key in battle_profile.door_durability:
			sim.tide.config.door_durability[key] = battle_profile.door_durability[key]
	sim.tide.config.night_queue_cap = true
	if run.state.mode == "duoming":
		sim.tide.config.capacity = int(run.config.roster_caps.duoming)
	session.rules = Data.battle_rules.duplicate(true)
	session.rules.duration = float(battle_profile.duration)
	_apply_build(session.rules,run.state.build)
	if run.state.has("opening_family"):
		var opening = preload("res://src/night/FactionOpening.gd")
		var family: Dictionary = opening.FAMILIES[run.state.opening_family]
		sim.tide.config.waves = opening.family_waves(sim.tide.config.waves,family)
		sim.tide.config.supply_id = family.id
		sim.tide.config.supply_slots = family.slots
		session.rules.reinforce.count = floori(float(Data.battle_rules.reinforce.count) / family.slots) + int(run.state.build.get("reinforce_count_delta",0))
	if run.state.has("growth"):
		session.rules.incense_regen = float(run.config.growth_night.incense_regen)
	sim.serial = 0
	panel.start_battle(run.state.mode)
	if not session.running:
		return {"ok":false,"reason":"P5_BATTLE_START_FAILED"}
	session.incense = float(run.state.incense)
	session.names = float(run.state.names)
	_renown_peak = session.names
	if run.story_enabled() and not session.renown_changed.is_connected(_note_renown):
		session.renown_changed.connect(_note_renown)
	if run.state.has("growth"): session.configure_growth(str(run.state.seed),run.state.growth)
	if node.id == "n10" and run.state.get("opening_faction","") == "守香司":
		var fallen_ids: Array = run.state.fallen.map(func(unit): return unit.id)
		if ["H01","H03","H06"].all(func(id): return id in fallen_ids) and "H07" not in fallen_ids:
			session.rules.purchases["H07"] = preload("res://src/night/FactionOpening.gd").RESERVE_FEE
	if run.story_enabled():
		session.rules.purchases.merge(Story.rules().battle_recruits)
	session.ledger.clear()
	session._record("night_node_start",0,str(node.id))
	combat.set_meta("night_profile",battle_profile.duplicate(true))
	sim.unit_spawned.connect(callback)
	if not sim.lethal_hit.is_connected(_lethal_hit):
		sim.lethal_hit.connect(_lethal_hit)
	if not sim.unit_fallen.is_connected(_fallen):
		sim.unit_fallen.connect(_fallen)
	if not sim.unit_allegiance_changed.is_connected(_allegiance_changed):
		sim.unit_allegiance_changed.connect(_allegiance_changed)
	if run.state.mode == "shouxiang":
		for old in sim.humans:
			old.free()
		sim.humans.clear()
		for spec in starting_roster:
			if float(spec.hp) <= 0:
				continue
			var deploy_post: String = str(spec.post)
			var legal: Array[String] = session.legal_posts(str(spec.id), true)
			if spec.get("side","") == "xianghuo" and spec.get("growth",{}).get("gray",false):
				legal.assign([deploy_post] if sim.world.can_deploy_at(deploy_post) else session.legal_posts())
			if not legal.has(deploy_post):
				if legal.is_empty():
					return {"ok":false,"reason":"P5_INVALID_ROSTER_POST"}
				var old_post: Node2D = sim.world.get_node_or_null(deploy_post)
				var origin: Vector2
				if old_post != null:
					origin = old_post.position
				else:
					var old_spec: Dictionary = run.post_spec(deploy_post,run.state.has("nameless_modifiers"))
					if old_spec.is_empty():
						return {"ok":false,"reason":"P5_INVALID_ROSTER_POST"}
					origin = Vector2(Rules.body_to_px(old_spec.x),Rules.HORIZON_Y - float(old_spec.floor_offset) * Rules.STORY_HEIGHT_PX)
				legal.sort_custom(func(a,b): return sim.world.get_node(a).position.distance_squared_to(origin) < sim.world.get_node(b).position.distance_squared_to(origin))
				deploy_post = legal[0]
				session._record("night_redeploy",0,str(spec.uid) + ":" + str(spec.post) + "->" + deploy_post)
			var unit: Node2D = sim.spawn_human(str(spec.id),deploy_post)
			if unit == null:
				return {"ok":false,"reason":"P5_INVALID_ROSTER_POST"}
			# Remove the temporary uid assigned by the generic spawn listener.
			tracked.erase(str(unit.get_meta("night_uid","")))
			_apply_roster(unit,spec)
			unit.position = sim.post_destination(unit,unit.current_post)
			unit.brain.settled_position = unit.position
	else:
		sim.clear_targets()
		sim.tide.pending.clear()
		sim.tide.wave_index = 0
		sim.tide.spawn_count = 0
		for spec in starting_roster:
			if float(spec.hp) > 0:
				carry_queue.append(spec.duplicate(true))
				sim.tide.pending.append(str(spec.id))
		sim.tide._spawn_pending()
	if run.state.get("roster_enabled",false):
		session.codex.restore(run.codex.snapshot())
		session.configure_roster(str(run.state.seed)+":"+str(node.id))
	if run.state.has("nameless_modifiers"):
		var seed_text := str(run.state.seed)+":"+str(node.id)
		if not session.configure_ritual(run.state.ritual,seed_text,run.state.stats.battles.is_empty(),float(run.state.get("ritual_ward_hp",-1))):
			return {"ok":false,"reason":"P10_INVALID_PLAN"}
		var ward: Node2D = session.ritual_ward_actor()
		if is_instance_valid(ward):
			tracked.erase(str(ward.get_meta("night_uid","")))
			var carried_ward: Dictionary = run.state.get("ritual_ward",{})
			if not carried_ward.is_empty():
				apply_carried_unit(ward,carried_ward)
			ward.set_meta("night_uid",RITUAL_WARD_UID)
			ward.set_meta("night_home_post",ward.current_post)
			ward.position = sim.post_destination(ward,ward.current_post)
			ward.brain.settled_position = ward.position
		if not preload("res://src/data/StageOptions.gd").start(session,node.boss_id,run.state.nameless_modifiers,seed_text):
			return {"ok":false,"reason":"P10_INVALID_PLAN"}
	if node.get("boss_id","")=="B01" and run.state.ledger.any(func(entry): return entry.action=="brace_hall" and entry.detail.get("target","")==node.id):
		var hall: Node = sim.world.get_node("door_hall")
		hall.set_durability(minf(hall.max_durability,hall.durability + float(Data.battle_rules.repair.heal)))
		session._update_warnings()
	_rebind_carried_references(sim)
	var listing: Dictionary = run.state.get("story", {}).get("self_listing", {})
	if not listing.is_empty():
		# Wan enters already wounded. This night cannot buy an unwounded replacement.
		session.rules.purchases.erase(str(listing.unit))
	for unit in sim.humans + sim.targets:
		_note_seen(unit.unit_id)
	sim._update_units()
	session._update_warnings()
	Clock.set_paused(false)
	_begin_recording(combat,run)
	return {"ok":true,"reason":"P5_BATTLE_STARTED"}

func _apply_build(rules: Dictionary, build: Dictionary) -> void:
	rules.incense_regen += float(build.get("incense_regen_delta",0))
	rules.ritual.duration = clampf(rules.ritual.duration + float(build.get("ritual_duration_delta",0)),3,5)
	rules.ritual.reward_incense += float(build.get("ritual_reward_incense_delta",0))
	rules.repair.heal += float(build.get("repair_heal_delta",0))
	for id in rules.mutations:
		rules.mutations[id] = maxf(1,rules.mutations[id] + float(build.get("mutation_cost_delta",0)))
	rules.reinforce.count += int(build.get("reinforce_count_delta",0))

func _spawned(unit: Node2D) -> void:
	_note_seen(unit.unit_id)
	var own_side := "xianghuo" if active_run.state.mode == "shouxiang" else "yegui"
	if unit.side != own_side:
		return
	if unit.side == "yegui" and not carry_queue.is_empty() and (not active_run.state.has("nameless_modifiers") or (unit.simulation.tide.spawning_pending and carry_queue.front().id == unit.unit_id)):
		var spec: Dictionary = carry_queue.pop_front()
		_apply_roster(unit,spec)
	else:
		var uid: String = str(active_run.state.current_node_id) + ":" + str(unit.instance_id)
		unit.set_meta("night_uid",uid)
		unit.set_meta("night_home_post",unit.current_post)
		tracked[uid] = _roster_record(unit)

func _apply_roster(unit: Node2D, spec: Dictionary) -> void:
	apply_carried_unit(unit,spec)
	tracked[str(spec.uid)] = spec.duplicate(true)

static func apply_carried_unit(unit: Node2D, spec: Dictionary) -> void:
	# The live night and replay both restore the same owned unit, without a new formula.
	for key in ["hp","max_hp","attack","defense","upgrade_level","equipment_id","mutation_count"]:
		if spec.has(key):
			unit.set(key,int(spec[key]) if key in ["upgrade_level","mutation_count"] else spec[key])
	for key in GROWTH_CARRY_FIELDS:
		if spec.has(key):
			var value = spec[key]
			if value is Array or value is Dictionary: value = value.duplicate(true)
			unit.set(key,PackedStringArray(value) if key == "tags" else (int(value) if key in ["skill_cost","speed_stat"] else value))
	if unit.side == "xianghuo" and unit.brain == null: unit.brain = unit.simulation.HumanAI.new(unit.simulation,unit)
	if not unit.roster.is_empty():
		unit.roster.erase("hunt")
		unit.roster.erase("exterior_route")
		unit.roster.erase("mechanism_route")
		if unit.roster.has("ghost"):
			for key in ["charge","corpse_id","priority_structure","partner_id"]: unit.roster.ghost.erase(key)
	if not unit.growth.is_empty():
		unit.growth.erase("charge_job")
		unit.growth.get("statuses",{}).erase("charge")
	unit.sync_meta()
	unit.set_meta("night_uid",str(spec.uid))
	unit.set_meta("night_home_post",str(spec.post))
	unit.queue_redraw()

func _roster_record(unit: Node2D) -> Dictionary:
	var record := {"uid":str(unit.get_meta("night_uid",unit.instance_id)),"id":unit.unit_id,
		"hp":unit.hp,"max_hp":unit.max_hp,"attack":unit.attack,"defense":unit.defense,
		"upgrade_level":unit.upgrade_level,"equipment_id":unit.equipment_id,"mutation_count":unit.mutation_count,
		"post":str(unit.get_meta("night_home_post",unit.current_post))}
	if active_combat != null and active_combat.get_node("Session").growth.enabled:
		for key in GROWTH_CARRY_FIELDS: record[key] = Snapshot._encode(unit.get(key))
		if not record.growth.is_empty():
			var borrower_id: String = str(record.growth.get("borrower_id",""))
			for other in unit.simulation.humans:
				if other.instance_id == borrower_id: record.growth.borrower_uid = str(other.get_meta("night_uid",other.instance_id))
	return record

func _note_seen(id: String) -> void:
	if id not in encountered:
		encountered.append(id)

func _lethal_hit(unit: Node2D, attacker: Node2D, kind: String, damage: float, hp_before: float) -> void:
	var uid := str(unit.get_meta("night_uid",""))
	if not tracked.has(uid): return
	tracked[uid].fatal_hit = {"source":attacker.unit_id if is_instance_valid(attacker) else "",
		"instance":attacker.instance_id if is_instance_valid(attacker) else "", "kind":kind,
		"room":unit.simulation.world.room_at(unit.position,unit.floor_id),"post":unit.current_post,
		"seconds":unit.simulation.simulation_time,"damage":damage,"hp_before":hp_before}

func _fallen(unit: Node2D) -> void:
	_note_seen(unit.unit_id)
	if unit.simulation.session.is_ritual_ward(unit):
		return
	var uid: String = str(unit.get_meta("night_uid",""))
	if not uid.is_empty():
		if not str(unit.growth.get("departure_reason","")).is_empty():
			_depart(unit,str(unit.growth.departure_reason))
		else:
			tracked[uid] = _settled_record(unit)

func collect(combat: Node, run: RefCounted) -> Dictionary:
	var sim: Node = combat.get_node("Simulation")
	var session: Node = combat.get_node("Session")
	var roster: Array[Dictionary] = []
	var alive: Dictionary = {}
	var player_units: Array = sim.humans + sim.targets
	var owned_side: String = "xianghuo" if run.state.mode == "shouxiang" else "yegui"
	for unit in player_units:
		if session.is_ritual_ward(unit): continue
		var original_side: String = str(unit.roster.get("statuses",{}).get("misrecord",{}).get("original_side",unit.side))
		if original_side != owned_side: continue
		_note_seen(unit.unit_id)
		if not unit.dead:
			var spec := _settled_record(unit)
			roster.append(spec)
			alive[str(spec.uid)] = true
		else:
			_fallen(unit)
	for spec in carry_queue:
		roster.append(spec.duplicate(true))
		alive[str(spec.uid)] = true
	# Scheduled reinforcements already belong to the night, even if their source lane
	# was occupied at the final tick. Earlier carried records keep their real stats.
	if run.state.mode == "duoming":
		for index in range(carry_queue.size(),sim.tide.pending.size()):
			var id: String = sim.tide.pending[index]
			var row: Dictionary = Data.get_unit(id)
			var uid: String = str(run.state.current_node_id) + ":queued:" + str(index)
			roster.append({"uid":uid,"id":id,"hp":float(row["生命"]),"max_hp":float(row["生命"]),
				"attack":float(row["攻击"]),"defense":float(row["防御"]),"upgrade_level":0,
				"equipment_id":"","mutation_count":0,"post":"ghost_main_path"})
			alive[uid] = true
			_note_seen(id)
	var fallen: Array[Dictionary] = []
	for uid in tracked:
		if not alive.has(uid):
			var spec: Dictionary = tracked[uid].duplicate(true)
			spec.hp = 0
			fallen.append(spec)
	var result: Dictionary = session.result.duplicate(true)
	var ward: Node2D = session.ritual_ward_actor()
	if is_instance_valid(ward):
		result.ritual_ward = _settled_record(ward)
	result.roster = roster
	result.fallen = fallen
	if session.growth.enabled: result.departed = departed.duplicate(true)
	result.encountered = encountered.duplicate()
	result.elapsed = sim.simulation_time
	result.incense = session.incense
	result.names = session.names
	result.first_breach = session.first_breach.duplicate(true)
	result.milestones = sim.tide.milestones.duplicate(true)
	result.profile_id = battle_profile.get("id","")
	if session.growth.enabled: result.growth = session.growth.snapshot()
	if session.roster.enabled:
		result.codex = session.codex.snapshot()
		result.killer_id = str(session.result.get("killer_id",""))
	if run.story_enabled() and not session.result.is_empty():
		result.node_id = _story_node
		result.story = _story_report(sim, session, run)
	result.objectives = run.current_node().get("objectives",{}).get(run.state.mode,{}).duplicate(true)
	if not session.result.is_empty() and recording != null:
		if replay_receipt.is_empty(): replay_receipt = Archive.store_record(recording.finish())
		result.replay = replay_receipt.duplicate(true)
	return result

func _note_renown(value: float) -> void:
	_renown_peak = maxf(_renown_peak, value)

func _story_report(sim: Node, session: Node, run: RefCounted) -> Dictionary:
	var row := {"seed":str(run.state.seed), "attempt":_story_attempt,
		"renown_peak":_renown_peak, "register_held":false}
	for key in Story.ACTION_COUNTS:
		row[key] = 0
	if run.state.mode != "shouxiang":
		return row
	row.register_held = session.names > 0 and str(session.result.reason) not in Story.REGISTER_LOST
	var remaining_tide: bool = sim.targets.any(func(actor): return not actor.dead) or not sim.tide.pending.is_empty() \
		or sim.tide.wave_index < sim.tide.config.waves.size() or sim.tide.has_chunk_supply()
	var spared := {}
	for entry in session.ledger:
		match entry.action:
			"ritual_completed":
				row.exorcise_count += 1
				if remaining_tide:
					spared[entry.detail] = true
			"slay_exorcisable":
				row.slay_exorcisable_count += 1
			"growth_borrow_start":
				row.borrow_god_count += 1
			"growth_borrow_backlash":
				row.empty_god_count += 1
			"growth_recruited", "recruited_ghost":
				spared[entry.detail] = true
	row.release_or_recruit_count = spared.size()
	return row

func snapshot(combat: Node) -> Dictionary:
	var state := Snapshot.capture(combat)
	var current_exact := Marshalls.raw_to_base64(var_to_bytes(state))
	state.bridge = {"carry_queue":carry_queue.duplicate(true),"tracked":tracked.duplicate(true),"encountered":encountered.duplicate(),"battle_profile":battle_profile.duplicate(true),"starting_roster":starting_roster.duplicate(true),"departed":departed.duplicate(true)}
	state.bridge.current_exact = current_exact
	state.bridge.carry_queue_exact = Marshalls.raw_to_base64(var_to_bytes(carry_queue))
	if active_run.story_enabled():
		state.bridge.renown_peak = _renown_peak
	if recording != null: state.bridge.recording = recording.checkpoint()
	return state

func restore(combat: Node, run: RefCounted, state: Dictionary) -> Dictionary:
	# Validate the ownership log and its recording before replacing the live battle.
	if not _valid_bridge_state(combat,run,state):
		return {"ok":false,"reason":"P5_SAVE_BATTLE_INVALID"}
	var bridge_state: Dictionary = state.bridge
	var restore_state: Dictionary = state
	var restored_queue: Array = bridge_state.carry_queue
	if bridge_state.has("carry_queue_exact"):
		var packed_queue = bridge_state.carry_queue_exact
		if not packed_queue is String or packed_queue.is_empty() or packed_queue.length() > Archive.MAX_BYTES:
			return {"ok":false,"reason":"P5_SAVE_BATTLE_INVALID"}
		var exact_queue = bytes_to_var(Marshalls.base64_to_raw(packed_queue))
		if not exact_queue is Array or not _valid_bridge_roster(exact_queue,str(run.state.mode),false) or Record.digest(exact_queue) != Record.digest(bridge_state.carry_queue):
			return {"ok":false,"reason":"P5_SAVE_BATTLE_INVALID"}
		restored_queue = exact_queue
	if bridge_state.has("current_exact"):
		var packed = bridge_state.current_exact
		if not packed is String or packed.is_empty() or packed.length() > Archive.MAX_BYTES:
			return {"ok":false,"reason":"P5_SAVE_BATTLE_INVALID"}
		var exact_current = bytes_to_var(Marshalls.base64_to_raw(packed))
		if not exact_current is Dictionary:
			return {"ok":false,"reason":"P5_SAVE_BATTLE_INVALID"}
		var readable: Dictionary = state.duplicate(true)
		readable.erase("bridge")
		if Record.digest(exact_current) != Record.digest(readable) or not Snapshot._valid_snapshot(combat,exact_current):
			return {"ok":false,"reason":"P5_SAVE_BATTLE_INVALID"}
		restore_state = exact_current
	var answer := Snapshot.restore(combat,restore_state)
	if not answer.ok: return answer
	_renown_peak = float(bridge_state.get("renown_peak", restore_state.session.names))
	if recording != null: recording.stop()
	replay_receipt.clear()
	active_run = run
	active_combat = combat
	carry_queue.assign(restored_queue)
	tracked = bridge_state.get("tracked",{}).duplicate(true)
	departed.assign(bridge_state.get("departed",[]))
	encountered.assign(bridge_state.get("encountered",[]))
	battle_profile = bridge_state.get("battle_profile",{}).duplicate(true)
	starting_roster.assign(bridge_state.get("starting_roster",[]))
	combat.set_meta("night_profile",battle_profile.duplicate(true))
	var sim: Node = combat.get_node("Simulation")
	var callback := Callable(self,"_spawned")
	if not sim.unit_spawned.is_connected(callback):
		sim.unit_spawned.connect(callback)
	if not sim.lethal_hit.is_connected(_lethal_hit):
		sim.lethal_hit.connect(_lethal_hit)
	if not sim.unit_fallen.is_connected(_fallen):
		sim.unit_fallen.connect(_fallen)
	if not sim.unit_allegiance_changed.is_connected(_allegiance_changed):
		sim.unit_allegiance_changed.connect(_allegiance_changed)
	var checkpoint: Dictionary = bridge_state.get("recording",{})
	var migrated := not _prior_recording_rules(bridge_state, checkpoint).is_empty()
	_begin_recording(combat,run,{} if migrated else checkpoint,migrated)
	return answer

func _begin_recording(combat: Node, run: RefCounted, resume: Dictionary = {}, migrated := false) -> void:
	var node: Dictionary = run.current_node()
	var details := {"seed":str(run.state.seed),"source":"night","node_id":str(node.id),"label":str(node.get("title_key",node.id)),"mode":str(run.state.mode),"profile_id":str(node.get("profile_id","")),"director_limit":0,"objectives":node.get("objectives",{}).duplicate(true),"night_queue":carry_queue.duplicate(true),"night_queue_exact":Marshalls.raw_to_base64(var_to_bytes(carry_queue))}
	if migrated or (resume.is_empty() and combat.get_node("Simulation").simulation_time > 0):
		details.source = "night_resume_fragment"
	recording = Record.new()
	recording.begin(combat,details,resume)

func _prior_recording_rules(bridge: Dictionary, checkpoint: Variant) -> String:
	if not checkpoint is Dictionary:
		return ""
	if checkpoint.get("rules_hash") == PRE_CAMP_BRACE_RULES:
		return PRE_CAMP_BRACE_RULES
	if checkpoint.get("rules_hash") == PILOT_TRIAL_RULES:
		return PILOT_TRIAL_RULES
	var expected := P11_REVIEW_RULES if bridge.has("renown_peak") else P10_RULES
	return expected if checkpoint.get("rules_hash") == expected else ""

func _valid_bridge_state(combat: Node, run: RefCounted, state: Dictionary) -> bool:
	if not state.get("bridge") is Dictionary or not state.get("session") is Dictionary or not state.get("simulation") is Dictionary or not state.get("tide") is Dictionary:
		return false
	if run.state.get("phase") != "battle" or state.session.get("mode") != run.state.get("mode"):
		return false
	if run.state.has("opening_family"):
		var family: Dictionary = preload("res://src/night/FactionOpening.gd").FAMILIES[run.state.opening_family]
		var tide_config = state.tide.get("config")
		if not tide_config is Dictionary or tide_config.get("supply_id") != family.id or tide_config.get("supply_slots") != family.slots:
			return false
	if run.state.has("nameless_modifiers"):
		var ritual = state.get("ritual")
		var stage = state.get("stage")
		if not ritual is Dictionary or ritual.get("id","R01") != run.state.ritual or not stage is Dictionary:
			return false
		var current: Dictionary = run.current_node()
		if stage.get("boss_id","") != current.boss_id or stage.get("modifier_ids",[]) != run.state.nameless_modifiers:
			return false
	var bridge: Dictionary = state.bridge
	if bridge.has("renown_peak") and (not _finite_number(bridge.renown_peak) or not _finite_number(state.session.get("names")) or bridge.renown_peak < state.session.names):
		return false
	for key in ["carry_queue","encountered","starting_roster"]:
		if not bridge.get(key) is Array:
			return false
	for key in ["tracked","battle_profile"]:
		if not bridge.get(key) is Dictionary:
			return false
	if bridge.has("departed") and not _valid_departures(bridge.departed): return false
	var mode: String = run.state.mode
	if not _valid_bridge_roster(bridge.starting_roster,mode,false) or not _valid_bridge_roster(bridge.carry_queue,mode,false):
		return false
	if bridge.starting_roster != run.state.roster:
		return false
	var profile_id: String = str(run.current_node().get("profile_id",""))
	if bridge.battle_profile != run.config.battle_profiles.get(profile_id,{}):
		return false
	for uid in bridge.tracked:
		var record = bridge.tracked[uid]
		if not uid is String or not record is Dictionary or record.get("uid") != uid or not _valid_bridge_roster([record],mode,true):
			return false
	for id in bridge.encountered:
		if not id is String or not Data.combat_profiles.has(id):
			return false
	if not state.tide.get("pending") is Array or bridge.carry_queue.size() > state.tide.pending.size():
		return false
	if mode == "shouxiang" and not bridge.carry_queue.is_empty():
		return false
	for index in bridge.carry_queue.size():
		var record: Dictionary = bridge.carry_queue[index]
		if state.tide.pending[index] != record.id or not bridge.tracked.has(record.uid):
			return false
	if bridge.has("recording"):
		var prior := _prior_recording_rules(bridge, bridge.recording)
		var checked := Archive.validate_checkpoint(bridge.recording,prior)
		if not checked.ok or not Snapshot._valid_snapshot(combat,bridge.recording.initial):
			return false
		var metadata: Dictionary = bridge.recording.metadata
		if metadata.get("seed") != run.state.seed or metadata.get("node_id") != run.state.current_node_id or metadata.get("mode") != mode or metadata.get("profile_id") != profile_id or metadata.get("source") not in ["night","night_resume_fragment"] or metadata.get("director_limit") != 0:
			return false
		if bridge.recording.initial.session.get("mode") != mode:
			return false
		var initial_time = bridge.recording.initial.simulation.get("simulation_time")
		var current_time = state.simulation.get("simulation_time")
		if not _finite_number(initial_time) or not _finite_number(current_time) or float(initial_time) > float(current_time):
			return false
		var recorded_time := 0.0
		for delta in bridge.recording.steps:
			recorded_time += float(delta)
		if absf(recorded_time - (float(current_time) - float(initial_time))) > 0.00001:
			return false
	return true

func _valid_bridge_roster(records: Array, mode: String, allow_fallen: bool) -> bool:
	var seen: Array[String] = []
	for record in records:
		if not record is Dictionary or not record.get("uid") is String or str(record.uid).is_empty() or str(record.uid) in seen or not Data.combat_profiles.has(str(record.get("id",""))):
			return false
		seen.append(str(record.uid))
		if record.has("growth") and not record.growth is Dictionary: return false
		if record.has("roster") and not preload("res://src/roster/RosterEngine.gd").valid_unit_state(record.roster): return false
		if record.has("side") and record.side not in ["xianghuo","yegui"]: return false
		if record.has("profile") and not Snapshot.valid_profile(record.profile,str(record.id)): return false
		if (str(record.id).begins_with("G") != (mode == "duoming") and not (mode == "shouxiang" and record.get("side") == "xianghuo" and record.get("growth",{}).get("gray",false))) or not record.get("post") is String or not record.get("equipment_id") is String:
			return false
		if record.has("growth") and not preload("res://src/growth/GrowthEngine.gd").valid_unit_growth(record.growth): return false
		for key in ["hp","max_hp","attack","defense","upgrade_level","mutation_count"]:
			if not _finite_number(record.get(key)) or float(record[key]) < 0:
				return false
		if record.max_hp <= 0 or record.hp > record.max_hp or (not allow_fallen and record.hp <= 0):
			return false
		if float(record.upgrade_level) != int(record.upgrade_level) or record.upgrade_level > Data.battle_rules.upgrade.max_level or float(record.mutation_count) != int(record.mutation_count) or record.mutation_count > Data.battle_rules.mutation_limit:
			return false
	return true

static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

func _rebind_carried_references(sim: Node) -> void:
	var actors_by_uid: Dictionary = {}
	for unit in sim.humans + sim.targets:
		actors_by_uid[str(unit.get_meta("night_uid",unit.instance_id))] = unit
	for unit in sim.humans + sim.targets:
		if unit.growth.has("borrower_uid"):
			var owner = actors_by_uid.get(str(unit.growth.borrower_uid))
			unit.growth.borrower_id = str(owner.instance_id) if is_instance_valid(owner) else ""

func _allegiance_changed(unit: Node2D, _old_side: String, new_side: String) -> void:
	if active_run == null: return
	if unit.simulation.session.is_ritual_ward(unit): return
	if unit.roster.get("statuses",{}).has("misrecord"): return
	var owned_side := "xianghuo" if active_run.state.mode == "shouxiang" else "yegui"
	if new_side == owned_side:
		var uid: String = str(unit.get_meta("night_uid",""))
		if uid.is_empty():
			uid = str(active_run.state.current_node_id) + ":" + unit.instance_id
			unit.set_meta("night_uid",uid)
		unit.set_meta("night_home_post",unit.current_post)
		tracked[uid] = _roster_record(unit)
		for index in range(departed.size()-1,-1,-1):
			if departed[index].uid == uid: departed.remove_at(index)
	else:
		_depart(unit,"left_side")

func _depart(unit: Node2D, reason: String) -> void:
	var uid: String = str(unit.get_meta("night_uid",""))
	if uid.is_empty() or not tracked.has(uid): return
	var spec := _roster_record(unit)
	spec.departure_reason = reason
	tracked.erase(uid)
	for index in range(departed.size()-1,-1,-1):
		if departed[index].uid == uid: departed.remove_at(index)
	departed.append(spec)

static func _valid_departures(value: Variant) -> bool:
	if not value is Array: return false
	var seen: Array[String] = []
	for spec in value:
		if not spec is Dictionary or not spec.get("uid") is String or spec.uid in seen or not Data.combat_profiles.has(str(spec.get("id",""))) or spec.get("departure_reason") not in ["left_side","fusion"]: return false
		if not _finite_number(spec.get("hp")) or float(spec.hp) < 0: return false
		seen.append(spec.uid)
	return true

func _settled_record(unit: Node2D) -> Dictionary:
	var record := _roster_record(unit)
	var previous: Dictionary = tracked.get(record.uid,{})
	if unit.dead and previous.has("fatal_hit"): record.fatal_hit = previous.fatal_hit.duplicate(true)
	var misrecord: Dictionary = unit.roster.get("statuses",{}).get("misrecord",{})
	if not misrecord.is_empty():
		record.side = str(misrecord.original_side)
		record.role = str(Data.combat_profiles[unit.unit_id].role)
		record.roster.statuses.erase("misrecord")
		if record.side == "yegui": record.post = "ghost_main_path"
	return record
