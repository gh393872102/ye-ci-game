extends RefCounted
## P7 changes this night's reward pool, never the permanent source unit tables.
const TABLE := "res://data/nights/p7_growth_night.json"

static func table() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	return data if data is Dictionary else {}

static func configure(base: Dictionary, build_id := "") -> Dictionary:
	var config: Dictionary = base.duplicate(true)
	var growth := table()
	config.growth_night = growth
	for profile in config.battle_profiles.values():
		profile.victory_incense = float(growth.victory_incense)
	config.growth_build_id = build_id
	var path: Dictionary = growth.get("paths",{}).get(build_id,{})
	var preferred: Array = path.get("items",[])
	# Equipment slots replace the old P5 prototype stat cards in a growth night.
	for id in config.rewards.keys():
		if config.rewards[id].effect.kind in ["equipment","stats","build","mutate"]:
			config.rewards.erase(id)
	for id in Data.growth_rules.items:
		var item: Dictionary = Data.growth_rules.items[id]
		var slot: String = item.slot
		var weight: float = growth.item_weights.get(slot,2)
		if id in preferred: weight *= float(growth.preferred_weight_multiplier)
		config.rewards["p7_" + id] = _card("p7_" + id,str(item.name),str(item.get("description",item.get("effect_text","今夜可装入对应装备槽。"))),"build","both",weight,float(growth.item_prices.get(slot,8)),{"kind":"growth_item","id":id})
	for id in Data.growth_rules.jobs:
		var job: Dictionary = Data.growth_rules.jobs[id]
		config.rewards["p7_" + id] = _card("p7_" + id,str(job.get("name",id)),str(job.get("description","获得一次点职凭据；在对应人物面板使用。")),"build","shouxiang",float(growth.job_weight),float(growth.job_price),{"kind":"growth_item","id":id})
	config.rewards.p7_remnant = _card("p7_remnant","霜盏残名","双面灯融契材料；不占HUD资源栏。","build","duoming",float(growth.material_weight),float(growth.material_price),{"kind":"growth_material","id":"H06"})
	for id in growth.roster_prices:
		if not Data.combat_profiles.has(id): continue
		var row: Dictionary = Data.get_unit(id)
		var side := "duoming" if str(id).begins_with("G") else "shouxiang"
		var post := legal_post(str(id),"")
		var name_text: String = row.get("姓名",row.get("名称",id))
		var weight := 3.0
		for member in path.get("roster",[]):
			if member.id == id: weight *= float(growth.preferred_weight_multiplier)
		config.rewards["p7_recruit_" + id] = _card("p7_recruit_" + id,name_text + "应夜","本夜加入编制，使用源表属性与合法掩体岗位。","roster",side,weight,float(growth.roster_prices[id]),{"kind":"recruit","unit_id":id,"count":1,"post":post})
	var event: Dictionary = growth.event_material
	for field in ["title","description"]:
		event.choice[field] = TranslationServer.translate(event.choice[field])
	config.events[event.event_id].choices.append(event.choice.duplicate(true))
	# The old generic extra growth stat is replaced by a concrete job stamp.
	for choice in config.events.altar.choices:
		if choice.id == "listen":
			choice.title = TranslationServer.translate("P11_JOB_TITLE")
			choice.description = TranslationServer.translate("P11_JOB_BODY")
			choice.effects = [{"kind":"growth_item","id":"J01"}]
	if not path.is_empty():
		config.initial_roster[path.seat] = []
		for spec in path.roster:
			var member: Dictionary = spec.duplicate(true)
			member.post = legal_post(str(member.id),str(member.post))
			config.initial_roster[path.seat].append(member)
		if path.seat == "duoming":
			config.initial_roster.duoming.append({"id":"G01","post":"ghost_main_path","count":12})
	config.initial_roster_note = TranslationServer.translate("P11_GROWTH_ROSTER")
	return config

static func _card(id: String, title: String, description: String, category: String, mode: String, weight: float, cost: float, effect: Dictionary) -> Dictionary:
	return {"id":id,"title":title,"description":description,"category":category,"mode":mode,"weight":weight,"cost":cost,"requires_target":false,"effect":effect}

