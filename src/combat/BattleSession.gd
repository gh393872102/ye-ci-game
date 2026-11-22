extends Node
## P4 decisions and objectives on the shared P2/P3 simulation. All costs live in data.
const Growth = preload("res://src/growth/GrowthEngine.gd")
const Codex = preload("res://src/progression/CodexStore.gd")
const Roster = preload("res://src/roster/RosterEngine.gd")
const Ritual = preload("res://src/rituals/BattleRitual.gd")
const GROWTH_ACTIONS := ["equip_item","unequip_item","mutate_form","fuse","stamp_job","borrow_god","use_key"]
var growth: RefCounted
var roster: RefCounted
var ritual: RefCounted
var ritual_row: Dictionary:
	get: return ritual.row
var codex: RefCounted
var simulation: Node2D
var mode := ""
var active := true
var running := false
signal command_applied(seat: String, action: String, arguments: Dictionary, origin: String)
signal ledger_recorded(action: String, detail: String)
var input_locked := false
var simulation_speed := 1.0
var dual_enabled := false
var player_seat := ""
var wallets: Dictionary = {}
var _legacy_incense := 0.0
var _command_seat := ""
var _command_origin := "player"
var incense: float:
	get:
		return float(wallets.get(_effective_seat(),0)) if dual_enabled else _legacy_incense
	set(value):
		if dual_enabled:
			wallets[_effective_seat()] = value
		else:
			_legacy_incense = value
signal renown_changed(value: float)
var names := 0.0:
	set(value):
		if names == value:
			return
		names = value
		renown_changed.emit(value)
var remaining := 0.0
var result: Dictionary = {}
var pending_purchase := ""
var rules: Dictionary = {}
var warnings: Array[String] = []
var ledger: Array[Dictionary] = []
var repair_jobs: Array[Dictionary] = []
var reinforce_left := 0.0
var reinforce_count := 0
var occupation := 0.0
var extinguish_left := 0.0
var first_breach: Dictionary = {}
var _reserved_cost := 0.0

func _init() -> void:
	ritual = Ritual.new(self)
	growth = Growth.new(self)
	roster = Roster.new(self)
	codex = Codex.new("",false)
	rules = Data.battle_rules.duplicate(true)

func start_battle(seat: String) -> Dictionary:
	if seat not in ["shouxiang", "duoming"] or simulation == null or not simulation.tide_enabled:
		return _reject("P4_INVALID_MODE")
	if running and active:
		return _reject("P4_BATTLE_RUNNING")
	_clear_p10_stage()
	ritual.reset()
	growth = Growth.new(self)
	roster = Roster.new(self)
	codex = Codex.new("",false)
	dual_enabled = false
	wallets.clear()
	player_seat = seat
	_command_seat = ""
	_command_origin = "player"
	mode = seat
	active = true
	running = false
	pending_purchase = ""
	_reserved_cost = 0
	repair_jobs.clear()
	ledger.clear()
	warnings.clear()
	result.clear()
	first_breach.clear()
	occupation = 0
	reinforce_count = 0
	reinforce_left = 0
	extinguish_left = float(rules.extinguish_seconds)
	incense = float(rules.starting_incense[mode])
	names = float(rules.starting_names)
	remaining = float(rules.duration)
	simulation.reset_preset("preset_hold_g0")
	running = true
	_record("start", 0, mode)
	_update_warnings()
	return _ok()

func enter_debug() -> void:
	# P3 debug presets deliberately do not settle a P4 match or consume its resource.
	active = false
	running = false
	_clear_p10_stage()
	ritual.reset()
	pending_purchase = ""
	_reserved_cost = 0
	repair_jobs.clear()
	warnings.clear()
	if simulation != null:
		for unit in simulation.humans:
			unit.brain.channel.cancel("CHANNEL_CANCELLED")
			unit.brain.repair_door = null
			if unit.brain.purpose in ["repair", "repair_return"]:
				unit.brain.route.clear()

func _available(seat: String) -> String:
	if not active or not running or not result.is_empty():
		return "P4_NOT_RUNNING"
	if input_locked and _command_origin == "player":
		return "P6_READ_ONLY"
	if dual_enabled:
		if _command_seat.is_empty() and player_seat.is_empty():
			return "P6_READ_ONLY"
		if _effective_seat() != seat:
			return "P4_WRONG_SEAT"
	elif mode != seat:
		return "P4_WRONG_SEAT"
	return ""

func _owned(unit: Node2D, side: String) -> bool:
	return is_instance_valid(unit) and unit in (simulation.humans if side == "xianghuo" else simulation.targets) and not unit.dead and unit.side == side and unit.simulation == simulation

func _purchase_reason(id: String) -> String:
	var invalid := _available("shouxiang")
	if not invalid.is_empty():
		return invalid
	if not rules.purchases.has(id):
		return "P4_UNKNOWN_PURCHASE"
	if not pending_purchase.is_empty():
		return "P4_PURCHASE_PENDING"
	var count := 0
	var named := id.begins_with("H")
	for unit in simulation.humans:
		if unit.dead:
			continue
		if named and unit.unit_id == id:
			return "P4_NAMED_PRESENT"
		if unit.unit_id.begins_with("H") == named:
			count += 1
	if count >= int(rules.named_cap if named else rules.troop_cap):
		return "P4_UNIT_CAP"
	if incense < float(rules.purchases[id]):
		return "P4_NO_INCENSE"
	return ""

