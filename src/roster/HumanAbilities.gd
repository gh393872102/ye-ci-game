extends RefCounted
## Source-named human and troop behaviors; numbers are in p8_humans.json.
const COMMON_GHOSTS := ["G01","G02","G03","G04","G05","G06","G07","G08"]
var _engine: WeakRef
var engine: RefCounted:
	get: return _engine.get_ref()

func _init(owner: RefCounted) -> void:
	_engine = weakref(owner)

func _sim() -> Node:
	return engine.sim()

func _target(unit: Node2D, args: Dictionary, friendly := false, radius := -1.0) -> Node2D:
	var candidates: Array = engine.near(unit,radius if radius >= 0 else float(engine.params(unit).get("radius_body",3)),friendly)
	if args.has("target_id"):
		var selected: Node2D = engine.actor(str(args.target_id))
		if selected == unit and friendly: return selected
		return selected if selected in candidates else null
	return candidates[0] if not candidates.is_empty() else null

func lantern_targets(unit: Node2D) -> Array:
	var nearby: Array = engine.near(unit,float(engine.params(unit).get("radius_body",3)))
	return nearby.filter(func(target): return (target.unit_id in COMMON_GHOSTS or target.unit_id=="G24") and _sim().world.inside_base(target.position))

func can_extend_dispel(unit: Node2D) -> bool:
	return unit.unit_id=="H22" and engine.growth().state.get("defense_objective","")=="hold_register" and engine.growth().has(unit,"I12")

func dispel_extra(unit: Node2D, target: Node2D) -> float:
	var rule: Dictionary = engine.params("H22")
	if unit.position.distance_to(target.position) > Rules.body_to_px(float(rule.radius_body)):
		return float(rule.mirror_extra_incense)
	return 0.0

func dispel_targets(unit: Node2D, manual := false) -> Array:
	var radius: float = engine.params(unit).get("radius_body",3)
	if manual and can_extend_dispel(unit): radius = float(engine.params("H22").mirror_radius_body)
	var nearby: Array = engine.near(unit,radius)
	return nearby.filter(func(enemy):
		if enemy.unit_id=="G30": return unit.unit_id!="H22" or dispel_extra(unit,enemy)==0
		return enemy.roster.statuses.has("cloth") or enemy.growth.statuses.has("ward"))

func uses_register_pin(unit: Node2D) -> bool:
	var growth: RefCounted = engine.growth()
	return unit.unit_id == "H24" and growth.state.get("defense_objective","") == "hold_register" and growth.has(unit,"I17")

func uses_impact_mirror(unit: Node2D) -> bool:
	var growth: RefCounted = engine.growth()
	return unit.unit_id == "H18" and growth.state.get("defense_objective","") == "hold_register" and growth.has(unit,"Y11")

func can_raise_mirror(unit: Node2D) -> bool:
	if uses_impact_mirror(unit):
		return engine.near(unit,float(engine.params("H18").radius_body)).any(func(enemy): return "破门" in enemy.tags)
	return not engine.near(unit,5,false).is_empty()

func pin_targets(unit: Node2D) -> Array:
	var candidates: Array = engine.near(unit,float(engine.params("H24").radius_body))
	if uses_register_pin(unit):
		return candidates.filter(func(enemy): return "破门" in enemy.tags and _sim().world.room_at(enemy.position,enemy.floor_id) == "register")
	return candidates

func pin_duration(target: Node2D) -> float:
	var rule: Dictionary = engine.params("H24")
	if target.height_px > 80: return float(rule.duration)*float(rule.large_multiplier)
	if target.unit_id in ["G07","G04"]: return float(rule.duration)*float(rule.small_multiplier)
	return float(rule.duration)

func execution_targets(unit: Node2D) -> Array:
	var rule: Dictionary = engine.params("H13")
	return engine.near(unit,float(rule.radius_body)).filter(func(target): return target.unit_id in COMMON_GHOSTS and target.hp/target.max_hp<=float(rule.hp_threshold))

func _paid(unit: Node2D, id: String, extra := 0.0, copied := false) -> bool:
	var cost := float(Data.get_unit(id).get("技能香耗",0))+extra
	return copied or engine.pay(unit,cost)

func _done(unit: Node2D, id: String, kind: String, target: Node2D = null) -> Dictionary:
	engine.cooldown(unit,float(engine.params(id).get("cooldown",8)))
	engine.event(kind,unit,target.instance_id if target != null else id)
	engine.visual(kind,unit,target.position if target != null else Vector2.ZERO)
	return engine.ok()

func cast_as(mimic: Node2D, source_id: String, args: Dictionary = {}) -> Dictionary:
	# A mirror reproduces combat effects, never personal inventory, paid rituals or a human-only movement job.
	if source_id in ["H01","H02","H04","H11","H15","H25","H28","H30","H31"]: return engine.reject("P8_COPY_UNSUPPORTED")
	var copied := args.duplicate(true)
	copied.copy_id = source_id
	return cast(mimic,copied)

