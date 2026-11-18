extends RefCounted
## The registry is explicit: a missing item or implementation identifier stops startup.
const EFFECT_IDS := ["I01","I02","I03","I04","I05","I06","I07","I08","I09","I10","I11","I12","I13","I14","I15","I16","I17","I18","I19","I20","Y01","Y02","Y03","Y04","Y05","Y06","Y07","Y08","Y09","Y10","Y11","Y12","Y13","Y14","Y15","Y16","N01","N02","N03","N04","N05","N06","N07","N08","N09","N10","N11","N12"]
static func read_config(directory: String, units: Dictionary, profiles: Dictionary) -> Dictionary:
	var result := {"rules":{},"errors":[]}
	var rules := _read(directory + "/growth_rules.json",result.errors)
	if rules.is_empty(): return result
	rules.jobs = _read_jobs(directory + "/" + str(rules.get("jobs_file","job_stamps.csv")),result.errors)
	var items: Dictionary = {}
	for file in rules.get("item_files",[]):
		var table := _read(directory + "/" + str(file),result.errors)
		for id in table:
			var item = table[id]
			if items.has(id) or not item is Dictionary or item.get("id") != id or item.get("effect_id") not in EFFECT_IDS or item.get("slot") not in ["censer","art","nameplate"] or not item.get("params") is Dictionary or item.get("status") not in ["active","interface"]:
				result.errors.append("Invalid/unknown growth item: " + str(id))
				continue
			var expected_slot:String="censer" if str(id).begins_with("I") else ("art" if str(id).begins_with("Y") else "nameplate")
			if item.slot!=expected_slot or item.effect_id!=id or not item.get("name") is String or not item.get("description") is String:
				result.errors.append("Mismatched growth item slot/effect/text: " + str(id))
			var required:String={"I01":"charges","I02":"charges names","I03":"duration_multiplier","I04":"radius_body","I05":"fall_chance","I06":"bridge_multiplier water_multiplier","I07":"radius_bonus_body","I08":"charges","I09":"damage_conversion incense cooldown limit","I10":"structure_multiplier repair_multiplier","I11":"ritual_multiplier","I12":"reflect reveal_chance reveal_duration","I13":"radius_body charges","I14":"fire_multiplier chance duration damage_per_second radius_body","I15":"cooldown radius_body pull_body","I16":"charge_multiplier warning_time","I17":"progress_loss","I18":"damage_multiplier radius_body heal_multiplier","I19":"uses","I20":"skill_multiplier interval name_drain","Y01":"radius_body damage","Y02":"threshold multiplier","Y03":"duration multiplier","Y04":"multiplier","Y06":"incense cooldown","Y07":"duration","Y09":"multiplier","Y10":"multiplier","Y11":"multiplier","Y13":"multiplier","Y14":"multiplier","Y15":"push_body","Y16":"multiplier","N01":"hp_multiplier","N02":"speed_multiplier","N03":"attack_multiplier","N04":"door_damage_multiplier radius_body","N05":"cost_reduction","N06":"chance","N07":"multiplier","N08":"multiplier","N09":"multiplier duration","N11":"defense_multiplier landing_multiplier","N12":"attack_multiplier incoming_multiplier"}.get(str(id),"")
			for key in required.split(" ",false):
				if not _number(item.params.get(key),0):result.errors.append("Missing/invalid growth parameter: " + str(id) + "." + str(key))
			for key in item.params:
				if not _number(item.params[key],0):result.errors.append("Invalid growth effect number")
			for key in ["equip_cost","remove_cost"]:
				if not _number(item.get(key),0): result.errors.append("Invalid item cost")
			items[id] = item
	for id in EFFECT_IDS:
		if not items.has(id): result.errors.append("Missing growth effect: " + id)
	for group in ["mutations","fusions","jobs","borrow","skills","environment"]:
		if not rules.get(group) is Dictionary: result.errors.append("Missing growth section: " + group)
	if not result.errors.is_empty(): return result
	for id in rules.mutations:
		var recipe: Dictionary = rules.mutations[id]
		if recipe.get("id") != id or not _number(recipe.get("cost"),0) or recipe.get("status") not in ["active","locked","interface"] or not recipe.get("sources") is Array: result.errors.append("Invalid mutation recipe")
		for source in recipe.get("sources",[]):
			if not units.has(source): result.errors.append("Unknown mutation source")
		if recipe.get("status") == "active" and not profiles.has(str(recipe.get("result_id",""))): result.errors.append("Missing mutation combat profile")
	for id in ["V01","V02","V03"]:
		if not rules.mutations.has(id) or rules.mutations[id].get("cost")!={"V01":8,"V02":12,"V03":15}[id]:result.errors.append("Changed fixed mutation cost")
	for id in rules.fusions:
		var recipe: Dictionary = rules.fusions[id]
		if recipe.get("id") != id or not _number(recipe.get("cost"),0) or not recipe.get("sources") is Array or not units.has(str(recipe.get("result_id",""))): result.errors.append("Invalid fusion recipe")
		var expected:Array={"F01":["G09","G04"],"F02":["G12","G20"],"F03":["G11"],"F04":["G23","G28"],"F05":["borrowed_ghost","H22"]}.get(str(id),[])
		if expected.is_empty() or recipe.sources!=expected or recipe.cost!=20:result.errors.append("Invalid canonical fusion sources/cost")
		if recipe.get("status")=="active" and not profiles.has(str(recipe.get("result_id",""))):result.errors.append("Missing fusion result profile")
		if not str(recipe.get("material_id","")).is_empty() and not units.has(recipe.material_id): result.errors.append("Unknown fusion material")
	for id in rules.jobs:
		if rules.jobs[id].get("source_id")!={"J01":"H09","J02":"H17"}.get(str(id),""):result.errors.append("Invalid job stamp identity")
		if not units.has(str(rules.jobs[id].get("source_id",""))): result.errors.append("Unknown job source")
	for key in ["cost","names_cost","duration","success_duration","failure_rate","risky_failure_rate","failure_name_loss","gray_duration","recruit_chance","vulnerable_recruit_chance"]:
		if not _number(rules.borrow.get(key),0):result.errors.append("Missing/invalid borrow rule: "+key)
	for key in rules.skills:
		if not _number(rules.skills[key],0):result.errors.append("Invalid growth skill value")
	for key in rules.environment:
		if not _number(rules.environment[key],0):result.errors.append("Invalid environment multiplier")
	rules.items = items
	if result.errors.is_empty(): result.rules = rules
	return result
static func _read(path: String, errors: Array) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		errors.append("Invalid growth JSON: " + path)
		return {}
	return data
static func _number(value, minimum: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value >= minimum

static func _read_jobs(path:String,errors:Array)->Dictionary:
	var jobs:Dictionary={}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:errors.append("Missing job stamps CSV");return jobs
	if file.get_csv_line()!=PackedStringArray(["id","name","source_id","tag","cost","params"]):errors.append("Invalid job stamps columns");return jobs
	while not file.eof_reached():
		var row:=file.get_csv_line()
		if row.size()==1 and row[0]=="":continue
		if row.size()!=6 or jobs.has(row[0]) or not row[4].is_valid_float():errors.append("Invalid job stamp row");continue
		var params=JSON.parse_string(row[5])
		if not params is Dictionary:errors.append("Invalid job stamp params");continue
		var item:Dictionary={"id":row[0],"name":row[1],"source_id":row[2],"tag":row[3],"cost":float(row[4])}
		item.merge(params,false);jobs[row[0]]=item
	if jobs.size()!=2 or not jobs.has("J01") or not jobs.has("J02"):errors.append("Missing required job stamps")
	return jobs
