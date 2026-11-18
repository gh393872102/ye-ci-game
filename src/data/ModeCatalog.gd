extends RefCounted
## Allowed P6 content and decision preferences. No alternate unit values are admitted.
static func read_config(path: String, profiles: Dictionary) -> Dictionary:
	var result := {"rules":{},"errors":[]}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		result.errors.append("Invalid modes JSON")
		return result
	var config: Dictionary = parser.data
	for key in ["allowed_humans","allowed_ghosts","profiles","rituals"]:
		if not config.get(key) is Array or config[key].is_empty():
			result.errors.append("Missing modes list: " + key)
	for key in ["defaults","ai_levels","limits"]:
		if not config.get(key) is Dictionary:
			result.errors.append("Missing modes section: " + key)
	if config.get("director_limit") != 3:
		result.errors.append("P6 director limit must be three")
	if not result.errors.is_empty():
		return result
	for id in config.allowed_humans + config.allowed_ghosts:
		if not id is String or not profiles.has(id):
			result.errors.append("Unknown modes unit: " + str(id))
	for id in config.allowed_humans:
		if str(id).begins_with("G"):
			result.errors.append("Ghost in human modes list")
	for id in config.allowed_ghosts:
		if not str(id).begins_with("G"):
			result.errors.append("Human in ghost modes list")
	for id in config.profiles:
		if id not in ["entry","upper"]:
			result.errors.append("Unsupported modes layout profile")
	if config.rituals != ["example_incense"]:
		result.errors.append("P6 only implements example_incense")
	for key in ["duration_min","duration_max","incense_min","incense_max","names_min","names_max","human_max","named_max","troop_max","post_max","ghost_max"]:
		if not _number(config.limits.get(key),0):
			result.errors.append("Invalid modes limit: " + key)
	if not result.errors.is_empty():
		return result
	if config.limits.duration_min < 120 or config.limits.duration_max > 600 or config.limits.duration_min > config.limits.duration_max or config.limits.incense_min > config.limits.incense_max or config.limits.incense_max > 60 or config.limits.names_min > config.limits.names_max or config.limits.human_max > 12 or config.limits.troop_max > 4 or config.limits.named_max > 8 or config.limits.post_max > 3 or config.limits.ghost_max > 120:
		result.errors.append("Modes limits exceed implemented rules")
	for name in ["calm","normal","fierce"]:
		if not config.ai_levels.get(name) is Dictionary:
			result.errors.append("Missing AI ferocity: " + name)
			continue
		var level: Dictionary = config.ai_levels[name]
		for key in level:
			if key not in ["decision_interval","jitter","repair_ratio","upgrade_chance","breaker_preference","reinforce_chance","reserve_incense","purchase_chance","ritual_chance"]:
				result.errors.append("Unknown AI setting; ferocity cannot alter unit stats: " + str(key))
		for key in ["decision_interval","jitter","repair_ratio","upgrade_chance","breaker_preference","reinforce_chance","reserve_incense","purchase_chance","ritual_chance"]:
			if not _number(level.get(key),0):
				result.errors.append("Invalid AI decision setting: " + key)
		if not result.errors.is_empty():
			continue
		if level.decision_interval <= 0 or level.jitter >= level.decision_interval:
			result.errors.append("Invalid AI decision interval/jitter")
		for key in ["repair_ratio","upgrade_chance","breaker_preference","reinforce_chance","purchase_chance","ritual_chance"]:
			if float(level[key]) > 1:
				result.errors.append("Invalid AI probability: " + key)
	var defaults: Dictionary = config.defaults
	if defaults.get("kind") not in ["watch","duel"] or defaults.get("player_seat") not in ["shouxiang","duoming"] or not defaults.get("seed") is String or defaults.get("profile_id") not in config.profiles or defaults.get("ritual") != "example_incense" or defaults.get("ferocity") not in config.ai_levels or not defaults.get("director_enabled") is bool:
		result.errors.append("Invalid modes defaults")
	if not _number(defaults.get("duration"),float(config.limits.duration_min)) or float(defaults.get("duration",601)) > config.limits.duration_max or not _number(defaults.get("names"),float(config.limits.names_min)) or float(defaults.get("names",13)) > config.limits.names_max:
		result.errors.append("Invalid modes default timing/names")
	if not defaults.get("incense") is Dictionary:
		result.errors.append("Invalid modes default wallets")
	else:
		for seat in ["shouxiang","duoming"]:
			if not _number(defaults.incense.get(seat),float(config.limits.incense_min)) or float(defaults.incense.get(seat,61)) > config.limits.incense_max:
				result.errors.append("Invalid modes default incense")
	for key in ["humans","ghosts"]:
		if not defaults.get(key) is Array:
			result.errors.append("Invalid modes default roster")
		else:
			for item in defaults[key]:
				if not item is Dictionary or item.get("id") not in config["allowed_" + key] or not _number(item.get("count"),1) or float(item.count) != int(item.count):
					result.errors.append("Invalid modes default unit")
				elif key == "humans" and not item.get("post") is String:
					result.errors.append("Missing modes default post")
	if result.errors.is_empty():
		_validate_default_rosters(config,profiles,result.errors)
	if result.errors.is_empty():
		result.rules = config
	return result

static func _number(value, minimum: float) -> bool:
	return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(value)) and float(value) >= minimum

static func _validate_default_rosters(config: Dictionary, profiles: Dictionary, errors: Array) -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/reference_gate_court.json"))
	var posts: Dictionary = {}
	for post in layout.posts:
		if post.default_deployment:
			posts[str(post.id)] = post
	var named: Array[String] = []
	var at_post: Dictionary = {}
	var troops := 0
	var human_count := 0
	for item in config.defaults.humans:
		var id: String = item.id
		var count := int(item.count)
		human_count += count
		if id.begins_with("H"):
			if count != 1 or id in named:
				errors.append("Modes named unit must be unique")
			named.append(id)
		else:
			troops += count
		var post_id: String = item.post
		if not posts.has(post_id):
			errors.append("Modes default deployment must be a cover post")
			continue
		var role: String = profiles[id].role
		if role == "talisman":
			role = "crossbow"
		if role not in posts[post_id].allowed_roles:
			errors.append("Modes default post rejects unit role")
		at_post[post_id] = int(at_post.get(post_id,0)) + count
		if at_post[post_id] > int(config.limits.post_max):
			errors.append("Modes default post exceeds capacity")
	if human_count > int(config.limits.human_max) or named.size() > int(config.limits.named_max) or troops > int(config.limits.troop_max):
		errors.append("Modes default humans exceed roster capacity")
	var ghost_count := 0
	for item in config.defaults.ghosts:
		ghost_count += int(item.count)
	if ghost_count > int(config.limits.ghost_max):
		errors.append("Modes default tide exceeds capacity")
