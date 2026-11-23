extends RefCounted
## Optional per-night growth runtime. Disabled keeps the established P0-P6 simulation intact.
const Catalog = preload("res://src/data/GrowthCatalog.gd")
var session: Node
var enabled := false
var state: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _init(owner_session: Node) -> void:
	session = owner_session
	configure("",{})
	enabled = false
	state.enabled = false

func configure(seed: String, initial: Dictionary = {}) -> void:
	var full := initial.has("fusion_used") and initial.has("rng_state")
	state = {"enabled":true,"seed":seed,"rng_state":"0","inventory":{},"materials":[],"fusion_used":0,"fusion_limit":2,
		"ritual_flag":"","unlocks":{},"events":[],"seals":{},"fields":[],"borrow_jobs":[],"environments":[],"locked_paths":[],"serial":0,"time":0.0,"stored_items":{},"starting_loadouts":[]}
	rng.seed = seed.hash()
	if full:
		state = initial.duplicate(true)
		rng.state = int(state.rng_state)
		state.seals = {};state.fields = [];state.borrow_jobs = []
	else:
		for key in ["inventory","materials","ritual_flag","environments","locked_paths","starting_loadouts","defense_objective","water_mutation_trial"]:
			if initial.has(key):state[key] = initial[key].duplicate(true) if initial[key] is Array or initial[key] is Dictionary else initial[key]
	if not state.has("stored_items"):state.stored_items={}
	if not state.has("starting_loadouts"):state.starting_loadouts=[]
	enabled = true
	state.enabled = true
	var opposing: String = "duoming" if session!=null and session.mode=="shouxiang" else "shouxiang"
	state.npc_incense=float(Data.battle_rules.starting_incense[opposing])
	state.rng_state = str(rng.state)

func snapshot() -> Dictionary:
	state.enabled = enabled
	state.rng_state = str(rng.state)
	return _canonical(state)

func restore(value: Dictionary) -> Dictionary:
	if not valid_state(value): return _reject("P7_INVALID_STATE")
	state = value.duplicate(true)
	if not state.has("stored_items"):state.stored_items={}
	if not state.has("starting_loadouts"):state.starting_loadouts=[]
	enabled = bool(state.enabled)
	rng.state = int(state.rng_state)
	return _ok()

static func valid_state(value: Dictionary) -> bool:
	if not value.get("enabled") is bool or not value.get("seed") is String or not value.get("rng_state") is String or not str(value.rng_state).is_valid_int():return false
	for key in ["inventory","unlocks","seals"]:
		if not value.get(key) is Dictionary:return false
	for key in ["materials","events","fields","borrow_jobs","environments","locked_paths"]:
		if not value.get(key) is Array:return false
	for key in ["fusion_used","fusion_limit","serial","time"]:
		if not _number(value.get(key),0):return false
	for key in ["fusion_used","fusion_limit","serial"]:
		if float(value[key])!=int(value[key]):return false
	if not _number(value.get("npc_incense"),0):return false
	if value.fusion_used>value.fusion_limit or value.fusion_limit>2 or value.fusion_limit<1:return false
	for id in value.inventory:
		if id not in Catalog.EFFECT_IDS and id not in ["J01","J02"]:return false
		if not _integer(value.inventory[id],0):return false
	for id in value.materials:
		if not id is String or not Data.units.has(id):return false
	for id in value.unlocks:
		if not value.unlocks[id] is bool:return false
	for event in value.events:
		if not event is Dictionary or not _number(event.get("time"),0) or not event.get("kind") is String or not event.get("unit_id") is String or not event.get("detail") is String:return false
	for id in value.seals:
		var seal=value.seals[id]
		if not seal is Dictionary or not _number(seal.get("left"),0) or not seal.get("owner_id") is String or not _integer(seal.get("hits"),0):return false
	for field in value.fields:
		if not field is Dictionary or not field.get("kind") is String or not _point(field.get("point")) or not _integer(field.get("floor_id"),0) or not _number(field.get("left"),0):return false
		if field.has("end") and not _point(field.end):return false
		if field.has("radius") and not _number(field.radius,0):return false
		if field.has("damage_per_second") and (not _number(field.damage_per_second,0) or field.get("safe_side") not in ["","xianghuo","yegui"]): return false
	for job in value.borrow_jobs:
		if not job is Dictionary or not job.get("unit_id") is String or not _point(job.get("position")) or not _number(job.get("elapsed"),0) or not _number(job.get("duration"),.001) or not _integer(job.get("damage_revision"),0):return false
	for zone in value.environments:
		if not zone is Dictionary or not zone.get("id") is String or zone.get("kind") not in ["water","bridge"] or not _number(zone.get("from_body"),0) or not _number(zone.get("to_body"),0) or zone.from_body>zone.to_body or not _integer(zone.get("floor_id"),0):return false
	for lock in value.locked_paths:
		if lock is String:continue
		if not lock is Dictionary or not lock.get("id") is String or not lock.get("locked") is bool:return false
	if value.has("stored_items"):
		if not value.stored_items is Dictionary:return false
		for id in value.stored_items:
			if id not in Catalog.EFFECT_IDS or not value.stored_items[id] is Array:return false
			for item in value.stored_items[id]:
				if not item is Dictionary or not _integer(item.get("charges"),0) or not _number(item.get("ready_at"),0):return false
	if value.has("starting_loadouts"):
		if not value.starting_loadouts is Array:return false
		for loadout in value.starting_loadouts:
			if not loadout is Dictionary or not Data.combat_profiles.has(str(loadout.get("id",""))) or not loadout.get("items") is Array or not _integer(loadout.get("remaining"),0):return false
			for id in loadout.items:
				if id not in Catalog.EFFECT_IDS:return false
	return _json_safe(value)

static func valid_unit_growth(value: Dictionary) -> bool:
	if value.is_empty():return true
	if not value.get("slots") is Dictionary:return false
	var slots: Dictionary=value.slots
	if not slots.get("censer") is String or not slots.get("nameplate") is String or not slots.get("arts") is Array or slots.arts.size()!=2:return false
	if slots.censer!="" and (slots.censer not in Catalog.EFFECT_IDS or not str(slots.censer).begins_with("I")):return false
	if slots.nameplate!="" and (slots.nameplate not in Catalog.EFFECT_IDS or not str(slots.nameplate).begins_with("N")):return false
	var equipped:Array[String]=[]
	for id in slots.arts:
		if not id is String or (id!="" and (id not in Catalog.EFFECT_IDS or not id.begins_with("Y"))):return false
		if id!="" and id in equipped:return false
		if id!="":equipped.append(id)
	for key in ["cooldowns","charges","statuses","base","applied","counters","environment"]:
		if not value.get(key) is Dictionary:return false
	if not value.get("job_tags") is Array:return false
	for id in value.job_tags:
		if id not in ["J01","J02"]:return false
	for entry in value.cooldowns.values():
		if not _number(entry,0):return false
	for entry in value.charges.values():
		if not _integer(entry,0):return false
	for entry in value.statuses.values():
		if not entry is Dictionary or not _number(entry.get("left"),0):return false
	if value.statuses.has("construct"):
		var construct:Dictionary=value.statuses.construct
		if not construct.get("object_id") is String or not _number(construct.get("hp"),.001):return false
		if construct.has("complete_at") and not _number(construct.complete_at,0):return false
		# Completion calls WorldObstacle.set_occupied; a door reference is not a slot.
		var layout:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/reference_gate_court.json"))
		var found_slot:=false
		for slot in layout.obstacle_slots+layout.facilities:
			if slot.id==construct.object_id:found_slot=true;break
		if not found_slot:return false
	if value.statuses.has("ward"):
		var ward:Dictionary=value.statuses.ward
		if ward.has("multiplier") and not _number(ward.multiplier,.001):return false
	for key in ["base","applied"]:
		for stat in ["hp","attack","defense"]:
			if not _number(value[key].get(stat),0):return false
	for entry in value.counters.values():
		if not entry is bool and not _number(entry,0):return false
	for entry in value.environment.values():
		if not entry is bool:return false
	if not value.get("gray") is bool or not value.get("temporary") is bool or not _number(value.get("gray_left"),0) or not value.get("fusion_id") is String:return false
	if value.fusion_id!="" and value.fusion_id not in ["F01","F02","F03","F04","F05"]:return false
	if value.has("charge_job"):
		var job=value.charge_job
		if not job is Dictionary or not job.get("target_id") is String or not _number(job.get("elapsed"),0) or not _number(job.get("duration"),.001):return false
	return _json_safe(value)

static func _integer(value, minimum:float)->bool:
	return _number(value,minimum) and float(value)==int(value)
static func _point(value)->bool:
	return value is Array and value.size()==2 and _number(value[0],-INF) and _number(value[1],-INF)

static func _json_safe(value: Variant) -> bool:
	if value is Array:
		for item in value:
			if not _json_safe(item):return false
	elif value is Dictionary:
		for key in value:
			if (not key is String and not key is StringName) or not _json_safe(value[key]):return false
	elif typeof(value)==TYPE_FLOAT:
		return is_finite(value)
	elif typeof(value) not in [TYPE_NIL,TYPE_INT,TYPE_BOOL,TYPE_STRING,TYPE_STRING_NAME]:return false
	return true
static func _number(value, minimum:float) ->bool:
	return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(value)) and float(value)>=minimum

func sim() -> Node:
	return session.simulation if session!=null else null
func rules() -> Dictionary:
	return Data.growth_rules
func _unit(id:String) -> Node2D:
	if sim()==null:return null
	for unit in sim().humans+sim().targets:
		if not unit.dead and unit.instance_id==id:return unit
	return null