func cast(unit: Node2D, args: Dictionary = {}) -> Dictionary:
	var id: String = str(args.get("copy_id",unit.unit_id))
	var copied: bool = id != unit.unit_id
	var p: Dictionary = engine.params(id)
	var target: Node2D
	var growth: RefCounted = engine.growth()
	if id in engine.session.ritual.param("fire_units",[]):
		return engine.reject("P10_FIRE_FORBIDDEN")
	match id:
		"H01":
			if copied: return engine.reject("P8_COPY_TARGET_REQUIRED")
			target = _target(unit,args,false,float(engine.session.rules.ritual.range_body))
			if target == null: return engine.reject()
			var result: Dictionary = engine.session.start_ritual(unit,target)
			return result
		"H02":
			if engine.session.names < float(Data.mode_rules.limits.names_max):
				if engine.ghosts.recovery_blocked(unit,unit): return engine.reject("P8_REKINDLE_BLOCKED")
				if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
				var restored: float = engine.ghosts.heal_modifier(unit,float(p.names_restore),unit)
				if restored > 0: engine.restore_names(restored,unit)
				return _done(unit,id,"rekindle")
			target = _target(unit,args,true)
			if target == null or target.unit_id == "H31" or float(target.roster.get("reserve_incense",0)) >= float(p.reserve_transfer): return engine.reject()
			if engine.ghosts.recovery_blocked(target,unit): return engine.reject("P8_REKINDLE_BLOCKED")
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			engine.ensure(target)
			target.roster.reserve_incense += engine.ghosts.heal_modifier(target,float(p.reserve_transfer),unit)
			return _done(unit,id,"incense_restored",target)
		"H03","H32":
			if id == "H03" and args.has("target_id"):
				var named: Node2D = engine.actor(str(args.target_id))
				if named != null and named.unit_id == "G31" and named.floor_id == unit.floor_id and named.position.distance_to(unit.position) <= Rules.body_to_px(float(p.radius_body)):
					if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
					engine.ghosts.on_named(named,unit)
					return _done(unit,id,"named_layers_collapsed",named)
			var ward := "named_ward" if id == "H03" else "face_ward"
			var candidates: Array = engine.near(unit,float(p.radius_body),true)
			candidates.append(unit)
			for ally in candidates:
				if args.has("target_id") and ally.instance_id != str(args.target_id): continue
				growth.ensure(ally)
				if int(ally.growth.counters.get(ward,0)) > 0: continue
				if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
				ally.growth.counters[ward] = 1
				engine.ensure(ally)
				if id == "H03":
					ally.roster.statuses.erase("nameless")
					ally.roster.counters.named_this_battle = true
					engine.ghosts.on_named(ally,unit)
				else:
					ally.roster.face_state = "faced"
					ally.roster.statuses.erase("faceless")
					ally.queue_redraw()
					if growth.state.get("ritual_flag","") in ["kaimian","开面"]: engine.restore_names(float(p.kaimian_names),unit)
				return _done(unit,id,"named_ward" if id == "H03" else "temporary_face",ally)
			return engine.reject()
		"H04","T03":
			target = _target(unit,args,true)
			if target == null or target.unit_id == "H31": return engine.reject()
			engine.ensure(target)
			if float(target.roster.reserve_incense) >= float(p.transfer)*2: return engine.reject()
			# Transfer prepays the same incense currency; it never creates a third resource.
			var transfer: float = float(p.transfer)
			if not copied and not engine.pay(unit,transfer): return engine.reject("P4_NO_INCENSE")
			target.roster.reserve_incense += transfer
			var result := _done(unit,id,"incense_transfer",target)
			if id == "H04" and _sim().world.room_at(unit.position,unit.floor_id) == "register": engine.cooldown(unit,float(p.cooldown)*float(p.register_cooldown_multiplier))
			return result
		"H05":
			target = _target(unit,args)
			if target == null or not "哭" in target.tags: return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			engine.status(unit,"silence_field",float(p.duration),unit)
			return _done(unit,id,"silence_field")
		"H06","H21","H27":
			var candidates: Array = engine.near(unit,float(p.radius_body),false)
			if candidates.is_empty(): return engine.reject()
			var needed := false
			for enemy in candidates:
				if growth.is_hidden(enemy) or enemy.unit_id in ["G01","G04"] or _open_face_light(id,enemy) or enemy.roster.statuses.has("dream") or enemy.side == "xianghuo" and enemy.brain.channel.active or id == "H21" and growth.in_environment(enemy,"water"): needed = true
			if not needed: return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			var duration: float = float(p.duration)
			if id == "H21" and not growth.in_environment(unit,"water"): duration *= float(p.dry_duration_multiplier)
			unit.roster.statuses.lantern = {"left":duration,"radius":float(p.radius_body),"source_id":unit.instance_id,"caster_id":id}
			_light(unit,id,float(p.radius_body),duration)
			return _done(unit,id,"crow_path" if id == "H27" else "river_lantern" if id == "H21" else "cold_light")
		"H07","T04":
			var radius: float = growth.drum_radius(unit,float(p.radius_body))
			var friends: Array = engine.near(unit,radius,true)
			var enemies: Array = engine.near(unit,radius,false)
			var wake := []
			var hidden := []
			var interrupted := []
			var can_mark_elite := false
			for ally in friends:
				if ally.growth.statuses.has("stun") or ally.growth.statuses.has("cry_stun") or ally.roster.statuses.has("dream"):
					wake.append(ally.instance_id)
			for enemy in enemies:
				if not enemy.roster.get("marked",false) and enemy.unit_id not in ["G01","G02","G03","G04","G05","G06","G07","G08"]:
					can_mark_elite = true
				if growth.is_hidden(enemy): hidden.append(enemy.instance_id)
				if enemy.roster.statuses.has("dream"): interrupted.append(enemy.instance_id)
			if wake.is_empty() and enemies.is_empty(): return engine.reject()
			if args.get("watch_for_distress",false) and wake.is_empty() and hidden.is_empty() and interrupted.is_empty():
				var hunting_pair: bool = can_mark_elite and _sim().humans.any(func(ally): return not ally.dead and ally.side == unit.side and ally.unit_id == "H31")
				if not hunting_pair: return engine.reject()
			var seat: String = growth.seat_of(unit)
			var before: float = engine.session.incense_for(seat)
			var reserve: float = unit.roster.reserve_incense
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			for ally in friends:
				ally.growth.statuses.erase("stun")
				ally.growth.statuses.erase("cry_stun")
				ally.roster.statuses.erase("dream")
			for enemy in enemies: engine.status(enemy,"revealed",float(p.get("reveal_seconds",3)),unit)
			var answer := _done(unit,id,"watch_drum")
			answer.drum = {"radius":radius,"woken":wake,"hidden":hidden,"dreams":interrupted,"marked":enemies.map(func(e): return e.instance_id),"paid":before-engine.session.incense_for(seat),"reserve_paid":reserve-float(unit.roster.reserve_incense)}
			engine.drum_resolved.emit(unit,answer.drum)
			return answer
		"H08":
			if _sim().world.room_at(unit.position,unit.floor_id) != "register" or engine.near(unit,5,false).is_empty(): return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			engine.state.register_ward = float(p.duration)
			engine.state.register_ward_multiplier = float(p.drain_multiplier)
			return _done(unit,id,"register_guard")
		"H09":
			var door: Node2D = _near_door(unit,float(p.radius_body))
			if door == null or engine.near(unit,3,false).is_empty(): return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			unit.roster.statuses.gate_guard = {"left":float(p.duration),"door_id":str(door.name),"source_id":unit.instance_id}
			return _done(unit,id,"hold_gate")
		"H10","H13":
			target = _target(unit,args)
			if target == null or target.hp/target.max_hp > float(p.hp_threshold): return engine.reject()
			if id == "H10" and target.unit_id in COMMON_GHOSTS: return engine.reject()
			if id == "H13" and target.unit_id not in COMMON_GHOSTS: return engine.reject("P8_NOT_COMMON_GHOST")
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			if unit.side == "xianghuo" and target.side == "yegui":
				engine.session._record("slay_exorcisable", 0, target.instance_id)
			if id == "H13":
				target.receive_damage(target.hp+target.defense+1,unit,"execution")
				engine.drain_names(float(p.name_penalty),unit)
			else: _sim().deal_damage(unit,target,"decisive_slash",unit.attack*float(p.damage_multiplier))
			return _done(unit,id,"execution" if id == "H13" else "decisive_slash",target)
		"H11","H25":
			var result: Dictionary = growth.place_barricade(unit,str(args.get("object_id","")))
			if result.ok: return _done(unit,id,"earth_wall" if id == "H11" else "barricade_build")
			return result
		"H12":
			target = _target(unit,args)
			if target == null or target.roster.statuses.has("chain"): return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			engine.status(target,"chain",float(p.duration),unit)
			return _done(unit,id,"chain",target)
		"H14":
			var reach: float = engine.loud_skill_radius(unit,float(p.radius_body))
			var enemies: Array = engine.near(unit,reach,false)
			if enemies.is_empty(): return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			engine.reveal_from_loud_skill(unit,id,reach)
			for enemy in enemies:
				engine.status(enemy,"taunt",float(p.duration),unit,{"target_id":unit.instance_id})
				if not engine.is_silenced(unit): engine.status(enemy,"stun",float(p.stun_seconds),unit)
			return _done(unit,id,"silent_taunt" if engine.is_silenced(unit) else "gong")
		"H15":
			target = engine.actor(str(args.get("target_id",""))) if args.has("target_id") else _support_target(unit)
			if target == null or target == unit or target.side != unit.side or not _sim().world.inside_base(target.position) or _sim().world.is_open_court(target.position): return engine.reject("P8_INDOOR_SUPPORT_ONLY")
			var post: String = target.current_post
			if not _sim().world.can_deploy_at(post): return engine.reject("P8_INDOOR_SUPPORT_ONLY")
			var destination: Vector2 = _sim().post_destination(unit,post)
			var route: Array = _sim().world.navigation.route(unit.position,unit.floor_id,destination,target.floor_id,true)
			if route.is_empty(): return engine.reject("P4_REPAIR_ROUTE")
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			unit.brain.route.assign(route)
			unit.brain.purpose = "support"
			unit.brain.target_post = post
			unit.roster.counters.support_post = post
			return _done(unit,id,"roof_support",target)
		"H16":
			target = _target(unit,args)
			if target == null: return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			engine.status(target,"armor_down",float(p.duration),unit,{"fraction":float(p.defense_reduction)})
			_sim().deal_damage(unit,target,"opening_staff",unit.attack)
			return _done(unit,id,"opening_staff",target)
		"H17":
			var door := seal_target(unit)
			if door == null: return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			growth.seal_door(unit,door)
			return _done(unit,id,"seal")
		"H18":
			if not can_raise_mirror(unit): return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			if uses_impact_mirror(unit):
				unit.roster.statuses.erase("mirror")
				engine.status(unit,"impact_mirror",float(p.duration),unit)
				engine.cooldown(unit,float(p.cooldown))
				return engine.ok()
			unit.roster.statuses.erase("impact_mirror")
			engine.status(unit,"mirror",float(p.duration),unit)
			return _done(unit,id,"gold_mirror")
		"H19":
			var candidates := lantern_targets(unit)
			if candidates.is_empty(): return engine.reject()
			target = engine.actor(str(args.target_id)) if args.has("target_id") else candidates[0]
			if target not in candidates: return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			if growth.light_without_borrowing(unit,target):
				# The growth effect already has both endpoints. A generic cast adds a beam from the origin.
				engine.cooldown(unit,float(p.cooldown))
				engine.event("lamp_reveal",unit,target.instance_id)
				return engine.ok().merged({"lantern_target":target.instance_id,"borrowed":false})
			if unit.side == "xianghuo" and target.side == "yegui":
				engine.session._record("recruited_ghost", 0, target.instance_id)
			growth._gray(target,unit,float(p.duration))
			return _done(unit,id,"borrow_ghost",target).merged({"lantern_target":target.instance_id,"borrowed":true})
		"H20":
			target = _target(unit,args)
			if target == null or growth.state.get("ritual_flag","") in ["hanshi","寒食"]: return engine.reject()
			if not _paid(unit,id,float(p.extra_incense),copied): return engine.reject("P4_NO_INCENSE")
			for enemy in ( _sim().humans+_sim().targets).duplicate():
				if enemy.dead or enemy.side == unit.side or enemy.floor_id != target.floor_id or enemy.position.distance_to(target.position) > Rules.body_to_px(float(p.radius_body)): continue
				enemy.receive_damage(float(p.damage)*growth.ritual_fire_multiplier(unit),unit,"fire")
				if enemy.side == "xianghuo" and enemy.brain.channel.active: enemy.brain.channel.cancel("P8_FIRE_INTERRUPTED")
				engine.status(enemy,"misname",.5,unit)
			growth.ignite_ritual_fire(unit,target.position,target.floor_id,id)
			return _done(unit,id,"burning_petition",target)
		"H22":
			var eligible := dispel_targets(unit,args.has("target_id") and not copied)
			if eligible.is_empty(): return engine.reject()
			target = engine.actor(str(args.target_id)) if args.has("target_id") else eligible.front()
			if target not in eligible: return engine.reject()
			var extra := 0.0 if copied else dispel_extra(unit,target)
			if not _paid(unit,id,extra,copied): return engine.reject("P4_NO_INCENSE")
			target.roster.statuses.erase("cloth")
			target.growth.statuses.erase("ward")
			if target.unit_id == "G30":
				target.receive_damage(float(p.dispel_damage),unit,"dispel")
				engine.status(target,"stun",2,unit)
			return _done(unit,id,"false_god_unmasked" if target.unit_id == "G30" else "dispel",target)
		"H23":
			target = _target(unit,args)
			if target == null: return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			engine.status(target,"misname",float(p.duration),unit)
			return _done(unit,id,"misname",target)
		"H24":
			var guarded := not copied and uses_register_pin(unit)
			if guarded:
				var candidates := pin_targets(unit)
				if args.has("target_id"):
					var chosen: Node2D = engine.actor(str(args.target_id))
					target = chosen if chosen in candidates else null
				elif not candidates.is_empty():
					target = candidates.front()
			else:
				target = _target(unit,args)
			if target == null: return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			engine.status(target,"stun",pin_duration(target),unit)
			return _done(unit,id,"register_pin" if guarded else "bone_pin",target)
		"H26":
			var enemies: Array = engine.near(unit,float(p.radius_body),false)
			if enemies.is_empty(): return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			for enemy in enemies:
				engine.status(enemy,"fear",float(p.duration),unit)
				enemy.receive_damage(float(p.damage)*growth.ritual_fire_multiplier(unit),unit,"firecracker")
			if growth.state.get("ritual_flag","") not in ["jizao","祭灶"]:
				for friend in engine.near(unit,float(p.radius_body),true): engine.status(friend,"stun",.3,unit)
			growth.ignite_ritual_fire(unit,unit.position,unit.floor_id,id)
			return _done(unit,id,"firecracker_scatter")
		"H28":
			if bool(unit.roster.counters.get("market_used",false)): return engine.reject("P8_MARKET_USED")
			if not args.get("confirm_market",false): return engine.reject("P8_MARKET_CONFIRM")
			if not _paid(unit,id,float(p.market_price),copied): return engine.reject("P4_NO_INCENSE")
			var item: String = str(p.market_item)
			growth.state.inventory[item] = int(growth.state.inventory.get(item,0))+1
			unit.roster.counters.market_used = true
			return _done(unit,id,"personal_market")
		"H29":
			var enemies: Array = engine.near(unit,float(p.radius_body),false)
			if enemies.is_empty() or engine.is_silenced(unit): return engine.reject()
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			for enemy in enemies:
				var destination: float = unit.position.x if str(args.get("mode","pull")) == "pull" else enemy.position.x+(1 if enemy.position.x>=unit.position.x else -1)*Rules.body_to_px(float(p.push_body))
				growth._displace(enemy,destination,Rules.body_to_px(float(p.push_body)))
				engine.status(enemy,"taunt",float(p.duration),unit,{"target_id":unit.instance_id})
			return _done(unit,id,"blind_strings")
		"H30":
			# Passive interception consumes this character on an actual erase attempt.
			return engine.reject("P8_PASSIVE_NAME_GUARD")
		"H31":
			target = _target(unit,args,false,float(p.radius_body))
			if target == null or not target.roster.get("marked",false) or target.unit_id in ["G01","G02","G03","G04","G05","G06","G07","G08"]: return engine.reject("P8_MARKED_ELITE_ONLY")
			if unit.floor_id != 0 or target.floor_id != 0 or not unit.may_briefly_leave_base: return engine.reject("P8_HUNT_LOCATION")
			var post_id: String = engine.nearest_post(unit)
			var home: Vector2 = _sim().world.get_node(post_id).position
			var distance: float = unit.position.distance_to(target.position)+target.position.distance_to(home)
			if distance/Rules.body_to_px(float(p.hunt_speed)) > float(p.max_outside_seconds) or _sim().world.segment_blocked(unit.position,target.position,0): return engine.reject("P8_HUNT_ROUTE")
			if not _paid(unit,id,0,copied): return engine.reject("P4_NO_INCENSE")
			unit.roster.hunt = {"target_id":target.instance_id,"goal":[target.position.x,target.position.y],"home":[home.x,home.y],"post":post_id,"elapsed":0.0,"outside":0.0,"returning":false,"hit":false}
			return _done(unit,id,"hunt_departure",target)
		"T01":
			if engine.near(unit,1.2,false).is_empty(): return engine.reject()
			engine.status(unit,"brace",2,unit)
			return _done(unit,id,"troop_brace")
		"T02":
			target = _target(unit,args)
			if target == null or not _sim().can_attack(unit,target) or not _sim().perform_attack(unit,target): return engine.reject()
			return _done(unit,id,"crossbow_shot",target)
	return engine.reject("P8_SKILL_UNIMPLEMENTED")