func purchase_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for id in rules.purchases:
		var reason := _purchase_reason(id)
		options.append({"id":id, "cost":rules.purchases[id], "allowed":reason.is_empty(), "reason":reason})
	return options

func legal_posts(id: String = "", already_owned := false) -> Array[String]:
	var posts: Array[String] = []
	if simulation == null:
		return posts
	for post in simulation.world.posts:
		if deployment_reason(str(post.name), id, already_owned).is_empty():
			posts.append(str(post.name))
	return posts

func deployment_reason(post_id: String, id: String, already_owned := false) -> String:
	if not simulation.world.can_deploy_at(post_id):
		return "P4_ILLEGAL_POST"
	if not id.is_empty() and (not Data.combat_profiles.has(id) or (not already_owned and not rules.purchases.has(id))):
		return "P4_UNKNOWN_PURCHASE"
	var post: Marker2D = simulation.world.get_node(post_id)
	if not id.is_empty():
		var role: String = Data.combat_profiles[id].role
		if role == "talisman":
			role = "crossbow"
		if not role in post.get_meta("allowed_roles"):
			return "P4_POST_ROLE"
	if post_vacancies(post_id) == 0:
		return "P4_POST_FULL"
	return ""

func post_vacancies(post_id: String) -> int:
	var occupants := 0
	for unit in simulation.humans:
		if not unit.dead and unit.current_post == post_id:
			occupants += 1
	return maxi(0, int(rules.post_cap) - occupants)

func purchase(id: String) -> Dictionary:
	var reason := _purchase_reason(id)
	if not reason.is_empty():
		return _reject(reason)
	_reserved_cost = float(rules.purchases[id])
	incense -= _reserved_cost
	pending_purchase = id
	_record("purchase_reserved", -_reserved_cost, id)
	_emit_command("shouxiang","purchase",{"id":id})
	return _ok()

func deploy_at(post_id: String) -> Dictionary:
	var reason := _available("shouxiang")
	if not reason.is_empty():
		return _reject(reason)
	if pending_purchase.is_empty():
		return _reject("P4_NO_PURCHASE")
	reason = deployment_reason(post_id, pending_purchase)
	if not reason.is_empty():
		return _reject(reason)
	# Recheck caps and unique identities after a reservation, without charging twice.
	var id := pending_purchase
	var count := 0
	for actor in simulation.humans:
		if actor.dead:
			continue
		if id.begins_with("H") and actor.unit_id == id:
			return _reject("P4_NAMED_PRESENT")
		if actor.unit_id.begins_with("H") == id.begins_with("H"):
			count += 1
	if count >= int(rules.named_cap if id.begins_with("H") else rules.troop_cap):
		return _reject("P4_UNIT_CAP")
	var unit: Node2D = simulation.spawn_human(id, post_id)
	if unit == null:
		return _reject("P4_ILLEGAL_POST")
	unit.position = simulation.post_destination(unit, post_id)
	unit.brain.settled_position = unit.position
	pending_purchase = ""
	_reserved_cost = 0
	_record("deployed", 0, "%s:%s" % [id, post_id])
	_emit_command("shouxiang","deploy_at",{"post_id":post_id})
	return {"ok":true, "reason":"P4_DEPLOYED", "unit":unit}

func cancel_purchase() -> Dictionary:
	var reason := _available("shouxiang")
	if not reason.is_empty():
		return _reject(reason)
	if pending_purchase.is_empty():
		return _reject("P4_NO_PURCHASE")
	_refund_pending()
	_emit_command("shouxiang","cancel_purchase",{})
	return _ok()

func preview_upgrade(unit: Node2D) -> Dictionary:
	var reason := _available("shouxiang")
	if reason.is_empty() and not _owned(unit, "xianghuo"):
		reason = "P4_INVALID_UNIT"
	if reason.is_empty() and unit.upgrade_level >= int(rules.upgrade.max_level):
		reason = "P4_UPGRADE_CAP"
	if reason.is_empty() and incense < float(rules.upgrade.cost):
		reason = "P4_NO_INCENSE"
	var valid := _owned(unit, "xianghuo")
	return {"cost":rules.upgrade.cost, "hp_bonus":rules.upgrade.hp, "defense_bonus":rules.upgrade.defense,
		"current_hp":unit.max_hp if valid else 0, "next_hp":unit.max_hp + float(rules.upgrade.hp) if valid else 0,
		"current_defense":unit.defense if valid else 0, "next_defense":unit.defense + float(rules.upgrade.defense) if valid else 0,
		"allowed":reason.is_empty(), "reason":reason}

func upgrade(unit: Node2D) -> Dictionary:
	var preview := preview_upgrade(unit)
	if not preview.allowed:
		return _reject(preview.reason)
	incense -= float(rules.upgrade.cost)
	unit.upgrade_level += 1
	unit.max_hp += float(rules.upgrade.hp)
	unit.hp += float(rules.upgrade.hp)
	unit.defense += float(rules.upgrade.defense)
	if growth.enabled: growth.refresh_base(unit)
	_record("upgrade", -float(rules.upgrade.cost), unit.instance_id)
	_emit_command("shouxiang","upgrade",{"unit_id":unit.instance_id})
	return _ok()