func seat_of(unit:Node2D)->String:
	return "shouxiang" if unit.side=="xianghuo" else "duoming"
func ensure(unit:Node2D)->void:
	if unit.growth.is_empty():
		unit.growth={"slots":{"censer":"","arts":["",""],"nameplate":""},"cooldowns":{},"charges":{},"statuses":{},
			"base":{"hp":unit.max_hp,"attack":unit.attack,"defense":unit.defense},"applied":{"hp":0.0,"attack":0.0,"defense":0.0},
			"counters":{},"environment":{},"job_tags":[],"gray":false,"temporary":false,"gray_left":0.0,"fusion_id":""}
func has(unit:Node2D,id:String)->bool:
	if not enabled or not is_instance_valid(unit) or unit.growth.is_empty():return false
	var slots:Dictionary=unit.growth.slots
	for item_id in [slots.censer,slots.nameplate]+slots.arts:
		if item_id!="" and rules().items.has(item_id) and str(rules().items[item_id].effect_id)==id and str(rules().items[item_id].status)=="active":return true
	return false
func params(id:String)->Dictionary:
	return rules().items[id].params
func eligible(unit:Node2D)->bool:
	return is_instance_valid(unit) and not unit.dead and unit.unit_id not in ["G01","G02","G03","G04","G05","G06","G07","G08"]
func execute(action:String,args:Dictionary)->Dictionary:
	if not enabled or sim()==null:return _reject("P7_DISABLED")
	var unit:Node2D=_unit(str(args.get("unit_id",args.get("first_id",""))))
	if unit==null:return _reject("P7_INVALID_UNIT")
	var seat:=seat_of(unit)
	var reason:String=session._available(seat)
	if not reason.is_empty():return _reject(reason)
	ensure(unit)
	if action in ["equip_item","unequip_item"] and session._command_origin=="player" and not Clock.paused:return _reject("P7_PAUSE_REQUIRED")
	var result:Dictionary
	match action:
		"equip_item":result=_equip(unit,str(args.get("item_id","")),int(args.get("slot_index",0)))
		"unequip_item":result=_unequip(unit,str(args.get("slot","")),int(args.get("slot_index",args.get("index",0))))
		"mutate_form":result=_mutate(unit,str(args.get("form_id","")))
		"fuse":result=_fuse(unit,_unit(str(args.get("second_id",""))),str(args.get("recipe_id","")),str(args.get("material_id","")))
		"stamp_job":result=_stamp(unit,str(args.get("job_id","")))
		"borrow_god":result=_borrow(unit)
		"use_key":result=_use_key(unit,str(args.get("door_id","")))
		_:return _reject("P7_INVALID_ACTION")
	if result.ok:
		state.rng_state=str(rng.state)
		session._emit_command(seat,action,args.duplicate(true))
	return result

func equip_price(old_id: String, new_id: String) -> float:
	var items: Dictionary = rules().items
	var removal := float(items[old_id].remove_cost) if not old_id.is_empty() else 0.0
	return removal + float(items[new_id].equip_cost)

func _equip(unit:Node2D,id:String,index:int)->Dictionary:
	if not eligible(unit):return _reject("P7_NO_SLOTS")
	if not rules().items.has(id):return _reject("P7_UNKNOWN_ITEM")
	var item:Dictionary=rules().items[id]
	if int(state.inventory.get(id,0))<=0:return _reject("P7_NO_ITEM")
	if item.slot=="art" and (index<0 or index>1):return _reject("P7_INVALID_SLOT")
	var slot:String=item.slot
	var old:String=unit.growth.slots.arts[index] if slot=="art" else unit.growth.slots[slot]
	if old==id or (slot=="art" and id in unit.growth.slots.arts):return _reject("P7_ALREADY_EQUIPPED")
	var cost:float=equip_price(old, id)
	if session.incense<cost:return _reject("P7_NO_INCENSE")
	session.incense-=cost
	if old!="":_return_item(unit,old)
	state.inventory[id]-=1
	if slot=="art":unit.growth.slots.arts[index]=id
	else:unit.growth.slots[slot]=id
	_take_item(unit,id)
	_refresh(unit)
	_event("equipped",unit,id,-cost)
	if sim().roster_engine()!=null: session.codex.resolve(id,"equipped")
	if id=="I19" and not _use_key(unit,"").ok:return {"ok":true,"reason":"P7_NO_LOCK"}
	return _ok()
func _unequip(unit:Node2D,slot:String,index:int)->Dictionary:
	if slot not in ["censer","art","nameplate"] or (slot=="art" and (index<0 or index>1)):return _reject("P7_INVALID_SLOT")
	var id:String=unit.growth.slots.arts[index] if slot=="art" else unit.growth.slots[slot]
	if id=="":return _reject("P7_EMPTY_SLOT")
	var cost:float=rules().items[id].remove_cost
	if session.incense<cost:return _reject("P7_NO_INCENSE")
	session.incense-=cost
	_return_item(unit,id)
	if slot=="art":unit.growth.slots.arts[index]=""
	else:unit.growth.slots[slot]=""
	_refresh(unit)
	_event("unequipped",unit,id,-cost)
	return _ok()
func _refresh(unit:Node2D)->void:
	var hp_bonus:=float(unit.growth.base.hp)*(float(params("N01").hp_multiplier)-1 if has(unit,"N01") else 0.0)
	var attack_bonus:=float(unit.growth.base.attack)*(float(params("N03").attack_multiplier)-1 if has(unit,"N03") else 0.0)
	unit.hp=clampf(unit.hp+hp_bonus-float(unit.growth.applied.hp),0,unit.max_hp+hp_bonus-float(unit.growth.applied.hp))
	unit.max_hp=float(unit.growth.base.hp)+hp_bonus
	unit.attack=float(unit.growth.base.attack)+attack_bonus
	unit.defense=float(unit.growth.base.defense)
	unit.growth.applied={"hp":hp_bonus,"attack":attack_bonus,"defense":0.0}
	unit.queue_redraw()
func refresh_base(unit:Node2D)->void:
	if not enabled:return
	ensure(unit)
	unit.growth.base={"hp":unit.max_hp-float(unit.growth.applied.hp),"attack":unit.attack-float(unit.growth.applied.attack),"defense":unit.defense-float(unit.growth.applied.defense)}
	_refresh(unit)

func mutation_available(id: String) -> bool:
	return rules().mutations[id].status == "active" or (id == "V05" and state.get("water_mutation_trial", false))

func mutation_reason(unit: Node2D, id: String, available_incense: float) -> String:
	if not is_instance_valid(unit) or unit.dead or unit.side != "yegui" or not rules().mutations.has(id):
		return "P7_INVALID_SOURCE"
	var recipe: Dictionary = rules().mutations[id]
	if not mutation_available(id):
		return "P7_LOCKED_RECIPE"
	if unit.unit_id not in recipe.sources or unit.mutation_count >= 2:
		return "P7_INVALID_SOURCE"
	if id == "V05" and not in_environment(unit, "water"):
		return "P7_NEEDS_WATER"
	if id == "V02" and unit.position.x > Rules.body_to_px(float(sim().tide.config.climb.from_x)):
		return "P4_MUTATION_PAST_CLIMB"
	if available_incense < float(recipe.cost):
		return "P7_NO_INCENSE"
	return ""

func _mutate(unit: Node2D, id: String) -> Dictionary:
	var reason := mutation_reason(unit, id, session.incense)
	if not reason.is_empty():
		return _reject(reason)
	var recipe: Dictionary = rules().mutations[id]
	session.incense-=float(recipe.cost)
	_transform(unit,str(recipe.result_id),"")
	_event("mutation",unit,id,-float(recipe.cost))
	return _ok()
func _transform(unit:Node2D,id:String,fusion:String)->void:
	var ratio:float=unit.hp/unit.max_hp
	var old_side:String=unit.side
	var old_row:Dictionary=Data.get_unit(unit.unit_id)
	var bonus:Dictionary={"hp":float(unit.growth.base.hp)-float(old_row["生命"]),"attack":float(unit.growth.base.attack)-float(old_row["攻击"]),"defense":float(unit.growth.base.defense)-float(old_row["防御"])}
	var stored:Dictionary=unit.growth.duplicate(true)
	var count:int=unit.mutation_count+1
	unit.configure(id,unit.instance_id,sim())
	if old_side=="xianghuo":unit.side=old_side;unit.role="guard"
	unit.growth=stored
	unit.mutation_count=count
	unit.growth.fusion_id=fusion
	unit.growth.base={"hp":unit.max_hp+float(bonus.hp),"attack":unit.attack+float(bonus.attack),"defense":unit.defense+float(bonus.defense)}
	unit.growth.applied={"hp":0.0,"attack":0.0,"defense":0.0}
	_refresh(unit)
	unit.hp=unit.max_hp*ratio
	unit.sync_meta()