func advance(unit: Node2D, delta: float) -> void:
	if unit.roster.statuses.has("lantern"):
		var field: Dictionary = unit.roster.statuses.lantern
		_light(unit,str(field.caster_id),float(field.radius),.2)
	if unit.unit_id == "H11":
		var previous: Array = unit.roster.counters.get("last_position",[unit.position.x,unit.position.y])
		var moved := unit.position.distance_to(Vector2(previous[0],previous[1])) > .1
		unit.roster.counters.stationary_seconds = 0.0 if moved else float(unit.roster.counters.get("stationary_seconds",0))+delta
		unit.roster.counters.last_position = [unit.position.x,unit.position.y]
	if unit.unit_id == "H28" and _sim().post_broken(unit.current_post) and unit.brain.route.is_empty(): unit.brain.retreat("structure")
	if unit.unit_id == "H09" and _near_door(unit,float(engine.params(unit).radius_body)) == null:
		unit.roster.cooldowns.skill = float(unit.roster.cooldowns.get("skill",0))+delta*(1-1/float(engine.params(unit).away_cooldown_multiplier)) if not engine.ready(unit) else 0.0
	if unit.roster.has("hunt") or unit.side == "xianghuo" and (unit.brain.channel.active or not unit.brain.route.is_empty() or unit.brain.repair_door != null): return
	if not engine.ready(unit) or not engine.can_act(unit) or not engine.growth().can_act(unit): return
	if unit.unit_id in ["H01","H28","H30"]: return
	engine.cast(unit,{"watch_for_distress":true} if unit.unit_id == "H07" else {})