func equip(unit: Node2D) -> Dictionary:
	if growth.enabled: return _reject("P7_USE_SLOTS")
	var reason := _available("shouxiang")
	if not reason.is_empty():
		return _reject(reason)
	if not _owned(unit, "xianghuo"):
		return _reject("P4_INVALID_UNIT")
	if not unit.equipment_id.is_empty():
		return _reject("P4_EQUIPMENT_FULL")
	if incense < float(rules.equipment.cost):
		return _reject("P4_NO_INCENSE")
	incense -= float(rules.equipment.cost)
	unit.equipment_id = str(rules.equipment.id)
	unit.max_hp += float(rules.equipment.hp)
	unit.hp += float(rules.equipment.hp)
	unit.defense += float(rules.equipment.defense)
	_record("equip", -float(rules.equipment.cost), unit.instance_id)
	_emit_command("shouxiang","equip",{"unit_id":unit.instance_id})
	return _ok()

func preview_ritual(caster: Node2D, target: Node2D) -> Dictionary:
	var reason := _available("shouxiang")
	if not reason.is_empty():
		return {"reason":reason, "hint":reason}
	if not _owned(caster, "xianghuo") or not _owned(target, "yegui") or caster.role != "ritual":
		return {"reason":"P4_INVALID_RITUAL", "hint":"P9_RITUAL_PICK"}
	if roster.enabled and (not roster.can_act(caster) or not growth.can_act(caster) or caster.roster.statuses.has("nameless")):
		return {"reason":"P8_SKILL_BLOCKED", "hint":"P8_SKILL_BLOCKED"}
	if caster.brain.channel.active:
		return {"reason":"P4_RITUAL_ACTIVE", "hint":"P4_RITUAL_ACTIVE"}
	if not caster.brain.route.is_empty():
		return {"reason":"P4_RITUAL_RANGE", "hint":"P9_RITUAL_MOVING"}
	var hint: String = caster.brain.channel.target_reason(simulation, caster, target)
	if not hint.is_empty():
		return {"reason":"P4_RITUAL_RANGE", "hint":hint}
	var cost: float = growth.ritual_cost(caster, float(rules.ritual.cost)) if growth.enabled else float(rules.ritual.cost)
	if incense < cost:
		return {"reason":"P4_NO_INCENSE", "hint":"P4_NO_INCENSE"}
	return {"reason":"", "hint":"", "cost":cost, "duration":configured_ritual_duration(caster,target)}

func configured_ritual_duration(caster: Node2D, target: Node2D) -> float:
	var duration := float(rules.ritual.duration)
	if growth.enabled:
		duration = growth.ritual_duration(caster, target, duration)
	if roster.enabled:
		duration = roster.ritual_duration(caster, target, duration)
	return duration * float(ritual.param("ritual_duration_multiplier",1.0))

func start_ritual(caster: Node2D, target: Node2D) -> Dictionary:
	var preview := preview_ritual(caster, target)
	if not preview.reason.is_empty():
		return _reject(preview.reason)
	var ritual_cost: float = preview.cost
	if not caster.brain.channel.start(simulation, caster, target):
		return _reject("P4_RITUAL_RANGE")
	caster.brain.last_channel_target = target.instance_id
	if roster.enabled and caster.unit_id=="H01":
		roster.status(target,"revealed",float(roster.params(caster).reveal_seconds),caster)
		roster.cooldown(caster,float(roster.params(caster).cooldown))
	incense -= ritual_cost
	_record("ritual_start", -ritual_cost, target.instance_id)
	_emit_command("shouxiang","start_ritual",{"caster_id":caster.instance_id,"target_id":target.instance_id})
	simulation.vfx.invalidate()
	return _ok()

func ritual_completed(caster: Node2D, target: Node2D) -> void:
	if not active or not running or not _owned(caster,"xianghuo") or not _owned(target,"yegui"):
		return
	var channel: RefCounted = caster.brain.channel
	if not channel.paid or channel.target != target or channel.elapsed < channel.duration or channel.last_result != "P4_RITUAL_COMPLETED":
		return
	# Purification removes the living target from combat, rather than inflicting damage.
	var retained: bool = roster.ritual_completed(caster,target) if roster.enabled else false
	if retained:
		codex.resolve(target.unit_id,"protected_reading")
		if target.unit_id=="G32" and float(target.roster.get("ghost",{}).get("naming_left",0))>0: codex.list_name(target.unit_id)
		return
	var name_gain := float(rules.ritual.reward_names)
	if target.unit_id == ritual.param("water_ghost",""):
		name_gain += float(ritual.param("purified_names",0.0))
	if roster.enabled:
		name_gain = roster.name_reward(caster,target,name_gain)
	name_gain *= rekindle_multiplier()
	var recruited: bool = growth.ritual_completed(caster,target) if growth.enabled else false
	if not recruited:
		target.dead = true
		target.corpse_left = Rules.CORPSE_SECONDS
		target.attacks_enabled = false
		target.motion_enabled = false
		target.set_state("Purified")
	if dual_enabled:
		wallets.shouxiang = minf(float(rules.incense_cap) - _reserved_cost, incense_for("shouxiang") + float(rules.ritual.reward_incense))
	else:
		incense = minf(float(rules.incense_cap), incense + float(rules.ritual.reward_incense))
	var names_before_credit := names
	names = minf(float(Data.mode_rules.limits.names_max),names+name_gain) if roster.enabled else names+name_gain
	if roster.enabled:
		codex.resolve(target.unit_id,"purified")
		target.roster.counters.death_noted = true
	_record("ritual_completed", float(rules.ritual.reward_incense), target.instance_id, names-names_before_credit, "shouxiang")
	simulation.tide.effect("purified", target.position, target.instance_id)
	simulation.vfx.purification(target.position, recruited, names > names_before_credit)