func _fuse(first:Node2D,second:Node2D,id:String,material:String)->Dictionary:
	if not rules().fusions.has(id):return _reject("P7_BAD_FUSION")
	var recipe:Dictionary=rules().fusions[id]
	if recipe.status!="active":return _reject("P7_LOCKED_RECIPE")
	if state.fusion_used>=state.fusion_limit:return _reject("P7_FUSION_LIMIT")
	if first.mutation_count>=2:return _reject("P7_MUTATION_LIMIT")
	if id=="F03":
		if second!=null or first.unit_id!="G11" or material!="H06" or material not in state.materials:return _reject("P7_BAD_FUSION")
	elif id=="F05":
		if not bool(first.growth.get("gray",false)) or not bool(first.growth.get("temporary",false)) or first.growth.get("borrowed_by","")!="H19" or second==null or second.unit_id!="H22":return _reject("P7_BAD_FUSION")
	else:
		if second==null or second==first or second.side!=first.side or second.mutation_count>=2:return _reject("P7_BAD_FUSION")
		var ids:Array=[first.unit_id,second.unit_id]
		if recipe.sources[0] not in ids or recipe.sources[1] not in ids:return _reject("P7_BAD_FUSION")
	if session.incense<float(recipe.cost):return _reject("P7_NO_INCENSE")
	session.incense-=float(recipe.cost)
	state.fusion_used+=1
	if id=="F03":state.materials.erase(material)
	if id=="F05":
		first.growth.temporary=false;first.growth.gray_left=0.0;first.mutation_count+=1;first.growth.fusion_id=id
	else:
		if second!=null:first.mutation_count=maxi(first.mutation_count,second.mutation_count)
		_transform(first,str(recipe.result_id),id)
		first.display_name=str(recipe.result_name)
		if second!=null:
			ensure(second);second.growth.departure_reason="fusion";second.dead=true;second.corpse_left=Rules.CORPSE_SECONDS
	if id=="F03":first.growth.statuses.double_lamp={"left":float(rules().skills.double_lamp_duration)}
	state.unlocks[id]=true
	if sim().roster_engine()!=null: session.codex.resolve(first.unit_id,"fusion")
	_event("fusion",first,id,-float(recipe.cost))
	sim().vfx.fusion(first.position, second.position if second != null else first.position, first.height_px, id)
	return _ok()
func _stamp(unit:Node2D,id:String)->Dictionary:
	if unit.side!="xianghuo" or not rules().jobs.has(id) or rules().jobs[id].source_id!=unit.unit_id:return _reject("P7_INVALID_JOB")
	if id in unit.growth.job_tags:return _reject("P7_ALREADY_STAMPED")
	if int(state.inventory.get(id,0))<=0:return _reject("P7_NO_ITEM")
	state.inventory[id]-=1;unit.growth.job_tags.append(id)
	_event("job_stamp",unit,id)
	return _ok()
func _borrow(unit:Node2D)->Dictionary:
	if unit.side!="xianghuo" or not _ritual_room(unit):return _reject("P7_BAD_RITUAL_LOCATION")
	for job in state.borrow_jobs:
		if job.unit_id==unit.instance_id:return _reject("P7_BORROW_ACTIVE")
	var data:Dictionary=rules().borrow
	var cost:=ritual_cost(unit,float(session.ritual.param("borrow_incense",data.cost)))
	if session.incense<cost or session.names<float(data.names_cost):return _reject("P7_NO_INCENSE")
	session.incense-=cost;session.names-=float(data.names_cost)
	state.borrow_jobs.append({"unit_id":unit.instance_id,"elapsed":0.0,"duration":float(data.duration),"position":[unit.position.x,unit.position.y],"damage_revision":unit.damage_revision})
	_event("borrow_start",unit,"",-cost,-float(data.names_cost))
	return _ok()
func _ritual_room(unit:Node2D)->bool:
	return sim().world.inside_base(unit.position) and not sim().world.is_open_court(unit.position) and sim().world.room_at(unit.position,unit.floor_id) in ["hall","register","incense"]
func _use_key(unit:Node2D,door_id:String)->Dictionary:
	if not has(unit,"I19") or int(unit.growth.charges.get("I19",0))>0:return _reject("P7_NO_KEY")
	for entry in state.locked_paths:
		var id:String=str(entry) if entry is String else str(entry.get("id",""))
		var locked:bool=true if entry is String else bool(entry.get("locked",true))
		if not locked or (door_id!="" and door_id!=id):continue
		var door:Node=sim().world.get_node_or_null(id)
		if door==null or door not in sim().world.doors:continue
		door.set_open(true)
		unit.growth.charges.I19=1
		if entry is Dictionary:entry.locked=false
		else:state.locked_paths[state.locked_paths.find(entry)]={"id":id,"locked":false}
		_event("key_opened",unit,id)
		return _ok()
	_event("no_lock",unit,"")
	return _reject("P7_NO_LOCK")
func options(unit:Node2D)->Dictionary:
	var inventory:Array[Dictionary]=[]
	for id in state.inventory:
		if int(state.inventory[id])>0 and rules().items.has(id):
			var item:Dictionary=rules().items[id].duplicate(true);item.qty=state.inventory[id];inventory.append(item)
	if is_instance_valid(unit):ensure(unit)
	return {"eligible":eligible(unit),"reason":"" if eligible(unit) else "P7_NO_SLOTS","slots":unit.growth.slots.duplicate(true) if is_instance_valid(unit) else {},"inventory":inventory,"mutations":rules().mutations.values(),"fusions":rules().fusions.values(),"jobs":rules().jobs.values(),"borrow":rules().borrow}
func _event(kind:String,unit:Node2D,detail:String,incense_delta:=0.0,names_delta:=0.0)->void:
	state.events.append({"time":float(state.time),"kind":kind,"unit_id":unit.instance_id if is_instance_valid(unit) else "","detail":detail,"incense_delta":incense_delta,"names_delta":names_delta})
	if session!=null:session._record("growth_"+kind,incense_delta,detail,names_delta)
func _ok()->Dictionary:return {"ok":true,"reason":"P7_COMMAND_OK"}
func _reject(reason:String)->Dictionary:return {"ok":false,"reason":reason}

func advance(delta:float)->void:
	if not enabled or sim()==null or delta<=0:return
	state.time+=delta
	if not session.dual_enabled:state.npc_incense=minf(float(session.rules.incense_cap),float(state.npc_incense)+float(session.rules.incense_regen)*delta)
	_recapture_contacts()
	for unit in (sim().humans+sim().targets).duplicate():
		if unit.dead:continue
		ensure(unit)
		for key in unit.growth.cooldowns.keys():unit.growth.cooldowns[key]=maxf(0,float(unit.growth.cooldowns[key])-skill_delta(unit,delta))
		for key in unit.growth.statuses.keys():
			unit.growth.statuses[key].left=float(unit.growth.statuses[key].get("left",0))-delta
			if unit.growth.statuses[key].left<=0:
				if key=="construct":unit.growth.statuses[key].left=0.0
				else:unit.growth.statuses.erase(key)
		if bool(unit.growth.gray) and bool(unit.growth.temporary):
			unit.growth.gray_left=maxf(0,float(unit.growth.gray_left)-delta)
			if unit.growth.gray_left<=0:_ungray(unit)
		if has(unit,"I02") and session.names<=0 and _uses(unit,"I02")==0:
			_spent(unit,"I02");session.names+=float(params("I02").names)*session.rekindle_multiplier();_event("rekindle",unit,"I02");_visual("rekindle",unit.position,unit.floor_id,1.5)
		if has(unit,"I15") and _ready(unit,"I15"):
			var enemy=_nearest(unit,Rules.body_to_px(float(params("I15").radius_body)),false)
			if enemy!=null:_displace(enemy,unit.position.x,Rules.body_to_px(float(params("I15").pull_body)));_event("attraction",unit,enemy.instance_id);_visual("pull",enemy.position,enemy.floor_id,.7)
			_cd(unit,"I15",float(params("I15").cooldown))
		if has(unit,"I04"):apply_light(unit,float(params("I04").radius_body),.2)
		if unit.unit_id=="G04" or str(unit.growth.fusion_id)=="F01":
			unit.growth.counters.invisible=(str(unit.growth.fusion_id)!="F01" or unit.floor_id>0) and not unit.growth.statuses.has("revealed")
		if unit.unit_id=="G11" and sim().roster_engine()==null:
			apply_light(unit,float(rules().skills.double_lamp_radius_body) if unit.growth.statuses.has("double_lamp") else float(rules().skills.light_radius_body),.2)
		unit.modulate.a=.2 if is_hidden(unit) else 1.0
		if unit.growth.has("charge_job"):
			var job:Dictionary=unit.growth.charge_job
			job.elapsed+=delta
			if float(job.elapsed)>=float(job.duration):
				var target:Node2D=sim().world.get_node_or_null(str(job.target_id).trim_prefix("world:")) if str(job.target_id).begins_with("world:") else _unit(str(job.target_id))
				if target!=null and target.position.distance_to(unit.position)<=Rules.body_to_px(float(unit.profile.range_body)+.5):
					sim().deal_damage(unit,target,"charge" if target.is_in_group("units") else "charge_structure",unit.attack*float(rules().skills.charge_multiplier));_event("charge_hit",unit,str(target.name))
				unit.growth.erase("charge_job")
		_auto_skill(unit,delta)
	for door_id in state.seals.keys():
		state.seals[door_id].left-=delta
		if state.seals[door_id].left<=0:_break_seal(str(door_id),null)
	for index in range(state.borrow_jobs.size()-1,-1,-1):
		var job:Dictionary=state.borrow_jobs[index]
		var caster=_unit(str(job.unit_id))
		if caster==null or caster.damage_revision!=int(job.damage_revision) or caster.position.distance_to(Vector2(job.position[0],job.position[1]))>1 or not _ritual_room(caster):
			state.borrow_jobs.remove_at(index);if caster!=null:_event("borrow_interrupted",caster,"")
			continue
		job.elapsed+=delta
		if job.elapsed>=job.duration:
			state.borrow_jobs.remove_at(index);_finish_borrow(caster)
	for index in range(state.fields.size()-1,-1,-1):
		var field:Dictionary=state.fields[index]
		var active_delta := minf(delta,float(field.left))
		field.left-=delta
		if field.kind=="fire":
			var fire := params("I14")
			var radius := Rules.body_to_px(float(field.get("radius",fire.radius_body)))
			var owner := _unit(str(field.get("owner_id","")))
			for target in (sim().humans+sim().targets).duplicate():
				if not target.dead and target.floor_id==int(field.floor_id) and target.position.distance_to(Vector2(field.point[0],field.point[1]))<radius:
					if target.side == field.get("safe_side",""): continue
					if not field.has("damage_per_second") and state.ritual_flag in ["jizao","祭灶"] and owner!=null and target.side==owner.side: continue
					var amount := float(field.get("damage_per_second",fire.damage_per_second)) * (active_delta if field.has("damage_per_second") else delta)
					target.receive_damage(amount,owner,"fire_field")
		if field.left<=0:state.fields.remove_at(index)
	state.rng_state=str(rng.state)

