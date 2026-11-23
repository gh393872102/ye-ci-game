extends RefCounted
## JSON-safe state for continuing the same live battle, not restarting the node.
const Stages = preload("res://src/data/StageOptions.gd")
const UNIT_FIELDS := ["unit_id","instance_id","floor_id","hp","max_hp","attack","defense","speed_stat","profile","current_post","ai_state","current_speed","velocity","attack_left","hit_flash","dead","corpse_left","hold_lock","may_briefly_leave_base","return_after","attacks_enabled","motion_enabled","lane_index","progress","height_px","upgrade_level","equipment_id","mutation_count","damage_revision"]
const UNIT_EXTRA_FIELDS := ["roster","growth","side","tags","skill_id","trait_id","skill_cost","skill_text","trait_text","display_name","role"]
const HUMAN_FIELDS := ["route","target_post","purpose","pressure_elapsed","hold_left","last_reason","last_channel_target","visited_posts","settled_position","repair_door"]
const GHOST_FIELDS := ["stage","gap_route","landing_left"]
const CHANNEL_FIELDS := ["active","elapsed","duration","target","completions","last_result","start_position","damage_revision","paid"]
const EXCURSION_FIELDS := ["active","remaining","origin","destination","returning","completed"]
const SESSION_FIELDS := ["mode","active","running","incense","names","remaining","result","pending_purchase","rules","warnings","ledger","repair_jobs","reinforce_left","reinforce_count","occupation","extinguish_left","first_breach","_reserved_cost"]
const SESSION_EXTRA_FIELDS := ["register_break","dual_enabled","player_seat","wallets","_legacy_incense","simulation_speed"]
const TIDE_FIELDS := ["config","preset","elapsed","arrival","arrived_by","wave_index","pending","effects","milestones","spawn_count"]
const SIM_FIELDS := ["simulation_time","serial","events","damage_log","traces","passage_timers"]
const SHOT_FIELDS := ["owner_unit","direction","speed","distance_left","attack","side","kind","finished"]

static func capture(combat: Node) -> Dictionary:
	var sim: Node = combat.get_node("Simulation")
	var actors: Array[Dictionary] = []
	for group in ["humans","targets","corpses"]:
		for unit in sim.get(group):
			var spec := {"group":group,"fields":_read(unit,UNIT_FIELDS + UNIT_EXTRA_FIELDS),"position":_encode(unit.position),"z_index":unit.z_index,"night_uid":str(unit.get_meta("night_uid","")),"night_home_post":str(unit.get_meta("night_home_post",unit.current_post))}
			spec.brain = _read(unit.brain,HUMAN_FIELDS if unit.side == "xianghuo" else GHOST_FIELDS)
			if unit.side == "xianghuo":
				spec.channel = _read(unit.brain.channel,CHANNEL_FIELDS)
				if unit.brain.channel.active and unit.brain.channel.purify_only: spec.channel.purify_only = true
				spec.excursion = _read(unit.brain.excursion,EXCURSION_FIELDS)
			actors.append(spec)
	var structures: Array[Dictionary] = []
	for door in sim.world.doors:
		structures.append({"name":str(door.name),"kind":"door","fields":_read(door,["max_durability","durability","destroyed","is_open","defense"])})
	for obstacle in sim.world.obstacles:
		structures.append({"name":str(obstacle.name),"kind":"obstacle","fields":_read(obstacle,["max_durability","durability","occupied","defense"])})
	var shots: Array[Dictionary] = []
	for shot in sim.projectiles:
		shots.append({"position":_encode(shot.position),"fields":_read(shot,SHOT_FIELDS)})
	var snapshot := {"version":1,"actors":actors,"structures":structures,"shots":shots,
		"simulation":_read(sim,SIM_FIELDS + ["step_index"]),"tide":_read(sim.tide,TIDE_FIELDS),"session":_read(sim.session,SESSION_FIELDS + SESSION_EXTRA_FIELDS),
		"growth":sim.session.growth.snapshot(),"roster_engine":sim.session.roster.snapshot(),"codex":sim.session.codex.snapshot(),"camera_left":combat.get_node("BattleCamera").left(),"speed":Clock.resume_scale,"clock_combat_time":Clock.combat_time}
	var ids: Array = sim.world.layout.get("chunk_ids",[])
	if not ids.is_empty():
		snapshot.chunk_ids = ids.duplicate()
		snapshot.ritual = sim.session.ritual_snapshot()
		snapshot.stage = Stages.capture(sim.session)
	return snapshot