func repair(door_id: String) -> Dictionary:
	var reason := _available("shouxiang")
	if not reason.is_empty():
		return _reject(reason)
	var door: Node2D = simulation.world.get_node_or_null(NodePath(door_id))
	if door == null or not door in simulation.world.doors or door.durability >= door.max_durability:
		return _reject("P4_INVALID_DOOR")
	if door.destroyed and not bool(rules.repair.rebuild_destroyed):
		return _reject("P4_INVALID_DOOR")
	for job in repair_jobs:
		if job.door == door:
			return _reject("P4_REPAIR_BUSY")
	var destination: Vector2 = door.position + Vector2(float(rules.repair.inside_offset), 0)
	if not simulation.world.is_walkable(destination, door.floor_id):
		return _reject("P4_REPAIR_ROUTE")
	var repairer: Node2D
	var best := INF
	var best_path: Array[Dictionary] = []
	var reachable_worker := false
	for unit in simulation.humans:
		if unit.dead or unit.role == "ritual" or unit.brain.repair_door != null or not unit.brain.route.is_empty():
			continue
		var path: Array[Dictionary] = simulation.world.navigation.route(unit.position, unit.floor_id, destination, door.floor_id, true)
		if path.is_empty():
			continue
		reachable_worker = true
		# Discounts belong to the actual worker; consider every affordable route.
		if growth.enabled and incense < growth.repair_cost(unit, float(rules.repair.cost)):
			continue
		var distance := 0.0
		var last: Vector2 = unit.position
		for step in path:
			distance += last.distance_to(step.point)
			last = step.point
		if distance < best:
			repairer = unit
			best = distance
			best_path = path
	if repairer == null:
		return _reject("P4_NO_INCENSE" if growth.enabled and reachable_worker else "P4_REPAIR_ROUTE")
	var repair_cost: float = growth.repair_cost(repairer,float(rules.repair.cost)) if growth.enabled else float(rules.repair.cost)
	if incense < repair_cost: return _reject("P4_NO_INCENSE")
	incense -= repair_cost
	repairer.brain.repair_door = door
	repairer.brain.route = best_path
	repairer.brain.purpose = "repair"
	repairer.brain.last_reason = ""
	repairer.set_state("RepairApproach")
	var job := {"unit":repairer,"door":door,"elapsed":0.0,"destination":destination}
	if growth.enabled:
		job.duration = growth.repair_duration(repairer,float(rules.repair.duration))
		job.heal = float(rules.repair.heal) * growth.repair_multiplier(repairer)
	repair_jobs.append(job)
	_record("repair_started", -repair_cost, door_id)
	_emit_command("shouxiang","repair",{"door_id":door_id})
	return {"ok":true,"reason":"P4_REPAIR_STARTED","unit":repairer}

func preview_mutation(unit: Node2D, form_id: String) -> Dictionary:
	var reason := _available("duoming")
	if reason.is_empty() and (not _owned(unit, "yegui") or unit.unit_id != "G01" or unit.mutation_count >= int(rules.mutation_limit)):
		reason = "P4_INVALID_MUTATION"
	if reason.is_empty() and not rules.mutations.has(form_id):
		reason = "P4_MUTATION_RESERVED"
	if reason.is_empty() and form_id == "G09" and (unit.floor_id != 0 or unit.position.x > Rules.body_to_px(float(simulation.tide.config.climb.from_x))):
		reason = "P4_MUTATION_PAST_CLIMB"
	var cost := float(rules.mutations.get(form_id, 0))
	if reason.is_empty() and incense < cost:
		reason = "P4_NO_INCENSE"
	return {"allowed":reason.is_empty(),"reason":reason,"cost":cost,"form_id":form_id}

func mutate(unit: Node2D, form_id: String) -> Dictionary:
	if growth.enabled:
		var form: String = {"G11":"V01","G09":"V02","G12":"V03"}.get(form_id,form_id)
		return growth.execute("mutate_form",{"unit_id":unit.instance_id if is_instance_valid(unit) else "","form_id":form})
	var preview := preview_mutation(unit, form_id)
	if not preview.allowed:
		return _reject(preview.reason)
	var cost: float = preview.cost
	var ratio: float = unit.hp / unit.max_hp
	var mutations: int = unit.mutation_count + 1
	var unique_id: String = unit.instance_id
	unit.configure(form_id, unique_id, simulation)
	unit.hp = unit.max_hp * ratio
	unit.mutation_count = mutations
	incense -= cost
	_record("mutate", -cost, "%s:%s" % [unique_id,form_id])
	simulation.tide.effect("mutation", unit.position, form_id)
	_emit_command("duoming","mutate",{"unit_id":unique_id,"form_id":form_id})
	return {"ok":true,"reason":"P4_MUTATED","unit":unit}

func window_recruits() -> int:
	if simulation.tide.config.get("supply_id","") != "G01": return 0
	return floori(float(rules.reinforce.count) / 2.0)

