extends RefCounted
## P8 named behaviors extend the same simulation; all mutable combat state is serializable.
signal petition_resolved(unit: Node2D, receipt: Dictionary)
signal drum_resolved(unit: Node2D, receipt: Dictionary)

const Humans = preload("res://src/roster/HumanAbilities.gd")
const Ghosts = preload("res://src/roster/GhostAbilities.gd")
var session: Node
var enabled := false
var state: Dictionary = {}
var humans: RefCounted
var ghosts: RefCounted
var rng := RandomNumberGenerator.new()

func _init(owner: Node) -> void:
	session = owner
	humans = Humans.new(self)
	ghosts = Ghosts.new(self)

func configure(seed_text: String, initial: Dictionary = {}) -> void:
	enabled = true
	rng.seed = seed_text.hash()
	state = {"enabled":true,"seed":seed_text,"time":0.0,"rng_state":str(rng.state),"broken_paths":[],"last_erased_by":"","last_killer_id":"","register_ward":0.0,"register_ward_multiplier":1.0,"effects":[]}
	if not initial.is_empty():
		for key in initial: state[key] = initial[key].duplicate(true) if initial[key] is Dictionary or initial[key] is Array else initial[key]
		state.enabled = true
		rng.state = int(state.get("rng_state",str(rng.state)))
	sim().world.set_meta("broken_paths",state.broken_paths.duplicate())
	for unit in sim().humans + sim().targets: ensure(unit)

func sim() -> Node:
	return session.simulation

func growth() -> RefCounted:
	return session.growth

func params(value: Variant) -> Dictionary:
	var id: String = value if value is String else value.unit_id
	return Data.roster_rules.get("abilities",{}).get(id,{})

func ensure(unit: Node2D) -> void:
	if not is_instance_valid(unit): return
	if unit.roster.is_empty():
		unit.roster = {"cooldowns":{},"statuses":{},"counters":{},"face_state":"faceless" if unit.unit_id in ["G01","G04","G19","G26","G30","G32"] else "faced","marked":false,"reserve_incense":0.0,"initialized":false}
	var profile: Dictionary = Data.roster_rules.get("profiles",{}).get(unit.unit_id,{})
	unit.height_px = float(profile.get("height_px",unit.height_px))
	unit.may_briefly_leave_base = bool(profile.get("may_briefly_leave_base",false))
	unit.return_after = float(profile.get("return_after",0))
	if not bool(unit.roster.initialized):
		unit.roster.initialized = true
		session.codex.encounter(unit.unit_id)
		if unit.unit_id == "H30":
			session.names = minf(float(Data.mode_rules.limits.names_max),session.names + float(params(unit).starting_names))
			event("inherited_name",unit,"H30")
	growth().ensure(unit)

func actor(id: String) -> Node2D:
	for unit in sim().humans + sim().targets:
		if unit.instance_id == id and not unit.dead: return unit
	return null

func near(unit: Node2D, radius_body: float, friendly := false, samefloor := true) -> Array[Node2D]:
	var found: Array[Node2D] = []
	var human_side: bool = (unit.side == "xianghuo") == friendly
	var candidates: Array = sim().humans if human_side else sim().targets
	var radius_px: float = Rules.body_to_px(radius_body)
	for other in candidates:
		if other == unit or other.dead or ((other.side == unit.side) != friendly): continue
		if samefloor and other.floor_id != unit.floor_id: continue
		if other.position.distance_to(unit.position) <= radius_px: found.append(other)
	found.sort_custom(func(a,b): return unit.position.distance_squared_to(a.position) < unit.position.distance_squared_to(b.position))
	return found

func ready(unit: Node2D, key := "skill") -> bool:
	ensure(unit)
	return float(unit.roster.cooldowns.get(key,0)) <= 0

func cooldown(unit: Node2D, seconds: float, key := "skill") -> void:
	unit.roster.cooldowns[key] = maxf(0,seconds)

func pay(unit: Node2D, cost: float) -> bool:
	ensure(unit)
	var local := minf(cost,float(unit.roster.reserve_incense))
	if not growth()._pay(unit,cost-local): return false
	unit.roster.reserve_incense -= local
	return true

func change_incense(seat: String, delta: float) -> float:
	var before: float = session.incense_for(seat)
	var value := clampf(before+delta,0,float(session.rules.incense_cap))
	if session.dual_enabled: session.wallets[seat] = value
	elif seat == session.mode: session.incense = value
	else: growth().state.npc_incense = value
	return value-before

func event(kind: String, unit: Node2D, detail := "") -> void:
	sim().record_event("roster_"+kind,unit,detail)
	if is_instance_valid(unit): unit.queue_redraw()

