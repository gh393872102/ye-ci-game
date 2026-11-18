extends RefCounted
## P8 validates every source identity and executable handler before entering a scene.
const TAGS := ["香火","名面","破门","上楼","水巷","灯","符","金","哭","无册","超度","机关"]
static func read_config(units: Dictionary) -> Dictionary:
	var result := {"rules":{"profiles":{},"skills":{},"traits":{},"abilities":{}},"errors":[]}
	for path in ["res://data/units/p8_humans.json","res://data/units/p8_ghosts.json"]:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			result.errors.append("Invalid P8 roster catalog: "+path)
			continue
		for section in ["profiles","skills","traits","abilities"]:
			if not parsed.get(section) is Dictionary:
				result.errors.append("Missing P8 roster section: "+section)
				continue
			for key in parsed[section]:
				if result.rules[section].has(key): result.errors.append("Duplicate P8 %s: %s" % [section,key])
				result.rules[section][key] = parsed[section][key]
	var expected: Array[String] = []
	for prefix in ["H","G"]:
		for number in range(1,33): expected.append("%s%02d" % [prefix,number])
	for number in range(1,5): expected.append("T%02d" % number)
	if result.rules.profiles.size() != 68: result.errors.append("P8 requires exactly 32 humans + 32 ghosts + 4 troops")
	var scripts: Dictionary = {}
	for id in expected:
		if not units.has(id) or not result.rules.profiles.get(id) is Dictionary:
			result.errors.append("Missing P8 unit: "+id)
			continue
		var row: Dictionary = units[id]
		var profile: Dictionary = result.rules.profiles[id]
		if profile.get("role") not in ["guard","ritual","crossbow","talisman","tide"] or not profile.get("projectile") is String: result.errors.append("Invalid P8 combat profile: "+id)
		if not number(profile.get("range_body"),.01,8) or not number(profile.get("return_after"),0,3): result.errors.append("Invalid P8 profile range: "+id)
		for tag in str(row.get("标签","")).split(";",false):
			if tag not in TAGS: result.errors.append("Invalid P8 source tag: %s %s" % [id,tag])
		for spec in [["skill_id","skills","专属技能","skill_script","skill_method"],["trait_id","traits","特性","trait_script","trait_method"]]:
			var key: String = str(profile.get(spec[0],""))
			if key.is_empty() or not result.rules[spec[1]].get(key) is Dictionary:
				result.errors.append("Missing P8 %s for %s" % [spec[0],id])
				continue
			var entry: Dictionary = result.rules[spec[1]][key]
			if row.has(spec[2]) and str(row[spec[2]]).split("：")[0] != str(entry.get("name","")):
				result.errors.append("P8 source name mismatch: "+id+" "+key)
			var path: String = str(profile.get(spec[3],entry.get("script","")))
			var method: String = str(profile.get(spec[4],entry.get("method","")))
			if not path.begins_with("res://src/roster/") or not ResourceLoader.exists(path):
				result.errors.append("Missing P8 skill script: "+id+" "+path)
				continue
			if not scripts.has(path): scripts[path] = load(path)
			var script: Script = scripts[path]
			var found := false
			if script != null and script.can_instantiate():
				for method_spec in script.get_script_method_list():
					if str(method_spec.name) == method: found = true
			if not found: result.errors.append("Missing P8 skill method: "+id+" "+method)
		if bool(profile.get("may_briefly_leave_base",false)) != (id in ["H25","H31"]): result.errors.append("P8 departure permission mismatch: "+id)
		var large := id in ["G17","G18","G19","G20","G21","G22","G23","G24","G31","G32"]
		var height := float(profile.get("height_px",0))
		if large and (height < 128 or height > 176) or not large and height != 80: result.errors.append("P8 height mismatch: "+id)
		if not result.rules.abilities.get(id) is Dictionary or result.rules.abilities[id].is_empty(): result.errors.append("Missing P8 ability parameters: "+id)
		for key in result.rules.abilities.get(id,{}):
			var value = result.rules.abilities[id][key]
			if value is String:
				if key != "market_item" or not Data.growth_rules.get("items",{}).has(value): result.errors.append("Invalid P8 ability reference: "+id+" "+key)
			elif not number(value,0,10000): result.errors.append("Invalid P8 ability parameter: "+id+" "+key)
	var routes = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/p8_routes.json"))
	if not routes is Dictionary or not routes.get("window_side_passage") is Dictionary or not routes.get("mechanism_side_route") is Dictionary:
		result.errors.append("Invalid P8 movement routes")
	else:
		var window: Dictionary = routes.window_side_passage
		var mechanism: Dictionary = routes.mechanism_side_route
		if window.get("unit_ids") != ["G07"] or mechanism.get("unit_ids") != ["G24"]: result.errors.append("Invalid P8 route permission")
		for key in ["departure_x_body","entry_x_body"]:
			if not number(window.get(key),0,120): result.errors.append("Invalid P8 route position: "+key)
		if not number(window.get("ledge_offset_px"),100,200) or not number(window.get("speed_multiplier"),.1,1) or window.get("entry_floor")!=2: result.errors.append("Invalid P8 route scale")
		if mechanism.get("stair_id")!="stair_main" or mechanism.get("post_id")!="post_stair_head" or not mechanism.get("front_doors") is Array: result.errors.append("Invalid P8 side access")
		result.rules.routes = routes
	return result

static func number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum
