extends RefCounted
## Ghost skills operate through the shared simulator. Every timer belongs to a unit.
var _engine:WeakRef
var engine:RefCounted:
	get:return _engine.get_ref()
func _init(owner_engine:RefCounted)->void:_engine=weakref(owner_engine)
func sim()->Node:return engine.sim()
func growth()->RefCounted:return engine.growth()
func p(unit_or_id,key:String)->float:return float(engine.params(unit_or_id).get(key,0))
func state(unit:Node2D)->Dictionary:
	if not unit.roster.has("ghost"):unit.roster.ghost={}
	return unit.roster.ghost
func result(ok:bool,reason:="P8_SKILL_OK")->Dictionary:return {"ok":ok,"reason":reason if ok else "P8_NO_TARGET"}
func foes(unit:Node2D,radius:=-1.0)->Array:
	return engine.near(unit,p(unit,"radius") if radius<0 else radius,false,true)
func allies(unit:Node2D,radius:=-1.0)->Array:
	return engine.near(unit,p(unit,"radius") if radius<0 else radius,true,true)
func valid_target(unit:Node2D,target:Node2D,radius:=-1.0)->bool:
	return is_instance_valid(target) and not target.dead and target.side!=unit.side and target.floor_id==unit.floor_id and target.position.distance_to(unit.position)<=Rules.body_to_px(p(unit,"radius") if radius<0 else radius)
func target_for(unit:Node2D,args:Dictionary)->Node2D:
	if args.has("target_id"):
		var requested: Node2D = engine.actor(str(args.target_id))
		return requested if valid_target(unit,requested) else null
	var candidates:=foes(unit)
	if unit.unit_id in ["G06","G24"]:
		for other in candidates:
			if other.side=="xianghuo" and (other.brain.channel.active or other.brain.repair_door!=null):return other
	if unit.unit_id in ["G16","G23","G25","G28","G31","G32"]:
		for other in candidates:
			if other.unit_id.begins_with("H") and other.roster.get("face_state","faced")=="faced" and not other.roster.statuses.has("nameless"):return other
	return candidates[0] if not candidates.is_empty() else null
func status(target:Node2D,kind:String,duration:float,source:Node2D,extra:Dictionary={})->Dictionary:
	return engine.status(target,kind,duration,source,extra)
func visual(kind:String,unit:Node2D,duration:=1.2)->void:
	state(unit).visual_kind=kind;state(unit).visual_until=float(growth().state.time)+duration
	engine.visual(kind,unit,unit.position,duration)
func event(kind:String,unit:Node2D,detail:="")->void:engine.event(kind,unit,detail)
func damage(source:Node2D,target:Node2D,value:float,kind:String)->void:
	if not is_instance_valid(target):
		return
	if target.is_in_group("units") and target.dead:
		return
	if not target.is_in_group("units") and target.durability <= 0:
		return
	sim().deal_damage(source,target,kind,value)
func interrupt(unit:Node2D)->void:
	if unit.side=="xianghuo" and unit.brain!=null and unit.brain.channel.active:unit.brain.channel.cancel("P8_SKILL_INTERRUPTED")
func silent(unit:Node2D)->bool:
	return engine.is_silenced(unit) or unit.roster.statuses.has("silence")
func commit(unit:Node2D,kind:String,detail:="")->Dictionary:
	state(unit).visual_target=detail
	engine.cooldown(unit,p(unit,"cooldown"));event(kind,unit,detail);visual(kind,unit)
	return result(true)

func advance(unit:Node2D,delta:float)->void:
	var memory:=state(unit)
	if float(memory.get("arm_disabled",0))>0:memory.arm_disabled=maxf(0,float(memory.arm_disabled)-delta)
	if unit.unit_id=="G04":
		growth().ensure(unit)
		unit.growth.counters.invisible=not unit.growth.statuses.has("revealed") and not unit.roster.statuses.has("revealed")
	if unit.unit_id=="G19" and engine.ready(unit,"face_repel"):
		for other in foes(unit):
			if int(other.growth.get("counters",{}).get("face_ward",0))>0:
				damage(other,unit,p(unit,"collapse_damage"),"face_mirror");engine.cooldown(unit,p(unit,"cooldown"),"face_repel");event("mirror_face_collapse",unit,other.instance_id);visual("mirror_collapse",unit);break
	if unit.unit_id=="G18":
		memory.part_left=float(memory.get("part_left",0))-delta
		if memory.part_left<=0:
			memory.part_left=p(unit,"cooldown");memory.weak_part=(int(memory.get("weak_part",-1))+1)%int(p(unit,"part_count"))
			event("parade_weak_part",unit,str(memory.weak_part));visual("parade_part",unit)
	if unit.unit_id=="G31" and not memory.has("layers"):memory.layers=0
	if unit.unit_id=="G32" and float(memory.get("naming_left",0))>0:memory.naming_left=maxf(0,float(memory.naming_left)-delta)
	if not engine.ready(unit):return
	if not engine.can_act(unit) or not growth().can_act(unit):return
	engine.cast(unit)