func _auto_skill(unit:Node2D,_delta:float)->void:
	# An already-paid light field keeps its full duration even while its caster reads.
	if unit.unit_id in ["H06","H21","H27"] and unit.growth.statuses.has("light_field"):
		apply_light(unit,float(rules().skills.light_radius_body)+(3 if unit.unit_id=="H27" else 0),.2)
	if unit.growth.statuses.has("construct"):
		var job:Dictionary=unit.growth.statuses.construct
		if float(job.left)<=float(job.get("complete_at",.1)):
			unit.growth.statuses.erase("construct")
			var object=sim().world.get_node_or_null(str(job.object_id))
			if object!=null:
				object.max_durability=float(job.hp);object.set_durability(float(job.hp));object.set_occupied(true)
				_event("barricade",unit,str(object.name));_visual("barricade",object.position,object.floor_id,1)
	for job in state.borrow_jobs:
		if job.unit_id==unit.instance_id:return
	if unit.side=="xianghuo" and unit.brain.channel.active:return
	if unit.growth.statuses.has("charm"):
		var ally=_nearest(unit,Rules.body_to_px(float(unit.profile.range_body)),true)
		if ally!=null and unit.attack_left<=0:sim().deal_damage(unit,ally,"charmed_attack");unit.attack_left=Rules.ATTACK_INTERVAL
		return
	if str(unit.growth.fusion_id)=="F02":
		var barrier=sim().next_barrier(unit.position.x,unit.floor_id)
		if barrier!=null and _ready(unit,"charge") and barrier.position.x-unit.position.x<Rules.body_to_px(4):charge(unit,barrier)
	if sim().roster_engine()!=null:return
	if unit.growth.statuses.has("stun") or unit.growth.statuses.has("root"):return
	if unit.growth.statuses.has("misname") and _ready(unit,"misname_delay"):
		unit.growth.statuses.erase("misname");_cd(unit,"misname_delay",float(rules().skills.status_skill_cooldown));_cd(unit,"status",float(rules().skills.status_skill_cooldown));_cd(unit,"charge",float(rules().skills.charge_cooldown));_event("skill_misfired",unit,"");return
	match unit.unit_id:
		"H17":
			if _ready(unit,"seal"):
				for door in sim().world.doors:
					if not door.destroyed and door.floor_id==unit.floor_id and door.position.distance_to(unit.position)<Rules.body_to_px(3) and door.durability<door.max_durability and _door_threatened(unit,door) and _pay(unit,float(unit.skill_cost)):
						seal_door(unit,door);_cd(unit,"seal",float(rules().skills.seal_cooldown));break
		"H11","H25":
			if _ready(unit,"barricade"):place_barricade(unit)
		"H02":
			if _ready(unit,"healing"):
				for ally in sim().humans:
					if not ally.dead and ally.hp<ally.max_hp and ally.position.distance_to(unit.position)<=Rules.body_to_px(3) and _pay(unit,float(unit.skill_cost)):
						heal(ally,float(rules().skills.heal_amount));_cd(unit,"healing",float(rules().skills.status_skill_cooldown));break
		"H06","H21","H27":
			var radius:=float(rules().skills.light_radius_body)+(3 if unit.unit_id=="H27" else 0)
			if _ready(unit,"light") and _light_needed(unit,radius) and _pay(unit,float(unit.skill_cost)):
				unit.growth.statuses.light_field={"left":float(rules().skills.light_duration)};_cd(unit,"light",float(rules().skills.light_cooldown))
				apply_light(unit,radius,.2)
		"H07":
			if _ready(unit,"drum") and _drum_needed(unit) and _pay(unit,float(unit.skill_cost)):drum(unit);_cd(unit,"drum",float(rules().skills.status_skill_cooldown))
		"H03","H32":
			if _ready(unit,"ward"):
				for ally in sim().humans:
					ensure(ally)
					var key="named_ward" if unit.unit_id=="H03" else "face_ward"
					if ally.position.distance_to(unit.position)<Rules.body_to_px(3) and int(ally.growth.counters.get(key,0))==0 and _pay(unit,float(unit.skill_cost)):
						ally.growth.counters[key]=1;_cd(unit,"ward",float(rules().skills.status_skill_cooldown));_visual("ward",ally.position,ally.floor_id,1);break
		"H24":
			var target=_nearest(unit,Rules.body_to_px(3),false)
			if target!=null and _ready(unit,"pin") and _pay(unit,float(unit.skill_cost)):
				apply_status(target,"stun",float(rules().skills.pin_duration)*(float(rules().skills.large_stun_multiplier) if target.height_px>Rules.UNIT_HEIGHT_PX else 1.0),unit);_cd(unit,"pin",float(rules().skills.status_skill_cooldown))
		"H19":
			var target=_nearest(unit,Rules.body_to_px(2.5),false)
			if target!=null and sim().world.inside_base(target.position) and _ready(unit,"borrow_ghost") and _pay(unit,float(unit.skill_cost)):
				if not light_without_borrowing(unit,target):
					_gray(target,unit,float(rules().borrow.gray_duration))
					_event("borrow_ghost",unit,target.instance_id)
				_cd(unit,"borrow_ghost",float(rules().skills.status_skill_cooldown))
		"H22":
			var target=_nearest(unit,Rules.body_to_px(float(rules().skills.status_radius_body)),false)
			if target!=null and target.unit_id=="G30" and _ready(unit,"dispel") and _pay(unit,float(unit.skill_cost)):
				target.receive_damage(float(rules().skills.dispel_false_god_damage),unit,"dispel");apply_status(target,"stun",float(rules().skills.dispel_stun),unit);_cd(unit,"dispel",float(rules().skills.status_skill_cooldown));_event("false_god_unmasked",unit,target.instance_id)
		"H23":
			var target=_nearest(unit,Rules.body_to_px(float(rules().skills.status_radius_body)),false)
			if target!=null and _ready(unit,"misname") and _pay(unit,float(unit.skill_cost)):
				apply_status(target,"misname",float(rules().skills.misname_duration),unit);_cd(unit,"misname",float(rules().skills.status_skill_cooldown));_event("misname",unit,target.instance_id)
		"G10":
			var target=_nearest(unit,Rules.body_to_px(2.5),false)
			if target!=null and in_environment(unit,"water") and _ready(unit,"drag"):
				apply_status(target,"drag",float(rules().skills.drag_duration),unit);_displace(target,unit.position.x,Rules.body_to_px(float(rules().skills.drag_body)));target.receive_damage(float(rules().skills.drag_damage),unit,"water");_cd(unit,"drag",float(rules().skills.status_skill_cooldown))
		"G17":
			var target=_nearest(unit,Rules.body_to_px(3),false)
			if target!=null and on_beam(target) and _ready(unit,"fall"):
				knock_from_beam(target,unit);_cd(unit,"fall",float(rules().skills.status_skill_cooldown))
		"G14","G25","G28","G29":
			var target=_nearest(unit,Rules.body_to_px(2.5),false)
			if target!=null and _ready(unit,"status"):
				var kind={"G14":"charm","G25":"name_erase","G28":"face_theft","G29":"charm"}[unit.unit_id]
				apply_status(target,kind,3,unit);_cd(unit,"status",float(rules().skills.status_skill_cooldown))
		"G13","G20":
			var barrier=sim().next_barrier(unit.position.x,unit.floor_id)
			if barrier!=null and _ready(unit,"charge") and barrier.position.x-unit.position.x<Rules.body_to_px(4):
				charge(unit,barrier)


func ritual_cost(unit:Node2D,base:float)->float:return maxf(0,base-float(params("N05").cost_reduction)) if enabled and has(unit,"N05") else base
func ritual_duration(unit:Node2D,target:Node2D,base:float)->float:
	if not enabled:return base
	if has(unit,"I11") and in_environment(target,"water"):base*=float(params("I11").ritual_multiplier)
	if unit.unit_id=="H21" and in_environment(target,"water"):base*=float(rules().skills.river_ritual_multiplier)
	if has(unit,"Y13") and session.names<=0:base*=float(params("Y13").multiplier)
	return base
func ritual_completed(caster:Node2D,target:Node2D,purify_only := false)->bool:
	if not enabled:return false
	ensure(caster);ensure(target)
	if has(caster,"Y01"):
		for enemy in sim().targets.duplicate():
			if enemy!=target and not enemy.dead and enemy.position.distance_to(target.position)<=Rules.body_to_px(float(params("Y01").radius_body)):
				var damage:float=float(params("Y01").damage)
				if enemy.unit_id not in ["G01","G02","G03","G04","G05","G06","G07","G08"]:damage=minf(damage,maxf(0,enemy.hp-1))
				enemy.receive_damage(damage,caster,"incense")
		_visual("incense_burst",target.position,target.floor_id,1.2)
	if has(caster,"Y03"):
		for ally in (sim().humans if caster.side=="xianghuo" else sim().targets):
			ensure(ally);ally.growth.statuses.procession={"left":float(params("Y03").duration)}
	_recover_kill(caster)
	var chance:float=float(rules().borrow.vulnerable_recruit_chance) if target.unit_id in ["G02","G08","G24"] else float(rules().borrow.recruit_chance)
	var recruited:=rng.randf()<chance and not purify_only
	state.rng_state=str(rng.state)
	if recruited:_gray(target,caster,float(rules().borrow.gray_duration));_event("recruited",caster,target.instance_id)
	_visual("purified",target.position,target.floor_id,1.5)
	_event("ritual_release",caster,target.instance_id)
	return recruited
