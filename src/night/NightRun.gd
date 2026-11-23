extends RefCounted
## One local night: validated decisions, persistent resources, weighted offers and explicit recovery.
const Opening = preload("res://src/night/FactionOpening.gd")
const P10Plan = preload("res://src/night/P10NightPlan.gd")
const Chunks = preload("res://src/data/ChunkCatalog.gd")
const GrowthNight = preload("res://src/growth/GrowthNight.gd")
const Codex = preload("res://src/progression/CodexStore.gd")
const Roster = preload("res://src/roster/RosterEngine.gd")
const Story = preload("res://src/night/NightStory.gd")
var codex: RefCounted
const Growth = preload("res://src/growth/GrowthEngine.gd")
var base_config: Dictionary = {}
var _starting_growth := false
const Save = preload("res://src/night/NightSave.gd")
var config: Dictionary = {}
var state: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _posts: Dictionary = {}
var _chunk_posts: Dictionary = {}

func _init(rules: Dictionary = {}) -> void:
	codex = Codex.new("",false)
	base_config = (Data.night_rules if rules.is_empty() else rules).duplicate(true)
	config = base_config.duplicate(true)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/reference_gate_court.json"))
	for post in layout.posts:
		if post.default_deployment:
			_posts[str(post.id)] = post

func new_run(mode: String, kind := "example", seed_text := "") -> Dictionary:
	if mode not in ["shouxiang","duoming"] or kind != "example" or config.is_empty():
		return _reject("P5_INVALID_START")
	if not state.is_empty() and state.phase != "ended":
		return _reject("P5_NIGHT_RUNNING")
	if not _starting_growth: config = base_config.duplicate(true)
	if seed_text.is_empty():
		seed_text = "夜-%d-%d" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	_rng.seed = seed_text.hash()
	var build: Dictionary = {}
	for key in config.build_caps:
		build[key] = 0.0
	var previous_story: Dictionary = state.get("story", {})
	state = {"version":1,"phase":"map","mode":mode,"kind":kind,"seed":seed_text,"ritual":"example_incense",
		"incense":float(config.starting_incense[mode]),"names":float(config.starting_names),"roster":[],"fallen":[],
		"build":build,"visited":[],"completed":[],"current_node_id":"","offers":[],"purchased":[],
		"stats":{"battles":[],"elapsed":0.0},"battle_snapshot":{},"before_battle":{},"last_battle":{},
		"selected_rewards":[],"unlocks":{},"ledger":[],"mercy_used":false,"outcome":"","reason":"","serial":0,
		"rng_state":str(_rng.state)}
	if not previous_story.is_empty():
		state.story = Story.start(float(state.names), previous_story)
	for item in config.initial_roster[mode]:
		for index in int(item.count):
			state.roster.append(_unit(str(item.id),str(item.post)))
	_unlock_roster(state.roster)
	_record("new_night",{"mode":mode,"seed":seed_text,"initial_roster_note":config.initial_roster_note})
	return _ok()

func new_growth_run(mode: String, seed_text := "", build_id := "", faction := "") -> Dictionary:
	if not state.is_empty() and state.phase != "ended": return _reject("P5_NIGHT_RUNNING")
	if not faction.is_empty() and (not Opening.accepts(mode,faction) or not build_id.is_empty()):
		return _reject("P7_INVALID_BUILD")
	var catalog := GrowthNight.table()
	if mode not in ["shouxiang","duoming"] or (not build_id.is_empty() and (not catalog.paths.has(build_id) or catalog.paths[build_id].seat != mode)):
		return _reject("P7_INVALID_BUILD")
	config = GrowthNight.configure(base_config,build_id)
	if not faction.is_empty(): Opening.apply(config,faction)
	_starting_growth = true
	var answer := new_run(mode,"example",seed_text)
	_starting_growth = false
	if not answer.ok:
		config = base_config.duplicate(true)
		return answer
	state.departed = []
	state.growth_build_id = build_id
	state.growth = GrowthNight.initial(str(state.seed),mode,build_id)
	if Opening.FAMILIES.has(faction):
		state.opening_family = faction
	elif not faction.is_empty():
		state.opening_faction = faction
		state.growth.defense_objective = "hold_register"
	_record("growth_night",{"build_id":build_id})
	return answer

func new_roster_run(mode: String, seed_text := "", build_id := "", codex_path := "", ritual_id := "example_incense", faction := "") -> Dictionary:
	var answer := new_growth_run(mode,seed_text,build_id,faction)
	if not answer.ok: return answer
	codex = Codex.new(codex_path,not codex_path.is_empty())
	if not codex_path.is_empty() and FileAccess.file_exists(codex_path): codex.load_save()
	state.roster_enabled = true
	codex.encounter(_custom_entry(ritual_id))
	for unit in state.roster: codex.encounter(str(unit.id))
	for id in state.growth.inventory:
		if int(state.growth.inventory[id])>0: codex.encounter(str(id))
	state.codex = codex.snapshot()
	return answer

func _custom_entry(rule_id: String) -> String:
	if rule_id == "example_incense": return "ritual_example_incense"
	for id in codex.catalog:
		var entry: Dictionary = codex.catalog[id]
		if entry.book == "customs" and entry.source.get("rule_id") == rule_id: return id
	return ""

func new_p10_run(mode: String, kind: String, seed_text: String, choice: String, modifiers: Array, codex_path := "", faction := "") -> Dictionary:
	if Story.rules().is_empty():
		return _reject("P11_STORY_CONFIG")
	if seed_text.is_empty(): seed_text = "夜-%d-%d" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	var ritual := P10Plan.selected_ritual(seed_text) if choice.is_empty() and kind == "fierce" else choice
	if not faction.is_empty() and (kind != "example" or not Opening.accepts(mode,faction) or (mode == "duoming" and ritual != "R01")):
		return _reject("P7_INVALID_BUILD")
	var planned := GrowthNight.configure(base_config,"")
	if not faction.is_empty(): Opening.apply(planned,faction)
	if not P10Plan.configure(planned,kind,seed_text,ritual,modifiers): return _reject("P10_INVALID_PLAN")
	var answer := new_roster_run(mode,seed_text,"",codex_path,ritual,faction)
	if not answer.ok: return answer
	config = planned
	state.kind = kind
	state.ritual = ritual
	state.nameless_modifiers = modifiers.duplicate()
	if not state.has("story"):
		state.story = Story.start(float(state.names))
	if kind == "fierce":
		state.incense = maxf(0,float(state.incense) - 4.0)
		_record("fierce_opening",{"incense_delta":-4.0,"ritual":ritual,"modifiers":modifiers.duplicate()})
	return answer

