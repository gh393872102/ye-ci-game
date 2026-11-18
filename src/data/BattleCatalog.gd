extends RefCounted
## Validate the new P4 table before Boot creates a decision session.
static func read_config(path: String, profiles: Dictionary) -> Dictionary:
	var result := {"rules":{},"errors":[]}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		result.errors.append("Invalid battle JSON")
		return result
	var data: Dictionary = parser.data
	var schema := {
		"duration":1,"starting_names":1,"incense_regen":0,"incense_cap":1,"named_cap":1,"troop_cap":1,"post_cap":1,
		"mutation_limit":1,"occupation_seconds":1,"occupation_recovery":0,"name_drain_per_second":0,"extinguish_seconds":1,
		"door_warning_ratio":0,"name_warning":0,
		"starting_incense":{"shouxiang":0,"duoming":0},
		"purchases":{"T01":1,"T02":1,"T04":1,"H01":1,"H09":1,"H17":1},
		"upgrade":{"cost":1,"hp":0,"defense":0,"max_level":1},
		"equipment":{"cost":1,"hp":0,"defense":0},
		"ritual":{"cost":1,"duration":1,"reward_incense":0,"reward_names":0,"range_body":1},
		"repair":{"cost":1,"heal":1,"duration":1,"inside_offset":1},
		"mutations":{"G09":1,"G12":1},"reinforce":{"cost":1,"count":1,"cooldown":1,"limit":1}}
	_validate(data,schema,"",result.errors)
	if not result.errors.is_empty():
		return result
	if not data.equipment.get("id") is String or str(data.equipment.id).is_empty() or not data.repair.get("rebuild_destroyed") is bool:
		result.errors.append("Invalid battle equipment/repair configuration")
	for section in ["purchases","mutations"]:
		for id in data[section]:
			var value = data[section][id]
			if not profiles.has(id) or (typeof(value) not in [TYPE_FLOAT,TYPE_INT]) or float(value) <= 0:
				result.errors.append("Invalid battle unit reference or cost: " + str(id))
	if data.door_warning_ratio > 1 or data.ritual.duration < 3 or data.ritual.duration > 5 or data.extinguish_seconds < 8 or data.extinguish_seconds > 12:
		result.errors.append("Invalid battle timing/warning range")
	result.rules = data
	return result

static func _validate(data: Dictionary, schema: Dictionary, prefix: String, errors: Array) -> void:
	for key in schema:
		var label: String = prefix + str(key)
		if schema[key] is Dictionary:
			if not data.get(key) is Dictionary:
				errors.append("Missing battle section: " + label)
			else:
				_validate(data[key],schema[key],label + ".",errors)
		elif not data.has(key) or typeof(data[key]) not in [TYPE_FLOAT,TYPE_INT]:
			errors.append("Invalid battle numeric field: " + label)
		elif not is_finite(float(data[key])) or float(data[key]) < float(schema[key]):
			errors.append("Invalid battle numeric range: " + label)