func paper_armor_targets() -> Array:
	var scouts := []
	if window_recruits() == 0: return scouts
	for unit in simulation.targets:
		if unit.unit_id=="G07" and unit.side=="yegui" and not unit.dead and not unit.roster.has("window_paper"):
			scouts.append(unit)
	scouts.sort_custom(func(a,b): return a.position.x>b.position.x if a.position.x!=b.position.x else a.instance_id<b.instance_id)
	return scouts.slice(0,window_recruits())

func reinforce(formation := "") -> Dictionary:
	var reason := _available("duoming")
	if not reason.is_empty():
		return _reject(reason)
	if ritual.has_flag("bridge_reinforcements") and simulation.tide.bridge_supply_cut():
		return _reject("P10_BRIDGE_SUPPLY_CUT")
	if reinforce_count >= int(rules.reinforce.limit):
		return _reject("P4_REINFORCE_LIMIT")
	if reinforce_left > 0:
		return _reject("P4_REINFORCE_COOLDOWN")
	if incense < float(rules.reinforce.cost):
		return _reject("P4_NO_INCENSE")
	var count := int(rules.reinforce.count)
	var id: String = simulation.tide.config.get("supply_id","G01")
	var detail := str(count)
	if formation == "paper":
		var recipients := paper_armor_targets()
		if recipients.is_empty(): return _reject("WINDOW_PAPER_NO_TARGET")
		for unit in recipients:
			unit.roster.window_paper = "ready"
			unit.queue_redraw()
		detail = "纸甲 × %d" % recipients.size()
	else:
		if not formation.is_empty():
			if formation != "window" or window_recruits() == 0: return _reject("P6_INVALID_ACTION")
			count = window_recruits()
			id = "G07"
			detail = "%s × %d" % [id,count]
		if simulation.targets.size() + simulation.tide.pending.size() + count > int(simulation.tide.config.capacity):
			return _reject("P4_TIDE_CAP")
		for index in count:
			simulation.tide.pending.append(id)
	incense -= float(rules.reinforce.cost)
	reinforce_count += 1
	reinforce_left = float(rules.reinforce.cooldown)
	_record("reinforce", -float(rules.reinforce.cost), detail)
	_emit_command("duoming","reinforce",{} if formation.is_empty() else {"formation":formation})
	return _ok()

func advance(delta: float) -> void:
	if not active or not running or delta <= 0:
		return
	if not input_locked: simulation_speed = Clock.resume_scale
	remaining = maxf(0, remaining - delta)
	if remaining < 0.000001:
		remaining = 0.0
	var regenerated := float(rules.incense_regen) * float(ritual.param("incense_regen_multiplier",1.0)) * delta
	if dual_enabled:
		for seat in ["shouxiang","duoming"]:
			var reserved := _reserved_cost if seat == "shouxiang" else 0.0
			wallets[seat] = minf(float(rules.incense_cap) - reserved, incense_for(seat) + regenerated)
	else:
		incense = minf(float(rules.incense_cap) - _reserved_cost, incense + regenerated)
	reinforce_left = maxf(0, reinforce_left - delta)

func after_step(delta: float) -> void:
	if not active or not running or delta <= 0:
		return
	_capture_first_breach()
	_advance_repairs(delta)
	var ritual_failure: String = ritual.advance(delta)
	if not ritual_failure.is_empty():
		_update_warnings()
		_finish("victory" if mode == "duoming" and not dual_enabled else "defeat",ritual_failure)
		return
	var hostile := 0
	var defenders := 0
	for unit in simulation.targets:
		if not unit.dead and simulation.world.room_at(unit.position, unit.floor_id) == "register":
			hostile += 1
	for unit in simulation.humans:
		if not unit.dead and simulation.world.room_at(unit.position, unit.floor_id) == "register":
			defenders += 1
	# Any live defender contests the room. Reinforcement/recovery really reverses capture.
	if hostile > 0 and defenders == 0:
		occupation += delta
		if roster.enabled:
			var source: Node2D
			for unit in simulation.targets:
				if not unit.dead and simulation.world.room_at(unit.position,unit.floor_id)=="register": source=unit;break
			roster.drain_names(float(rules.name_drain_per_second)*delta,source)
		else: names = maxf(0, names - float(rules.name_drain_per_second) * delta)
	else:
		occupation = maxf(0, occupation - float(rules.occupation_recovery) * delta)
	if names <= 0:
		extinguish_left = maxf(0, extinguish_left - delta)
	else:
		extinguish_left = float(rules.extinguish_seconds)
	_update_warnings()
	if dual_enabled:
		if names <= 0 and extinguish_left <= 0:
			_finish("defeat","P4_END_REGISTER_EXTINGUISHED")
		elif occupation >= float(rules.occupation_seconds):
			_finish("defeat","P4_END_REGISTER_CAPTURED")
		elif _ritual_line_broken():
			_finish("defeat","P4_END_RITUAL_LINE_BROKEN")
		elif remaining <= 0:
			_finish("victory","P4_END_HELD_TO_DAYBREAK")
		elif _tide_exhausted():
			_finish("victory","P4_END_TIDE_EXHAUSTED")
		return
	if mode == "duoming":
		if names <= 0:
			_finish("victory", "P4_END_NAMES_DRAINED")
		elif occupation >= float(rules.occupation_seconds):
			_finish("victory", "P4_END_REGISTER_CAPTURED")
		elif remaining <= 0:
			_finish("defeat", "P4_END_DAYBREAK")
		elif _tide_exhausted():
			_finish("defeat", "P4_END_TIDE_EXHAUSTED")
	else:
		if names <= 0 and extinguish_left <= 0:
			_finish("defeat", "P4_END_REGISTER_EXTINGUISHED")
		elif occupation >= float(rules.occupation_seconds):
			_finish("defeat", "P4_END_REGISTER_CAPTURED")
		elif _ritual_line_broken():
			_finish("defeat", "P4_END_RITUAL_LINE_BROKEN")
		elif remaining <= 0:
			_finish("victory", "P4_END_HELD_TO_DAYBREAK")