func cast(unit:Node2D,args:Dictionary={})->Dictionary:
	if not is_instance_valid(unit) or unit.dead or not engine.ready(unit):return result(false)
	var memory:=state(unit)
	match unit.unit_id:
		"G01":
			var barrier=sim().next_barrier(unit.position.x,unit.floor_id)
			if barrier==null or barrier.position.distance_to(unit.position)>Rules.body_to_px(p(unit,"radius")) or allies(unit).is_empty():return result(false)
			return commit(unit,"crowd_door",str(barrier.name))
		"G02":
			var reader:Node2D
			for other in foes(unit):
				if other.side=="xianghuo" and other.brain.channel.active:reader=other;break
			var desk=sim().world.get_node("register_desk")
			if reader==null and (unit.floor_id!=desk.floor_id or unit.position.distance_to(desk.position)>Rules.body_to_px(p(unit,"radius"))):return result(false)
			var opposing:="shouxiang" if unit.side=="yegui" else "duoming"
			var actual:float=-engine.change_incense(opposing,-p(unit,"drain"))
			if actual<=0:return result(false)
			engine.change_incense(growth().seat_of(unit),actual)
			return commit(unit,"beg_incense",reader.instance_id if reader!=null else "register")
		"G03":
			var reach: float = engine.loud_skill_radius(unit,p(unit,"radius"))
			var heard := foes(unit,reach)
			if heard.is_empty():return result(false)
			if silent(unit):
				engine.reveal_from_loud_skill(unit,unit.unit_id,reach)
				damage(unit,unit,p(unit,"backlash"),"cry_backlash")
				return commit(unit,"cry_backlash")
			for other in heard:status(other,"cry_weak",p(unit,"duration"),unit,{"multiplier":p(unit,"defense_multiplier")})
			return commit(unit,"mourning_cry")
		"G04":
			growth().ensure(unit)
			if growth().is_hidden(unit):
				if not memory.get("hidden_announced",false):memory.hidden_announced=true;visual("wall_shadow",unit);event("wall_shadow",unit)
			else:memory.hidden_announced=false
			engine.cooldown(unit,p(unit,"cooldown"));return result(true)
		"G05":
			var corpse=corpse_for(unit)
			if corpse==null:return result(false)
			memory.corpse_id=corpse.instance_id
			return commit(unit,"seek_remains",corpse.instance_id)
		"G06":
			var target := target_for(unit,args)
			if float(memory.get("arm_disabled",0))>0 or target==null or target.side!="xianghuo" or not (target.brain.channel.active or target.brain.repair_door!=null):return result(false)
			damage(unit,target,p(unit,"damage"),"claw");interrupt(target)
			if target.brain.repair_door!=null:target.brain.repair_door=null
			status(target,"root",p(unit,"duration"),unit)
			return commit(unit,"long_claw",target.instance_id)
		"G07","G09":
			# The existing wall/beam route is the only movement source; no teleport.
			if unit.side != "yegui" or unit.brain.stage not in ["climb","upper","descend"]:return result(false)
			return commit(unit,"narrow_window" if unit.unit_id=="G07" else "beam_pounce",unit.brain.stage)
		"G08":
			return result(false) # Reactive explosion is on_death/ritual_completed, once.
		"G10":
			var target := target_for(unit,args)
			if target==null or not growth().in_environment(unit,"water"):return result(false)
			var drag: float = engine.session.ritual.water_drag_multiplier(unit)
			status(target,"drag",p(unit,"duration")*drag,unit);growth()._displace(target,unit.position.x,Rules.body_to_px(p(unit,"drag_body")*drag))
			damage(unit,target,p(unit,"damage"),"water_drag");interrupt(target)
			return commit(unit,"water_drag",target.instance_id)
		"G11":
			var radius:float=float(growth().rules().skills.double_lamp_radius_body) if unit.growth.statuses.has("double_lamp") else p(unit,"radius")
			var targets:Array=foes(unit,radius)
			if targets.is_empty():return result(false)
			# One light tick, through the common status/damage entries; no legacy double burn.
			for other in targets:
				status(other,"revealed",p(unit,"reveal_duration"),unit)
				if other.unit_id in ["G01","G04"] or other.roster.get("face_state","faced")=="faceless":damage(unit,other,p(unit,"damage"),"light")
				if engine.session.ritual.has_flag("reveal_faces") and other.roster.get("face_state","faced") == "faceless" and growth()._ready(other,"light_fear"):
					var fear: float = engine.session.ritual.light_fear_duration(other,float(growth().rules().skills.light_fear_duration))
					status(other,"fear",fear,unit)
					growth()._cd(other,"light_fear",float(growth().rules().skills.fear_cooldown))
			return commit(unit,"bone_lantern")
		"G12":
			var barrier=sim().next_barrier(unit.position.x,unit.floor_id)
			if barrier==null or barrier.position.distance_to(unit.position)>Rules.body_to_px(p(unit,"radius")):return result(false)
			# Shared attack already applies the established G12 structure multiplier.
			visual("door_ram",unit);event("door_ram",unit,str(barrier.name));engine.cooldown(unit,p(unit,"cooldown"));return result(true)
		"G13":
			var target := target_for(unit,args)
			var partner=partner_for(unit)
			if partner==null:return result(false)
			if target==null:target=sim().next_barrier(unit.position.x,unit.floor_id)
			if target==null or target.position.distance_to(unit.position)>Rules.body_to_px(p(unit,"radius")):return result(false)
			state(unit).partner_id=partner.instance_id;state(partner).partner_id=unit.instance_id
			start_charge(unit,target,p(unit,"charge_multiplier"),p(unit,"push_body"));start_charge(partner,target,p(unit,"charge_multiplier"),p(unit,"push_body"))
			engine.cooldown(partner,p(unit,"cooldown"));return commit(unit,"empty_sedan_pair",partner.instance_id)
		"G14":
			var target := target_for(unit,args)
			if target==null:return result(false)
			status(target,"charm",p(unit,"duration"),unit)
			return commit(unit,"wedding_charm",target.instance_id)
		"G15":
			var target := target_for(unit,args)
			if target!=null and target.unit_id.begins_with("H") and target.roster.get("face_state","faced")=="faced":
				status(target,"slow",p(unit,"duration"),unit,{"multiplier":p(unit,"slow_multiplier")});return commit(unit,"tailor_named_slow",target.instance_id)
			for ally in allies(unit):
				if not ally.roster.statuses.has("cloth"):
					status(ally,"cloth",p(unit,"duration"),unit,{"multiplier":p(unit,"damage_multiplier")});return commit(unit,"burial_cloth",ally.instance_id)
			return result(false)
		"G16":
			var target := target_for(unit,args)
			if target==null:return result(false)
			for ally in allies(unit):status(ally,"focus",p(unit,"duration"),unit,{"target_id":target.instance_id})
			status(target,"marked",p(unit,"duration"),unit)
			return commit(unit,"warrant_focus",target.instance_id)
		"G17":return smash_path(unit,args)
		"G18":
			visual("parade_part",unit);return commit(unit,"parade_formation",str(memory.get("weak_part",0)))
		"G19":
			var target := target_for(unit,args)
			if target==null or not target.unit_id.begins_with("H"):return result(false)
			var copied:Dictionary=engine.cast_as(unit,target.unit_id,args)
			if not copied.get("ok",false):return copied
			memory.copied_id=target.unit_id;unit.roster.face_state="faceless"
			return commit(unit,"mirror_copy",target.unit_id)
		"G20":
			var target := target_for(unit,args)
			if growth().in_environment(unit,"water") or broken_bridge_at(unit):status(unit,"stun",p(unit,"fall_duration"),unit);return commit(unit,"horse_fall")
			if target==null:target=sim().next_barrier(unit.position.x,unit.floor_id)
			if target==null or target.position.distance_to(unit.position)>Rules.body_to_px(p(unit,"radius")):return result(false)
			start_charge(unit,target,p(unit,"charge_multiplier"),p(unit,"push_body"));return commit(unit,"night_charge")
		"G21":
			var reach: float = engine.loud_skill_radius(unit,p(unit,"radius"))
			var heard := foes(unit,reach)
			if heard.is_empty():return result(false)
			if silent(unit):
				engine.reveal_from_loud_skill(unit,unit.unit_id,reach)
				damage(unit,unit,p(unit,"backlash"),"bell_backlash")
				return commit(unit,"bell_backlash")
			for other in heard:status(other,"stun",p(unit,"duration"),unit)
			return commit(unit,"bell_shock")
		"G22":
			var target := target_for(unit,args)
			if target==null:return result(false)
			status(target,"dream",p(unit,"duration"),unit,{"source_id":unit.instance_id})
			return commit(unit,"womb_dream",target.instance_id)
		"G23":return result(false) # Faces are gained by real defeats in after_damage.
		"G24":
			var target := target_for(unit,args)
			if target!=null and target.side=="xianghuo" and target.brain.repair_door!=null:
				damage(unit,target,p(unit,"repair_damage"),"sabotage");target.brain.repair_door=null;return commit(unit,"break_repairer",target.instance_id)
			# Before entering the building, retain the authored side-window approach.
			if unit.floor_id==0 and unit.position.x<Rules.body_to_px(float(sim().tide.config.climb.to_x)):return result(false)
			var barrier=nearest_breakable(unit)
			if barrier==null:return result(false)
			state(unit).priority_structure=str(barrier.name)
			return commit(unit,"sabotage_mechanism",str(barrier.name))
		"G25":
			var target := target_for(unit,args)
			if target==null or not target.unit_id.begins_with("H"):return result(false)
			status(target,"name_erase",p(unit,"duration"),unit)
			return commit(unit,"erase_name",target.instance_id)
		"G26":
			var target := target_for(unit,args)
			if target==null and not near_register(unit):return result(false)
			status(unit,"blank_field",p(unit,"duration"),unit,{"radius":p(unit,"radius")})
			return commit(unit,"blank_page")
		"G27":
			var target := target_for(unit,args)
			if target==null and not near_register(unit):return result(false)
			status(unit,"poison_field",p(unit,"duration"),unit,{"radius":p(unit,"radius")})
			return commit(unit,"reverse_incense")
		"G28":
			var target := target_for(unit,args)
			if target==null or target.roster.get("face_state","faced")=="faceless":return result(false)
			var applied:=status(target,"face_theft",p(unit,"duration"),unit)
			if applied.get("ok",false) and not applied.get("blocked",false):
				target.roster.face_state="faceless";status(unit,"held_face",p(unit,"duration"),unit)
			return commit(unit,"steal_face",target.instance_id)
		"G29":
			var target := target_for(unit,args)
			if target==null:return result(false)
			var original:String=target.side
			var applied:Dictionary=status(target,"misrecord",p(unit,"duration"),unit,{"original_side":original,"restore_left":p(unit,"duration"),"source_id":unit.instance_id,"end_stun":p(unit,"end_stun")})
			if not applied.get("ok",false):return applied
			if applied.get("blocked",false):return commit(unit,"misrecord_reflected" if applied.get("reason","")=="P8_SPELL_REFLECTED" else "misrecord_blocked",target.instance_id)
			engine.set_allegiance(target,unit.side,p(unit,"duration"),unit)
			return commit(unit,"misrecord_side",target.instance_id)
		"G30":return false_god(unit)
		"G31":
			var target := target_for(unit,args)
			if target==null:return result(false)
			var taken:float=engine.drain_names(p(unit,"name_loss"),unit)
			if taken<=0:return result(false)
			add_layers(unit,1);return commit(unit,"stack_names",str(memory.layers))
		"G32":
			var target := target_for(unit,args)
			if target==null:return result(false)
			var phase:int=int(memory.get("phase",0))%3;memory.phase=phase+1
			match phase:
				0:status(target,"name_erase",p(unit,"duration"),unit)
				1:status(target,"face_theft",p(unit,"duration"),unit)
				2:status(unit,"blank_field",p(unit,"duration"),unit,{"radius":p(unit,"radius")})
			return commit(unit,"open_register",str(phase))
	return result(false)

