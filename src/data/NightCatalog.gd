extends RefCounted
## P5 route and reward validation. Invalid data blocks Boot before a night starts.
static func read_config(path: String, profiles: Dictionary) -> Dictionary:
	var result := {"rules":{},"errors":[]}
	var config := _read(path, result.errors)
	if config.is_empty():
		return result
	for section in ["rewards","events","battle_profiles"]:
		var key: String = section + "_path"
		if not config.get(key) is String:
			result.errors.append("Missing night table path: " + key)
		else:
			config[section] = _read(config[key], result.errors)
	for key in ["title","start_node","ritual","initial_roster_note"]:
		if not config.get(key) is String or str(config[key]).is_empty():
			result.errors.append("Invalid night string: " + key)
	if config.get("ritual") != "example_incense":
		result.errors.append("P5 only implements example_incense")
	for key in ["starting_names","names_cap","incense_cap"]:
		_number(config,key,0,result.errors)
	for section in ["starting_incense","roster_caps","initial_roster","rest","mercy","build_caps"]:
		if not config.get(section) is Dictionary:
			result.errors.append("Missing night section: " + section)
	if not result.errors.is_empty():
		return result
	for mode in ["shouxiang","duoming"]:
		_number(config.starting_incense,mode,0,result.errors)
		_number(config.roster_caps,mode,1,result.errors)
		if not config.initial_roster.get(mode) is Array:
			result.errors.append("Invalid initial night roster")
		else:
			for item in config.initial_roster[mode]:
				if not item is Dictionary or not profiles.has(str(item.get("id",""))) or not item.get("post") is String:
					result.errors.append("Invalid initial night unit reference")
				else:
					_number(item,"count",1,result.errors)
	for key in ["heal_ratio","incense","names"]:
		_number(config.rest,key,0,result.errors)
	for key in ["limit","minimum_incense","minimum_names","minimum_hp_ratio"]:
		_number(config.mercy,key,0,result.errors)
	if config.rest.get("heal_ratio",2) > 1 or config.mercy.get("minimum_hp_ratio",2) > 1 or config.mercy.get("limit",2) != 1:
		result.errors.append("Invalid night healing/mercy range")
	for key in config.build_caps:
		if typeof(config.build_caps[key]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(config.build_caps[key])):
			result.errors.append("Invalid night build cap")
	_validate_profiles(config.battle_profiles,result.errors)
	for id in config.rewards:
		var card = config.rewards[id]
		if not card is Dictionary:
			result.errors.append("Invalid night reward: " + str(id))
			continue
		if card.get("id") != id or card.get("mode") not in ["both","shouxiang","duoming"] or card.get("category") not in ["roster","build","survival"]:
			result.errors.append("Invalid night reward identity: " + str(id))
		for key in ["title","description"]:
			if not card.get(key) is String or str(card[key]).is_empty():
				result.errors.append("Missing night reward text")
		_number(card,"weight",0.001,result.errors)
		_number(card,"cost",0,result.errors)
		if not card.get("requires_target") is bool:
			result.errors.append("Invalid reward targeting")
		_effect(card.get("effect"),config,profiles,result.errors)
	for mode in ["shouxiang","duoming"]:
		var categories: Array[String] = []
		var eligible := 0
		for card in config.rewards.values():
			if card is Dictionary and card.get("mode") in ["both",mode]:
				eligible += 1
				if not categories.has(str(card.get("category",""))):
					categories.append(str(card.get("category","")))
		if eligible < 3 or not ("roster" in categories and "build" in categories and "survival" in categories):
			result.errors.append("Night reward pool must retain roster/build/survival for each seat")
	for id in config.events:
		var event = config.events[id]
		if not event is Dictionary or event.get("id") != id or not event.get("choices") is Array:
			result.errors.append("Invalid night event: " + str(id))
			continue
		var choices: Array[String] = []
		for choice in event.choices:
			if not choice is Dictionary or not choice.get("id") is String or choices.has(str(choice.id)) or not choice.get("effects") is Array:
				result.errors.append("Invalid/duplicate event choice")
				continue
			choices.append(str(choice.id))
			for key in ["title","description"]:
				if not choice.get(key) is String or str(choice[key]).is_empty():
					result.errors.append("Invalid night event text")
			_number(choice,"cost_incense",0,result.errors)
			_number(choice,"cost_names",0,result.errors)
			for effect in choice.effects:
				_effect(effect,config,profiles,result.errors)
	_validate_route(config,result.errors)
	if result.errors.is_empty():
		for field in ["title","initial_roster_note"]:
			config[field] = TranslationServer.translate(config[field])
		for node in config.nodes:
			_translate_text(node)
		for event in config.events.values():
			_translate_text(event)
			for choice in event.choices:
				_translate_text(choice)
		result.rules = config
	return result

static func _translate_text(row: Dictionary) -> void:
	for field in ["title","description"]:
		row[field] = TranslationServer.translate(row[field])

static func _read(path: String, errors: Array) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		errors.append("Invalid night JSON: " + path)
		return {}
	return parser.data

