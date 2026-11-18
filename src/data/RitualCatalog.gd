extends RefCounted
## P10 ceremony rules are shared by the night, observation, and combat.
const Table = preload("res://src/data/CsvTable.gd")
const PATH := "res://data/rituals/rituals.csv"
const FLAGS := ["","water_tide","ground_fire","protect_ward","reveal_faces","bridge_reinforcements","quiet_backlash","early_nameless","forbid_fire","upper_failure_line","risky_borrow","register_seep"]
const POSITIVE := ["water_attack_multiplier","water_drag_multiplier","purified_names","incense_regen_multiplier",
	"fire_seconds","fire_radius_body","fire_damage_per_second","faceless_fear_multiplier","sound_reveal_seconds",
	"ritual_duration_multiplier","early_wave_seconds","physical_multiplier","seal_multiplier","upper_hold_seconds",
	"borrow_incense","seep_names_per_second"]
const TEXT := ["water_ghost","water_chunk","friendly_fire_exemption","ward_unit","ward_post"]
const LISTS := ["loud_units","fire_units","fire_kinds","physical_kinds"]

static func read_table() -> Dictionary:
	var columns := PackedStringArray(["id","title","description","flags","params","chunk_weights","reward_weights","required_chunks","boss_id"])
	var loaded := Table.read_table(PATH,columns)
	var errors: Array[String] = loaded.errors
	var rows := {}
	for index in range(1,13):
		var id := "R%02d" % index
		var raw: Dictionary = loaded.rows.get(id,{})
		if raw.is_empty():
			errors.append("Missing P10 ritual: " + id)
			continue
		var row := raw.duplicate()
		for column in ["flags","params","chunk_weights","reward_weights","required_chunks"]:
			row[column] = JSON.parse_string(raw[column])
		var flags: Array = [] if index == 1 else [FLAGS[index-1]]
		if row.title.is_empty() or row.description.is_empty() or row.flags != flags or not _valid_params(row.params,index):
			errors.append("Invalid P10 ritual rules: " + id)
			continue
		if not _valid_weights(row.chunk_weights) or not _valid_weights(row.reward_weights) or not _valid_list(row.required_chunks):
			errors.append("Invalid P10 ritual selection: " + id)
			continue
		var chunk_ids: Array = row.chunk_weights.keys() + row.required_chunks
		if chunk_ids.any(func(key): return not _numbered_id(key,"C",12)) or row.boss_id != ("B03" if index == 12 else ""):
			errors.append("Invalid P10 ritual stage: " + id)
			continue
		row.title = TranslationServer.translate(row.title)
		row.description = TranslationServer.translate(row.description)
		rows[id] = row
	if loaded.rows.size() != 12:
		errors.append("Expected exactly R01 through R12")
	return {"rows":rows,"errors":errors}

static func _valid_params(params: Variant, index: int) -> bool:
	if not params is Dictionary:
		return false
	var required: Array = [
		[], ["water_ghost","water_chunk","water_attack_multiplier","water_drag_multiplier","purified_names","wave_replacements"],
		["incense_regen_multiplier","fire_seconds","fire_radius_body","fire_damage_per_second","friendly_fire_exemption"],
		["ward_unit","ward_post"], ["faceless_fear_multiplier"], [], ["sound_reveal_seconds","loud_units"],
		["ritual_duration_multiplier","early_wave_seconds","early_wave"],
		["incense_regen_multiplier","physical_multiplier","seal_multiplier","fire_units","fire_kinds","physical_kinds"],
		["upper_hold_seconds","wave_replacements"], ["borrow_incense","borrow_failure_rate","event_weights"], ["seep_names_per_second"]
	][index-1]
	if params.size() != required.size():
		return false
	for key in required:
		var value: Variant = params.get(key)
		if key in POSITIVE and not _positive(value):
			return false
		if key in TEXT and (not value is String or value.is_empty()):
			return false
		if key in LISTS and (not _valid_list(value) or value.is_empty()):
			return false
		match key:
			"borrow_failure_rate":
				if not _positive(value) or float(value) >= 1.0: return false
			"wave_replacements","early_wave","event_weights":
				if not _valid_weights(value) or value.is_empty(): return false
				if key != "event_weights" and value.keys().any(func(id): return not _numbered_id(id,"G",32)): return false
				if key == "early_wave" and value.values().any(func(count): return floorf(float(count)) != float(count)): return false
				if key == "wave_replacements":
					var total := 0.0
					for weight in value.values(): total += float(weight)
					if total >= 1.0: return false
	return true

static func _numbered_id(value: Variant, prefix: String, maximum: int) -> bool:
	if not value is String or value.length() != 3 or not value.begins_with(prefix):
		return false
	for number in range(1,maximum+1):
		if value == "%s%02d" % [prefix,number]: return true
	return false

static func _positive(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0

static func _valid_weights(value: Variant) -> bool:
	return value is Dictionary and not value.keys().any(func(key): return not key is String or key.is_empty()) and value.values().all(_positive)

static func _valid_list(value: Variant) -> bool:
	return value is Array and value.all(func(entry): return entry is String and not entry.is_empty())

static func normalize(id: String) -> String:
	return "R01" if id == "example_incense" else id

static func row(id: String) -> Dictionary:
	return Data.ritual_rules.get(normalize(id),{})

static func reward_weight(id: String, card: Dictionary) -> float:
	var weights: Dictionary = row(id).get("reward_weights",{})
	var effect: Dictionary = card.get("effect",{})
	var subject := str(effect.get("unit_id",effect.get("id",card.get("id",""))))
	return float(card.get("weight",1)) * float(weights.get(subject,1))

static func event_weight(id: String, event_id: String) -> float:
	return float(row(id).get("params",{}).get("event_weights",{}).get(event_id,1))

static func add_ritual_rewards(rewards: Dictionary, id: String) -> void:
	# Theme-specific units also need an eligible card when the historical pool has none.
	var available := {}
	for card in rewards.values():
		if card.effect.kind == "recruit": available[str(card.effect.unit_id)] = true
	for unit_id: String in row(id).get("reward_weights",{}):
		if available.has(unit_id) or not Data.combat_profiles.has(unit_id):
			continue
		var source: Dictionary = Data.get_unit(unit_id)
		var ghost := unit_id.begins_with("G")
		var post: String = preload("res://src/growth/GrowthNight.gd").legal_post(unit_id,"")
		var price: float = float(Data.battle_rules.purchases.get(unit_id,source.get("变异花费",0)))
		if price <= 0: price = float(source.get("技能香耗",0)) + 4.0
		var card_id := "p10_recruit_" + unit_id
		rewards[card_id] = {
			"id":card_id, "title":TranslationServer.translate("P10_RECRUIT_TITLE") % str(source.get("姓名",source.get("名称",unit_id))),
			"description":str(TranslationServer.translate("P10_RECRUIT_DETAIL")),
			"category":"roster", "mode":"duoming" if ghost else "shouxiang", "weight":3.0,
			"cost":price, "requires_target":false, "effect":{"kind":"recruit","unit_id":unit_id,"count":1,"post":post},
		}