func _light(unit: Node2D, id: String, radius: float, duration: float) -> void:
	var growth: RefCounted = engine.growth()
	for enemy in engine.near(unit,radius,false):
		engine.status(enemy,"revealed",maxf(duration,1.0),unit)
		if (id == "H06" and enemy.unit_id in ["G01","G04"] or _open_face_light(id,enemy)) and growth._ready(enemy,"light_fear"):
			var fear: float = engine.session.ritual.light_fear_duration(enemy,float(growth.rules().skills.light_fear_duration))
			engine.status(enemy,"fear",fear,unit)
			growth._cd(enemy,"light_fear",float(growth.rules().skills.fear_cooldown))
		if id == "H21" and growth.in_environment(enemy,"water"): engine.status(enemy,"water_slow",duration,unit)
		if id == "H27" and enemy.side == "xianghuo" and enemy.brain.channel.active:
			enemy.receive_damage(float(engine.params(id).interrupt_damage),unit,"crow")
			engine.event("crow_interrupt",unit,enemy.instance_id)
	growth._visual("light",unit.position,unit.floor_id,.2,radius)

func _open_face_light(id: String, target: Node2D) -> bool:
	return id == "H06" and engine.session.ritual.has_flag("reveal_faces") and target.roster.get("face_state","faced") == "faceless"