static func _number(data: Dictionary, key: String, minimum: float, errors: Array) -> void:
	if typeof(data.get(key)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(data[key])) or float(data[key]) < minimum:
		errors.append("Invalid night numeric field: " + key)

static func _effect(effect, config: Dictionary, profiles: Dictionary, errors: Array) -> void:
	if not effect is Dictionary or effect.get("kind") not in ["recruit","equipment","stats","build","recover","mutate"]:
		errors.append("Unknown night reward effect")
		return
	match effect.kind:
		"recruit":
			if not profiles.has(str(effect.get("unit_id",""))) or not effect.get("post") is String:
				errors.append("Unknown night recruitment unit/post")
			_number(effect,"count",1,errors)
		"mutate":
			if effect.get("form_id") not in ["G09","G12"]:
				errors.append("Invalid night mutation formula")
		"build":
			if not config.build_caps.has(str(effect.get("key",""))):
				errors.append("Unknown night build rule")
			if typeof(effect.get("value")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(effect.value)):
				errors.append("Invalid night build value")
		"stats", "equipment":
			for key in ["hp","defense"]:
				_number(effect,key,0,errors)
			if effect.kind == "stats":
				_number(effect,"attack",0,errors)
			elif not effect.get("equipment_id") is String:
				errors.append("Invalid night equipment id")
		"recover":
			for key in ["incense","names","heal"]:
				_number(effect,key,0,errors)

static func _validate_profiles(profiles: Dictionary, errors: Array) -> void:
	for id in profiles:
		var battle = profiles[id]
		if not battle is Dictionary or battle.get("id") != id:
			errors.append("Invalid night battle profile")
			continue
		_number(battle,"duration",120,errors)
		_number(battle,"victory_incense",0,errors)
		_number(battle,"victory_names",0,errors)
		if battle.get("duration",601) > 600:
			errors.append("Night battle exceeds ten minutes")
		var waves = battle.get("phase_waves",battle.get("waves"))
		if not waves is Array or waves.is_empty():
			errors.append("Night battle has no waves")
			continue
		var previous := -1.0
		for wave in waves:
			if not wave is Dictionary:
				errors.append("Invalid night wave")
				continue
			_number(wave,"at",0,errors)
			if float(wave.get("at",-1)) < previous or float(wave.get("at",601)) >= float(battle.duration):
				errors.append("Unordered/outside night wave")
			previous = float(wave.get("at",0))
			for key in wave:
				if key != "at":
					if key not in ["G01","G09","G12"]:
						errors.append("Unknown night wave unit")
					_number(wave,str(key),0,errors)
		if id == "boss" and (not battle.get("phases") is Array or battle.phases.size() < 2 or not battle.has("phase_waves")):
			errors.append("Night boss needs real phase waves")

static func _validate_route(config: Dictionary, errors: Array) -> void:
	if not config.get("nodes") is Array:
		errors.append("Night route missing nodes")
		return
	var nodes: Dictionary = {}
	for node in config.nodes:
		if not node is Dictionary or not node.get("id") is String or nodes.has(str(node.get("id",""))) or not node.get("next") is Array:
			errors.append("Invalid/duplicate night node")
			continue
		nodes[node.id] = node
		for key in ["title","description","route"]:
			if not node.get(key) is String or str(node[key]).is_empty():
				errors.append("Invalid night node text")
		_number(node,"depth",0,errors)
		if node.get("type") not in ["battle","boss","market","event","rest"]:
			errors.append("Unknown night node type")
		if node.get("type") in ["battle","boss"] and not preload("res://src/modes/Seat.gd").valid_objectives(node.get("objectives")):
			errors.append("Unknown/incomplete night seat objectives")
		if node.get("type") in ["battle","boss"] and not config.battle_profiles.has(str(node.get("profile_id",""))):
			errors.append("Unknown night battle profile reference")
		if node.get("type") == "event" and not config.events.has(str(node.get("event_id",""))):
			errors.append("Unknown night event reference")
	for id in nodes:
		for next in nodes[id].next:
			if not nodes.has(str(next)):
				errors.append("Broken night node edge")
	if not nodes.has(str(config.start_node)) or not errors.is_empty():
		errors.append("Invalid night route root")
		return
	var reached: Array[String] = []
	_walk(str(config.start_node),nodes,[],reached,errors)
	if reached.size() != nodes.size():
		errors.append("Unreachable night route node")

static func _walk(id: String, nodes: Dictionary, path: Array, reached: Array[String], errors: Array) -> void:
	if path.has(id):
		errors.append("Cyclic night route")
		return
	var route := path.duplicate()
	route.append(id)
	if not reached.has(id):
		reached.append(id)
	if nodes[id].next.is_empty():
		var types: Array[String] = []
		for step in route:
			if not types.has(str(nodes[step].type)):
				types.append(str(nodes[step].type))
		if not ("market" in types and "event" in types and "rest" in types and "battle" in types):
			errors.append("Each night route needs battle, market, event and rest")
		if route.size() < 8 or route.size() > 12 or nodes[id].type != "boss":
			errors.append("Night route must visit 8-12 nodes ending at a boss")
	else:
		for next in nodes[id].next:
			_walk(str(next),nodes,route,reached,errors)