func carry_story(previous: Dictionary) -> void:
	if _phase("map") and state.visited.is_empty() and not previous.get("story", {}).is_empty():
		state.story = Story.start(float(state.names), previous.story)

func story_enabled() -> bool:
	return state.has("nameless_modifiers") and state.has("story")

func story_act() -> Dictionary:
	if not story_enabled():
		return {}
	var depth := int(current_node().get("depth", 0))
	for upcoming in available_nodes():
		depth = maxi(depth, int(upcoming.depth))
	return Story.act(depth)

func self_listing_choice() -> Dictionary:
	if not story_enabled() or not _phase("map") or state.mode != "shouxiang":
		return {}
	var rule: Dictionary = Story.rules().endings.E03
	if state.ritual != rule.ritual or not available_nodes().any(_terminal):
		return {}
	if not state.story.self_listing.is_empty():
		return {"paid":true, "allowed":false, "payment":state.story.self_listing.duplicate(true)}
	for unit in state.roster:
		if unit.id != rule.unit:
			continue
		var wounded_max := maxf(1.0, floorf(float(unit.max_hp) * float(rule.max_hp_ratio)))
		var reason := "P5_NO_NAMES" if float(state.names) < float(rule.names_cost) else ""
		if wounded_max >= float(unit.max_hp):
			reason = "P11_SELF_WAN_MISSING"
		return {"paid":false, "allowed":reason.is_empty(), "reason":reason, "payment":{
			"uid":unit.uid, "unit":unit.id, "names_paid":float(rule.names_cost),
			"max_hp_before":float(unit.max_hp), "max_hp_after":wounded_max}}
	return {"paid":false, "allowed":false, "reason":"P11_SELF_WAN_MISSING"}

func choose_self_listing() -> Dictionary:
	var choice := self_listing_choice()
	if choice.is_empty() or choice.paid:
		return _reject("P11_SELF_UNAVAILABLE")
	if not choice.allowed:
		return _reject(choice.reason)
	var payment: Dictionary = choice.payment
	for unit in state.roster:
		if unit.uid != payment.uid:
			continue
		state.names = float(state.names) - float(payment.names_paid)
		unit.max_hp = payment.max_hp_after
		unit.hp = minf(float(unit.hp), float(unit.max_hp))
		if unit.has("growth"):
			var base: Dictionary = unit.growth.base
			base.hp = maxf(1.0, float(base.hp) - float(payment.max_hp_before) + float(payment.max_hp_after))
		state.story.self_listing = payment
		_record("self_listed", payment.duplicate(true))
		return _ok("P11_SELF_PAID")
	return _reject("P11_SELF_WAN_MISSING")

func current_node() -> Dictionary:
	if state.is_empty():
		return {}
	return _node(str(state.current_node_id)).duplicate(true)

func _node(id: String) -> Dictionary:
	for node in config.nodes:
		if node.id == id:
			return node
	return {}

func available_nodes() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	if state.is_empty() or state.phase != "map":
		return available
	var ids: Array = [config.start_node] if str(state.current_node_id).is_empty() else _node(str(state.current_node_id)).next
	for id in ids:
		if not state.visited.has(id):
			available.append(_node(str(id)).duplicate(true))
	return available

## Core posts present on every ordinary R01 defending map.
func reserve_post_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if state.get("phase") != "map" or state.get("mode") != "shouxiang" or not state.has("opening_faction"): return options
	var counts := {}
	for member in state.roster:
		counts[member.post] = int(counts.get(member.post,0)) + 1
	for member in state.roster:
		if member.hp <= 0 or not str(member.id).begins_with("H"): continue
		for post in ["post_register","post_hall_door","post_table_hall","post_stair_head","post_inner_gate","post_rear"]:
			if post != member.post and counts.get(post,0) < Data.battle_rules.post_cap and _valid_post(post,member.id):
				options.append({"uid":member.uid,"id":member.id,"from":member.post,"to":post})
	return options

func reserve_post(uid: String, post: String) -> Dictionary:
	for option in reserve_post_options():
		if option.uid == uid and option.to == post:
			for member in state.roster:
				if member.uid == uid:
					member.post = post
					_record("reserve_post",option)
					return _ok()
	return _reject("P5_INVALID_POST")

func choose_node(id: String) -> Dictionary:
	if not _phase("map"):
		return _reject("P5_WRONG_PHASE")
	var allowed := false
	for node in available_nodes():
		if node.id == id:
			allowed = true
	if not allowed:
		return _reject("P5_INVALID_NODE")
	var node := _node(id)
	state.current_node_id = id
	state.visited.append(id)
	state.offers = []
	state.purchased = []
	state.battle_snapshot = {}
	match node.type:
		"battle","boss":
			state.phase = "battle"
			if state.has("nameless_modifiers"):
				for chunk_id in node.chunk_ids: codex.encounter(_custom_entry(chunk_id))
				state.codex = codex.snapshot()
			state.before_battle = {"roster":state.roster.duplicate(true),"incense":state.incense,"names":state.names,"fallen":state.fallen.duplicate(true)}
			if state.has("growth"):
				state.before_battle.growth = state.growth.duplicate(true)
				state.before_battle.departed = state.get("departed",[]).duplicate(true)
		"market":
			state.phase = "market"
			state.offers = _market()
		"event":
			state.phase = "event"
		"rest":
			state.phase = "rest"
	_record("choose_node",{"node_id":id,"type":node.type})
	return _ok()

func reward_options() -> Array[Dictionary]:
	return _options("reward")

func market_options() -> Array[Dictionary]:
	return _options("market")

func _options(phase: String) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if not _phase(phase):
		return options
	for stored in state.offers:
		var offer: Dictionary = stored.duplicate(true)
		var reason := _effect_reason(offer.effect,"",true)
		if phase == "market" and state.purchased.has(offer.id):
			reason = "P5_ALREADY_BOUGHT"
		elif phase == "market" and state.incense < float(offer.cost):
			reason = "P5_NO_INCENSE"
		offer.allowed = reason.is_empty()
		offer.reason = reason
		options.append(offer)
	return options

func target_options(offer_id: String) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if state.is_empty() or state.phase not in ["reward","market"]:
		return targets
	var offer := _offer(offer_id)
	if offer.is_empty() or not bool(offer.requires_target):
		return targets
	for unit in state.roster:
		if _eligible_target(unit, offer.effect):
			targets.append(unit.duplicate(true))
	return targets