func seal_target(unit: Node2D) -> Node2D:
	var door := _near_door(unit,float(engine.params("H17").radius_body))
	if door == null or str(door.name) in engine.growth().state.seals or engine.near(unit,4,false).is_empty(): return null
	return door

func _near_door(unit: Node2D, radius: float) -> Node2D:
	var best: Node2D
	var distance := Rules.body_to_px(radius)
	for door in _sim().world.doors:
		if door.destroyed or door.floor_id != unit.floor_id: continue
		if door.position.distance_to(unit.position) < distance:
			best = door
			distance = door.position.distance_to(unit.position)
	return best

func _support_target(unit: Node2D) -> Node2D:
	for ally in engine.near(unit,float(engine.params(unit).radius_body),true,false):
		if ally.floor_id != unit.floor_id and not engine.near(ally,2,false).is_empty(): return ally
	return null

func advance_actor(unit: Node2D, delta: float) -> bool:
	if not unit.roster.has("hunt"): return false
	var job: Dictionary = unit.roster.hunt
	var p: Dictionary = engine.params("H31")
	job.elapsed += delta
	if not _sim().world.inside_base(unit.position) or _sim().world.is_open_court(unit.position): job.outside += delta
	var home := Vector2(job.home[0],job.home[1])
	var destination := Vector2(job.goal[0],job.goal[1])
	var speed := Rules.body_to_px(float(p.hunt_speed))
	if job.elapsed+unit.position.distance_to(home)/speed >= float(p.max_outside_seconds): job.returning = true
	var goal: Vector2 = home if job.returning else destination
	_sim().open_passage(unit.position,goal,unit.floor_id)
	var next: Vector2 = unit.position.move_toward(goal,speed*delta)
	if _sim().world.segment_blocked(unit.position,next,unit.floor_id):
		job.returning = true
		goal = home
		next = unit.position.move_toward(goal,speed*delta)
	unit.velocity = (next-unit.position)/delta
	unit.current_speed = unit.velocity.length()
	unit.position = next
	unit.set_state("HuntReturn" if job.returning else "HuntStrike")
	if next.distance_to(goal) < .01:
		if job.returning:
			unit.current_post = str(job.post)
			unit.brain.settled_position = home
			unit.roster.counters.last_hunt_outside = job.outside
			unit.roster.erase("hunt")
			unit.set_state("HoldNewPost")
			engine.event("hunt_returned",unit,unit.current_post)
		else:
			var target: Node2D = engine.actor(str(job.target_id))
			if target != null and target.position.distance_to(unit.position) <= Rules.body_to_px(1.2):
				_sim().deal_damage(unit,target,"hunt_strike",unit.attack*float(p.damage_multiplier))
				engine.event("hunt_hit",unit,target.instance_id)
				engine.visual("hunt",unit)
			job.returning = true
	return true

