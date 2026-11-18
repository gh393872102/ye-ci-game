extends RefCounted
## Reject invalid movement, waves and structure references before entering Combat.
static func read_config(path: String, layout: Dictionary) -> Dictionary:
	var result := {"config":{},"errors":[]}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		result.errors.append("Invalid tide JSON")
		return result
	var config: Dictionary = parser.data
	for key in ["capacity","lane_offsets","spacing","dense_spacing","speed_stat_anchor","speed_body_anchor","speed_stat_step","large_speed","climb_factor","door_durability","obstacle_durability","waves","climb","descent"]:
		if not config.has(key):
			result.errors.append("Missing tide field: " + key)
	if not result.errors.is_empty():
		return result
	if int(config.capacity) < 150 or config.lane_offsets.size() != 4 or float(config.large_speed) < 1.4 or float(config.large_speed) > 1.8 or float(config.climb_factor) < 0.55 or float(config.climb_factor) > 0.7:
		result.errors.append("Invalid tide scale/speed/capacity")
	var lanes: Dictionary = {}
	for offset in config.lane_offsets:
		lanes[offset] = true
		if float(offset) < -64 or float(offset) > 0:
			result.errors.append("Tide lane outside walk band")
	if lanes.size() != 4:
		result.errors.append("Duplicate tide lane")
	for door in layout.doors:
		if float(config.door_durability.get(door.id,0)) <= 0:
			result.errors.append("Invalid tide door durability: " + str(door.id))
	var previous := -1.0
	for wave in config.waves:
		if not wave is Dictionary or not wave.has("at") or float(wave.at) < previous:
			result.errors.append("Invalid tide wave ordering")
			continue
		previous = float(wave.at)
		for key in wave:
			if key != "at" and (not key in ["G01","G09","G12"] or int(wave[key]) < 0):
				result.errors.append("Invalid tide wave unit: " + str(key))
	for route in ["climb","descent"]:
		var link: Dictionary = config[route]
		if not link.has_all(["from_x","to_x","to_floor"]) or float(link.get("from_x",0)) < 50 or float(link.get("to_x",121)) > 120 or not int(link.get("to_floor",-1)) in [0,2]:
			result.errors.append("Invalid tide route: " + route)
	result.config = config
	return result