func repair_cost(unit:Node2D,base:float)->float:
	if enabled and unit.unit_id=="H25":base*=float(rules().skills.craft_repair_multiplier)
	if enabled and "J01" in unit.growth.get("job_tags",[]):base*=float(rules().jobs.J01.repair_cost_multiplier)
	if enabled and has(unit,"N05"):base=maxf(0,base-float(params("N05").cost_reduction))
	return base
func repair_duration(unit:Node2D,base:float)->float:return base*float(params("Y09").multiplier) if enabled and has(unit,"Y09") else base
func repair_multiplier(unit:Node2D)->float:return float(params("I10").repair_multiplier) if enabled and has(unit,"I10") else 1.0
func damage_multiplier(attacker:Node2D,victim:Node2D,kind:String)->float:
	if not enabled or not is_instance_valid(attacker):return 1.0
	ensure(attacker)
	var value:=1.0
	if not victim.is_in_group("units"):
		if has(attacker,"I10"):value*=float(params("I10").structure_multiplier)
	else:
		ensure(victim)
		if has(attacker,"I18") and victim.side=="yegui":value*=float(params("I18").damage_multiplier)
		if has(attacker,"Y10") and victim.growth.statuses.has("revealed"):value*=float(params("Y10").multiplier)
		if has(attacker,"N09") and is_hidden(victim):value*=float(params("N09").multiplier);apply_status(victim,"revealed",float(params("N09").duration),attacker)
		if has(attacker,"N12") and "无册" in victim.tags:value*=float(params("N12").attack_multiplier)
	if has(attacker,"Y02"):
		for door in sim().world.doors:
			if door.floor_id==attacker.floor_id and door.position.distance_to(attacker.position)<Rules.body_to_px(3) and door.durability/door.max_durability<float(params("Y02").threshold):value*=float(params("Y02").multiplier);break
	if has(attacker,"Y04") and on_beam(attacker):value*=float(params("Y04").multiplier)
	if has(attacker,"I06") and in_environment(attacker,"bridge"):value*=float(params("I06").bridge_multiplier)
	if in_environment(attacker,"water") and not has(attacker,"N10"):value*=float(rules().environment.water_stat_multiplier)
	if kind in ["charge","charge_structure"] and has(attacker,"I16"):value*=float(params("I16").charge_multiplier)
	if kind=="fire" and has(attacker,"I14") and state.ritual_flag in ["jizao","祭灶"]:value*=float(params("I14").fire_multiplier)
	return value
func defense_for(unit:Node2D)->float:
	var value:float=unit.defense
	if not enabled:return value
	ensure(unit)
	if has(unit,"I06") and in_environment(unit,"bridge"):value*=float(params("I06").bridge_multiplier)
	if has(unit,"N11") and on_beam(unit):value*=float(params("N11").defense_multiplier)
	if in_environment(unit,"water") and not has(unit,"N10"):value*=float(rules().environment.water_stat_multiplier)
	if unit.growth.statuses.has("ward"):value*=float(unit.growth.statuses.ward.get("multiplier",1.2))
	return value
func before_receive(unit:Node2D,amount:float,attacker:Node2D=null,kind:String="physical")->float:
	if not enabled:return amount
	if kind in session.ritual.param("fire_kinds",[]): return 0.0
	ensure(unit)
	if has(unit,"Y11") and is_instance_valid(attacker) and "破门" in attacker.tags:amount*=float(params("Y11").multiplier)
	if has(unit,"N07") and kind in ["occult","reflection"]:amount*=float(params("N07").multiplier)
	if has(unit,"N12") and is_instance_valid(attacker) and "无册" in attacker.tags:amount*=float(params("N12").incoming_multiplier)
	if has(unit,"I06") and kind=="water":amount*=float(params("I06").water_multiplier)
	if has(unit,"I09") and _ready(unit,"I09") and _uses(unit,"I09")<int(params("I09").limit):
		amount*=1-float(params("I09").damage_conversion);_credit(unit,float(params("I09").incense));_cd(unit,"I09",float(params("I09").cooldown));_spent(unit,"I09");_event("damage_to_incense",unit,"I09")
	if has(unit,"I12") and kind=="occult" and is_instance_valid(attacker):
		attacker.receive_damage(amount*float(params("I12").reflect),unit,"reflection")
		if rng.randf()<float(params("I12").reveal_chance):apply_status(attacker,"revealed",float(params("I12").reveal_duration),unit)
		_event("reflection",unit,attacker.instance_id);_visual("mirror",unit.position,unit.floor_id,1)
	if amount >= unit.hp and unit.side == "xianghuo" and has(unit,"Y11") and has(unit,"I08") and _uses(unit,"I08") == 0:
		if state.get("defense_objective","") == "hold_register" and is_instance_valid(attacker) and attacker.side == "yegui" and "破门" in attacker.tags and sim().world.room_at(unit.position,unit.floor_id) == "register":
			_spent(unit,"I08")
			_event("paper_brace",unit,attacker.instance_id)
			_visual("paper_brace",unit.position,unit.floor_id,0.65)
			return 0.0
	if amount>=unit.hp and has(unit,"I13") and _uses(unit,"I13")==0:
		var candidates:Array=sim().humans if unit.side=="xianghuo" else sim().targets
		for substitute in candidates:
			if substitute!=unit and not substitute.dead and (substitute.unit_id.begins_with("T") or substitute.unit_id=="G01") and substitute.position.distance_to(unit.position)<=Rules.body_to_px(float(params("I13").radius_body)):
				_spent(unit,"I13");substitute.receive_damage(amount,attacker,"substitution");_event("substitute_death",unit,substitute.instance_id);_visual("thread",unit.position,unit.floor_id,1);return 0
	return amount
func channel_damage(unit:Node2D)->bool:
	if has(unit,"I17") and unit.brain.channel.active:
		unit.brain.channel.elapsed*=1-float(params("I17").progress_loss)
		unit.brain.channel.damage_revision=unit.damage_revision
		_event("channel_guard",unit,"I17");_visual("needle",unit.position,unit.floor_id,.8)
		return true
	return false
func after_damage(attacker:Node2D,victim:Node2D,_amount:float,kind:String,before:float)->void:
	if not enabled or not is_instance_valid(attacker):return
	if victim.is_in_group("units"):
		if victim.dead and before>0:
			_recover_kill(attacker)
			if victim.unit_id=="G08" and sim().roster_engine()==null:
				for other in (sim().humans+sim().targets).duplicate():
					if not other.dead and other!=victim and other.position.distance_to(victim.position)<=Rules.body_to_px(float(rules().skills.explosion_radius_body)):
						other.receive_damage(float(rules().skills.explosion_damage),victim,"incense_explosion")
				_visual("incense_burst",victim.position,victim.floor_id,1)
		if has(attacker,"Y15") and kind=="melee" and victim.height_px<=Rules.UNIT_HEIGHT_PX and not victim.dead:_displace(victim,attacker.position.x,-Rules.body_to_px(float(params("Y15").push_body)));_event("short_push",attacker,victim.instance_id)
		if kind == "fire" and session.ritual.has_flag("ground_fire"):
			ignite_ritual_fire(attacker,victim.position,victim.floor_id,attacker.unit_id)
		elif kind=="fire" and has(attacker,"I14") and state.ritual_flag not in ["jizao","祭灶"] and rng.randf()<float(params("I14").chance):
			state.fields.append({"kind":"fire","point":[victim.position.x,victim.position.y],"floor_id":victim.floor_id,"left":float(params("I14").duration),"owner_id":attacker.instance_id})
func before_structure_damage(attacker:Node2D,door:Node2D,amount:float)->float:
	if not enabled:return amount
	if state.seals.has(str(door.name)):
		var seal:Dictionary=state.seals[str(door.name)]
		seal.hits=int(seal.get("hits",0))+1
		if is_instance_valid(attacker):
			var reflected := float(rules().skills.seal_reflect_damage) * float(session.ritual.param("seal_multiplier",1.0))
			attacker.receive_damage(reflected,_unit(str(seal.owner_id)),"reflection")
		_break_seal(str(door.name),attacker)
		_event("seal_absorbed",_unit(str(seal.owner_id)),str(door.name));return 0
	for human in sim().humans:
		if human.dead or human.floor_id!=door.floor_id:continue
		if has(human,"N04") and human.position.distance_to(door.position)<=Rules.body_to_px(float(params("N04").radius_body)):amount*=float(params("N04").door_damage_multiplier)
		if sim().roster_engine()==null and human.unit_id=="H09" and door.durability>0 and amount>=door.durability and human.position.distance_to(door.position)<=Rules.body_to_px(2) and _ready(human,"hold_gate") and _pay(human,float(rules().skills.guard_last_hit_cost)):
			_cd(human,"hold_gate",float(rules().skills.guard_last_hit_cooldown));human.receive_damage(amount,attacker,"hold_gate");_event("last_gate_hit",human,str(door.name));_visual("hold_gate",door.position,door.floor_id,1.5);return 0
	return amount