func damage_multiplier(attacker: Node2D, victim: Node2D, _kind: String) -> float:
	if not is_instance_valid(attacker): return 1.0
	var amount := 1.0
	if attacker.unit_id == "H06" and not engine.growth().in_environment(attacker,"light") and not attacker.roster.statuses.has("lantern"):
		amount *= float(engine.params(attacker).dark_attack_multiplier)
	if attacker.unit_id == "H10" and engine.near(attacker,2,true).is_empty(): amount *= float(engine.params(attacker).alone_attack_multiplier)
	if victim.is_in_group("units"):
		if attacker.unit_id == "H12" and victim.unit_id in ["G16","G18"]: amount *= float(engine.params(attacker).official_damage_multiplier)
		if attacker.unit_id == "H16" and victim.unit_id.begins_with("G"): amount *= float(engine.params(attacker).ghost_damage_multiplier)
		if attacker.unit_id == "H22" and victim.unit_id == "G30": amount *= float(engine.params(attacker).god_damage_multiplier)
	return amount

func rooted_defense_bonus(unit: Node2D) -> float:
	var held := float(unit.roster.get("counters",{}).get("stationary_seconds",0))
	var params: Dictionary = engine.params(unit)
	return minf(float(params.max_defense_bonus),held*float(params.stationary_defense_per_second))

func defense_for(unit: Node2D, base: float) -> float:
	if unit.unit_id == "H11": base += rooted_defense_bonus(unit)
	if unit.unit_id == "H08": base += float(engine.params(unit).max_defense_bonus)*(1-engine.session.names/float(Data.mode_rules.limits.names_max))
	return base

func before_receive(unit: Node2D, amount: float, attacker: Node2D, kind: String) -> float:
	if unit.unit_id == "H18" and kind in ["melee","physical","charge"]:
		if amount > 0 and unit.roster.statuses.has("impact_mirror") and is_instance_valid(attacker) and attacker.side != unit.side and "破门" in attacker.tags:
			unit.roster.statuses.erase("impact_mirror")
			engine.event("impact_block",unit,attacker.instance_id)
			engine.visual("impact_block",unit)
			return 0
		amount *= float(engine.params(unit).physical_multiplier)
	if unit.roster.statuses.has("mirror") and kind not in ["melee","physical","charge","reflection"] and is_instance_valid(attacker):
		unit.roster.statuses.erase("mirror")
		attacker.receive_damage(amount*float(engine.params("H18").reflection_multiplier),unit,"reflection")
		engine.status(attacker,"revealed",3,unit)
		engine.event("gold_reflect",unit,attacker.instance_id)
		engine.visual("mirror",unit)
		return 0
	if unit.unit_id == "H10" and engine.near(unit,2,false).size() >= 2: amount *= float(engine.params(unit).focused_damage_multiplier)
	if unit.roster.statuses.has("brace"): amount *= float(engine.params("T01").brace_multiplier)
	if unit.unit_id == "H30" and kind in ["ritual","dispel","light"]: amount *= float(engine.params(unit).exorcism_damage_multiplier)
	return amount

func after_damage(_attacker: Node2D, _victim: Node2D, _amount: float, _kind: String, _before: float) -> void:
	pass