static func restore(combat: Node, state: Dictionary) -> Dictionary:
	var sim: Node = combat.get_node("Simulation")
	if not _valid_snapshot(combat,state):
		return {"ok":false,"reason":"P5_SAVE_BATTLE_INVALID"}
	sim.vfx.reset()
	for old in sim.humans + sim.targets + sim.corpses + sim.projectiles:
		old.free()
	sim.humans.clear()
	sim.targets.clear()
	sim.corpses.clear()
	sim.projectiles.clear()
	sim.session.growth = sim.session.Growth.new(sim.session)
	sim.session.roster = sim.session.Roster.new(sim.session)
	sim.session.codex = sim.session.Codex.new("",false)
	sim.world.set_meta("broken_paths",[])
	var refs: Dictionary = {}
	for structure in sim.world.doors + sim.world.obstacles:
		refs["world:" + str(structure.name)] = structure
	var restored: Array[Node] = []
	for spec in state.actors:
		var unit: Node2D = sim.Unit.new()
		unit.configure(str(spec.fields.unit_id),str(spec.fields.instance_id),sim)
		_apply(unit,spec.fields,UNIT_FIELDS + UNIT_EXTRA_FIELDS,refs)
		unit.position = _decode(spec.position,refs)
		unit.z_index = int(spec.z_index)
		unit.set_meta("night_uid",str(spec.get("night_uid","")))
		unit.set_meta("night_home_post",str(spec.get("night_home_post",unit.current_post)))
		unit.brain = sim.HumanAI.new(sim,unit) if unit.side == "xianghuo" else preload("res://src/ai/GhostBrain.gd").new(sim,unit,sim.tide)
		sim.add_child(unit)
		sim.get(spec.group).append(unit)
		refs["unit:" + unit.instance_id] = unit
		restored.append(unit)
	for index in state.actors.size():
		var spec: Dictionary = state.actors[index]
		var unit: Node = restored[index]
		_apply(unit.brain,spec.brain,HUMAN_FIELDS if unit.side == "xianghuo" else GHOST_FIELDS,refs)
		if unit.side == "xianghuo":
			_apply(unit.brain.channel,spec.channel,CHANNEL_FIELDS,refs)
			unit.brain.channel.purify_only = spec.channel.get("purify_only",false)
			_apply(unit.brain.excursion,spec.excursion,EXCURSION_FIELDS,refs)
		unit.sync_meta()
		unit.queue_redraw()
	for spec in state.get("structures",[]):
		var structure: Node = refs.get("world:" + str(spec.name))
		if structure == null:
			return {"ok":false,"reason":"P5_SAVE_BATTLE_INVALID"}
		if spec.kind == "door":
			_apply(structure,spec.fields,["max_durability","durability","destroyed","is_open","defense"],refs)
			structure.set_open(structure.is_open)
		else:
			_apply(structure,spec.fields,["max_durability","durability","occupied","defense"],refs)
			structure.set_occupied(structure.occupied)
	for spec in state.get("shots",[]):
		var shot: Node2D = sim.Shot.new()
		shot.simulation = sim
		shot.position = _decode(spec.position,refs)
		_apply(shot,spec.fields,SHOT_FIELDS,refs)
		sim.add_child(shot)
		sim.projectiles.append(shot)
	sim.step_index = 0
	_apply(sim,state.simulation,SIM_FIELDS + ["step_index"],refs)
	_apply(sim.tide,state.tide,TIDE_FIELDS,refs)
	sim.tide.leaders.clear()
	sim.tide.buckets.clear()
	sim.session.dual_enabled = false
	sim.session.wallets.clear()
	sim.session.player_seat = str(state.session.mode)
	sim.session.input_locked = false
	sim.session.simulation_speed = float(state.get("speed",1))
	_apply(sim.session,state.session,SESSION_FIELDS + SESSION_EXTRA_FIELDS,refs)
	if state.has("growth"): sim.session.growth.restore(state.growth)
	if state.has("roster_engine"): sim.session.roster.restore(state.roster_engine)
	if state.has("codex"): sim.session.codex.restore(state.codex)
	if state.has("chunk_ids"):
		sim.session.restore_ritual(state.ritual)
		if not Stages.restore(sim.session,state.stage):
			return {"ok":false,"reason":"P5_SAVE_BATTLE_INVALID"}
	sim._update_units()
	sim.queue_redraw()
	sim.world.queue_redraw()
	combat.get_node("BattleCamera").set_left(float(state.get("camera_left",6080)))
	var panel: Node = combat.get_node("Decisions")
	panel._clear_selected()
	panel.close_panel()
	# close_panel normally refunds pending deployment; restore it after clearing stale UI.
	_apply(sim.session,state.session,SESSION_FIELDS + SESSION_EXTRA_FIELDS,refs)
	sim.session.refresh_register_presence()
	panel.ending.hide()
	panel.prebattle.hide()
	panel.last_result = ""
	Clock.set_speed(float(state.get("speed",1)))
	Clock.combat_time = float(state.get("clock_combat_time",0))
	Clock.set_paused(true)
	if not sim.session.pending_purchase.is_empty():
		panel.current_panel = "deploy"
		panel._build_deploy()
	return {"ok":true,"reason":"P5_BATTLE_RESTORED"}

