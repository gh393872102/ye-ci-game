extends RefCounted
## Local battle-level archives. No account, server or fabricated past input history.
const Save = preload("res://src/night/NightSave.gd")
const Record = preload("res://src/replay/BattleRecord.gd")
const DIRECTORY := "user://battle_replays"
const MAX_BYTES := 16000000
static var directory := DIRECTORY

static func store_record(record: Dictionary) -> Dictionary:
	var check := validate(record)
	if not check.ok:
		return check
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"ok":false,"reason":"P6_ARCHIVE_WRITE_FAILED"}
	var id := Record.digest({"metadata":record.metadata,"initial":record.initial,"actions":record.actions,"steps":record.steps})
	var answer := Save.save(directory + "/" + id + ".json",record)
	if not answer.ok:
		return {"ok":false,"reason":"P6_ARCHIVE_WRITE_FAILED"}
	return {"ok":true,"reason":"P6_ARCHIVED","id":id,"archive_id":id,"seed":record.metadata.seed,"label":record.metadata.get("label",record.metadata.seed)}

static func list_seed(seed: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if seed.is_empty() or not DirAccess.dir_exists_absolute(directory):
		return entries
	for filename in DirAccess.get_files_at(directory):
		if not filename.ends_with(".json"):
			continue
		var id := filename.trim_suffix(".json")
		var loaded := load_record(id)
		if not loaded.ok:
			continue
		var record: Dictionary = loaded.record
		if str(record.metadata.seed) == seed:
			entries.append({"id":id,"seed":seed,"node_id":record.metadata.get("node_id",""),"label":record.metadata.get("label",seed),"duration":record.duration,"complete":record.complete,"source":record.metadata.get("source",""),"mode":record.metadata.get("mode","")})
	entries.sort_custom(func(a,b): return str(a.node_id) + str(a.label) < str(b.node_id) + str(b.label))
	return entries

static func load_record(id: String) -> Dictionary:
	if not _valid_id(id):
		return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	var path := directory + "/" + id + ".json"
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"P6_ARCHIVE_MISSING"}
	if file.get_length() > MAX_BYTES:
		return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	file.close()
	var loaded := Save.load_save(path)
	if not loaded.ok:
		return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	var answer := validate(loaded.state)
	if not answer.ok:
		return answer
	return {"ok":true,"reason":"P6_ARCHIVE_READY","record":loaded.state,"id":id}

static func export_record(id: String, path: String) -> Dictionary:
	var loaded := load_record(id)
	if not loaded.ok:
		return loaded
	var answer := Save.save(path,loaded.record)
	return {"ok":answer.ok,"reason":"P6_ARCHIVE_EXPORTED" if answer.ok else "P6_ARCHIVE_WRITE_FAILED"}

static func validate(record: Dictionary) -> Dictionary:
	return _validate_rules(record, Record.rules_hash())

static func _validate_rules(record: Dictionary, expected_hash: String) -> Dictionary:
	if record.get("version") != 1 or not record.get("metadata") is Dictionary or not record.metadata.get("seed") is String or str(record.metadata.seed).is_empty():
		return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	if record.metadata.has("config") and not record.metadata.config is Dictionary: return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	for key in ["label","node_id","source","mode"]:
		if record.metadata.has(key) and not record.metadata[key] is String: return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	if not _valid_night_queue(record.metadata): return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	if record.get("engine") != Engine.get_version_info().string or record.get("rules_hash") != expected_hash:
		return {"ok":false,"reason":"P6_ARCHIVE_INCOMPATIBLE"}
	for key in ["initial","final"]:
		if not record.get(key) is Dictionary:
			return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	for key in ["steps","actions","key_events"]:
		if not record.get(key) is Array:
			return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	if record.steps.size() > 200000 or record.actions.size() > 20000 or not record.get("complete") is bool or not record.get("event_hash") is String or not _number(record.get("duration"),0,3600) or not _integer(record.get("director_used"),0,3) or not _integer(record.metadata.get("director_limit"),0,3):
		return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	for delta in record.steps:
		if typeof(delta) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(delta)) or delta <= 0 or delta > 0.1:
			return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	if exact_state(record).is_empty(): return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	var last := 0
	var directors := 0
	for index in record.actions.size():
		var action = record.actions[index]
		if not action is Dictionary or not action.get("arguments") is Dictionary or action.get("seat") not in ["","shouxiang","duoming"] or action.get("origin") not in ["player","ai","director"]:
			return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
		if not _integer(action.get("step"),last,record.steps.size()) or action.get("order") != index:
			return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
		if action.get("action") not in ["unit_skill","mark_target","purchase","deploy_at","cancel_purchase","upgrade","equip","start_ritual","repair","mutate","reinforce","pause","speed","equip_item","unequip_item","mutate_form","fuse","stamp_job","borrow_god","use_key"]:
			return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
		if action.origin == "director":
			directors += 1
			if action.action not in ["pause","repair","reinforce"]: return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
		if action.action == "pause" and (action.origin != "director" or action.seat != ""): return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
		if action.action not in ["pause","speed"] and action.seat == "": return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
		if action.action == "speed" and (action.origin != "player" or action.seat != "" or not _number(action.arguments.get("value"),1,2) or (float(action.arguments.get("value",0)) != 1.0 and float(action.arguments.get("value",0)) != 2.0)): return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
		var required: Array = {"unit_skill":["unit_id"],"mark_target":["target_id"],"purchase":["id"],"deploy_at":["post_id"],"upgrade":["unit_id"],"equip":["unit_id"],"start_ritual":["caster_id","target_id"],"repair":["door_id"],"mutate":["unit_id","form_id"],"equip_item":["unit_id","item_id"],"unequip_item":["unit_id","slot"],"mutate_form":["unit_id","form_id"],"fuse":["first_id","recipe_id"],"stamp_job":["unit_id","job_id"],"borrow_god":["unit_id"],"use_key":["unit_id"]}.get(action.action,[])
		for key in required:
			if not action.arguments.get(key) is String or action.arguments[key].is_empty(): return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
		if action.arguments.has("slot_index") and not _integer(action.arguments.slot_index,0,1): return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
		if action.action not in ["pause","speed"] and action.action not in preload("res://src/modes/Seat.gd").commands(str(action.seat)): return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
		last = int(action.step)
	if directors != int(record.director_used) or directors > int(record.metadata.director_limit): return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	if Record.digest(record.key_events) != record.event_hash:
		return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	return {"ok":true,"reason":"P6_ARCHIVE_READY"}