func choose_reward(id: String, target_uid := "") -> Dictionary:
	if not _phase("reward"):
		return _reject("P5_WRONG_PHASE")
	var offer := _offer(id)
	if offer.is_empty():
		return _reject("P5_INVALID_OFFER")
	var reason := _effect_reason(offer.effect,target_uid)
	if not reason.is_empty():
		return _reject(reason)
	_apply(offer.effect,target_uid)
	state.selected_rewards.append({"id":id,"title":offer.title,"node_id":state.current_node_id,"target_uid":target_uid})
	_record("reward_selected",{"id":id,"target_uid":target_uid})
	state.offers = []
	_complete_node()
	return _ok()

func buy_offer(id: String, target_uid := "") -> Dictionary:
	if not _phase("market"):
		return _reject("P5_WRONG_PHASE")
	var offer := _offer(id)
	if offer.is_empty():
		return _reject("P5_INVALID_OFFER")
	if state.purchased.has(id):
		return _reject("P5_ALREADY_BOUGHT")
	if state.incense < float(offer.cost):
		return _reject("P5_NO_INCENSE")
	var reason := _effect_reason(offer.effect,target_uid)
	if not reason.is_empty():
		return _reject(reason)
	state.incense -= float(offer.cost)
	_apply(offer.effect,target_uid)
	state.purchased.append(id)
	_record("market_purchase",{"id":id,"target_uid":target_uid,"cost":offer.cost})
	return _ok()

func event_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if not _phase("event"):
		return options
	var event: Dictionary = config.events[current_node().event_id]
	for choice in event.choices:
		var option: Dictionary = choice.duplicate(true)
		var reason := ""
		if state.incense < float(choice.cost_incense):
			reason = "P5_NO_INCENSE"
		elif state.names < float(choice.cost_names):
			reason = "P5_NO_NAMES"
		option.allowed = reason.is_empty()
		option.reason = reason
		options.append(option)
	return options

func resolve_event(choice_id: String) -> Dictionary:
	if not _phase("event"):
		return _reject("P5_WRONG_PHASE")
	for choice in event_options():
		if choice.id != choice_id:
			continue
		if not choice.allowed:
			return _reject(choice.reason)
		state.incense -= float(choice.cost_incense)
		state.names -= float(choice.cost_names)
		for effect in choice.effects:
			_apply(effect,"")
		_record("event_resolved",{"event_id":current_node().event_id,"choice_id":choice_id,"cost_incense":choice.cost_incense,"cost_names":choice.cost_names})
		_complete_node()
		return _ok()
	return _reject("P5_INVALID_CHOICE")

func rest_reserve_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if not _phase("rest") or state.mode != "shouxiang" or not state.has("opening_faction"):
		return options
	var before_final: bool = current_node().next.any(func(id): return _terminal(_node(str(id))))
	if state.roster.size() > 2 or (state.roster.size() == 2 and not before_final):
		return options
	if state.roster.size() == 1 and not before_final and state.roster[0].hp >= state.roster[0].max_hp:
		return options
	for id in Opening.REST_RESERVES.get(state.get("opening_faction",""),[]):
		if state.fallen.any(func(member): return member.id == id): continue
		var post := GrowthNight.legal_post(id,"post_register")
		var effect := {"kind":"recruit","unit_id":id,"post":post,"count":1}
		if not _effect_reason(effect,"").is_empty(): continue
		var regroup: bool = state.roster.size() == 1 and state.roster[0].post != post and Data.battle_rules.post_cap >= 2 and _valid_post(post,state.roster[0].id)
		options.append({"can_regroup":regroup,"id":id,"cost":Opening.RESERVE_FEE,"post":post,"allowed":state.incense >= Opening.RESERVE_FEE,"effect":effect})
	return options

func hall_brace_target() -> String:
	if not _phase("rest") or not state.has("opening_faction") or state.mode!="shouxiang" or state.roster.is_empty(): return ""
	var exits: Array = current_node().next
	if exits.size()!=1: return ""
	var upcoming := _node(exits[0])
	return str(upcoming.id) if upcoming.get("boss_id","")=="B01" else ""

func brace_hall_at_rest() -> Dictionary:
	var target := hall_brace_target()
	if target.is_empty(): return _reject("P5_INVALID_CHOICE")
	if state.incense<Opening.RESERVE_FEE: return _reject("P5_NO_INCENSE")
	state.incense -= Opening.RESERVE_FEE
	_record("brace_hall",{"target":target,"cost":Opening.RESERVE_FEE})
	_complete_node()
	return _ok()

func rest_health_after(unit: Dictionary) -> float:
	return minf(float(unit.max_hp),float(unit.hp) + float(unit.max_hp) * float(config.rest.heal_ratio))

func treatment_health_after(unit: Dictionary) -> float:
	return minf(unit.max_hp,unit.hp + unit.max_hp * config.rest.treatment_ratio)

func can_treat(unit: Dictionary) -> bool:
	return _phase("rest") and state.mode=="shouxiang" and state.has("opening_faction") and state.roster.size()>=2 and unit.hp>0 and treatment_health_after(unit)>rest_health_after(unit) and state.incense>=config.rest.treatment_cost

func treat_at_rest(uid: String) -> Dictionary:
	for unit in state.get("roster",[]):
		if unit.uid!=uid: continue
		if not can_treat(unit): return _reject("P5_INVALID_CHOICE")
		var before: float = unit.hp
		unit.hp = treatment_health_after(unit)
		state.incense -= config.rest.treatment_cost
		_record("rest_treatment",{"uid":uid,"before":before,"after":unit.hp,"cost":config.rest.treatment_cost})
		_complete_node()
		return _ok()
	return _reject("P5_INVALID_CHOICE")

func finish_rest(reserve_id := "", regroup := false) -> Dictionary:
	if not _phase("rest"):
		return _reject("P5_WRONG_PHASE")
	if regroup and reserve_id.is_empty(): return _reject("P5_INVALID_CHOICE")
	if not reserve_id.is_empty():
		for option in rest_reserve_options():
			if option.id != reserve_id: continue
			if not option.allowed: return _reject("P5_NO_INCENSE")
			if regroup and not option.can_regroup: return _reject("P5_INVALID_POST")
			if regroup:
				var guard: Dictionary = state.roster[0]
				_record("reserve_post",{"uid":guard.uid,"id":guard.id,"from":guard.post,"to":option.post})
				guard.post = option.post
			state.incense -= option.cost
			_apply(option.effect,"")
			_record("rest_recruit",{"id":reserve_id,"cost":option.cost,"post":option.post})
			_complete_node()
			return _ok()
		return _reject("P5_INVALID_CHOICE")
	for unit in state.roster:
		unit.hp = rest_health_after(unit)
	state.incense = minf(float(config.incense_cap),float(state.incense) + float(config.rest.incense))
	state.names = minf(float(config.names_cap),float(state.names) + float(config.rest.names))
	_record("rest",config.rest.duplicate(true))
	_complete_node()
	return _ok()