func corpse_for(unit:Node2D)->Node2D:
	var best:Node2D
	var distance:float=Rules.body_to_px(p(unit,"radius"))
	for corpse in sim().corpses:
		if not is_instance_valid(corpse) or corpse.floor_id!=unit.floor_id or bool(corpse.roster.get("eaten",false)):continue
		var next:float=unit.position.distance_to(corpse.position)
		if next<distance:best=corpse;distance=next
	return best
func partner_for(unit:Node2D)->Node2D:
	for other in allies(unit,p(unit,"partner_radius")):
		if other.unit_id=="G13":return other
	return null
func nearest_breakable(unit:Node2D)->Node2D:
	var best:Node2D
	var distance:float=Rules.body_to_px(p(unit,"radius"))
	for object in sim().world.obstacles+sim().world.doors:
		if object.floor_id!=unit.floor_id or object.durability<=0:continue
		var next:float=unit.position.distance_to(object.position)
		if next<distance:best=object;distance=next
	return best
func near_register(unit:Node2D)->bool:
	var desk=sim().world.get_node("register_desk")
	return unit.floor_id==desk.floor_id and unit.position.distance_to(desk.position)<=Rules.body_to_px(p(unit,"radius"))
func broken_bridge_at(unit:Node2D)->bool:
	for zone in growth().state.environments:
		if zone.kind=="bridge" and zone.floor_id==unit.floor_id and unit.position.x>=Rules.body_to_px(float(zone.from_body)) and unit.position.x<=Rules.body_to_px(float(zone.to_body)) and engine.path_broken(str(zone.id)):return true
	return false