func on_death(unit: Node2D, _killer: Node2D) -> void:
	if unit.unit_id == "H02":
		engine.restore_names(float(engine.params(unit).death_return)+float(unit.roster.reserve_incense),unit)
		unit.roster.reserve_incense = 0.0
		engine.event("last_embers",unit,"H02")

func before_structure_damage(attacker: Node2D, object: Node2D, amount: float) -> float:
	for unit in _sim().humans:
		if unit.dead or unit.unit_id != "H09" or not unit.roster.statuses.has("gate_guard"): continue
		if str(object.name) != str(unit.roster.statuses.gate_guard.door_id) or object.position.distance_to(unit.position) > Rules.body_to_px(float(engine.params(unit).radius_body)): continue
		unit.receive_damage(amount,attacker,"gate_transfer")
		engine.event("gate_transferred",unit,str(object.name))
		engine.visual("hold_gate",unit)
		return 0
	return amount

func ritual_duration(caster: Node2D, _target: Node2D, base: float) -> float:
	if caster.unit_id == "H01":
		for unit in _sim().humans+_sim().targets:
			if not unit.dead and (unit.unit_id in ["H06","G11"] or engine.growth().has(unit,"I04")):
				return base*float(engine.params(caster).light_duration_multiplier)
	return base

func ritual_completed(_caster: Node2D, _target: Node2D) -> void:
	for unit in _sim().humans:
		if unit.unit_id == "H03" and not unit.dead: engine.restore_names(float(engine.params(unit).names_per_ritual),unit)

func block_name_erase(target: Node2D, source: Node2D) -> bool:
	if target.unit_id == "H23" and not bool(target.roster.counters.get("passing_name",false)):
		for ally in engine.near(target,5,true):
			if ally.unit_id == "H23": continue
			target.roster.counters.passing_name = true
			engine.status(ally,"name_erase",3,source)
			target.roster.counters.passing_name = false
			engine.event("name_passed",target,ally.instance_id)
			return true
	return _sacrifice_name(source)

func block_register_erase(source: Node2D) -> bool:
	return _sacrifice_name(source)

func _sacrifice_name(source: Node2D) -> bool:
	for unit in _sim().humans:
		if unit.dead or unit.unit_id != "H30" or bool(unit.roster.counters.get("sacrificed",false)): continue
		unit.roster.counters.sacrificed = true
		unit.receive_damage(unit.hp+1,source,"name_sacrifice")
		engine.event("substitute_name",unit,source.unit_id if source != null else "")
		engine.visual("name_guard",unit)
		return true
	return false