func speed_multiplier(unit:Node2D)->float:
	if not enabled:return 1.0
	ensure(unit)
	var value:=float(params("N02").speed_multiplier) if has(unit,"N02") else 1.0
	if in_environment(unit,"water") and not has(unit,"Y05"):value*=float(rules().environment.water_speed_multiplier)
	if unit.growth.statuses.has("landing_weak") and not has(unit,"Y05"):value*=float(rules().environment.landing_multiplier)
	if unit.growth.statuses.has("procession"):value*=float(params("Y03").multiplier)
	if unit.growth.statuses.has("charge"):value*=float(rules().skills.charge_speed_multiplier)
	if unit.growth.statuses.has("water_slow") and not has(unit,"Y05"):value*=float(rules().skills.river_slow_multiplier)
	return value
func stair_factor(unit:Node2D,base:float)->float:return 1.0 if enabled and has(unit,"Y12") else base
func can_act(unit:Node2D)->bool:
	if not enabled:return true
	ensure(unit)
	for job in state.borrow_jobs:
		if job.unit_id==unit.instance_id:return false
	return not (unit.growth.statuses.has("stun") or unit.growth.statuses.has("cry_stun") or unit.growth.statuses.has("root") or unit.growth.statuses.has("fear") or unit.growth.statuses.has("construct") or unit.growth.statuses.has("charm") or unit.growth.statuses.has("drag"))
func is_hidden(unit:Node2D)->bool:
	return enabled and not unit.growth.is_empty() and bool(unit.growth.counters.get("invisible",false)) and not unit.growth.statuses.has("revealed")
func skill_delta(unit:Node2D,delta:float)->float:return delta/maxf(1,session.simulation_speed) if has(unit,"Y08") else delta
func in_environment(unit:Node2D,kind:String)->bool:
	if unit.growth.get("environment",{}).get(kind,false):return true
	for zone in state.environments:
		if zone.kind==kind and int(zone.floor_id)==unit.floor_id and unit.position.x>=Rules.body_to_px(float(zone.from_body)) and unit.position.x<=Rules.body_to_px(float(zone.to_body)):return true
	return sim() != null and sim().world.chunk_area_at(unit.position,unit.floor_id).get("kind","") == kind
func on_beam(unit:Node2D)->bool:return (unit.floor_id>=2 and sim().world.is_upper_floor(unit.floor_id)) or bool(unit.growth.get("environment",{}).get("beam",false))
func apply_status(unit:Node2D,kind:String,duration:float,source:Node2D=null)->Dictionary:
	if not enabled or not is_instance_valid(unit) or unit.dead:return _reject("P7_INVALID_UNIT")
	ensure(unit)
	if kind in ["fear","face_theft"]:
		if int(unit.growth.counters.get("face_ward",0))>0:unit.growth.counters.face_ward-=1;_event("face_ward",unit,kind);return _ok()
		if has(unit,"I01") and _uses(unit,"I01")==0:_spent(unit,"I01");_event("mask_blocked",unit,kind);_visual("mask",unit.position,unit.floor_id,1);return _ok()
	if kind=="name_erase":
		if has(unit,"N06") and rng.randf()<float(params("N06").chance):_event("name_resisted",unit,"N06");return _ok()
		if int(unit.growth.counters.get("named_ward",0))>0:unit.growth.counters.named_ward-=1;_event("name_ward",unit,kind);return _ok()
		if has(unit,"I08") and _uses(unit,"I08")==0:_spent(unit,"I08");_event("blank_note",unit,kind);return _ok()
	if kind=="charm" and has(unit,"Y07"):kind="root";duration=float(params("Y07").duration)
	if kind=="cry_stun" and has(unit,"N08"):duration*=float(params("N08").multiplier)
	if kind=="drag" and has(unit,"I06"):duration*=float(params("I06").water_multiplier)
	unit.growth.statuses[kind]={"left":duration,"source_id":source.instance_id if is_instance_valid(source) else ""}
	if kind=="name_erase":session.names=maxf(0,session.names-1)
	if kind=="drag" and unit.side=="xianghuo" and unit.brain.channel.active:unit.brain.channel.cancel("P4_RITUAL_INTERRUPTED_MOVEMENT")
	_event("status_"+kind,unit,source.instance_id if is_instance_valid(source) else "")
	_visual(kind,unit.position,unit.floor_id,.8)
	state.rng_state=str(rng.state)
	return _ok()
func apply_light(caster:Node2D,radius_body:float,duration:float)->void:
	if not enabled:return
	ensure(caster)
	for enemy in sim().humans+sim().targets:
		if enemy.dead or enemy.side==caster.side or enemy.floor_id!=caster.floor_id or enemy.position.distance_to(caster.position)>Rules.body_to_px(radius_body):continue
		ensure(enemy);enemy.growth.statuses.revealed={"left":maxf(duration,float(rules().skills.reveal_duration))}
		if caster.unit_id=="H21" and in_environment(enemy,"water"):enemy.growth.statuses.water_slow={"left":duration}
		var open_face: bool = session.ritual.has_flag("reveal_faces") and enemy.roster.get("face_state","faced") == "faceless"
		if (caster.unit_id=="H06" and enemy.unit_id in ["G01","G04"] or open_face) and _ready(enemy,"light_fear"):
			var fear: float = session.ritual.light_fear_duration(enemy,float(rules().skills.light_fear_duration))
			apply_status(enemy,"fear",fear,caster);_cd(enemy,"light_fear",float(rules().skills.fear_cooldown));_event("light_fear",caster,enemy.instance_id)
		if caster.unit_id=="G11" and enemy.unit_id in ["G01","G04"] and _ready(caster,"light_burn"):
			enemy.receive_damage(float(rules().skills.light_damage),caster,"light");_cd(caster,"light_burn",float(rules().skills.light_tick))
	_visual("light",caster.position,caster.floor_id,.2,radius_body)
func drum_radius(unit: Node2D, base: float) -> float:
	return base + (float(params("I07").radius_bonus_body) if has(unit,"I07") else 0.0)

func drum(unit:Node2D)->void:
	var radius:=drum_radius(unit,float(rules().skills.drum_radius_body))
	for other in sim().humans+sim().targets:
		if other.floor_id!=unit.floor_id or other.position.distance_to(unit.position)>Rules.body_to_px(radius):continue
		ensure(other)
		if other.side==unit.side:other.growth.statuses.erase("stun");other.growth.statuses.erase("cry_stun")
		else:apply_status(other,"revealed",3,unit)
	_event("drum",unit,str(radius));_visual("drum",unit.position,unit.floor_id,1,radius)
func knock_from_beam(unit:Node2D,source:Node2D=null)->void:
	if not enabled:return
	ensure(unit)
	if has(unit,"I05"):
		var best:Node2D
		var distance:=INF
		for post in sim().world.posts:
			if int(post.get_meta("floor_id"))>0 and post.position.distance_to(unit.position)<distance:best=post;distance=post.position.distance_to(unit.position)
		if best!=null:unit.position=best.position;unit.floor_id=int(best.get_meta("floor_id"))
		_event("beam_nail_saved",unit,"I05")
	else:
		unit.floor_id=0;unit.position.y=sim().world.floor_y(0);unit.receive_damage(unit.max_hp,source,"fall")
	_visual("fall",unit.position,unit.floor_id,1)
func charge(unit:Node2D,target:Node2D)->void:
	if not enabled or not _ready(unit,"charge"):return
	ensure(unit)
	_cd(unit,"charge",float(rules().skills.charge_cooldown))
	unit.growth.statuses.charge={"left":float(params("I16").warning_time)}
	unit.growth.charge_job={"target_id":str(target.instance_id) if target.is_in_group("units") else "world:"+str(target.name),"elapsed":0.0,"duration":float(params("I16").warning_time)}
	_visual("charge_dust",unit.position,unit.floor_id,float(params("I16").warning_time))
	for watcher in sim().humans:
		if not watcher.dead and has(watcher,"I16"):
			_visual("charge_warning",unit.position,unit.floor_id,float(params("I16").warning_time),0,target.position)
			_event("charge_forewarned",watcher,unit.instance_id)
			break
	_event("charge_windup",unit,str(target.name))
func seal_door(unit:Node2D,door:Node2D)->void:
	ensure(unit)
	var duration:=float(rules().skills.seal_duration)*(float(params("I03").duration_multiplier) if has(unit,"I03") else 1.0)
	duration *= float(session.ritual.param("seal_multiplier",1.0))
	state.seals[str(door.name)]={"left":duration,"owner_id":unit.instance_id,"hits":0}
	_event("seal_created",unit,str(door.name));_visual("seal",door.position,door.floor_id,duration)
func _break_seal(id:String,attacker:Node2D)->void:
	if not state.seals.has(id):return
	var owner=_unit(str(state.seals[id].owner_id));state.seals.erase(id)
	if is_instance_valid(attacker) and owner!=null and not owner.dead and "J02" in owner.growth.job_tags:
		for ally in sim().humans:
			if ally.position.distance_to(owner.position)<=Rules.body_to_px(float(rules().jobs.J02.ward_radius_body)):
				ensure(ally);ally.growth.statuses.ward={"left":float(rules().jobs.J02.ward_duration),"multiplier":float(rules().jobs.J02.defense_multiplier)}
		_event("job_defense_ward",owner,"J02")
func _finish_borrow(caster:Node2D)->void:
	var legacy_probability: float = float(rules().borrow.risky_failure_rate) if state.ritual_flag in ["youshen","游神"] else float(rules().borrow.failure_rate)
	var probability := float(session.ritual.param("borrow_failure_rate",legacy_probability))
	var failed:=rng.randf()<probability
	var unit=sim().tide.spawn("G30" if failed else "G11",3,caster.position.x)
	if failed:
		var before: float = session.names
		session.names = maxf(0, before - float(rules().borrow.failure_name_loss))
		if before > 0 and session.names <= 0 and session.roster.enabled:
			session.roster.state.last_erased_by = str(unit.unit_id) if is_instance_valid(unit) else ""
		_event("borrow_backlash",caster,"G30");_visual("backlash",caster.position,caster.floor_id,2)
	else:
		if unit!=null:
			unit.floor_id=caster.floor_id;unit.position=caster.position;_gray(unit,caster,float(rules().borrow.success_duration));unit.display_name="祠神援手"
		_event("borrow_success",caster,"G11");_visual("god",caster.position,caster.floor_id,2)
	state.rng_state=str(rng.state)