func smash_path(unit:Node2D,args:Dictionary)->Dictionary:
	var wanted:String=str(args.get("path_id",""))
	for path in sim().world.layout.stairs:
		if wanted!="" and path.id!=wanted:continue
		if engine.path_broken(str(path.id)):continue
		var floor:int=int(path.from_floor) if unit.floor_id==int(path.from_floor) else int(path.to_floor)
		if unit.floor_id not in [int(path.from_floor),int(path.to_floor)]:continue
		var point:=Vector2(Rules.body_to_px(float(path.from_x if floor==int(path.from_floor) else path.to_x)),sim().world.floor_y(floor))
		if point.distance_to(unit.position)>Rules.body_to_px(p(unit,"radius")):continue
		engine.break_path(str(path.id))
		for other in foes(unit):
			if other.floor_id>0:growth().knock_from_beam(other,unit)
		return commit(unit,"beam_smashed",str(path.id))
	return result(false)
func start_charge(unit:Node2D,target:Node2D,multiplier:float,push:float)->void:
	state(unit).charge={"target_id":target.instance_id if target.is_in_group("units") else "world:"+str(target.name),"multiplier":multiplier,"push":push,"left":p(unit,"charge_duration")}
	status(unit,"charge",p(unit,"charge_duration"),unit);visual("night_charge",unit)
func advance_actor(unit:Node2D,delta:float)->bool:
	var memory:=state(unit)
	if unit.roster.statuses.has("dream"):return true
	if unit.unit_id=="G05" and memory.has("corpse_id"):
		var corpse:Node2D
		for other in sim().corpses:
			if other.instance_id==str(memory.corpse_id):corpse=other;break
		if corpse==null or corpse.roster.get("eaten",false):memory.erase("corpse_id");return false
		if unit.position.distance_to(corpse.position)<=Rules.body_to_px(p(unit,"eat_range")):
			engine.ensure(corpse);corpse.roster.eaten=true;engine.heal(unit,p(unit,"heal"),unit);status(unit,"feast_speed",p(unit,"duration"),unit,{"multiplier":p(unit,"speed_multiplier")})
			memory.erase("corpse_id");event("devour_remains",unit,corpse.instance_id);visual("devour_remains",unit);return true
		return _move_actor(unit,corpse.position,corpse.floor_id,delta,1.0)
	if memory.has("charge"):
		var task:Dictionary=memory.charge;task.left-=delta
		var target:Node2D=sim().world.get_node_or_null(str(task.target_id).trim_prefix("world:")) if str(task.target_id).begins_with("world:") else engine.actor(str(task.target_id))
		if target==null or task.left<=0:memory.erase("charge");return false
		if unit.position.distance_to(target.position)<=Rules.body_to_px(float(unit.profile.range_body)+.5):
			damage(unit,target,unit.attack*float(task.multiplier),"charge" if target.is_in_group("units") else "charge_structure")
			for other in foes(unit,p(unit,"charge_hit_radius")):growth()._displace(other,unit.position.x,-Rules.body_to_px(float(task.push)));interrupt(other)
			event("charge_collision",unit,str(task.target_id));visual("charge_collision",unit);memory.erase("charge");return true
		return _move_actor(unit,target.position,target.floor_id,delta,p(unit,"charge_speed"))
	var forced:Node2D
	if unit.roster.statuses.has("taunt"):forced=engine.actor(str(unit.roster.statuses.taunt.get("source_id","")))
	elif unit.roster.statuses.has("focus"):forced=engine.actor(str(unit.roster.statuses.focus.get("target_id","")))
	elif memory.has("priority_structure"):forced=sim().world.get_node_or_null(str(memory.priority_structure))
	if forced!=null and not forced.is_queued_for_deletion():
		if not forced.is_in_group("units") and forced.durability<=0:
			memory.erase("priority_structure");return false
		if forced.floor_id!=unit.floor_id:return false
		if forced.is_in_group("units") and forced.dead:return false
		if forced.position.distance_to(unit.position)<=Rules.body_to_px(float(unit.profile.range_body)):
			sim().perform_attack(unit,forced);return true
		return _move_actor(unit,forced.position,forced.floor_id,delta,1.0)
	return false
func _move_actor(unit:Node2D,destination:Vector2,floor:int,delta:float,multiplier:float)->bool:
	if not unit.motion_enabled or floor!=unit.floor_id:return false
	var route:Array=sim().world.navigation.horizontal_path(unit.position,destination,floor,true)
	if route.is_empty():return false
	var next:Vector2=route[0].point
	if next.distance_to(unit.position)<.1 and route.size()>1:next=route[1].point
	var previous:Vector2=unit.position
	var speed:float=Rules.body_to_px(sim().tide.speed(unit))*growth().speed_multiplier(unit)*multiplier
	var proposed:Vector2=unit.position.move_toward(next,speed*delta)
	if sim().world.segment_blocked(unit.position,proposed,floor):return false
	unit.position=proposed;unit.velocity=(unit.position-previous)/delta;unit.current_speed=unit.velocity.length();unit.progress+=unit.position.distance_to(previous)
	unit.set_state("GhostSkillMove");unit.sync_meta();return true
