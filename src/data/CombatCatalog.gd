extends RefCounted
## P2 links source CSV identities to behavior IDs; never duplicates the four stats.
static func read_catalog(path: String, units: Dictionary) -> Dictionary:
	var result := {"profiles": {}, "skills": {}, "traits": {}, "errors": []}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		result.errors.append("Invalid combat catalog JSON: " + path)
		return result
	var catalog: Dictionary = parser.data
	for section in ["profiles", "skills", "traits"]:
		if not catalog.get(section) is Dictionary:
			result.errors.append("Missing combat catalog section: " + section)
			return result
		result[section] = catalog[section]
	for id in catalog.profiles:
		var profile: Dictionary = catalog.profiles[id]
		if not units.has(id):
			result.errors.append("Combat profile has unknown unit: " + id)
			continue
		for pair in [["skill_id", "skills", "专属技能"], ["trait_id", "traits", "特性"]]:
			var key := str(profile.get(pair[0], ""))
			if key.is_empty():
				if units[id].has(pair[2]):
					result.errors.append("Missing %s for %s" % [pair[0], id])
			elif not catalog[pair[1]].has(key):
				result.errors.append("Unknown %s %s for %s" % [pair[0], key, id])
			elif str(units[id].get(pair[2], "")).split("：")[0] != catalog[pair[1]][key].name:
				result.errors.append("Source name mismatch for %s %s" % [id, key])
		if not profile.get("role", "") in ["guard", "ritual", "talisman", "crossbow", "debug_target", "tide"]:
			result.errors.append("Unknown combat role for " + id)
		if float(profile.get("range_body", 0)) <= 0 or float(profile.get("range_body", 0)) > 8:
			result.errors.append("Invalid combat range for " + id)
		if id in ["H01", "H09", "H17"] and profile.get("may_briefly_leave_base", false):
			result.errors.append("G0 human cannot leave base: " + id)
	for required in ["H01", "H09", "H17", "T01", "T02", "G01", "G09", "G12"]:
		if not catalog.profiles.has(required):
			result.errors.append("Missing P2 combat profile: " + required)
	return result