func draw_effects(canvas: Node2D) -> void:
	for effect in engine.state.get("effects",[]):
		if effect.kind in ["hold_gate", "incense_transfer", "incense_restored", "cold_light", "river_lantern", "crow_path", "seal", "gold_mirror", "dispel", "false_god_unmasked", "misname", "crossbow_shot"]:
			continue
		var a := Vector2(float(effect.source[0]),float(effect.source[1])).snapped(Vector2(2,2))
		var b := Vector2(float(effect.point[0]),float(effect.point[1])).snapped(Vector2(2,2))
		var phase: float = clampf(1-float(effect.left)/maxf(.01,float(effect.duration)),0,1)
		var ink := Color("c3cbb2")
		var red := Color("bf6855")
		var cold := Color("84b7b2")
		ink.a=1-phase*.6;red.a=ink.a;cold.a=ink.a
		match str(effect.unit_id):
			"H01":
				canvas.draw_rect(Rect2(b-Vector2(26,34),Vector2(52,68)),cold,false,4)
				for i in range(4): canvas.draw_line(b+Vector2(-16,-22+i*14),b+Vector2(16,-22+i*14),ink,3)
			"H02":
				for i in range(3):
					var p: Vector2=b+Vector2(-28+i*28,15)
					canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-9,0),p+Vector2(0,-42-phase*16),p+Vector2(10,-10)]),cold)
			"H03","H30":
				canvas.draw_rect(Rect2(b-Vector2(24,43),Vector2(48,76)),ink,false,4)
				canvas.draw_line(b+Vector2(-14,-24),b+Vector2(14,-24),red,5)
				canvas.draw_line(b+Vector2(0,-34),b+Vector2(0,20),red,5)
				if str(effect.unit_id)=="H30": canvas.draw_line(b+Vector2(-42,35),b+Vector2(42,-45),red,6)
			"H05":
				canvas.draw_arc(a,100+phase*35,0,TAU,16,cold,4)
				canvas.draw_line(a+Vector2(-40,-32),a+Vector2(40,32),ink,7)
			"H07","T04":
				var reach := Rules.body_to_px(float(effect.get("radius_body",3.0)))
				var beat := minf(1,phase*2)
				var front := lerpf(12,reach,beat)
				for direction in [-1,1]:
					var rim := a + Vector2(direction*front,0)
					canvas.draw_polyline(PackedVector2Array([rim + Vector2(-direction*14,-28),rim + Vector2(0,-10),rim + Vector2(0,10),rim + Vector2(-direction*14,28)]),ink,3)
					canvas.draw_line(rim - Vector2(direction*minf(40,front),0),rim,cold,3)
				var grip := a + Vector2(7,-9)
				var tip := grip + Vector2(22,-30).rotated(lerpf(-1.3,0.4,beat))
				canvas.draw_line(grip,tip,red,5)
				canvas.draw_circle(tip,5,ink)
			"H08":
				canvas.draw_colored_polygon(PackedVector2Array([a+Vector2(-70,-35),a+Vector2(70,-35),a+Vector2(50,45),a+Vector2(0,70),a+Vector2(-50,45)]),Color(cold,.28))
				canvas.draw_line(a+Vector2(-50,-8),a+Vector2(50,-8),ink,6)
			"H13":
				if effect.kind=="execution":
					var facing := -1.0 if b.x<a.x else 1.0
					var swing := smoothstep(0,0.32,phase)
					var grip := a+Vector2(9*facing,-6)
					var shaft := Vector2(facing*sin(lerpf(-0.45,1.95,swing)),-cos(lerpf(-0.45,1.95,swing)))
					var edge := Vector2(-shaft.y,shaft.x)*facing
					var tip := grip+shaft*55
					var tint := Color(0.92,0.77,0.51,1-smoothstep(0.32,0.85,phase))
					canvas.draw_line(grip,tip,Color(red,tint.a),5)
					canvas.draw_colored_polygon(PackedVector2Array([tip-shaft*15,tip,tip+edge*16+shaft*5,tip+edge*23-shaft*8,tip+edge*19-shaft*21]),tint)
					if phase>=0.20:
						canvas.draw_line(b-Vector2(facing*12,24),b+Vector2(facing*18,14),Color(red,1-phase),4)
			"H10","H31":
				canvas.draw_line(b+Vector2(-60,-48),b+Vector2(65,40),ink,8)
				canvas.draw_line(b+Vector2(-50,40),b+Vector2(58,-44),cold,4)
				if str(effect.unit_id)=="H31":canvas.draw_dashed_line(a,b,cold,4,22)
			"H11","H25":
				for i in range(4):
					canvas.draw_rect(Rect2(b+Vector2(-48+i*28,30-55*(1-phase)),Vector2(20,55*(1-phase))),ink,false,4)
			"H12":
				canvas.draw_line(a,b,ink,4)
				for i in range(7):canvas.draw_rect(Rect2(a.lerp(b,float(i)/6)-Vector2(7,5),Vector2(14,10)),cold,false,3)
			"H14":
				canvas.draw_arc(a,48,0,TAU,16,ink,7)
				canvas.draw_arc(a,70+phase*120,0,TAU,20,cold,4)
			"H15":
				canvas.draw_dashed_line(a,b,cold,4,18)
				canvas.draw_polyline(PackedVector2Array([b+Vector2(-35,0),b+Vector2(0,-35),b+Vector2(35,0)]),ink,6)
			"H16":
				canvas.draw_line(a,b,ink,6)
				canvas.draw_polyline(PackedVector2Array([b+Vector2(-35,-35),b+Vector2(-5,-8),b+Vector2(-20,25)]),red,5)
				canvas.draw_polyline(PackedVector2Array([b+Vector2(35,-35),b+Vector2(5,-8),b+Vector2(20,25)]),red,5)
			"H32":
				canvas.draw_arc(b,38,0,TAU,8,ink,6)
				canvas.draw_rect(Rect2(b-Vector2(21,24),Vector2(42,48)),cold,false,4)
				canvas.draw_line(b+Vector2(-15,-5),b+Vector2(-5,-5),red,4)
				canvas.draw_line(b+Vector2(5,-5),b+Vector2(15,-5),red,4)
			"H19":
				canvas.draw_dashed_line(a,b,cold,5,12)
				canvas.draw_arc(b,45,0,TAU,8,ink,4)
				# The paper lantern travels from the caster to the borrowed ghost.
				var lamp := a.lerp(b,phase)
				canvas.draw_rect(Rect2(lamp-Vector2(10,14),Vector2(20,28)),red)
				canvas.draw_line(lamp-Vector2(12,14),lamp+Vector2(12,-14),ink,4)
				canvas.draw_line(lamp+Vector2(0,14),lamp+Vector2(0,23),ink,3)
			"H20","H26":
				for i in range(7):
					var p: Vector2=b+Vector2(-90+i*30,-10 if i%2==0 else 15)
					canvas.draw_line(p+Vector2(-12,15),p+Vector2(6,-25-phase*35),red,5)
					canvas.draw_line(p+Vector2(-14,-14),p+Vector2(14,14),ink,3)
			"H24":
				# Three bone needles close on the target, then hold at the stun point.
				var approach := (a-b).normalized()
				if approach.is_zero_approx(): approach = Vector2.UP
				var travel := 1.0 - smoothstep(0.0, 0.38, phase)
				for index in range(-1, 2):
					var direction := approach.rotated(index * 0.55)
					var tip := b + direction * (9.0 + 46.0 * travel)
					var grip := tip + direction * 23.0
					canvas.draw_line(tip, grip, ink, 3)
					canvas.draw_line(grip, grip + direction * 8.0, red, 5)
			"H28":
				canvas.draw_line(a+Vector2(0,-65),a+Vector2(0,-35),ink,3)
				canvas.draw_rect(Rect2(a-Vector2(25,35),Vector2(50,65)),cold,false,5)
				canvas.draw_line(a+Vector2(-18,-12),a+Vector2(18,-12),red,4)
			"H29":
				for i in range(4):canvas.draw_line(a+Vector2(-15,i*11),b+Vector2(30+phase*65,i*11),cold,3)
			"T01":canvas.draw_rect(Rect2(a-Vector2(24,35),Vector2(48,70)),ink,false,5)