func _capture_first_breach() -> void:
	if not first_breach.is_empty():
		return
	for door in simulation.world.doors:
		if door.destroyed:
			first_breach = {"time":simulation.simulation_time,"door":str(door.name)}
			_record("first_breach",0,str(door.name))
			return

func _advance_repairs(delta: float) -> void:
	for index in range(repair_jobs.size() - 1, -1, -1):
		var job: Dictionary = repair_jobs[index]
		var unit: Node2D = job.unit
		if not is_instance_valid(unit) or unit.dead or unit.brain.repair_door != job.door:
			_record("repair_interrupted",0,str(job.door.name),0,"shouxiang")
			repair_jobs.remove_at(index)
			continue
		if not unit.brain.route.is_empty():
			continue
		if unit.floor_id != job.door.floor_id or unit.position.distance_to(job.destination) > 2:
			unit.brain.repair_door = null
			repair_jobs.remove_at(index)
			_record("repair_interrupted",0,str(job.door.name),0,"shouxiang")
			continue
		job.elapsed += delta
		unit.set_state("Repair")
		if job.elapsed < float(job.get("duration",rules.repair.duration)):
			continue
		var door: Node2D = job.door
		door.set_durability(door.durability + float(job.get("heal",rules.repair.heal)))
		if door.destroyed and door.durability > 0:
			door.destroyed = false
			door.set_open(false)
		unit.brain.repair_door = null
		unit.brain.purpose = "repair_return"
		unit.brain.route = simulation.world.navigation.route(unit.position, unit.floor_id, unit.brain.settled_position, int(simulation.world.get_node(unit.current_post).get_meta("floor_id")), true)
		_record("repair_completed",0,str(door.name),0,"shouxiang")
		repair_jobs.remove_at(index)

func _ritual_line_broken() -> bool:
	for unit in simulation.humans:
		if not unit.dead and (unit.role == "ritual" or (growth.enabled and growth.state.get("defense_objective", "") == "hold_register" and unit.unit_id.begins_with("H"))):
			return false
	if growth.enabled:
		# P7 adds priests cheaper than H01. Evaluate the actual purchase space,
		# independently of the current viewer seat or the command caller.
		var named_count := 0
		for unit in simulation.humans:
			if not unit.dead and unit.unit_id.begins_with("H"):
				named_count += 1
		if named_count >= int(rules.named_cap):
			return true
		var available_incense := incense_for("shouxiang") + _reserved_cost
		for id in rules.purchases:
			if Data.combat_profiles.get(id,{}).get("role","") != "ritual":
				continue
			if available_incense >= float(rules.purchases[id]) and not legal_posts(id).is_empty():
				return false
		return true
	return incense_for("shouxiang") + _reserved_cost < float(rules.purchases.H01) and pending_purchase != "H01"

func _tide_exhausted() -> bool:
	if not simulation.targets.is_empty() or not simulation.tide.pending.is_empty() or simulation.tide.wave_index < simulation.tide.config.waves.size() or simulation.tide.has_chunk_supply():
		return false
	# With regeneration and an unused reinforcement, the side can still replenish later.
	return simulation.tide.bridge_supply_cut() or reinforce_count >= int(rules.reinforce.limit) or (float(rules.incense_regen) <= 0 and incense_for("duoming") < float(rules.reinforce.cost))

func _update_warnings() -> void:
	warnings.clear()
	if ritual.upper_occupation > 0.0:
		_warn("P10_WARN_UPPER_UNHELD")
	if ritual.has_flag("register_seep"):
		_warn("P10_WARN_NAME_SEEP")
	for door in simulation.world.doors:
		if door.destroyed:
			_warn("P4_WARN_DOOR_BROKEN")
		elif door.durability / door.max_durability <= float(rules.door_warning_ratio):
			_warn("P4_WARN_DOOR_CRITICAL")
	if names <= 0:
		_warn("P4_WARN_REGISTER_EXTINGUISHING")
	elif names <= float(rules.name_warning) or occupation > 0:
		_warn("P4_WARN_REGISTER_CRITICAL")
	for unit in simulation.targets:
		if simulation.world.is_upper_floor(unit.floor_id) and not unit.dead:
			_warn("P4_WARN_UPPER_PRESSURE")
			break

func _warn(key: String) -> void:
	if not warnings.has(key):
		warnings.append(key)