func advance_world(delta:float)->void:
	for unit in (sim().humans+sim().targets).duplicate():
		if unit.dead:continue
		if unit.roster.statuses.has("misrecord"):
			var task:Dictionary=unit.roster.statuses.misrecord
			task.restore_left=float(task.get("restore_left",task.left))-delta
			if task.restore_left<=0:
				var source=engine.actor(str(task.get("source_id","")))
				var original:String=str(task.original_side);var stun:float=float(task.end_stun)
				# Keep the temporary marker during the signal so the night bridge does not
				# mistake restoration for a permanent recruitment/departure.
				engine.set_allegiance(unit,original,0,source)
				if original=="yegui":
					unit.current_post="ghost_main_path"
					unit.sync_meta()
				unit.roster.statuses.erase("misrecord")
				status(unit,"stun",stun,source);event("misrecord_ended",unit);visual("ink_stun",unit)
		if unit.roster.statuses.has("dream"):
			if unit.roster.statuses.has("revealed") or unit.growth.get("statuses",{}).has("revealed"):
				unit.roster.statuses.erase("dream");event("dream_awakened",unit);visual("dream_awakened",unit)
		if unit.roster.get("face_state","faced")=="faceless" and unit.unit_id.begins_with("H") and not unit.roster.statuses.has("faceless") and not unit.growth.get("statuses",{}).has("face_theft"):
			unit.roster.face_state="faced";event("face_restored",unit)

func after_damage(attacker:Node2D,victim:Node2D,amount:float,kind:String,before:float)->void:
	if not is_instance_valid(victim) or not victim.is_in_group("units"):return
	if victim.unit_id=="G06" and amount>0 and is_instance_valid(attacker) and attacker.side!=victim.side:
		var memory:=state(victim);memory.arm_hits=int(memory.get("arm_hits",0))+1
		if int(memory.arm_hits)>=int(p(victim,"arm_hits")):
			memory.arm_hits=0;memory.arm_disabled=p(victim,"arm_disabled");event("claw_disabled",victim);visual("broken_claw",victim)
	if is_instance_valid(attacker) and attacker.unit_id=="G23" and before>0 and victim.dead and victim.unit_id.begins_with("H") and victim.roster.get("face_state","faced")=="faced":
		var memory:=state(attacker);memory.faces=int(memory.get("faces",0))+1
		memory.stolen_names=float(memory.get("stolen_names",0))+engine.drain_names(p(attacker,"names_per_face"),attacker)
		attacker.attack+=p(attacker,"attack_per_face");attacker.max_hp+=p(attacker,"hp_per_face");attacker.hp+=p(attacker,"hp_per_face");growth().refresh_base(attacker)
		attacker.roster.face_state="faced";event("borrowed_face",attacker,victim.instance_id);visual("borrowed_face",attacker)
	if victim.dead:on_death(victim,attacker)
	if kind in ["reflection","mirror"] and victim.unit_id=="G19" and not victim.dead:
		damage(attacker,victim,p(victim,"collapse_damage"),"mirror_collapse");event("mirror_collapse",victim);visual("mirror_collapse",victim)
func on_death(unit:Node2D,_killer:Node2D=null)->void:
	var memory:=state(unit)
	if bool(memory.get("death_processed",false)):return
	memory.death_processed=true
	if unit.unit_id=="G08":explode(unit)
	if unit.unit_id=="G13":
		var partners:Array=allies(unit,p(unit,"partner_radius"))
		var linked=engine.actor(str(memory.get("partner_id","")))
		if linked!=null and linked not in partners:partners.append(linked)
		for partner in partners:
			if partner.unit_id=="G13":status(partner,"disorder",p(unit,"widow_duration"),unit,{"multiplier":p(unit,"widow_multiplier")});event("sedan_widowed",partner);visual("sedan_widowed",partner)
func explode(unit:Node2D)->void:
	var memory:=state(unit)
	if bool(memory.get("exploded",false)):return
	memory.exploded=true
	for other in (sim().humans+sim().targets).duplicate():
		if other==unit or other.dead or other.floor_id!=unit.floor_id or other.position.distance_to(unit.position)>Rules.body_to_px(p(unit,"radius")):continue
		damage(unit,other,p(unit,"damage"),"incense_explosion");interrupt(other)
	event("scatter_incense",unit);visual("scatter_incense",unit)
func damage_multiplier(attacker:Node2D,victim:Node2D,kind:String)->float:
	if not is_instance_valid(attacker):return 1.0
	var multiplier:=1.0
	if attacker.unit_id=="G10":multiplier*=1.0/float(growth().rules().environment.water_stat_multiplier) if growth().in_environment(attacker,"water") else p(attacker,"land_attack_multiplier")
	if attacker.unit_id=="G09" and attacker.floor_id==2:multiplier*=p(attacker,"beam_attack_multiplier")
	if attacker.unit_id=="G16" and victim.is_in_group("units") and victim.unit_id in ["H12","H14"]:multiplier*=p(attacker,"official_multiplier")
	if attacker.unit_id=="G24" and not victim.is_in_group("units"):multiplier*=p(attacker,"structure_multiplier")
	if attacker.unit_id=="G28" and attacker.roster.statuses.has("held_face"):multiplier*=p(attacker,"attack_multiplier")
	if attacker.roster.statuses.has("disorder"):multiplier*=float(attacker.roster.statuses.disorder.multiplier)
	return multiplier