static func _valid_snapshot(combat: Node, state: Dictionary) -> bool:
	# Reject malformed nested state before freeing any actors in the live scene.
	var sim: Node = combat.get_node("Simulation")
	if state.has("chunk_ids"):
		if state.chunk_ids != sim.world.layout.get("chunk_ids",[]) or not sim.session.valid_ritual_snapshot(state.get("ritual")) or not Stages.valid_snapshot(state.get("stage")):
			return false
	elif sim.world.layout.has("chunk_ids"): return false
	if state.get("version",0) != 1:
		return false
	for key in ["actors","structures","shots"]:
		if not state.get(key) is Array:
			return false
	for key in ["session","simulation","tide"]:
		if not state.get(key) is Dictionary:
			return false
	if not _valid_fields(sim.session,state.session,SESSION_FIELDS) or not _valid_fields(sim,state.simulation,SIM_FIELDS) or not _valid_fields(sim.tide,state.tide,TIDE_FIELDS):
		return false
	for key in SESSION_EXTRA_FIELDS:
		if state.session.has(key) and not _valid_fields(sim.session,state.session,[key]):
			return false
	if state.simulation.has("step_index") and not _number_valid(state.simulation.step_index):
		return false
	if state.has("growth") and (not state.growth is Dictionary or not sim.session.Growth.valid_state(state.growth)):
		return false
	if state.has("roster_engine") and not sim.session.Roster.valid_state(state.roster_engine): return false
	if state.has("codex") and not sim.session.Codex.valid(state.codex,sim.session.codex.catalog): return false
	var ids: Array[String] = []
	for spec in state.actors:
		if not spec is Dictionary or not spec.get("fields") is Dictionary or not Data.combat_profiles.has(str(spec.fields.get("unit_id",""))) or spec.get("group") not in ["humans","targets","corpses"]:
			return false
		var id: String = str(spec.fields.get("instance_id",""))
		if id.is_empty() or ids.has(id) or not _vector_valid(spec.get("position")) or not _number_valid(spec.get("z_index")):
			return false
		ids.append(id)
		var probe: Node2D = sim.Unit.new()
		probe.configure(str(spec.fields.unit_id),id,sim)
		var valid := _valid_fields(probe,spec.fields,UNIT_FIELDS) and valid_profile(spec.fields.get("profile"),str(spec.fields.unit_id))
		for key in UNIT_EXTRA_FIELDS:
			if spec.fields.has(key): valid = valid and _valid_fields(probe,spec.fields,[key])
		if spec.fields.has("growth"): valid = valid and sim.session.Growth.valid_unit_growth(spec.fields.growth)
		if spec.fields.has("roster"): valid = valid and sim.session.Roster.valid_unit_state(spec.fields.roster)
		if spec.fields.has("side"):
			valid = valid and spec.fields.side in ["xianghuo","yegui"]
			probe.side = str(spec.fields.side)
		if spec.group != "corpses": valid = valid and (spec.group == "humans") == (probe.side == "xianghuo")
		probe.brain = sim.HumanAI.new(sim,probe) if probe.side == "xianghuo" else preload("res://src/ai/GhostBrain.gd").new(sim,probe,sim.tide)
		valid = valid and spec.get("brain") is Dictionary and _valid_fields(probe.brain,spec.brain,HUMAN_FIELDS if probe.side == "xianghuo" else GHOST_FIELDS)
		if probe.side == "xianghuo":
			valid = valid and spec.get("channel") is Dictionary and spec.get("excursion") is Dictionary
			if valid:
				valid = spec.channel.get("purify_only",false) is bool and _valid_fields(probe.brain.channel,spec.channel,CHANNEL_FIELDS) and _valid_fields(probe.brain.excursion,spec.excursion,EXCURSION_FIELDS)
		probe.free()
		if not valid:
			return false
	var expected_structures := {}
	for door in sim.world.doors:
		expected_structures[str(door.name)] = "door"
	for obstacle in sim.world.obstacles:
		expected_structures[str(obstacle.name)] = "obstacle"
	if state.structures.size() != expected_structures.size():
		return false
	for spec in state.structures:
		if not spec is Dictionary or not spec.get("fields") is Dictionary or spec.get("kind") not in ["door","obstacle"]:
			return false
		var name = spec.get("name")
		if not name is String or expected_structures.get(name) != spec.kind:
			return false
		expected_structures.erase(name)
		var structure: Node = sim.world.get_node(name)
		var fields: Array = ["max_durability","durability","destroyed","is_open","defense"] if spec.kind == "door" else ["max_durability","durability","occupied","defense"]
		if not _valid_fields(structure,spec.fields,fields):
			return false
	for spec in state.shots:
		if not spec is Dictionary or not spec.get("fields") is Dictionary or not _vector_valid(spec.get("position")):
			return false
		var probe: Node2D = sim.Shot.new()
		var valid := _valid_fields(probe,spec.fields,SHOT_FIELDS)
		probe.free()
		if not valid:
			return false
	return true