func light_without_borrowing(caster: Node2D, target: Node2D) -> bool:
	if caster.unit_id != "H19" or caster.side != "xianghuo" or target.side != "yegui": return false
	if state.get("defense_objective","") != "hold_register" or not has(caster,"I08"): return false
	apply_status(target,"revealed",3.0,caster)
	apply_status(target,"stun",1.5,caster)
	_event("lamp_reveal",caster,target.instance_id)
	_visual("lamp_reveal",target.position,target.floor_id,0.65,0,caster.position)
	return true

func _gray(unit:Node2D,caster:Node2D,duration:float)->void:
	var old_side:String=unit.side
	ensure(unit);ensure(caster)
	unit.growth.gray=true;unit.growth.temporary=true;unit.growth.gray_left=duration*(float(params("Y16").multiplier) if has(caster,"Y16") else 1.0);unit.growth.borrowed_by=caster.unit_id;unit.growth.borrower_id=caster.instance_id
	sim().targets.erase(unit)
	if unit not in sim().humans:sim().humans.append(unit)
	unit.side="xianghuo";unit.role="guard"
	var best:Marker2D
	var distance:=INF
	for post in sim().world.posts:
		if int(post.get_meta("floor_id"))==unit.floor_id and post.position.distance_to(unit.position)<distance:best=post;distance=post.position.distance_to(unit.position)
	if best!=null:unit.current_post=str(best.name)
	unit.brain=sim().HumanAI.new(sim(),unit);unit.sync_meta();sim()._update_units()
	sim().unit_allegiance_changed.emit(unit,old_side,unit.side)
	if sim().roster_engine()!=null: session.codex.resolve(unit.unit_id,"recruited")
	_visual("gray",unit.position,unit.floor_id,1.5)
func _ungray(unit:Node2D)->void:
	var old_side:String=unit.side
	unit.growth.gray=false;unit.growth.temporary=false;unit.growth.gray_left=0.0
	sim().humans.erase(unit)
	if unit not in sim().targets:sim().targets.append(unit)
	unit.side="yegui";unit.role=str(unit.profile.role)
	unit.brain=preload("res://src/ai/GhostBrain.gd").new(sim(),unit,sim().tide)
	if sim().world.is_upper_floor(unit.floor_id):unit.brain.stage="upper"
	unit.sync_meta();sim()._update_units();_visual("recapture",unit.position,unit.floor_id,1.5)
	sim().unit_allegiance_changed.emit(unit,old_side,unit.side)
func heal(unit:Node2D,amount:float)->float:
	if not enabled:return amount
	for holder in sim().humans+sim().targets:
		if holder!=unit and has(holder,"I18") and holder.position.distance_to(unit.position)<=Rules.body_to_px(float(params("I18").radius_body)) and unit.unit_id.begins_with("H"):amount*=float(params("I18").heal_multiplier)
	unit.hp=minf(unit.max_hp,unit.hp+amount)
	_event("healed",unit,str(amount));return amount
func _recover_kill(unit:Node2D)->void:
	if has(unit,"Y06") and _ready(unit,"Y06"):_credit(unit,float(params("Y06").incense));_cd(unit,"Y06",float(params("Y06").cooldown));_event("kill_incense",unit,"Y06")
func _credit(unit:Node2D,amount:float)->void:
	if session.dual_enabled:session.wallets[seat_of(unit)]=minf(float(session.rules.incense_cap),session.incense_for(seat_of(unit))+amount)
	elif seat_of(unit)!=session.mode:state.npc_incense=minf(float(session.rules.incense_cap),float(state.npc_incense)+amount)
	else:session.incense=minf(float(session.rules.incense_cap),session.incense+amount)
func _pay(unit:Node2D,cost:float)->bool:
	if has(unit,"N05"):cost=maxf(0,cost-float(params("N05").cost_reduction))
	var seat:=seat_of(unit)
	if session.incense_for(seat)<cost:return false
	if session.dual_enabled:session.wallets[seat]=session.incense_for(seat)-cost
	elif seat!=session.mode:state.npc_incense-=cost
	else:session.incense-=cost
	return true
func _nearest(unit:Node2D,radius:float,friendly:bool)->Node2D:
	var best:Node2D
	for other in sim().humans+sim().targets:
		if other==unit or other.dead or (other.side==unit.side)!=friendly or other.floor_id!=unit.floor_id:continue
		var distance:float=other.position.distance_to(unit.position)
		if distance<=radius:radius=distance;best=other
	return best
func _displace(unit:Node2D,toward_x:float,distance:float)->void:
	var direction:=signf(toward_x-unit.position.x)
	var target:Vector2=unit.position+Vector2(direction*distance,0)
	if unit.side=="xianghuo" and not sim().world.inside_base(target):return
	if not sim().world.segment_blocked(unit.position,target,unit.floor_id):unit.position=target
func _uses(unit:Node2D,id:String)->int:return int(unit.growth.charges.get(id,0))
func _spent(unit:Node2D,id:String)->void:unit.growth.charges[id]=_uses(unit,id)+1
func _ready(unit:Node2D,id:String)->bool:return float(unit.growth.cooldowns.get(id,0))<=0
func _cd(unit:Node2D,id:String,left:float)->void:unit.growth.cooldowns[id]=left

func ritual_fire_multiplier(caster: Node2D) -> float:
	if session.ritual.has_flag("ground_fire") and has(caster,"I14"):
		return float(params("I14").fire_multiplier)
	return 1.0

func ignite_ritual_fire(caster: Node2D, point: Vector2, floor_id: int, skill_source: String) -> void:
	if not session.ritual.has_flag("ground_fire"):
		return
	var settings: Dictionary = session.ritual_row.params
	var radius := float(settings.fire_radius_body)
	var area: Dictionary = sim().world.chunk_area_at(point,floor_id)
	var source_id := str(area.get("fire_source",""))
	if not source_id.is_empty():
		var fire_source: Node2D = sim().world.get_node_or_null(source_id)
		if is_instance_valid(fire_source) and fire_source.occupied and fire_source.durability > 0:
			radius *= float(area.get("fire_radius_multiplier",1.0))
	state.fields.append({"kind":"fire","point":[point.x,point.y],"floor_id":floor_id,"left":float(settings.fire_seconds),
		"owner_id":caster.instance_id,"safe_side":caster.side if skill_source == settings.friendly_fire_exemption else "",
		"radius":radius,"damage_per_second":float(settings.fire_damage_per_second) * ritual_fire_multiplier(caster)})
	_event("ground_fire",caster,skill_source)

func _visual(kind:String,point:Vector2,floor_id:int,duration:float,radius:=0.0,end:=Vector2.ZERO)->void:
	if kind=="light":
		for field in state.fields:
			if field.kind==kind and field.floor_id==floor_id and Vector2(field.point[0],field.point[1]).distance_to(point)<8:
				field.point=[point.x,point.y];field.left=duration;field.radius=radius
				return
	state.fields.append({"kind":kind,"point":[point.x,point.y],"floor_id":floor_id,"left":duration,"radius":radius,"end":[end.x,end.y]})
