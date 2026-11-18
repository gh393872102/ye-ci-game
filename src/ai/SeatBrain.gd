extends RefCounted
## Seeded decision policy only. Every mutation goes through BattleSession's paid player commands.
var session: Node
var seat := ""
var ferocity := "normal"
var seed := ""
var settings: Dictionary = {}
var rng := RandomNumberGenerator.new()
var events: Array[Dictionary] = []
var elapsed := 0.0
var next_decision := 0.0
var decisions := 0

func _init(battle: Node, side: String, aggression: String, seed_text: String) -> void:
	session = battle
	seat = side
	ferocity = aggression
	seed = seed_text
	settings = Data.mode_rules.ai_levels[ferocity].duplicate(true)
	rng.seed = (seed + "|" + seat + "|" + ferocity).hash()
	next_decision = maxf(0.1,float(settings.decision_interval) + rng.randf_range(-float(settings.jitter),float(settings.jitter)))

func advance(delta: float) -> void:
	if delta <= 0 or not session.active or not session.running or not session.result.is_empty():
		return
	elapsed += delta
	if elapsed + 0.0000001 < next_decision:
		return
	decisions += 1
	next_decision = elapsed + maxf(0.1,float(settings.decision_interval) + rng.randf_range(-float(settings.jitter),float(settings.jitter)))
	if seat == "shouxiang":
		_defend()
	elif seat == "duoming":
		_attack()

func _defend() -> void:
	if not session.pending_purchase.is_empty():
		_deploy_reserved()
		return
	var humans := _ordered(session.simulation.humans)
	var ghosts := _ordered(session.simulation.targets)
	# Valid point-reading always stays at the caster's existing covered position.
	for caster in humans:
		if caster.role != "ritual" or caster.brain.channel.active or not caster.brain.route.is_empty():
			continue
		for target in ghosts:
			if caster.brain.channel.valid_target(session.simulation,caster,target) and rng.randf() < float(settings.ritual_chance):
				if _call("start_ritual",{"caster_id":caster.instance_id,"target_id":target.instance_id}).ok:
					return
	# Repair uses the shared actual worker route and work timer, including failure to find one.
	if session.repair_jobs.is_empty() and session.incense_for(seat) >= float(session.rules.repair.cost):
		for door in session.simulation.world.doors:
			if door.durability / door.max_durability <= float(settings.repair_ratio):
				if _call("repair",{"door_id":str(door.name)}).ok:
					return
	var options: Dictionary = _query("purchase_options",{})
	if options.ok:
		# Replacing a fallen ritual line is an explicit purchase, never a free resurrection.
		var has_ritual := false
		for actor in humans:
			has_ritual = has_ritual or actor.role == "ritual"
		if not has_ritual:
			for item in options.data:
				if item.id == "H01" and item.allowed and _buy_and_deploy(str(item.id)):
					return
		if rng.randf() < float(settings.purchase_chance):
			var desired: Array[String] = ["T01","T02","T04"]
			if rng.randf() < 0.5:
				desired = ["T02","T01","T04"]
			for id in desired:
				for item in options.data:
					if item.id == id and item.allowed and _buy_and_deploy(id):
						return
	if session.incense_for(seat) >= float(session.rules.upgrade.cost) + float(settings.reserve_incense) and rng.randf() < float(settings.upgrade_chance):
		for actor in humans:
			var preview := _query("preview_upgrade",{"unit_id":actor.instance_id})
			if preview.ok and preview.data.allowed and _call("upgrade",{"unit_id":actor.instance_id}).ok:
				return

func _buy_and_deploy(id: String) -> bool:
	var posts := _query("legal_posts",{"id":id})
	if not posts.ok or posts.data.is_empty():
		return false
	var post := _best_post(id,posts.data)
	if post.is_empty():
		return false
	if not _call("purchase",{"id":id}).ok:
		return false
	_call("deploy_at",{"post_id":post})
	return true

func _deploy_reserved() -> void:
	var posts := _query("legal_posts",{"id":session.pending_purchase})
	if posts.ok:
		var post := _best_post(str(session.pending_purchase),posts.data)
		if not post.is_empty():
			_call("deploy_at",{"post_id":post})
			return
	_call("cancel_purchase",{})

func _best_post(id: String, legal: Array) -> String:
	var role: String = Data.combat_profiles[id].role
	var order: Array[String]
	match role:
		"ritual": order = ["post_register","post_hall_door","post_rear"]
		"crossbow","talisman": order = ["post_window_1","post_window_2","post_hall_door","post_stair_head","post_register"]
		_: order = ["post_gate_inner","post_barricade_outer_court","post_inner_gate","post_hall_door","post_stair_head","post_register","post_rear"]
	for id_post in order:
		if id_post in legal and not session.simulation.post_broken(id_post):
			return id_post
	return ""

func _attack() -> void:
	var ghosts := _ordered(session.simulation.targets)
	var whites: Array[Node2D] = []
	var has_breaker := false
	var has_climber := false
	for actor in ghosts:
		if actor.unit_id == "G01" and actor.mutation_count < int(session.rules.mutation_limit):
			whites.append(actor)
		has_breaker = has_breaker or actor.unit_id == "G12"
		has_climber = has_climber or actor.unit_id == "G09"
	var preference := "G12" if rng.randf() < float(settings.breaker_preference) else "G09"
	if not has_breaker and has_climber:
		preference = "G12"
	elif not has_climber and has_breaker:
		preference = "G09"
	var forms: Array[String] = [preference]
	# Save for the missing role rather than repeatedly spending on the cheaper form.
	if has_breaker == has_climber:
		forms.append("G09" if preference == "G12" else "G12")
	for form in forms:
		for actor in whites:
			var args := {"unit_id":actor.instance_id,"form_id":form}
			var preview := _query("preview_mutation",args)
			if preview.ok and preview.data.allowed:
				if _call("mutate",args).ok:
					return
	# The existing cooldown, three-use limit and tide source queue are authoritative.
	if (whites.is_empty() or (has_breaker and has_climber)) and rng.randf() < float(settings.reinforce_chance) and session.incense_for(seat) >= float(session.rules.reinforce.cost):
		_call("reinforce",{})

func _ordered(units: Array) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for actor in units:
		if is_instance_valid(actor) and not actor.dead:
			result.append(actor)
	result.sort_custom(func(a,b): return a.instance_id < b.instance_id)
	return result

func _query(action: String, args: Dictionary) -> Dictionary:
	return session.execute_for(seat,action,args,"ai")

func _call(action: String, args: Dictionary) -> Dictionary:
	var result: Dictionary = session.execute_for(seat,action,args,"ai")
	events.append({"time":session.simulation.simulation_time,"seat":seat,"action":action,"arguments":args.duplicate(true),"ok":bool(result.ok),"reason":str(result.reason),"origin":"ai"})
	return result

func snapshot() -> Dictionary:
	return {"seat":seat,"ferocity":ferocity,"seed":seed,"rng_state":str(rng.state),"elapsed":elapsed,"next_decision":next_decision,"decisions":decisions,"events":events.duplicate(true)}