func _finish(outcome: String, reason: String) -> void:
	if not running:
		return
	if not pending_purchase.is_empty():
		_refund_pending()
	running = false
	result = {"outcome":outcome,"reason":reason,"mode":mode,"incense":incense_for("shouxiang") if dual_enabled else incense,"names":names,
		"remaining":remaining,"elapsed":simulation.simulation_time,"first_breach":first_breach.duplicate(),
		"humans_alive":simulation.humans.size(),"tide_alive":simulation.targets.size()}
	if dual_enabled:
		result.winner = "shouxiang" if outcome == "victory" else "duoming"
		result.wallets = wallets.duplicate(true)
	if roster.enabled:
		result.killer_id = _failure_actor(reason)
		if outcome == "defeat":
			var seed_text := str(roster.state.seed)
			if not ledger.is_empty() and ledger[0].action == "night_node_start":
				seed_text = seed_text.trim_suffix(":" + str(ledger[0].detail))
			codex.record_failure(seed_text, str(result.killer_id), reason)
	_record("finish",0,reason)

func _failure_actor(reason: String) -> String:
	match reason:
		"P4_END_REGISTER_EXTINGUISHED", "P4_END_NAMES_DRAINED":
			return str(roster.state.get("last_erased_by", ""))
		"P4_END_REGISTER_CAPTURED":
			for actor in simulation.targets:
				if not actor.dead and simulation.world.room_at(actor.position, actor.floor_id) == "register":
					return actor.unit_id
		"P4_END_RITUAL_LINE_BROKEN":
			return str(roster.state.get("last_reader_killer_id", ""))
		"P10_END_WARD_LOST":
			return str(roster.state.get("last_ward_killer_id", ""))
		"P10_END_UPPER_LOST":
			var defended := {}
			for actor in simulation.humans:
				if not actor.dead and simulation.world.is_upper_floor(actor.floor_id) and simulation.world.inside_base(actor.position):
					defended[actor.floor_id] = true
			for actor in simulation.targets:
				if not actor.dead and simulation.world.is_upper_floor(actor.floor_id) and simulation.world.inside_base(actor.position) and not defended.has(actor.floor_id):
					return actor.unit_id
		"P4_END_TIDE_EXHAUSTED":
			return str(roster.state.get("last_killer_id", ""))
	return ""

func _record(action: String, incense_delta: float, detail: String, names_delta := 0.0, record_seat := "") -> void:
	var entry := {"time":simulation.simulation_time if simulation != null else 0,"action":action,"incense_delta":incense_delta,"names_delta":names_delta,"incense":incense_for(record_seat) if dual_enabled and not record_seat.is_empty() else incense,"names":names,"detail":detail}
	if dual_enabled:
		entry.seat = _effective_seat() if record_seat.is_empty() else record_seat
	ledger.append(entry)
	ledger_recorded.emit(action, detail)

func _ok() -> Dictionary:
	return {"ok":true,"reason":"P4_COMMAND_OK"}