func leave_node() -> Dictionary:
	if _phase("mercy"):
		state.phase = "ended"
		_record("mercy_declined",{})
		return _ok()
	if not _phase("market"):
		return _reject("P5_WRONG_PHASE")
	_complete_node()
	return _ok()

func accept_battle(report: Dictionary) -> Dictionary:
	if not _phase("battle"):
		return _reject("P5_WRONG_PHASE")
	if report.get("outcome") not in ["victory","defeat"] or not report.get("reason") is String or not report.get("roster") is Array or not report.get("fallen",[]) is Array:
		return _reject("P5_INVALID_BATTLE")
	if report.has("node_id") and report.node_id != state.current_node_id:
		return _reject("P5_STALE_BATTLE")
	for key in ["incense","names","elapsed"]:
		if typeof(report.get(key)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(report[key])) or float(report[key]) < 0:
			return _reject("P5_INVALID_BATTLE")
	if story_enabled() and (report.get("node_id") != state.current_node_id or not Story.valid_battle(report.get("story"), str(state.seed), state.stats.battles.size(), str(state.mode), str(report.reason), float(report.names))):
		return _reject("P5_INVALID_BATTLE")
	if not _valid_roster(report.roster,str(state.mode),state.has("nameless_modifiers")):
		return _reject("P5_INVALID_BATTLE")
	if state.ritual == "R04":
		if not _valid_ritual_ward(report.get("ritual_ward"), report.reason == "P10_END_WARD_LOST"):
			return _reject("P5_INVALID_BATTLE")
		if report.reason == "P10_END_WARD_LOST" and report.outcome != ("victory" if state.mode == "duoming" else "defeat"):
			return _reject("P5_INVALID_BATTLE")
	elif report.has("ritual_ward") or report.reason == "P10_END_WARD_LOST":
		return _reject("P5_INVALID_BATTLE")
	if state.has("growth") and (not report.get("growth") is Dictionary or not Growth.valid_state(report.growth)):
		return _reject("P5_INVALID_BATTLE")
	if state.has("growth") and not preload("res://src/night/NightBattleBridge.gd")._valid_departures(report.get("departed",[])): return _reject("P5_INVALID_BATTLE")
	if state.get("roster_enabled",false):
		if not Codex.valid(report.get("codex"),codex.catalog) or not report.get("killer_id","") is String: return _reject("P5_INVALID_BATTLE")
		if not str(report.get("killer_id","")).is_empty() and not Data.units.has(str(report.killer_id)): return _reject("P5_INVALID_BATTLE")
		codex.merge(report.codex)
		if report.outcome == "defeat": codex.record_failure(str(state.seed),str(report.get("killer_id","")),str(report.reason))
		state.codex = codex.snapshot()
	if state.has("growth"):
		state.growth = report.growth.duplicate(true)
		for record in report.get("departed",[]):
			var present := false
			for old in state.departed:
				if old.uid == record.uid: present = true
			if not present: state.departed.append(record.duplicate(true))
		for discovery in state.growth.get("unlocks",{}):
			if Data.growth_rules.fusions.has(discovery): state.unlocks[discovery] = "fused"
	if report.has("ritual_ward"):
		state.ritual_ward = report.ritual_ward.duplicate(true)
		state.erase("ritual_ward_hp")
	state.roster = report.roster.duplicate(true)
	state.incense = minf(float(config.incense_cap),float(report.incense))
	state.names = minf(float(config.names_cap),float(report.names))
	for unit in report.get("fallen",[]):
		if unit is Dictionary and unit.has("uid") and not _fallen_has(str(unit.uid)):
			state.fallen.append(unit.duplicate(true))
	_unlock_roster(state.roster)
	for id in report.get("encountered",[]):
		if not state.unlocks.has(str(id)):
			state.unlocks[str(id)] = "encountered"
	state.battle_snapshot = {}
	var battle: Dictionary = report.duplicate(true)
	battle.node_id = state.current_node_id
	battle.reward_incense = 0.0
	battle.reward_names = 0.0
	state.stats.elapsed += float(report.elapsed)
	if report.reason == "P10_END_WARD_LOST":
		state.outcome = report.outcome
		state.reason = report.reason
		state.last_battle = battle
		state.offers = []
		state.phase = "ended"
	elif report.outcome == "victory":
		var profile: Dictionary = config.battle_profiles[current_node().profile_id]
		var prior_incense: float = state.incense
		var prior_names: float = state.names
		state.incense = minf(float(config.incense_cap),prior_incense + float(profile.victory_incense))
		state.names = minf(float(config.names_cap),prior_names + float(profile.victory_names))
		battle.reward_incense = state.incense - prior_incense
		battle.reward_names = state.names - prior_names
		state.last_battle = battle
		state.phase = "reward"
		state.offers = _rewards()
	else:
		state.outcome = "defeat"
		state.reason = report.reason
		state.last_battle = battle
		state.phase = "mercy" if state.kind == "example" and not state.mercy_used else "ended"
	state.stats.battles.append({"node_id":state.current_node_id,"outcome":report.outcome,"reason":report.reason,"elapsed":report.elapsed,"reward_incense":battle.reward_incense,"reward_names":battle.reward_names})
	if story_enabled():
		Story.record_battle(state.story, report.story, str(state.mode), float(state.names))
		if state.mode == "duoming" and state.phase == "ended" and _terminal(current_node()):
			state.story.flags.finished_seize_night = true
	_record("battle_settled",{"outcome":report.outcome,"reason":report.reason,"reward_incense":battle.reward_incense,"reward_names":battle.reward_names})
	return _ok()

func use_mercy() -> Dictionary:
	if not _phase("mercy") or state.mercy_used:
		return _reject("P5_MERCY_UNAVAILABLE")
	state.mercy_used = true
	if state.before_battle.has("growth"):
		state.growth = state.before_battle.growth.duplicate(true)
		state.departed = state.before_battle.get("departed",[]).duplicate(true)
	state.roster = state.before_battle.roster.duplicate(true)
	state.fallen = state.before_battle.fallen.duplicate(true)
	for unit in state.roster:
		unit.hp = maxf(float(unit.hp),float(unit.max_hp) * float(config.mercy.minimum_hp_ratio))
	state.incense = maxf(float(config.mercy.minimum_incense),float(state.before_battle.incense))
	state.names = maxf(float(config.mercy.minimum_names),float(state.before_battle.names))
	state.battle_snapshot = {}
	state.outcome = ""
	state.reason = ""
	state.phase = "battle"
	_record("free_rekindle",{"roster_restored":true,"minimum_hp_ratio":config.mercy.minimum_hp_ratio})
	return _ok()