static func legal_post(id: String, requested: String) -> String:
	if id.begins_with("G"): return "ghost_main_path"
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/reference_gate_court.json"))
	var role: String = Data.combat_profiles[id].role
	if role == "talisman": role = "crossbow"
	var candidates: Array[String] = []
	for post in layout.posts:
		if post.default_deployment and role in post.allowed_roles: candidates.append(str(post.id))
	if requested in candidates: return requested
	return candidates[-1] if role == "ritual" else candidates[0]

static func initial(seed_text: String, mode: String, build_id := "") -> Dictionary:
	var growth := table()
	var inventory: Dictionary = growth.starting_inventory[mode].duplicate(true)
	var path: Dictionary = growth.paths.get(build_id,{})
	if not path.is_empty():
		inventory.clear()
		for index in mini(2,path.items.size()): inventory[path.items[index]] = 1
	var engine := preload("res://src/growth/GrowthEngine.gd").new(null)
	engine.configure(seed_text,{"inventory":inventory,"materials":growth.starting_materials.duplicate()})
	var snapshot: Dictionary = engine.snapshot()
	snapshot.npc_incense = float(Data.battle_rules.starting_incense["duoming" if mode == "shouxiang" else "shouxiang"])
	return snapshot

static func validate_config(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["item_prices","item_weights","paths","starting_inventory","roster_prices","event_material"]:
		if not data.get(key) is Dictionary: errors.append("Missing growth night section: " + key)
	if not errors.is_empty(): return errors
	for group in ["item_prices","item_weights"]:
		for slot in ["censer","art","nameplate"]:
			if not _number(data[group].get(slot),0): errors.append("Invalid growth night item numeric field")
	for key in ["preferred_weight_multiplier","job_price","job_weight","material_price","material_weight","inventory_cap","incense_regen","victory_incense"]:
		if not _number(data.get(key),0): errors.append("Invalid growth night numeric field: " + key)
	for seat in ["shouxiang","duoming"]:
		if not data.starting_inventory.get(seat) is Dictionary:
			errors.append("Missing growth night starting inventory")
			continue
		for id in data.starting_inventory[seat]:
			if not Data.growth_rules.items.has(id) or not _number(data.starting_inventory[seat][id],0): errors.append("Unknown growth night starting item")
	for id in data.roster_prices:
		if not Data.combat_profiles.has(id) or not _number(data.roster_prices[id],0): errors.append("Unknown growth night recruit")
	for id in ["chaodu","shoumen","pomen","dengmian","shangliang","wuce"]:
		if not data.paths.get(id) is Dictionary:
			errors.append("Missing growth build path: " + id)
			continue
		var path: Dictionary = data.paths[id]
		if path.get("seat") not in ["shouxiang","duoming"] or not path.get("roster") is Array or not path.get("items") is Array:
			errors.append("Invalid growth build path: " + id)
			continue
		for item in path.items:
			if not Data.growth_rules.items.has(item) and not Data.growth_rules.jobs.has(item): errors.append("Unknown growth build item")
		for spec in path.roster:
			if not spec is Dictionary or not Data.combat_profiles.has(str(spec.get("id",""))) or not spec.get("post") is String or not _number(spec.get("count"),1): errors.append("Unknown growth build unit")
	return errors

static func _number(value: Variant, minimum: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum

static func validate_templates(data: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not data is Dictionary or data.is_empty(): return ["Invalid growth observation templates"]
	for key in ["ritual_break","gate_beam"]:
		if not data.get(key) is Dictionary or not data[key].get("title") is String or not data[key].get("loadouts") is Dictionary:
			errors.append("Invalid growth observation template")
			continue
		for id in data[key].loadouts:
			var items = data[key].loadouts[id]
			if not Data.combat_profiles.has(id) or str(id).begins_with("T") or id == "G01" or not items is Array:
				errors.append("Invalid growth observation loadout")
				continue
			var counts := {"censer":0,"art":0,"nameplate":0}
			var seen: Array = []
			for item_id in items:
				if not item_id is String or not Data.growth_rules.items.has(item_id) or item_id in seen:
					errors.append("Unknown or repeated growth observation item")
					continue
				seen.append(item_id)
				counts[Data.growth_rules.items[item_id].slot] += 1
			if counts.censer > 1 or counts.art > 2 or counts.nameplate > 1:
				errors.append("Growth observation loadout exceeds slots")
	return errors