func before_receive(unit:Node2D,amount:float,attacker:Node2D,kind:String)->float:
	if unit.roster.statuses.has("cloth"):amount*=float(unit.roster.statuses.cloth.multiplier)
	if unit.unit_id=="G07" and kind in ["fire","incense","explosion","area","incense_explosion"]:amount*=p(unit,"area_vulnerability")
	if unit.unit_id=="G14" and is_instance_valid(attacker) and attacker.unit_id in ["H16","H22"]:amount*=p(unit,"counter_multiplier")
	if unit.unit_id=="G18":
		var part:int=2 if is_instance_valid(attacker) and attacker.position.x>unit.position.x else (1 if kind in ["projectile","bolt","talisman","fire"] else 0)
		if part!=int(state(unit).get("weak_part",0)):amount=minf(amount*p(unit,"wrong_part_multiplier"),maxf(0,unit.hp-1))
		var formation:int=allies(unit,p(unit,"radius")).size()
		if formation>0:amount*=p(unit,"formation_multiplier")
	if unit.unit_id=="G19" and kind in ["reflection","mirror","face_mirror"]:amount*=p(unit,"mirror_damage_multiplier")
	if unit.unit_id=="G27" and (kind in ["fire","fire_field"] or growth().state.ritual_flag in ["jizao","祭灶"]):amount*=p(unit,"fire_vulnerability")
	if unit.unit_id=="G28" and (growth().state.ritual_flag in ["kaimian","开面"] or is_instance_valid(attacker) and attacker.unit_id=="H32"):amount*=p(unit,"counter_multiplier")
	if unit.unit_id=="G30" and is_instance_valid(attacker) and attacker.unit_id=="H22":amount*=p(unit,"dispel_multiplier")
	if unit.unit_id=="G32" and float(state(unit).get("naming_left",0))>0:amount*=p(unit,"named_damage_multiplier")
	return amount
func before_structure_damage(_attacker:Node2D,_object:Node2D,amount:float)->float:return amount
func ritual_duration(_caster:Node2D,target:Node2D,base:float)->float:
	if target.unit_id=="G01":base*=p(target,"ritual_multiplier")
	if target.unit_id=="G02" and target.hp/target.max_hp<=p(target,"low_hp_ratio"):base*=p(target,"ritual_multiplier")
	if target.unit_id=="G24":base*=p(target,"recruit_multiplier")
	return base
func ritual_completed(caster:Node2D,target:Node2D)->bool:
	var memory:=state(target)
	if target.unit_id=="G08":explode(target)
	if target.unit_id=="G23":
		var faces:int=int(memory.get("faces",0));engine.restore_names(float(memory.get("stolen_names",0)),target);memory.faces=0;memory.stolen_names=0.0
		if faces>0:event("faces_released",target,str(faces));visual("faces_released",target)
	if target.unit_id=="G31" and int(memory.get("layers",0))>0:
		remove_layers(target,mini(int(memory.layers),int(p(target,"collapse_layers"))));event("name_layers_collapsed",target);visual("name_layers_collapsed",target);return true
	if target.unit_id=="G32" and float(memory.get("naming_left",0))<=0 and engine.session.names>=p(target,"naming_names"):
		memory.naming_left=p(target,"naming_duration");event("naming_window",target,caster.instance_id);visual("naming_window",target,p(target,"naming_duration"));return true
	return false
func add_layers(unit:Node2D,count:int)->void:
	var memory:=state(unit);var actual:int=mini(count,int(p(unit,"max_layers"))-int(memory.get("layers",0)))
	if actual<=0:return
	memory.layers=int(memory.get("layers",0))+actual;unit.max_hp+=actual*p(unit,"hp_per_layer");unit.hp+=actual*p(unit,"hp_per_layer");unit.defense+=actual*p(unit,"defense_per_layer");growth().refresh_base(unit)
func remove_layers(unit:Node2D,count:int)->void:
	var memory:=state(unit);var actual:int=mini(count,int(memory.get("layers",0)))
	memory.layers=int(memory.get("layers",0))-actual;unit.max_hp-=actual*p(unit,"hp_per_layer");unit.hp=minf(unit.hp,unit.max_hp);unit.defense=maxf(0,unit.defense-actual*p(unit,"defense_per_layer"));growth().refresh_base(unit)
func false_god(unit:Node2D)->Dictionary:
	var exposed:=false
	for other in foes(unit):
		if other.side=="xianghuo":
			for job in growth().state.borrow_jobs:
				if job.unit_id==other.instance_id:exposed=true
	if not exposed:return result(false)
	for other in foes(unit):damage(unit,other,p(unit,"damage"),"false_god");status(other,"stun",p(unit,"duration"),unit)
	engine.drain_names(p(unit,"name_loss"),unit);return commit(unit,"false_god_offering")
func heal_modifier(target:Node2D,amount:float,source:Node2D=null,apply_effects:=true)->float:
	for ghost in sim().targets+sim().humans:
		if ghost.dead or not ghost.unit_id.begins_with("G"):continue
		if not field_contains(ghost,target,source):continue
		if ghost.roster.statuses.has("blank_field"):
			if apply_effects:event("blank_prevented_rekindle",ghost);visual("blank_prevented_rekindle",ghost)
			return 0
		if ghost.roster.statuses.has("poison_field"):
			if apply_effects:
				for other in sim().humans+sim().targets:
					if not other.dead and other.floor_id==ghost.floor_id and other.position.distance_to(ghost.position)<=Rules.body_to_px(p(ghost,"radius")):damage(ghost,other,amount*p(ghost,"poison_multiplier"),"poison_smoke")
				event("recovery_poisoned",ghost);visual("poison_smoke",ghost)
			return 0
	return amount
func field_contains(ghost:Node2D,target:Node2D,source:Node2D)->bool:
	for actor in [target,source]:
		if is_instance_valid(actor) and actor.floor_id==ghost.floor_id and actor.position.distance_to(ghost.position)<=Rules.body_to_px(p(ghost,"radius")):return true
	return target==null and near_register(ghost)
func name_reward(caster:Node2D,target:Node2D,base:float,apply_effects:=true)->float:
	for ghost in sim().targets+sim().humans:
		if not ghost.dead and ghost.roster.statuses.has("blank_field") and field_contains(ghost,target,caster):
			if apply_effects:event("blank_prevented_names",ghost)
			return 0
	return base

func speed_multiplier(unit:Node2D)->float:
	var value:=1.0
	if unit.unit_id=="G10":value*=1.0/float(growth().rules().environment.water_speed_multiplier) if growth().in_environment(unit,"water") else p(unit,"land_speed_multiplier")
	if unit.roster.statuses.has("slow"):value*=float(unit.roster.statuses.slow.multiplier)
	if unit.roster.statuses.has("feast_speed"):value*=float(unit.roster.statuses.feast_speed.multiplier)
	return value