func summary() -> Dictionary:
	if state.is_empty():
		var result := {}
	var result := {"outcome":state.outcome,"reason":state.reason,"mode":state.mode,"kind":state.kind,"seed":state.seed,
		"incense":state.incense,"names":state.names,"roster":state.roster.duplicate(true),"fallen":state.fallen.duplicate(true),
		"visited":state.visited.duplicate(),"battles":state.stats.battles.duplicate(true),"elapsed":state.stats.elapsed,
		"mercy_used":state.mercy_used,"unlocks":state.unlocks.duplicate(true),"departed":state.get("departed",[]).duplicate(true)}

	if state.get("roster_enabled",false):
		result.codex = codex.snapshot()
		result.killer_id = str(state.last_battle.get("killer_id",""))
	if story_enabled():
		result.story = state.story.duplicate(true)
		result.story.seize_finished_here = state.mode == "duoming" and _phase("ended") and _terminal(current_node())
	return result

func save(path: String) -> Dictionary:
	if state.is_empty():
		return _reject("P5_SAVE_INVALID")
	if state.has("ritual_ward") and (state.ritual != "R04" or not _valid_ritual_ward(state.ritual_ward,state.reason == "P10_END_WARD_LOST")):
		return _reject("P5_SAVE_INVALID")
	state.rng_state = str(_rng.state)
	if state.get("roster_enabled",false): state.codex = codex.snapshot()
	return Save.save(path,state)

func load_save(path: String) -> Dictionary:
	var loaded := Save.load_save(path)
	if not loaded.ok:
		return loaded
	var candidate: Dictionary = loaded.state
	var previous_config: Dictionary = config
	if candidate.has("opening_family"):
		if candidate.has("nameless_modifiers") and candidate.get("ritual") != "R01": return _reject("P5_SAVE_INVALID")
		if not candidate.get("growth") is Dictionary or candidate.get("mode") != "duoming" or candidate.get("kind") != "example" or candidate.get("growth_build_id") != "" or not Opening.FAMILIES.has(candidate.opening_family):
			return _reject("P5_SAVE_INVALID")
	if candidate.has("opening_faction"):
		if not candidate.get("growth") is Dictionary or candidate.growth.get("defense_objective") != "hold_register" or not Opening.PAIRS.has(candidate.opening_faction) or candidate.get("mode") != "shouxiang" or candidate.get("kind") != "example" or candidate.get("growth_build_id") != "":
			return _reject("P5_SAVE_INVALID")
	if candidate.has("growth"):
		if not candidate.get("growth_build_id") is String or (not str(candidate.growth_build_id).is_empty() and not GrowthNight.table().paths.has(candidate.growth_build_id)):
			return _reject("P5_SAVE_INVALID")
		config = GrowthNight.configure(base_config,str(candidate.growth_build_id))
		if candidate.has("opening_faction"):
			Opening.apply(config,candidate.opening_faction)
		elif candidate.has("opening_family"):
			Opening.apply(config,candidate.opening_family)
	else:
		config = base_config.duplicate(true)
	if candidate.has("nameless_modifiers"):
		if Story.rules().is_empty() or not candidate.get("nameless_modifiers") is Array or not candidate.get("seed") is String or not candidate.get("kind") is String or not candidate.get("ritual") is String or not candidate.get("roster_enabled",false) or not P10Plan.configure(config,candidate.kind,candidate.seed,candidate.ritual,candidate.nameless_modifiers):
			config = previous_config
			return _reject("P5_SAVE_INVALID")
		if not candidate.has("story") and _number(candidate.get("names"), 0):
			candidate.story = Story.start(float(candidate.names))
	if not _valid_state(candidate):
		config = previous_config
		return _reject("P5_SAVE_INVALID")
	state = candidate.duplicate(true)
	if state.get("roster_enabled",false): codex.restore(state.codex)
	_rng.state = int(state.rng_state)
	return _ok("P5_LOADED")