static func _valid_fields(object: Object, data: Dictionary, fields: Array) -> bool:
	for key in fields:
		if not data.has(key) or not _encoding_valid(data[key]):
			return false
		var current = object.get(key)
		var value = data[key]
		if current is Vector2 and not _vector_valid(value):
			return false
		if typeof(current) in [TYPE_INT,TYPE_FLOAT] and not _number_valid(value):
			return false
		if current is bool and not value is bool:
			return false
		if current is String and not value is String:
			return false
		if current is Array and not value is Array:
			return false
		if current is PackedStringArray:
			if not value is Array: return false
			for item in value:
				if not item is String: return false
		if current is Array and current.is_typed():
			for item in value:
				if typeof(item) != current.get_typed_builtin():
					return false
		if current is Dictionary and not value is Dictionary:
			return false
		if key in ["owner_unit","repair_door","target"] and value != null and (not value is Dictionary or not value.get("_reference") is String):
			return false
	return true

static func _number_valid(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

static func _vector_valid(value: Variant) -> bool:
	return value is Dictionary and value.get("_vector2") is Array and value._vector2.size() == 2 and _number_valid(value._vector2[0]) and _number_valid(value._vector2[1])

static func _encoding_valid(value: Variant) -> bool:
	if value is Dictionary:
		if value.has("_vector2"):
			return _vector_valid(value)
		if value.has("_reference"):
			return value._reference is String
		for item in value.values():
			if not _encoding_valid(item):
				return false
	elif value is Array:
		for item in value:
			if not _encoding_valid(item):
				return false
	return true

static func _read(object: Object, fields: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in fields:
		result[key] = _encode(object.get(key))
	return result

static func _apply(object: Object, data: Dictionary, allowed: Array, refs: Dictionary) -> void:
	for key in allowed:
		if not data.has(key):
			continue
		var value = _decode(data[key],refs)
		var current = object.get(key)
		if current is PackedStringArray and value is Array:
			object.set(key,PackedStringArray(value))
		elif current is Array and value is Array:
			current.assign(value)
		elif typeof(current) == TYPE_INT:
			object.set(key,int(value))
		else:
			object.set(key,value)

static func _encode(value: Variant) -> Variant:
	if typeof(value) == TYPE_OBJECT and not is_instance_valid(value):
		return null
	if value is Vector2:
		return {"_vector2":[value.x,value.y]}
	if value is Node:
		# A queued corpse has left the simulation even before the render frame frees it.
		if not is_instance_valid(value) or value.is_queued_for_deletion():
			return null
		return {"_reference":("unit:" + str(value.instance_id)) if value.is_in_group("units") else "world:" + str(value.name)}
	if value is Array or value is PackedStringArray:
		var result: Array = []
		for item in value:
			result.append(_encode(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[str(key)] = _encode(value[key])
		return result
	return value if typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING] else null

static func _decode(value: Variant, refs: Dictionary) -> Variant:
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_decode(item,refs))
		return result
	if value is Dictionary:
		if value.has("_vector2"):
			return Vector2(float(value._vector2[0]),float(value._vector2[1]))
		if value.has("_reference"):
			return refs.get(str(value._reference))
		var result: Dictionary = {}
		for key in value:
			result[key] = _decode(value[key],refs)
		return result
	return value

static func valid_profile(value: Variant, id: String) -> bool:
	if not value is Dictionary or not Data.combat_profiles.has(id): return false
	var source: Dictionary = Data.combat_profiles[id]
	for key in source:
		if not value.has(key): return false
		if typeof(source[key]) in [TYPE_INT,TYPE_FLOAT]:
			if not _number_valid(value[key]): return false
		elif typeof(source[key]) != typeof(value[key]): return false
	if value.get("role") not in ["guard","ritual","talisman","crossbow","debug_target","tide"]: return false
	if not _number_valid(value.get("range_body")) or value.range_body <= 0 or value.range_body > 8: return false
	if not value.get("projectile") is String or not value.get("may_briefly_leave_base") is bool or not _number_valid(value.get("return_after")) or value.return_after < 0: return false
	if not value.get("skill_id") is String or (not str(value.skill_id).is_empty() and not Data.skills.has(value.skill_id)): return false
	if not value.get("trait_id") is String or (not str(value.trait_id).is_empty() and not Data.traits.has(value.trait_id)): return false
	return _encoding_valid(value)