static func valid_state(unit_roster:Dictionary)->bool:
	if unit_roster.has("ghost"):
		if not unit_roster.ghost is Dictionary:return false
		var memory:Dictionary=unit_roster.ghost
		for key in ["arm_disabled","part_left","naming_left","stolen_names","visual_until"]:
			if memory.has(key) and not finite_number(memory[key],0):return false
		for key in ["arm_hits","weak_part","faces","layers","phase"]:
			if memory.has(key) and (not finite_number(memory[key],0) or float(memory[key])!=int(memory[key])):return false
		if memory.has("weak_part") and int(memory.weak_part)>2:return false
		if memory.has("layers") and int(memory.layers)>int(Data.roster_rules.get("abilities",{}).get("G31",{}).get("max_layers",6)):return false
		for key in ["hidden_announced","death_processed","exploded"]:
			if memory.has(key) and not memory[key] is bool:return false
		for key in ["corpse_id","priority_structure","copied_id","visual_kind","visual_target","partner_id"]:
			if memory.has(key) and not memory[key] is String:return false
		if memory.has("priority_structure") and not structure_id(memory.priority_structure):return false
		if memory.has("charge"):
			var task=memory.charge
			if not task is Dictionary or not task.get("target_id") is String:return false
			for key in ["multiplier","push","left"]:
				if not finite_number(task.get(key),0):return false
			if str(task.target_id).begins_with("world:") and not structure_id(str(task.target_id).trim_prefix("world:")):return false
	if not unit_roster.get("statuses",{}) is Dictionary:return false
	var statuses:Dictionary=unit_roster.get("statuses",{})
	for key in ["cloth","disorder","slow","feast_speed","cry_weak"]:
		if statuses.has(key) and (not statuses[key] is Dictionary or not finite_number(statuses[key].get("multiplier"),0)):return false
	for key in ["blank_field","poison_field"]:
		if statuses.has(key) and (not statuses[key] is Dictionary or not finite_number(statuses[key].get("radius"),.001)):return false
	if statuses.has("focus") and (not statuses.focus is Dictionary or not statuses.focus.get("target_id") is String):return false
	if statuses.has("misrecord"):
		var task=statuses.misrecord
		if not task is Dictionary or task.get("original_side") not in ["xianghuo","yegui"] or not task.get("source_id") is String or not finite_number(task.get("restore_left"),0) or not finite_number(task.get("end_stun"),0):return false
	return true
static func finite_number(value:Variant,minimum:float)->bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=minimum
static func structure_id(id:String)->bool:
	var layout:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/reference_gate_court.json"))
	for spec in layout.doors+layout.obstacle_slots+layout.facilities:
		if spec.id==id:return true
	return false