func _valid_state(candidate: Dictionary) -> bool:
	if candidate.has("roster_enabled") and not candidate.roster_enabled is bool: return false
	if candidate.get("roster_enabled",false) and (not candidate.has("growth") or not Codex.valid(candidate.get("codex"),codex.catalog)): return false
	if candidate.has("growth") and (not candidate.growth is Dictionary or not Growth.valid_state(candidate.growth)):
		return false
	if candidate.has("growth"):
		var build_id: String = str(candidate.get("growth_build_id",""))
		if not build_id.is_empty() and (not GrowthNight.table().paths.has(build_id) or GrowthNight.table().paths[build_id].seat != candidate.get("mode")): return false
	if candidate.has("departed") and not preload("res://src/night/NightBattleBridge.gd")._valid_departures(candidate.departed): return false
	if candidate.get("version") != 1:
		return false
	for key in ["phase","mode","kind","seed","ritual","current_node_id","rng_state","outcome","reason"]:
		if not candidate.get(key) is String:
			return false
	if candidate.phase not in ["map","battle","reward","market","event","rest","mercy","ended"] or candidate.mode not in ["shouxiang","duoming"] or not str(candidate.rng_state).is_valid_int():
		return false
	if candidate.has("story") and not _valid_story(candidate):
		return false
	if not candidate.has("nameless_modifiers") and (candidate.kind != "example" or candidate.ritual != "example_incense"): return false
	if candidate.has("ritual_ward_hp") and (candidate.ritual != "R04" or not _number(candidate.ritual_ward_hp,0)): return false
	if candidate.has("ritual_ward") and (candidate.ritual != "R04" or candidate.has("ritual_ward_hp") or not _valid_ritual_ward(candidate.ritual_ward,candidate.reason == "P10_END_WARD_LOST")):
		return false
	for key in ["roster","fallen","visited","completed","offers","purchased","selected_rewards","ledger"]:
		if not candidate.get(key) is Array:
			return false
	for key in ["build","stats","battle_snapshot","before_battle","last_battle","unlocks"]:
		if not candidate.get(key) is Dictionary:
			return false
	if not _resources(candidate) or not _number(candidate.get("serial"),0) or float(candidate.serial) != int(candidate.serial):
		return false
	var allow_chunk_posts := candidate.has("nameless_modifiers")
	if not candidate.get("mercy_used") is bool or not _valid_roster(candidate.roster,candidate.mode,allow_chunk_posts) or not _valid_fallen(candidate.fallen,candidate.mode):
		return false
	var previous := ""
	for id in candidate.visited:
		if not id is String or _node(id).is_empty() or (previous == "" and id != config.start_node) or (previous != "" and id not in _node(previous).next):
			return false
		previous = id
	if candidate.current_node_id != previous:
		return false
	var seen_completed: Array[String] = []
	for id in candidate.completed:
		if not id is String or id not in candidate.visited or id in seen_completed:
			return false
		seen_completed.append(id)
	if candidate.phase == "map" and previous != "" and previous not in candidate.completed:
		return false
	if candidate.phase not in ["map","ended"] and (previous == "" or previous in candidate.completed):
		return false
	if previous != "":
		var kind: String = _node(previous).type
		if candidate.phase in ["battle","reward","mercy"] and kind not in ["battle","boss"]:
			return false
		if candidate.phase in ["market","event","rest"] and candidate.phase != kind:
			return false
	var offer_ids: Array[String] = []
	for offer in candidate.offers:
		if not offer is Dictionary or not config.rewards.has(str(offer.get("id",""))) or offer_ids.has(str(offer.id)):
			return false
		var catalog_card: Dictionary = config.rewards[offer.id]
		# JSON reads numbers as floats even when the card generator used an int.
		if offer != catalog_card and offer != JSON.parse_string(JSON.stringify(catalog_card,"",true,true)):
			return false
		offer_ids.append(str(offer.id))
	if candidate.phase == "reward" and candidate.offers.size() != 3:
		return false
	var purchased: Array[String] = []
	for id in candidate.purchased:
		if not id is String or not config.rewards.has(id) or id in purchased:
			return false
		purchased.append(id)
	for key in config.build_caps:
		if not _number(candidate.build.get(key),-INF):
			return false
		var cap: float = config.build_caps[key]
		var value: float = candidate.build[key]
		if (cap >= 0 and (value < 0 or value > cap)) or (cap < 0 and (value > 0 or value < cap)):
			return false
	if not _number(candidate.stats.get("elapsed"),0) or not candidate.stats.get("battles") is Array:
		return false
	for battle in candidate.stats.battles:
		if not battle is Dictionary or not _valid_battle_record(battle):
			return false
	for selected in candidate.selected_rewards:
		if not selected is Dictionary or not config.rewards.has(str(selected.get("id",""))) or not selected.get("target_uid") is String or not selected.get("title") is String or str(selected.get("node_id","")) not in candidate.visited:
			return false
	for entry in candidate.ledger:
		if not entry is Dictionary or not entry.get("action") is String or not entry.get("node_id") is String or not entry.get("detail") is Dictionary or not _resources(entry):
			return false
	for id in candidate.unlocks:
		if Data.growth_rules.fusions.has(str(id)) and candidate.unlocks[id] == "fused": continue
		if not Data.units.has(str(id)) or candidate.unlocks[id] not in ["encountered","recruited","mutated","purified","defeated"]:
			return false
	if not candidate.before_battle.is_empty():
		var before: Dictionary = candidate.before_battle
		if candidate.has("growth") and (not before.get("growth") is Dictionary or not Growth.valid_state(before.growth)): return false
		if before.has("departed") and not preload("res://src/night/NightBattleBridge.gd")._valid_departures(before.departed): return false
		if not _resources(before) or not before.get("roster") is Array or not _valid_roster(before.roster,candidate.mode,allow_chunk_posts) or not before.get("fallen") is Array or not _valid_fallen(before.fallen,candidate.mode):
			return false
	elif candidate.phase in ["battle","reward","mercy"]:
		return false
	if not candidate.last_battle.is_empty():
		var last: Dictionary = candidate.last_battle
		if last.has("growth") and (not last.growth is Dictionary or not Growth.valid_state(last.growth)): return false
		if not _valid_battle_record(last) or not _resources(last) or not last.get("roster") is Array or not _valid_roster(last.roster,candidate.mode,allow_chunk_posts):
			return false
	if not candidate.battle_snapshot.is_empty():
		if candidate.phase != "battle" or not _valid_snapshot_shell(candidate.battle_snapshot):
			return false
	return true

func _valid_story(candidate: Dictionary) -> bool:
	if not Story.valid(candidate.story):
		return false
	var story: Dictionary = candidate.story
	if not str(story.ending).is_empty() and (not candidate.has("nameless_modifiers") or candidate.mode != "shouxiang" or candidate.phase != "ended" or candidate.outcome != "victory" or not _terminal(_node(candidate.current_node_id))):
		return false
	if story.self_listing.is_empty():
		return true
	var listing_rules: Dictionary = Story.rules().get("endings", {}).get("E03", {})
	if not candidate.has("nameless_modifiers") or candidate.mode != "shouxiang" or candidate.ritual != listing_rules.get("ritual") or story.self_listing.unit != listing_rules.get("unit"):
		return false
	var node := _node(candidate.current_node_id)
	if candidate.phase != "map":
		return _terminal(node)
	return node.get("next", []).any(func(id): return _terminal(_node(str(id))))

func _number(value, minimum: float) -> bool:
	return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(value)) and float(value) >= minimum

func _resources(data: Dictionary) -> bool:
	return _number(data.get("incense"),0) and float(data.incense) <= float(config.incense_cap) and _number(data.get("names"),0) and float(data.names) <= float(config.names_cap)

func _valid_battle_record(battle: Dictionary) -> bool:
	return battle.get("outcome") in ["victory","defeat"] and battle.get("reason") is String and not _node(str(battle.get("node_id",""))).is_empty() and _number(battle.get("elapsed"),0) and _number(battle.get("reward_incense"),0) and _number(battle.get("reward_names"),0)

func _valid_snapshot_shell(snapshot: Dictionary) -> bool:
	if snapshot.get("version") != 1:
		return false
	for key in ["actors","structures","shots"]:
		if not snapshot.get(key) is Array:
			return false
	for key in ["session","tide","simulation","bridge"]:
		if not snapshot.get(key) is Dictionary:
			return false
	return true

func _valid_fallen(fallen: Array, mode: String) -> bool:
	var seen: Array[String] = []
	for unit in fallen:
		if not unit is Dictionary or not unit.get("uid") is String or str(unit.uid) in seen or not Data.combat_profiles.has(str(unit.get("id",""))) or not _side_matches(unit,mode):
			return false
		seen.append(str(unit.uid))
		if not _number(unit.get("hp"),0) or float(unit.hp) != 0:
			return false
	return true