static func _valid_id(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _integer(value: Variant, minimum: float, maximum: float) -> bool:
	return _number(value,minimum,maximum) and float(value) == floorf(float(value))

static func validate_checkpoint(value: Variant, prior_rules := "") -> Dictionary:
	if not value is Dictionary: return {"ok":false,"reason":"P6_ARCHIVE_INVALID"}
	var probe: Dictionary = value.duplicate(true)
	probe.final = {}
	probe.key_events = []
	probe.event_hash = Record.digest([])
	probe.complete = false
	probe.duration = 0.0
	probe.director_used = 0
	if probe.get("actions") is Array:
		for action in probe.actions:
			if action is Dictionary and action.get("origin") == "director": probe.director_used += 1
	return _validate_rules(probe, prior_rules) if not prior_rules.is_empty() else validate(probe)

static func exact_state(record: Dictionary) -> Dictionary:
	# bytes_to_var deliberately excludes objects. JSON keeps a readable mirror;
	# exact binary numeric values avoid decimal round-off at combat cooldown edges.
	for key in ["initial_exact","steps_exact"]:
		if not record.get(key) is String or record[key].is_empty() or record[key].length() > MAX_BYTES: return {}
	var initial = bytes_to_var(Marshalls.base64_to_raw(record.initial_exact))
	var steps = bytes_to_var(Marshalls.base64_to_raw(record.steps_exact))
	if not initial is Dictionary or not steps is Array or steps.size() != record.steps.size(): return {}
	if Record.digest(initial) != Record.digest(record.initial): return {}
	for index in steps.size():
		if not _number(steps[index],0.000001,0.1) or absf(float(steps[index]) - float(record.steps[index])) > 0.000000000000001: return {}
	return {"initial":initial,"steps":steps}

static func _valid_night_queue(metadata: Dictionary) -> bool:
	if not metadata.has("night_queue") and not metadata.has("night_queue_exact"): return true
	if not metadata.get("night_queue") is Array or not metadata.get("night_queue_exact") is String: return false
	var queue = bytes_to_var(Marshalls.base64_to_raw(metadata.night_queue_exact))
	if not queue is Array or queue.size() > 120 or Record.digest(queue) != Record.digest(metadata.night_queue): return false
	for spec in queue:
		if not spec is Dictionary or not Data.combat_profiles.has(str(spec.get("id",""))) or not str(spec.get("id","")).begins_with("G"): return false
		if spec.has("growth") and (not spec.growth is Dictionary or not preload("res://src/growth/GrowthEngine.gd").valid_unit_growth(spec.growth)): return false
		if spec.has("roster") and not preload("res://src/roster/RosterEngine.gd").valid_unit_state(spec.roster): return false
		if spec.has("profile") and not preload("res://src/night/BattleSnapshot.gd").valid_profile(spec.profile,str(spec.id)): return false
		for key in ["uid","post","equipment_id"]:
			if not spec.get(key) is String: return false
		for key in ["hp","max_hp","attack","defense","upgrade_level","mutation_count"]:
			if not _number(spec.get(key),0,100000): return false
	return true