func _reject(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

func _effective_seat() -> String:
	if not _command_seat.is_empty():
		return _command_seat
	return player_seat if player_seat in ["shouxiang","duoming"] else mode

func incense_for(seat: String) -> float:
	if dual_enabled: return float(wallets.get(seat,0))
	if growth.enabled and seat != mode: return float(growth.state.get("npc_incense",0))
	return _legacy_incense

func configure_dual(incense_by_seat: Dictionary, controlled_seat: String) -> Dictionary:
	if controlled_seat not in ["","shouxiang","duoming"]:
		return _reject("P6_INVALID_SEAT")
	for seat in ["shouxiang","duoming"]:
		var value = incense_by_seat.get(seat)
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0 or float(value) > float(rules.incense_cap):
			return _reject("P6_INVALID_WALLET")
	wallets = incense_by_seat.duplicate(true)
	player_seat = controlled_seat
	mode = "shouxiang"
	dual_enabled = true
	_command_seat = ""
	_command_origin = "player"
	return _ok()

func _refund_pending() -> void:
	if dual_enabled:
		wallets.shouxiang = incense_for("shouxiang") + _reserved_cost
	else:
		incense += _reserved_cost
	_record("purchase_cancelled", _reserved_cost, pending_purchase,0,"shouxiang")
	pending_purchase = ""
	_reserved_cost = 0

func _emit_command(seat: String, action: String, args: Dictionary) -> void:
	command_applied.emit(seat,action,args.duplicate(true),_command_origin)

func _actor(id: String) -> Node2D:
	if simulation == null:
		return null
	for unit in simulation.humans + simulation.targets:
		if unit.instance_id == id:
			return unit
	return null

func execute_for(seat: String, action: String, args: Dictionary = {}, origin := "ai") -> Dictionary:
	if seat not in ["shouxiang","duoming"]:
		return _reject("P6_INVALID_SEAT")
	if origin not in ["player","ai","director","replay"]:
		return _reject("P6_INVALID_ORIGIN")
	if origin == "player" and dual_enabled and (player_seat.is_empty() or seat != player_seat):
		return _reject("P6_READ_ONLY" if player_seat.is_empty() else "P6_PLAYER_SEAT")
	var queries := ["purchase_options","legal_posts","preview_upgrade","preview_mutation","preview_ritual"]
	if not action in queries and not action in preload("res://src/modes/Seat.gd").commands(seat):
		return _reject("P6_INVALID_ACTION")
	if not dual_enabled and mode != seat:
		return _reject("P4_WRONG_SEAT")
	var prior_seat := _command_seat
	var prior_origin := _command_origin
	_command_seat = seat
	_command_origin = origin
	var response: Dictionary
	match action:
		"unit_skill","mark_target": response = roster_command(action,args)
		"purchase": response = purchase(str(args.get("id","")))
		"deploy_at": response = deploy_at(str(args.get("post_id","")))
		"cancel_purchase": response = cancel_purchase()
		"upgrade": response = upgrade(_actor(str(args.get("unit_id",""))))
		"equip": response = equip(_actor(str(args.get("unit_id",""))))
		"start_ritual": response = start_ritual(_actor(str(args.get("caster_id",""))),_actor(str(args.get("target_id",""))))
		"repair": response = repair(str(args.get("door_id","")))
		"mutate": response = mutate(_actor(str(args.get("unit_id",""))),str(args.get("form_id","")))
		"reinforce": response = reinforce(str(args.get("formation","")))
		"purchase_options": response = {"ok":true,"reason":"P4_COMMAND_OK","data":purchase_options()}
		"legal_posts": response = {"ok":true,"reason":"P4_COMMAND_OK","data":legal_posts(str(args.get("id","")))}
		"preview_upgrade": response = {"ok":true,"reason":"P4_COMMAND_OK","data":preview_upgrade(_actor(str(args.get("unit_id",""))))}
		"preview_mutation": response = {"ok":true,"reason":"P4_COMMAND_OK","data":preview_mutation(_actor(str(args.get("unit_id",""))),str(args.get("form_id","")))}
		"preview_ritual": response = {"ok":true,"reason":"P4_COMMAND_OK","data":preview_ritual(_actor(str(args.get("caster_id",""))),_actor(str(args.get("target_id",""))))}
		_:
			response = growth.execute(action,args) if growth.enabled and action in GROWTH_ACTIONS else _reject("P6_INVALID_ACTION")
	_command_seat = prior_seat
	_command_origin = prior_origin
	return response

func configure_growth(seed_text: String, initial: Dictionary = {}) -> void:
	growth.configure(seed_text,initial)
	var night: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/nights/p7_growth_night.json"))
	for id in night.get("roster_prices",{}):
		if str(id).begins_with("H") and Data.combat_profiles.has(id): rules.purchases[id] = float(night.roster_prices[id])

func configure_roster(seed_text: String, initial: Dictionary = {}) -> void:
	if not growth.enabled: configure_growth(seed_text)
	roster.configure(seed_text,initial)
	for unit in simulation.humans+simulation.targets: codex.encounter(unit.unit_id)

func configure_ritual(id: String, seed_text: String, first_battle := true, ward_hp := -1.0) -> bool:
	if not running or ritual.id != "R01" or not ritual.configure(id,seed_text,first_battle,ward_hp):
		return false
	_update_warnings()
	return true

func is_ritual_ward(unit: Node2D) -> bool:
	return ritual.wards(unit)

func ritual_ward_status() -> Dictionary:
	return ritual.ward_status()

func ritual_ward_actor() -> Node2D:
	return ritual.ward()

func ritual_snapshot() -> Dictionary:
	return ritual.snapshot()

func restore_ritual(value: Dictionary) -> void:
	ritual.restore(value)

static func valid_ritual_snapshot(value: Variant) -> bool:
	return Ritual.valid_snapshot(value)

func rekindle_multiplier() -> float:
	return float(get_meta("p10_rekindle_multiplier",1.0))

func _clear_p10_stage() -> void:
	if simulation != null and simulation.tide != null:
		simulation.tide.config.erase("bridge_reinforcements")
		if simulation.has_node("P10Stage"):
			load("res://src/data/StageOptions.gd").clear(self)

func roster_command(action: String, args: Dictionary) -> Dictionary:
	var reason := _available(_effective_seat())
	if not reason.is_empty(): return _reject(reason)
	if not roster.enabled: return _reject("P8_DISABLED")
	var allowed: Array = ["target_id"] if action == "mark_target" else ["unit_id","target_id","mode","object_id","path_id","confirm_market"]
	for key in args:
		if key not in allowed: return _reject("P8_INVALID_ARGUMENT")
		if key=="confirm_market":
			if not args[key] is bool: return _reject("P8_INVALID_ARGUMENT")
		elif not args[key] is String: return _reject("P8_INVALID_ARGUMENT")
	if args.has("mode") and args.mode not in ["pull","push"]: return _reject("P8_INVALID_ARGUMENT")
	var unit: Node2D = _actor(str(args.get("unit_id","")))
	if action == "mark_target":
		unit = _actor(str(args.get("target_id","")))
		if not is_instance_valid(unit) or unit.dead or unit.side != "yegui" or _effective_seat() != "shouxiang": return _reject("P8_INVALID_TARGET")
		roster.ensure(unit)
		unit.roster.marked = true
		roster.event("target_marked",unit)
		_emit_command("shouxiang",action,args)
		return roster.ok()
	if not _owned(unit,"xianghuo" if _effective_seat()=="shouxiang" else "yegui"): return _reject("P4_INVALID_UNIT")
	var result: Dictionary = roster.cast(unit,args)
	# H01 uses start_ritual's existing paid command; avoid recording it twice.
	if result.ok and (unit.unit_id != "H01" or result.reason == "P8_SKILL_MISFIRED"): _emit_command(_effective_seat(),action,args)
	return result