func draw_effects(canvas:Node2D)->void:
	for zone in state.environments:
		var y:float=sim().world.floor_y(int(zone.floor_id))
		var a:=Vector2(Rules.body_to_px(float(zone.from_body)),y-5)
		var b:=Vector2(Rules.body_to_px(float(zone.to_body)),y-5)
		canvas.draw_dashed_line(a,b,Color("5b9399") if zone.kind=="water" else Color("a29270"),5,14)
	for entry in state.locked_paths:
		var id:String=str(entry) if entry is String else str(entry.get("id",""))
		if not path_locked(id):continue
		var door=sim().world.get_node_or_null(id)
		if door!=null:
			var p:Vector2=door.position-Vector2(0,150)
			canvas.draw_rect(Rect2(p-Vector2(12,0),Vector2(24,20)),Color("be9f62"),false,3)
			canvas.draw_arc(p-Vector2(0,2),9,PI,TAU,12,Color("be9f62"),3)
	for field in state.fields:
		var point:=Vector2(field.point[0],field.point[1])
		var kind:String=field.kind
		match kind:
			"light", "revealed", "fear", "bone_lantern", "seal", "incense_transfer", "incense_restored", "gold_mirror", "dispel", "false_god_unmasked", "crossbow_shot", "cold_light", "river_lantern", "crow_path", "beam_pounce", "purified":
				continue
			"lamp_reveal":
				var fade := clampf(float(field.left)/0.65,0,1)
				var target := point - Vector2(0,108)
				var lamp := Vector2(field.end[0],field.end[1])-Vector2(0,76)
				canvas.draw_line(lamp,target,Color(1,0.75,0.28,fade*0.8),3)
				canvas.draw_arc(target,16 + (1-fade)*12,0,TAU,24,Color(1,0.78,0.31,fade),3)
			"paper_brace":
				var t := clampf(1.0 - float(field.left) / 0.65,0,1)
				var center := point - Vector2(0,112 + 20*t)
				for side in [-1,1]:
					var half := Vector2(side * (9 + 24*t),0)
					var paper := PackedVector2Array([center + half + Vector2(-6,-16),center + half + Vector2(8,-14),center + half + Vector2(5,12),center + half + Vector2(-9,17)])
					canvas.draw_colored_polygon(paper,Color(0.96,0.85,0.62,1-t))
					canvas.draw_line(center + half - Vector2(0,9),center + half + Vector2(0,5),Color(0.7,0.17,0.1,1-t),3)
			"charge_warning":canvas.draw_dashed_line(point-Vector2(0,12),Vector2(field.end[0],field.end[1])-Vector2(0,12),Color("c6a77c"),4,18)
			"hold_gate":
				var glint := clampf(float(field.left), 0.0, 1.0)
				var rim := PackedVector2Array([point+Vector2(-17,-69),point+Vector2(-28,-60),point+Vector2(-27,-37),point+Vector2(-19,-24)])
				canvas.draw_polyline(rim, Color(0.92, 0.73, 0.45, glint), 3)
				canvas.draw_texture_rect(preload("res://assets/vfx/ink/impact.png"),Rect2(point-Vector2(55,17),Vector2(95,19)),false,Color(.9,.85,.75,glint*.76))
			"charge_dust":
				for i in 7:canvas.draw_rect(Rect2(point+Vector2(-i*18,-8-(i%3)*12),Vector2(10,10)),Color(.6,.57,.48,.55))
			"rekindle":
				canvas.draw_arc(point-Vector2(0,72),24,0,PI,16,Color("c7d2bb"),4)
				canvas.draw_line(point-Vector2(11,73),point-Vector2(5,73),Color("bda072"),3)
				canvas.draw_line(point-Vector2(-5,73),point-Vector2(-11,73),Color("bda072"),3)
				for i in 5:canvas.draw_line(point+Vector2(i*14-28,-95),point+Vector2(i*14-28,-110-i*6),Color("bfc7a9"),3)
			"backlash":
				canvas.draw_polyline(PackedVector2Array([point+Vector2(-60,-130),point+Vector2(40,-90),point+Vector2(-35,-45),point+Vector2(60,-10)]),Color("a84a53"),6)
			"needle":canvas.draw_line(point+Vector2(-32,-112),point+Vector2(-30,-30),Color("d0caaa"),4)
			"fire":
				if field.has("damage_per_second"):
					var radius := Rules.body_to_px(float(field.radius))
					canvas.draw_line(point-Vector2(radius,4),point+Vector2(radius,-4),Color(.76,.27,.1,.62),5)
					for index in 5:
						var foot := point+Vector2((index-2)*radius*.43,0)
						var rise := 20.0+float((index*17)%23)
						canvas.draw_colored_polygon(PackedVector2Array([foot-Vector2(9,0),foot+Vector2(3,-rise),foot+Vector2(12,0)]),Color(.8,.36,.14,.68))
				else:
					canvas.draw_colored_polygon(PackedVector2Array([point,point+Vector2(25,-60),point+Vector2(38,0)]),Color(.8,.3,.12,.65))
			_:
				var energy := clampf(float(field.left) / maxf(.01, float(field.get("duration", 1.0))), 0, 1)
				var light := Color("c2b693") if kind in ["gray", "ward"] else Color("9fb3aa")
				light.a = .68 * energy
				for i in 4:
					var foot := point + Vector2(-27 + i * 18, -3)
					var tip := foot + Vector2(-9 + i * 3, -7 - (i % 3) * 6 - 12 * (1-energy))
					canvas.draw_line(foot, tip, light, 2.0)

func _return_item(unit:Node2D,id:String)->void:
	if id in ["I01","I02","I08","I13","I19"] and _uses(unit,id)>0:return
	state.inventory[id]=int(state.inventory.get(id,0))+1
	if not state.stored_items.has(id):state.stored_items[id]=[]
	state.stored_items[id].append({"charges":_uses(unit,id),"ready_at":float(state.time)+float(unit.growth.cooldowns.get(id,0))})
func _take_item(unit:Node2D,id:String)->void:
	var stored:Array=state.stored_items.get(id,[])
	if stored.is_empty():unit.growth.charges[id]=0;unit.growth.cooldowns[id]=0.0
	else:
		var data:Dictionary=stored.pop_front()
		unit.growth.charges[id]=int(data.charges)
		unit.growth.cooldowns[id]=maxf(0,float(data.ready_at)-float(state.time))
func landing_duration(unit:Node2D,base:float)->float:
	return base*float(params("N11").landing_multiplier) if has(unit,"N11") else base

func place_barricade(unit:Node2D,object_id:String="")->Dictionary:
	if not enabled or unit.unit_id not in ["H11","H25"] or not _ready(unit,"barricade"):return _reject("P7_INVALID_UNIT")
	ensure(unit)
	for object in sim().world.obstacles:
		if (object_id!="" and str(object.name)!=object_id) or object.max_durability<=0 or object.occupied or object.floor_id!=unit.floor_id or object.position.distance_to(unit.position)>=Rules.body_to_px(8):continue
		if not _pay(unit,float(rules().skills.barricade_cost)):return _reject("P7_NO_INCENSE")
		var duration:=repair_duration(unit,float(rules().skills.construct_duration))
		unit.growth.statuses.construct={"left":duration+.1,"complete_at":.1,"object_id":str(object.name),"hp":float(rules().skills.barricade_durability)*(float(params("Y14").multiplier) if has(unit,"Y14") else 1.0)}
		_cd(unit,"barricade",float(rules().skills.barricade_cooldown));_event("barricade_started",unit,str(object.name))
		return {"ok":true,"reason":"P7_COMMAND_OK","object":object,"duration":duration}
	return _reject("P7_NO_BARRICADE_SLOT")

func path_locked(id:String)->bool:
	for entry in state.locked_paths:
		if entry is String and entry==id:return true
		if entry is Dictionary and str(entry.id)==id:return bool(entry.locked)
	return false

func on_landed(unit:Node2D)->void:
	if not enabled:return
	if str(unit.growth.get("fusion_id",""))=="F01":
		var data:Dictionary=rules().fusions.F01.params
		var target=_nearest(unit,Rules.body_to_px(float(data.pounce_radius_body)),false)
		if target!=null:sim().deal_damage(unit,target,"pounce",unit.attack*float(data.pounce_multiplier))
		_event("fusion_pounce",unit,target.instance_id if target!=null else "")
		_visual("upper_alarm",unit.position,unit.floor_id,1.5)

static func _canonical(value:Variant)->Variant:
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[str(key)]=_canonical(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(_canonical(item))
		return result
	return str(value) if value is StringName else value

func _recapture_contacts()->void:
	# Resolve touching unregistered enemies before a new support skill can borrow them away.
	for unit in sim().humans.duplicate():
		if unit.dead or not bool(unit.growth.get("gray",false)):continue
		for other in sim().targets.duplicate():
			if not other.dead and "无册" in other.tags and other.floor_id==unit.floor_id and other.position.distance_to(unit.position)<=Rules.body_to_px(float(rules().skills.gray_touch_range_body)):
				_ungray(unit);_event("gray_recaptured",unit,other.instance_id)
				var owner=_unit(str(unit.growth.get("borrower_id","")))
				if owner!=null and owner.unit_id=="H19":apply_status(owner,"charm",float(rules().skills.borrow_backlash_duration),other)
				break

func apply_starting_loadout(unit:Node2D)->void:
	if not enabled or not eligible(unit):return
	for loadout in state.starting_loadouts:
		if str(loadout.id)!=unit.unit_id or int(loadout.remaining)<=0:continue
		ensure(unit)
		var prior_seat:String=session._command_seat
		var prior_origin:String=session._command_origin
		session._command_seat=seat_of(unit);session._command_origin="ai"
		var art_index:=0
		for id in loadout.items:
			if not rules().items.has(str(id)):continue
			var previous:int=int(state.inventory.get(str(id),0))
			state.inventory[str(id)]=previous+1
			var result:=_equip(unit,str(id),art_index if rules().items[id].slot=="art" else 0)
			state.inventory[str(id)]=previous
			if result.ok and rules().items[id].slot=="art":art_index+=1
		loadout.remaining-=1
		session._command_seat=prior_seat;session._command_origin=prior_origin
		return

func _door_threatened(unit:Node2D,door:Node2D)->bool:
	for enemy in sim().humans+sim().targets:
		if enemy!=unit and not enemy.dead and enemy.side!=unit.side and enemy.floor_id==door.floor_id and enemy.position.distance_to(door.position)<=Rules.body_to_px(float(rules().skills.status_radius_body)):
			return true
	return false
func _light_needed(unit:Node2D,radius_body:float)->bool:
	for enemy in sim().humans+sim().targets:
		if enemy==unit or enemy.dead or enemy.side==unit.side or enemy.floor_id!=unit.floor_id or enemy.position.distance_to(unit.position)>Rules.body_to_px(radius_body):continue
		ensure(enemy)
		if is_hidden(enemy):return true
		if unit.unit_id=="H06" and enemy.unit_id in ["G01","G04"] and _ready(enemy,"light_fear") and not enemy.growth.statuses.has("fear"):return true
		if unit.unit_id=="H21" and in_environment(enemy,"water") and not enemy.growth.statuses.has("water_slow"):return true
	return false
func _drum_needed(unit:Node2D)->bool:
	var radius:=drum_radius(unit,float(rules().skills.drum_radius_body))
	for other in sim().humans+sim().targets:
		if other==unit or other.dead or other.floor_id!=unit.floor_id or other.position.distance_to(unit.position)>Rules.body_to_px(radius):continue
		ensure(other)
		if other.side!=unit.side:
			if is_hidden(other):return true
		elif other.growth.statuses.has("stun") or other.growth.statuses.has("cry_stun"):return true
	return false