func _valid_roster(roster: Array, mode: String, allow_chunk_posts := false) -> bool:
	if roster.size() > int(config.roster_caps[mode]):
		return false
	var seen: Array[String] = []
	var named_ids: Array[String] = []
	var troops := 0
	for unit in roster:
		if unit is Dictionary and unit.has("roster") and not Roster.valid_unit_state(unit.roster): return false
		if not unit is Dictionary or not unit.get("uid") is String or str(unit.uid).is_empty() or seen.has(str(unit.uid)) or not Data.combat_profiles.has(str(unit.get("id",""))):
			return false
		if not _side_matches(unit,mode):
			return false
		seen.append(str(unit.uid))
		if unit.has("growth") and not Growth.valid_unit_growth(unit.growth): return false
		if unit.has("profile") and not preload("res://src/night/BattleSnapshot.gd").valid_profile(unit.profile,str(unit.id)): return false
		for key in ["hp","max_hp","attack","defense","upgrade_level","mutation_count"]:
			if not _number(unit.get(key),0):
				return false
		if unit.hp <= 0 or unit.max_hp <= 0 or unit.hp > unit.max_hp or not unit.get("post") is String or not unit.get("equipment_id") is String or not _valid_unit_post(unit,allow_chunk_posts):
			return false
		if int(unit.upgrade_level) != float(unit.upgrade_level) or unit.upgrade_level > Data.battle_rules.upgrade.max_level or int(unit.mutation_count) != float(unit.mutation_count) or unit.mutation_count > Data.battle_rules.mutation_limit:
			return false
		if unit.id == "G01" and (unit.mutation_count != 0 or unit.equipment_id != ""):
			return false
		if str(unit.id).begins_with("H"):
			if unit.id in named_ids:
				return false
			named_ids.append(str(unit.id))
		elif str(unit.id).begins_with("T"):
			troops += 1
	return named_ids.size() <= int(Data.battle_rules.named_cap) and troops <= int(Data.battle_rules.troop_cap)

func _valid_ritual_ward(ward: Variant, dead: bool) -> bool:
	var params: Dictionary = P10Plan.Rituals.row("R04").params
	if not ward is Dictionary or ward.get("uid") != preload("res://src/night/NightBattleBridge.gd").RITUAL_WARD_UID:
		return false
	if ward.get("id") != params.ward_unit or ward.get("post") != params.ward_post or ward.get("side") != "xianghuo":
		return false
	if not _number(ward.get("hp"),0) or (ward.hp == 0) != dead:
		return false
	# The ordinary roster validator requires a live actor; validate the other fields
	# against the same contract after adapting only the recorded death HP.
	var actor: Dictionary = ward.duplicate()
	if dead:
		actor.hp = actor.get("max_hp")
	return _valid_roster([actor],"shouxiang")

func _offer(id: String) -> Dictionary:
	for offer in state.offers:
		if offer.id == id:
			return offer
	return {}

func _effect_reason(effect: Dictionary, target_uid: String, allow_missing := false) -> String:
	match effect.kind:
		"growth_item":
			if not state.has("growth") or int(state.growth.inventory.get(effect.id,0)) >= int(config.growth_night.inventory_cap): return "P7_INVENTORY_CAP"
		"growth_material":
			if not state.has("growth") or effect.id in state.growth.materials: return "P7_MATERIAL_PRESENT"
		"recruit":
			if state.roster.size() + int(effect.count) > int(config.roster_caps[state.mode]):
				return "P5_ROSTER_CAP"
			if state.mode == "shouxiang":
				var troops := 0
				for unit in state.roster:
					if str(unit.id).begins_with("T"):
						troops += 1
				if str(effect.unit_id).begins_with("T") and troops + int(effect.count) > int(Data.battle_rules.troop_cap):
					return "P5_ROSTER_CAP"
				var named := 0
				var at_post := 0
				for unit in state.roster:
					if str(unit.id).begins_with("H"):
						named += 1
					if str(unit.post) == str(effect.post):
						at_post += 1
					if str(effect.unit_id).begins_with("H") and unit.id == effect.unit_id:
						return "P5_NAMED_PRESENT"
				if str(effect.unit_id).begins_with("H") and named + int(effect.count) > int(Data.battle_rules.named_cap):
					return "P5_ROSTER_CAP"
				if not _valid_post(str(effect.post),str(effect.unit_id)):
					return "P5_INVALID_POST"
				if at_post + int(effect.count) > int(Data.battle_rules.post_cap):
					return "P5_POST_FULL"
		"equipment", "stats", "mutate":
			var targets: Array[Dictionary] = []
			for unit in state.roster:
				if _eligible_target(unit,effect):
					targets.append(unit)
			if targets.is_empty():
				return "P5_NO_TARGET"
			if target_uid.is_empty() and allow_missing:
				return ""
			for unit in targets:
				if unit.uid == target_uid:
					return ""
			return "P5_NO_TARGET"
		"build":
			var cap: float = config.build_caps[effect.key]
			if (cap >= 0 and float(state.build[effect.key]) >= cap) or (cap < 0 and float(state.build[effect.key]) <= cap):
				return "P5_BUILD_CAP"
	return ""

func post_spec(post_id: String, allow_chunk_posts := false) -> Dictionary:
	if _posts.has(post_id) or not allow_chunk_posts:
		return _posts.get(post_id,{})
	if _chunk_posts.is_empty():
		var layout := Chunks.compose(Chunks.CORE + Chunks.OPTIONAL)
		var floor_offsets := {}
		for band in layout.get("floor_bands",[]):
			floor_offsets[int(band.floor_id)] = float(band.offset)
		for post in layout.get("posts",[]):
			if not post.default_deployment:
				continue
			var spec: Dictionary = post.duplicate()
			spec.floor_offset = floor_offsets[int(post.floor_id)]
			_chunk_posts[str(post.id)] = spec
	return _chunk_posts.get(post_id,{})

func _valid_post(post_id: String, id: String, allow_chunk_posts := false) -> bool:
	if id.begins_with("G"):
		return post_id == "ghost_main_path"
	var spec := post_spec(post_id,allow_chunk_posts)
	if spec.is_empty():
		return false
	var role: String = Data.combat_profiles[id].role
	if role == "talisman":
		role = "crossbow"
	return role in spec.allowed_roles

func _eligible_target(unit: Dictionary, effect: Dictionary) -> bool:
	# Ordinary white robes have no equipment slots; reserve named equipment for elites.
	if effect.kind == "mutate":
		return float(unit.hp) > 0 and str(unit.id) == "G01" and int(unit.mutation_count) < int(Data.battle_rules.mutation_limit)
	if float(unit.hp) <= 0 or str(unit.id) == "G01":
		return false
	return effect.kind != "equipment" or str(unit.equipment_id).is_empty()