func visual(kind: String, unit: Node2D, point := Vector2.ZERO, duration := 1.2) -> void:
	if not is_instance_valid(unit): return
	var where: Vector2 = unit.position if point == Vector2.ZERO else point
	growth()._visual(kind,where,unit.floor_id,duration)
	if not unit.unit_id.begins_with("G"):
		state.effects.append({"unit_id":unit.unit_id,"kind":kind,"source":[unit.position.x,unit.position.y-40],"point":[where.x,where.y-40],"left":duration,"duration":duration})
		if kind == "watch_drum":
			state.effects.back().radius_body = growth().drum_radius(unit,float(params(unit).get("radius_body",3)))
		if state.effects.size()>128: state.effects.pop_front()

func reject(reason := "P8_NO_TARGET") -> Dictionary:
	return {"ok":false,"reason":reason}

func ok() -> Dictionary:
	return {"ok":true,"reason":"P8_SKILL_DONE"}

func cast(unit: Node2D, args: Dictionary = {}) -> Dictionary:
	if not enabled or not is_instance_valid(unit) or unit.dead: return reject("P8_INVALID_UNIT")
	ensure(unit)
	if not can_act(unit) or growth().is_hidden(unit) and unit.roster.statuses.has("dream"): return reject("P8_SKILL_BLOCKED")
	if unit.growth.statuses.has("misname"):
		unit.growth.statuses.erase("misname")
		cooldown(unit,float(params(unit).get("cooldown",8)))
		event("skill_misfired",unit,unit.skill_id)
		visual("misname",unit)
		# The attempted cast consumes a status and cooldown, so it is an applied command
		# even though the skill effect fails. Replay must retain that state transition.
		return {"ok":true,"reason":"P8_SKILL_MISFIRED","effect_applied":false}
	if not ready(unit): return reject("P8_SKILL_COOLDOWN")
	if unit.roster.statuses.has("nameless"): return reject("P8_NAME_ERASED")
	return ghosts.cast(unit,args) if unit.unit_id.begins_with("G") else humans.cast(unit,args)

func cast_as(unit: Node2D, source_id: String, args: Dictionary = {}) -> Dictionary:
	return humans.cast_as(unit,source_id,args)

func advance(delta: float) -> void:
	if not enabled or delta <= 0: return
	state.time += delta
	for i in range(state.get("effects",[]).size()-1,-1,-1):
		state.effects[i].left -= delta
		if state.effects[i].left <= 0: state.effects.remove_at(i)
	state.register_ward = maxf(0,float(state.register_ward)-delta)
	for unit in (sim().humans+sim().targets).duplicate():
		if unit.dead: continue
		ensure(unit)
		var skill_delta: float = growth().skill_delta(unit,delta)
		if unit.unit_id == "H07": skill_delta = delta/maxf(1,session.simulation_speed)
		for key in unit.roster.cooldowns: unit.roster.cooldowns[key] = maxf(0,float(unit.roster.cooldowns[key])-skill_delta)
		for key in unit.roster.statuses.keys():
			if key == "misrecord": continue
			unit.roster.statuses[key].left = float(unit.roster.statuses[key].get("left",0))-delta
			if unit.roster.statuses[key].left <= 0:
				unit.roster.statuses.erase(key)
				if key == "faceless": unit.roster.face_state = "faced"
		if unit.unit_id.begins_with("G"): ghosts.advance(unit,delta)
		else: humans.advance(unit,delta)
	ghosts.advance_world(delta)
	state.rng_state = str(rng.state)

func advance_actor(unit: Node2D, delta: float) -> bool:
	if not enabled: return false
	return ghosts.advance_actor(unit,delta) if unit.unit_id.begins_with("G") else humans.advance_actor(unit,delta)

func can_act(unit: Node2D) -> bool:
	if not enabled or unit.roster.is_empty(): return true
	return not unit.roster.statuses.has("dream") and not unit.roster.statuses.has("stun")

func is_silenced(unit: Node2D) -> bool:
	if growth().state.get("ritual_flag","") in ["jinsheng","禁声"]: return true
	for other in sim().humans+sim().targets:
		if other.dead or other.roster.is_empty() or not other.roster.statuses.has("silence_field"): continue
		if other.floor_id == unit.floor_id and other.position.distance_to(unit.position) <= Rules.body_to_px(float(params(other).get("radius_body",3))): return true
	return false