func draw_effects(canvas:Node2D)->void:
	var ink:=Color("b6c7ac")
	var red:=Color("b65b59")
	for unit in sim().humans+sim().targets:
		if unit.dead or not unit.unit_id.begins_with("G") or not unit.roster.has("ghost"):continue
		var memory:Dictionary=unit.roster.ghost
		var point:Vector2=unit.position-Vector2(0,unit.height_px*.65)
		if unit.roster.statuses.has("blank_field") or unit.roster.statuses.has("poison_field"):
			var radius:float=Rules.body_to_px(p(unit,"radius"))
			canvas.draw_rect(Rect2(unit.position-Vector2(radius,25),Vector2(radius*2,25)),Color(.62,.66,.52,.16) if unit.unit_id=="G26" else Color(.38,.56,.34,.2))
		if unit.unit_id=="G18":
			for part in range(3):
				canvas.draw_rect(Rect2(point+Vector2(-23+part*20,-30-part*7),Vector2(13,13)),red if part==int(memory.get("weak_part",0)) else Color("4a5d55"),true)
		if float(memory.get("naming_left",0))>0:
			canvas.draw_rect(Rect2(point-Vector2(48,55),Vector2(96,125)),Color("d8c388"),false,4)
		if float(memory.get("visual_until",0))<float(growth().state.time):continue
		var endpoint:=point+Vector2(90,0)
		var target=engine.actor(str(memory.get("visual_target","")))
		if target!=null:endpoint=target.position-Vector2(0,target.height_px*.6)
		match unit.unit_id:
			"G01":
				for i in range(3):canvas.draw_polyline(PackedVector2Array([point+Vector2(-30+i*24,-15),point+Vector2(-15+i*24,0),point+Vector2(-30+i*24,15)]),ink,4)
			"G02":
				canvas.draw_dashed_line(point,endpoint,Color("a9c3ba"),3,12)
				canvas.draw_arc(point,18,PI,TAU,12,ink,3)
			"G03":
				for i in range(3):canvas.draw_arc(point,35+i*24,PI*.1,PI*.9,16,Color(.55,.65,.65,.6),3)
			"G04":
				for i in range(5):canvas.draw_line(point+Vector2(-28+i*13,-40),point+Vector2(-42+i*13,45),Color(.4,.6,.65,.5),3)
			"G05":
				canvas.draw_arc(point,35,0,PI,16,red,5)
				for i in range(5):canvas.draw_line(point+Vector2(-25+i*12,5),point+Vector2(-25+i*12,17),ink,3)
			"G06":
				canvas.draw_line(point,endpoint,ink,5)
				for i in range(3):canvas.draw_line(endpoint+Vector2(0,-18+i*16),endpoint+Vector2(25,-22+i*16),red,4)
			"G07":
				canvas.draw_rect(Rect2(point-Vector2(23,35),Vector2(46,70)),ink,false,4)
				canvas.draw_line(point-Vector2(0,35),point+Vector2(0,35),ink,3)
			"G08":
				for i in range(8):
					var vector:=Vector2.from_angle(i*TAU/8)
					canvas.draw_line(point+vector*20,point+vector*65,red,4)
			"G09":
				canvas.draw_line(point-Vector2(0,140),point+Vector2(0,40),Color("a19c7b"),4)
				canvas.draw_polyline(PackedVector2Array([point+Vector2(-25,15),point+Vector2(0,45),point+Vector2(25,15)]),red,5)
			"G10":
				for i in range(3):canvas.draw_arc(point+Vector2(i*27-27,25),26,PI,TAU,12,Color("7fbbb6"),4)
				canvas.draw_dashed_line(point,endpoint,Color("7fbbb6"),4,10)
			"G12":
				canvas.draw_rect(Rect2(point-Vector2(35,24),Vector2(70,48)),ink,false,6)
				canvas.draw_line(point+Vector2(38,-35),point+Vector2(58,0),red,5)
			"G13":
				canvas.draw_rect(Rect2(point-Vector2(28,30),Vector2(56,60)),red,false,5)
				canvas.draw_line(point+Vector2(-80,8),point+Vector2(80,8),ink,5)
			"G14":
				canvas.draw_polyline(PackedVector2Array([point+Vector2(-35,-25),point+Vector2(35,25),point+Vector2(35,-25),point+Vector2(-35,25),point+Vector2(-35,-25)]),red,4)
			"G15":canvas.draw_colored_polygon(PackedVector2Array([point+Vector2(-38,-35),point+Vector2(38,-35),point+Vector2(25,40),point+Vector2(-25,40)]),Color(.55,.6,.55,.45))
			"G16":
				canvas.draw_rect(Rect2(endpoint-Vector2(20,45),Vector2(40,65)),Color("b49f76"),false,3)
				canvas.draw_line(endpoint+Vector2(-14,-30),endpoint+Vector2(14,0),red,4)
			"G17":canvas.draw_polyline(PackedVector2Array([point+Vector2(-60,-30),point+Vector2(-25,-30),point+Vector2(-25,-5),point+Vector2(10,-5),point+Vector2(10,30),point+Vector2(55,30)]),red,6)
			"G18":canvas.draw_line(point+Vector2(-45,-15),point+Vector2(45,-15),ink,4)
			"G19":canvas.draw_polyline(PackedVector2Array([point+Vector2(0,-45),point+Vector2(32,0),point+Vector2(0,45),point+Vector2(-32,0),point+Vector2(0,-45)]),Color("a3c9ce"),5)
			"G20":
				canvas.draw_line(point+Vector2(-75,0),point+Vector2(85,0),ink,5)
				canvas.draw_colored_polygon(PackedVector2Array([point+Vector2(85,-13),point+Vector2(115,0),point+Vector2(85,13)]),red)
			"G21":
				canvas.draw_arc(point,38,PI,TAU,20,Color("b6a278"),6)
				canvas.draw_line(point+Vector2(-38,0),point+Vector2(38,0),ink,5)
				canvas.draw_circle(point+Vector2(0,10),8,red)
			"G22":
				canvas.draw_arc(endpoint-Vector2(0,35),25,PI*.2,PI*1.6,24,Color("afbad2"),5)
				canvas.draw_line(endpoint-Vector2(15,10),endpoint+Vector2(15,10),ink,3)
			"G23","G28":
				for i in range(1 if unit.unit_id=="G23" else 3):
					var face:=point+Vector2(i*25-15,-20-i*8)
					canvas.draw_rect(Rect2(face-Vector2(12,19),Vector2(24,38)),Color("d0bea0"),false,3)
					canvas.draw_line(face+Vector2(-6,-5),face+Vector2(6,-5),red,3)
			"G24":
				canvas.draw_line(point+Vector2(-35,-40),point+Vector2(35,35),ink,6)
				canvas.draw_line(point+Vector2(35,-40),point+Vector2(-35,35),red,5)
			"G25":
				canvas.draw_rect(Rect2(endpoint-Vector2(24,35),Vector2(48,70)),ink,false,3)
				canvas.draw_line(endpoint+Vector2(-38,0),endpoint+Vector2(38,-12),red,8)
			"G26":canvas.draw_rect(Rect2(point-Vector2(38,50),Vector2(76,100)),Color(.7,.75,.65,.5),true)
			"G27":
				for i in range(4):canvas.draw_polyline(PackedVector2Array([point+Vector2(i*20-40,35),point+Vector2(i*20-28,5),point+Vector2(i*20-40,-30)]),Color("82a173"),5)
			"G29":
				canvas.draw_dashed_line(point+Vector2(-45,-30),point+Vector2(45,30),ink,5,12)
				canvas.draw_dashed_line(point+Vector2(-45,30),point+Vector2(45,-30),red,5,12)
			"G30":
				canvas.draw_polyline(PackedVector2Array([point+Vector2(-45,-30),point+Vector2(0,-60),point+Vector2(45,-30)]),red,5)
				canvas.draw_rect(Rect2(point-Vector2(35,30),Vector2(70,70)),ink,false,4)
			"G31":
				for i in range(4):canvas.draw_rect(Rect2(point+Vector2(-38+i*8,-45+i*14),Vector2(76-i*16,35)),ink,false,3)
			"G32":
				canvas.draw_rect(Rect2(point-Vector2(60,45),Vector2(120,90)),Color("b3ac8c"),false,5)
				for i in range(5):canvas.draw_line(point+Vector2(-42+i*21,-30),point+Vector2(-42+i*21,30),red,4)

func on_named(target:Node2D,source:Node2D=null)->void:
	if target.unit_id=="G31" and int(state(target).get("layers",0))>0:
		remove_layers(target,mini(int(state(target).layers),int(p(target,"collapse_layers"))))
		event("named_layers_collapsed",target,source.instance_id if source!=null else "");visual("name_layers_collapsed",target)

func recovery_blocked(target:Node2D,source:Node2D=null)->bool:
	for ghost in sim().targets+sim().humans:
		if not ghost.dead and ghost.roster.statuses.has("blank_field") and field_contains(ghost,target,source):return true
	return false