func _apply(effect: Dictionary, target_uid: String) -> void:
	match effect.kind:
		"growth_item":
			state.growth.inventory[effect.id] = int(state.growth.inventory.get(effect.id,0)) + 1
			if state.get("roster_enabled",false): codex.resolve(str(effect.id),"obtained")
		"growth_material":
			state.growth.materials.append(str(effect.id))
		"recruit":
			for index in int(effect.count):
				state.roster.append(_unit(str(effect.unit_id),str(effect.post)))
			state.unlocks[str(effect.unit_id)] = "recruited"
			if state.get("roster_enabled",false): codex.resolve(str(effect.unit_id),"recruited")
		"mutate":
			for unit in state.roster:
				if unit.uid == target_uid:
					var ratio: float = float(unit.hp) / float(unit.max_hp)
					var source: Dictionary = Data.get_unit(str(effect.form_id))
					unit.id = str(effect.form_id)
					unit.max_hp = float(source["生命"])
					unit.hp = float(unit.max_hp) * ratio
					unit.attack = float(source["攻击"])
					unit.defense = float(source["防御"])
					unit.mutation_count += 1
					state.unlocks[str(effect.form_id)] = "mutated"
		"equipment", "stats":
			for unit in state.roster:
				if unit.uid == target_uid:
					unit.max_hp += float(effect.hp)
					unit.hp += float(effect.hp)
					unit.defense += float(effect.defense)
					unit.attack += float(effect.get("attack",0))
					if effect.kind == "equipment":
						unit.equipment_id = str(effect.equipment_id)
		"build":
			var value: float = float(state.build[effect.key]) + float(effect.value)
			var cap: float = config.build_caps[effect.key]
			state.build[effect.key] = minf(cap,value) if cap >= 0 else maxf(cap,value)
		"recover":
			state.incense = minf(float(config.incense_cap),float(state.incense) + float(effect.incense))
			state.names = minf(float(config.names_cap),float(state.names) + float(effect.names))
			for unit in state.roster:
				unit.hp = minf(float(unit.max_hp),float(unit.hp) + float(effect.heal))

func _unit(id: String, post: String) -> Dictionary:
	state.serial += 1
	var source: Dictionary = Data.get_unit(id)
	return {"uid":"night_%d" % state.serial,"id":id,"hp":float(source["生命"]),"max_hp":float(source["生命"]),
		"attack":float(source["攻击"]),"defense":float(source["防御"]),"upgrade_level":0,"equipment_id":"","mutation_count":0,"post":post}

func _rewards() -> Array[Dictionary]:
	var pool := _pool()
	var chosen: Array[Dictionary] = []
	var builds: Array[Dictionary] = []
	for card in pool:
		if card.category == "build":
			builds.append(card)
	if not builds.is_empty():
		chosen.append(_draw(builds))
	while chosen.size() < 3:
		var possible: Array[Dictionary] = []
		var survival := false
		for card in chosen:
			survival = survival or card.category == "survival"
		for card in pool:
			if not chosen.has(card) and (not survival or card.category != "survival"):
				possible.append(card)
		if possible.is_empty():
			break
		chosen.append(_draw(possible))
	state.rng_state = str(_rng.state)
	return chosen

func _market() -> Array[Dictionary]:
	var pool := _pool()
	var chosen: Array[Dictionary] = []
	for category in ["roster","roster","build","build"]:
		var possible: Array[Dictionary] = []
		for card in pool:
			if card.category == category and not chosen.has(card):
				possible.append(card)
		if not possible.is_empty():
			chosen.append(_draw(possible))
	state.rng_state = str(_rng.state)
	return chosen

func _pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for id in config.rewards:
		var card: Dictionary = config.rewards[id]
		if card.mode in ["both",state.mode] and _effect_reason(card.effect,"",true).is_empty():
			pool.append(card.duplicate(true))
	return pool

func _draw(pool: Array[Dictionary]) -> Dictionary:
	var total := 0.0
	for card in pool:
		total += _card_weight(card)
	var cursor := _rng.randf() * total
	for card in pool:
		cursor -= _card_weight(card)
		if cursor <= 0:
			return card.duplicate(true)
	return pool[-1].duplicate(true)

func _card_weight(card: Dictionary) -> float:
	if state.kind == "fierce": return P10Plan.Rituals.reward_weight(state.ritual,card)
	return float(card.weight)

func _complete_node() -> void:
	if not state.completed.has(state.current_node_id):
		state.completed.append(state.current_node_id)
	if current_node().next.is_empty():
		state.phase = "ended"
		state.outcome = "victory"
		state.reason = "P5_NIGHT_COMPLETE"
		if state.get("roster_enabled",false):
			codex.resolve(_custom_entry(state.ritual),"completed")
			if story_enabled() and _terminal(current_node()) and state.last_battle.get("node_id") == state.current_node_id and state.last_battle.get("outcome") == "victory":
				_complete_story()
			state.codex = codex.snapshot()
	else:
		state.phase = "map"

func _terminal(node: Dictionary) -> bool:
	return node.get("type") == "boss" and node.get("next", []).is_empty()

func _complete_story() -> void:
	Story.note_names(state.story, float(state.names), float(state.names))
	if state.mode == "duoming":
		state.story.flags.finished_seize_night = true
	else:
		state.story.ending = Story.select_ending(state.story)
	for id in Story.rules().epilogues:
		var entry: Dictionary = Story.rules().epilogues[id]
		var on_ending: bool = entry.has("ending") and entry.ending == state.story.ending
		if not on_ending and entry.get("completed_ritual", "") != state.ritual:
			continue
		if entry.get("resolve", false):
			codex.resolve(id, "listed")
		codex.list_name(id)
	if not str(state.story.ending).is_empty():
		_record("story_ending", {"id":state.story.ending})

func _fallen_has(uid: String) -> bool:
	for unit in state.fallen:
		if str(unit.get("uid","")) == uid:
			return true
	return false

func _unlock_roster(roster: Array) -> void:
	for unit in roster:
		if not state.unlocks.has(str(unit.id)):
			state.unlocks[str(unit.id)] = "encountered"

func _phase(phase: String) -> bool:
	return not state.is_empty() and state.phase == phase

func _record(action: String, detail: Dictionary) -> void:
	if story_enabled():
		Story.note_names(state.story, float(state.names), float(state.names))
	state.ledger.append({"action":action,"node_id":state.current_node_id,"incense":state.incense,"names":state.names,"detail":detail})

func _ok(reason := "P5_COMMAND_OK") -> Dictionary:
	return {"ok":true,"reason":reason}

func _reject(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

func _side_matches(unit: Dictionary, mode: String) -> bool:
	if unit.has("growth") and not unit.growth is Dictionary: return false
	if unit.get("side","") == "xianghuo" and unit.get("growth",{}).get("gray",false):
		return mode == "shouxiang"
	return str(unit.get("id","")).begins_with("G") == (mode == "duoming")

func _valid_unit_post(unit: Dictionary, allow_chunk_posts: bool) -> bool:
	if unit.get("side","") == "xianghuo" and unit.get("growth",{}).get("gray",false):
		return not post_spec(str(unit.post),allow_chunk_posts).is_empty()
	return _valid_post(str(unit.post),str(unit.id),allow_chunk_posts)