func reveal_from_loud_skill(unit: Node2D, skill_owner: String, radius_body: float) -> void:
	if skill_owner not in session.ritual.param("loud_units",[]):
		return
	var duration: float = float(session.ritual.param("sound_reveal_seconds",0.0))
	for side in [false,true]:
		for other in near(unit,radius_body,side):
			if growth().is_hidden(other):
				status(other,"revealed",duration,unit)
				event("sound_reveal",unit,other.instance_id)

func loud_skill_radius(unit: Node2D, base: float) -> float:
	var area: Dictionary = sim().world.chunk_area_at(unit.position,unit.floor_id)
	return base * float(area.get("sound_radius_multiplier",1.0))

func status(target: Node2D, kind: String, duration: float, source: Node2D = null, extra: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(target) or target.dead: return reject("P8_INVALID_UNIT")
	ensure(target)
	if is_instance_valid(source): ensure(source)
	if is_instance_valid(source) and source != target and source.side != target.side and not extra.get("reflected",false) and target.roster.statuses.has("mirror") and kind in ["charm","misrecord","name_erase","nameless","face_theft","misname","dream","root","drag"]:
		target.roster.statuses.erase("mirror")
		var reflected: Dictionary = extra.duplicate(true)
		reflected.erase("original_side")
		reflected.reflected = true
		if kind == "misrecord":
			reflected.original_side = source.side
			reflected.restore_left = duration
			reflected.end_stun = float(extra.get("end_stun",1))
		status(source,kind,duration,target,reflected)
		if kind == "misrecord": set_allegiance(source,target.side,duration,target)
		status(source,"revealed",3,target)
		event("spell_reflected",target,source.instance_id)
		visual("mirror",target)
		return {"ok":true,"blocked":true,"reason":"P8_SPELL_REFLECTED"}
	if kind in ["charm","misrecord"] and target.unit_id == "H05":
		event("speech_immune",target,kind)
		return {"ok":true,"blocked":true,"reason":"P8_STATUS_BLOCKED"}
	if kind == "charm" and target.unit_id == "H18": duration *= float(params(target).charm_duration_multiplier)
	if kind in ["name_erase","nameless"] and humans.block_name_erase(target,source):
		return {"ok":true,"blocked":true,"reason":"P8_STATUS_BLOCKED"}
	if kind in ["name_erase","face_theft","fear"]:
		# The P7 ward/equipment path remains authoritative for resistance and charges.
		var names_before: float = session.names
		var key := kind
		var result: Dictionary = growth().apply_status(target,key,duration,source)
		var applied: bool = target.growth.statuses.has(key) and str(target.growth.statuses[key].get("source_id","")) == (source.instance_id if source != null else "")
		if not applied: return {"ok":result.ok,"blocked":true,"reason":"P8_STATUS_BLOCKED"}
		if kind == "name_erase":
			session.names = names_before
			drain_names(1,source)
			kind = "nameless"
		elif kind == "face_theft":
			kind = "faceless"
			target.roster.face_state = "faceless"
	elif kind in ["charm","stun","cry_stun","root","drag","revealed","misname","water_slow"]:
		var answer: Dictionary = growth().apply_status(target,kind,duration,source)
		if kind == "revealed":
			target.roster.marked = true
			target.roster.statuses.erase("dream")
		return answer
	var values := extra.duplicate(true)
	values.left = maxf(0.01,duration)
	values.source_id = source.instance_id if is_instance_valid(source) else ""
	target.roster.statuses[kind] = values
	event(kind,target,values.source_id)
	visual(kind,target)
	return ok()

func drain_names(amount: float, source: Node2D = null) -> float:
	if amount <= 0: return 0
	if humans.block_register_erase(source): return 0
	if float(state.get("register_ward",0)) > 0: amount *= float(state.register_ward_multiplier)
	var before: float = session.names
	session.names = maxf(0,before-amount)
	if before > session.names:
		state.last_erased_by = str(source.unit_id) if is_instance_valid(source) else ""
	if is_instance_valid(source):
		event("names_drained",source,str(before-session.names))
	return before-session.names

func restore_names(amount: float, source: Node2D = null) -> float:
	if amount <= 0: return 0
	if source != null: amount = ghosts.name_reward(source,source,amount)
	amount *= session.rekindle_multiplier()
	var before: float = session.names
	session.names = minf(float(Data.mode_rules.limits.names_max),before+amount)
	return session.names-before

func heal(target: Node2D, amount: float, source: Node2D = null) -> float:
	amount = ghosts.heal_modifier(target,amount,source)
	if target.unit_id == "H31": return 0
	for other in near(target,3,true):
		if other.unit_id == "H16": amount *= float(params(other).healing_multiplier)
	return growth().heal(target,amount) if amount > 0 else 0.0

func set_allegiance(target: Node2D, side: String, _duration: float, source: Node2D = null) -> void:
	if not is_instance_valid(target) or target.dead or side not in ["xianghuo","yegui"] or target.side == side: return
	var previous: String = target.side
	sim().humans.erase(target)
	sim().targets.erase(target)
	target.side = side
	if side == "xianghuo":
		if not sim().world.can_deploy_at(target.current_post): target.current_post = nearest_post(target)
		target.brain = sim().HumanAI.new(sim(),target)
		sim().humans.append(target)
	else:
		target.brain = preload("res://src/ai/GhostBrain.gd").new(sim(),target,sim().tide)
		if sim().world.is_upper_floor(target.floor_id): target.brain.stage = "upper"
		elif target.position.x >= Rules.body_to_px(float(sim().tide.config.descent.to_x)): target.brain.stage = "rear"
		sim().targets.append(target)
	target.sync_meta()
	sim()._update_units()
	sim().unit_allegiance_changed.emit(target,previous,side)
	event("allegiance",target,previous+"->"+side)
	visual("misrecord",target)

func nearest_post(unit: Node2D) -> String:
	var closest := "post_register"
	var distance := INF
	for spec in sim().world.layout.posts:
		if not bool(spec.default_deployment) or int(spec.floor_id) != unit.floor_id: continue
		var post: Node2D = sim().world.get_node(spec.id)
		if post.position.distance_squared_to(unit.position) < distance:
			distance = post.position.distance_squared_to(unit.position)
			closest = str(spec.id)
	return closest

func damage_multiplier(attacker: Node2D, victim: Node2D, kind: String) -> float:
	return humans.damage_multiplier(attacker,victim,kind)*ghosts.damage_multiplier(attacker,victim,kind)

func speed_multiplier(unit: Node2D, base := 1.0) -> float:
	ensure(unit)
	var value: float = base*ghosts.speed_multiplier(unit)
	if unit.unit_id == "H15":
		if growth().in_environment(unit,"water") and not growth().has(unit,"Y05"): value /= float(growth().rules().environment.water_speed_multiplier)
		if unit.growth.statuses.has("water_slow") and not growth().has(unit,"Y05"): value /= float(growth().rules().skills.river_slow_multiplier)
	if unit.roster.statuses.has("chain"): value = 0.0
	if unit.unit_id == "H08": value = maxf(float(params(unit).min_speed_multiplier),value*clampf(session.names/float(Data.mode_rules.limits.names_max),0,1))
	return value

func defense_for(unit: Node2D, base: float) -> float:
	if unit.roster.statuses.has("armor_down"): base *= 1-float(unit.roster.statuses.armor_down.get("fraction",.25))
	if unit.roster.statuses.has("cry_weak"): base *= float(unit.roster.statuses.cry_weak.get("multiplier",.8))
	return maxf(0,humans.defense_for(unit,base))

func before_receive(unit: Node2D, amount: float, attacker: Node2D, kind: String) -> float:
	ensure(unit)
	return ghosts.before_receive(unit,humans.before_receive(unit,amount,attacker,kind),attacker,kind)

func after_damage(attacker: Node2D, victim: Node2D, amount: float, kind: String, before: float) -> void:
	humans.after_damage(attacker,victim,amount,kind,before)
	ghosts.after_damage(attacker,victim,amount,kind,before)

func on_death(unit: Node2D, killer: Node2D = null) -> void:
	ensure(unit)
	if bool(unit.roster.counters.get("death_noted",false)): return
	unit.roster.counters.death_noted = true
	var opposing_killer := str(killer.unit_id) if is_instance_valid(killer) and killer.side != unit.side else ""
	if unit.side == "xianghuo" and unit.role == "ritual":
		state.last_reader_killer_id = opposing_killer
	if session.is_ritual_ward(unit):
		state.last_ward_killer_id = opposing_killer
	if not opposing_killer.is_empty():
		state.last_killer_id = opposing_killer
		session.codex.resolve(unit.unit_id,"defeated")
	humans.on_death(unit,killer)
	ghosts.on_death(unit,killer)
	event("defeated",unit,str(killer.unit_id) if is_instance_valid(killer) else "")

func before_structure_damage(attacker: Node2D, object: Node2D, amount: float) -> float:
	return ghosts.before_structure_damage(attacker,object,humans.before_structure_damage(attacker,object,amount))

func ritual_duration(caster: Node2D, target: Node2D, base: float) -> float:
	return ghosts.ritual_duration(caster,target,humans.ritual_duration(caster,target,base))

func ritual_completed(caster: Node2D, target: Node2D) -> bool:
	humans.ritual_completed(caster,target)
	return ghosts.ritual_completed(caster,target)

func name_reward(caster: Node2D, target: Node2D, base: float) -> float:
	return ghosts.name_reward(caster,target,base)

func break_path(id: String) -> bool:
	if not sim().world.path_is_open(id) or sim().world.stair_link(id).is_empty(): return false
	state.broken_paths.append(id)
	sim().world.set_meta("broken_paths",state.broken_paths.duplicate())
	sim().world.break_path_structure(id)
	sim().world.redraw_geometry()
	return true

func path_broken(id: String) -> bool:
	return id in state.get("broken_paths",[])

func snapshot() -> Dictionary:
	if not enabled: return {}
	state.rng_state = str(rng.state)
	return canonical(state)

func restore(value: Dictionary) -> void:
	state = value.duplicate(true)
	enabled = not state.is_empty() and bool(state.get("enabled",false))
	if enabled:
		rng.state = int(state.rng_state)
		sim().world.set_meta("broken_paths",state.get("broken_paths",[]).duplicate())

static func valid_state(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.get("enabled") != true or not value.get("seed") is String or not value.get("rng_state") is String or not str(value.rng_state).is_valid_int(): return false
	for key in ["time","register_ward","register_ward_multiplier"]:
		if not _number(value.get(key)) or float(value[key]) < 0: return false
	if value.has("focus_fire_id") and not value.focus_fire_id is String: return false
	if not value.get("broken_paths") is Array: return false
	for id in value.broken_paths:
		if not id is String or id not in ["stair_main","stair_beam","stair_rear","stair_side_entry","stair_side_exit","stair_water_entry","stair_water_exit","stair_stone_entry","stair_stone_exit","stair_side_hall"]: return false
	if not value.get("effects",[]) is Array: return false
	for effect in value.get("effects",[]):
		if not effect is Dictionary or not effect.get("unit_id") is String or not effect.get("kind") is String or not _point(effect.get("point")) or not _point(effect.get("source")): return false
		if not _number(effect.get("left")) or not _number(effect.get("duration")) or float(effect.left)<0 or float(effect.duration)<=0: return false
	return _plain(value)

static func valid_unit_state(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.get("face_state") not in ["faced","faceless"] or not value.get("marked") is bool or not value.get("initialized") is bool: return false
	if not _number(value.get("reserve_incense")) or float(value.reserve_incense) < 0: return false
	for key in ["cooldowns","statuses","counters"]:
		if not value.get(key) is Dictionary: return false
	for key in value.cooldowns:
		if not _number(value.cooldowns[key]) or float(value.cooldowns[key]) < 0: return false
	for key in value.statuses:
		if not value.statuses[key] is Dictionary or not _number(value.statuses[key].get("left")) or float(value.statuses[key].left)<0: return false
	if value.has("hunt"):
		var job = value.hunt
		if not job is Dictionary or not job.get("target_id") is String or not job.get("post") is String or not _point(job.get("goal")) or not _point(job.get("home")): return false
		for key in ["elapsed","outside"]:
			if not _number(job.get(key)) or float(job[key])<0: return false
		if not job.get("returning") is bool or not job.get("hit") is bool: return false
	for key in ["exterior_route","mechanism_route"]:
		if not value.has(key): continue
		if not value[key] is Array or value[key].size()>64: return false
		for step in value[key]:
			if key=="exterior_route":
				if not _point(step): return false
			elif not step is Dictionary or not _point(step.get("point")) or not _number(step.get("floor")) or not step.get("stair") is bool: return false
	return Ghosts.valid_state(value) and _plain(value)

static func _point(value: Variant) -> bool:
	return value is Array and value.size()==2 and _number(value[0]) and _number(value[1])

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(value))

static func _plain(value: Variant, depth := 0) -> bool:
	if depth > 12: return false
	if value is Dictionary:
		if value.size() > 1024: return false
		for key in value:
			if not typeof(key) in [TYPE_STRING,TYPE_STRING_NAME] or not _plain(value[key],depth+1): return false
	elif value is Array:
		if value.size() > 1024: return false
		for item in value:
			if not _plain(item,depth+1): return false
	elif value is float:
		return is_finite(value)
	elif not typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING]: return false
	return true

static func canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var output: Dictionary = {}
		for key in value: output[str(key)] = canonical(value[key])
		return output
	if value is Array:
		var output: Array = []
		for item in value: output.append(canonical(item))
		return output
	return value
