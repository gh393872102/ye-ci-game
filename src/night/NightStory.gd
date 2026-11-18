extends RefCounted
## Narrative progress travels through the single night slot, independently of combat upgrades.
const PATH := "res://data/story/endings.json"
const ENDING_IDS := ["E01", "E02", "E03"]
const ACTION_COUNTS := ["exorcise_count", "slay_exorcisable_count", "borrow_god_count", "empty_god_count", "release_or_recruit_count"]
const REGISTER_LOST := ["P4_END_REGISTER_CAPTURED", "P4_END_REGISTER_EXTINGUISHED", "P4_END_NAMES_DRAINED"]
static var _rules: Dictionary = {}

static func rules() -> Dictionary:
	if _rules.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if _valid_rules(value):
			_rules = value
	return _rules

static func start(names: float, previous: Dictionary = {}) -> Dictionary:
	var flags: Dictionary = previous.get("flags", {}).duplicate(true)
	for key in ACTION_COUNTS + ["register_held", "register_checked"]:
		if not flags.has(key):
			flags[key] = 0
	flags.renown = names
	flags.renown_peak = maxf(names, float(flags.get("renown_peak", 0)))
	flags.finished_seize_night = bool(flags.get("finished_seize_night", false))
	return {"version":1, "flags":flags, "ending":"", "self_listing":{}}

static func act(depth: int) -> Dictionary:
	var acts: Array = rules().get("acts", [])
	for index in range(acts.size() - 1, -1, -1):
		if depth >= int(acts[index].from_depth):
			return acts[index]
	return {}

static func note_names(story: Dictionary, names: float, peak: float) -> void:
	story.flags.renown = names
	story.flags.renown_peak = maxf(float(story.flags.renown_peak), maxf(peak, names))

static func record_battle(story: Dictionary, battle: Dictionary, mode: String, names: float) -> void:
	for key in ACTION_COUNTS:
		story.flags[key] = int(story.flags[key]) + int(battle[key])
	if mode == "shouxiang":
		story.flags.register_checked = int(story.flags.register_checked) + 1
		story.flags.register_held = int(story.flags.register_held) + int(bool(battle.register_held))
		note_names(story, names, float(battle.renown_peak))

static func select_ending(story: Dictionary) -> String:
	if not story.self_listing.is_empty():
		return "E03"
	for id in rules().automatic_order:
		if qualifies(id, story.flags):
			return id
	return ""

static func qualifies(id: String, flags: Dictionary) -> bool:
	var rule: Dictionary = rules().endings[id]
	var names := float(flags.renown)
	match id:
		"E01":
			return (names >= float(rule.renown_min) or float(flags.renown_peak) >= float(rule.renown_peak_min)) \
				and int(flags.exorcise_count) >= int(rule.exorcise_min) \
				and float(flags.exorcise_count) >= float(rule.exorcise_to_slay_ratio) * int(flags.slay_exorcisable_count) \
				and (int(flags.empty_god_count) <= int(rule.empty_god_max) or int(flags.borrow_god_count) <= int(rule.or_borrow_max))
		"E02":
			return names >= float(rule.renown_min) and names <= float(rule.renown_max) \
				and flags.finished_seize_night == rule.finished_seize_night \
				and int(flags.release_or_recruit_count) >= int(rule.release_or_recruit_min)
	return false

static func valid(story: Variant) -> bool:
	if not story is Dictionary or story.get("version") != 1 or not story.get("flags") is Dictionary:
		return false
	if story.get("ending") not in [""] + ENDING_IDS or not story.get("self_listing") is Dictionary:
		return false
	var flags: Dictionary = story.flags
	if not _valid_counts(flags) or not _integer(flags.get("register_held")) or not _integer(flags.get("register_checked")):
		return false
	if int(flags.register_held) > int(flags.register_checked) or not flags.get("finished_seize_night") is bool:
		return false
	if not _number(flags.get("renown")) or not _number(flags.get("renown_peak")) or float(flags.renown_peak) < float(flags.renown):
		return false
	var listing: Dictionary = story.self_listing
	if listing.is_empty():
		return story.ending != "E03"
	return listing.get("unit") is String and listing.get("uid") is String and not str(listing.uid).is_empty() \
		and _number(listing.get("names_paid"), 0.001) and _number(listing.get("max_hp_after"), 1) \
		and _number(listing.get("max_hp_before"), float(listing.max_hp_after) + 0.001)

static func valid_battle(battle: Variant, seed: String, attempt: int, mode: String, reason: String, names: float) -> bool:
	if not battle is Dictionary or battle.get("seed") != seed or battle.get("attempt") != attempt:
		return false
	if not _valid_counts(battle) or not battle.get("register_held") is bool:
		return false
	if not _number(battle.get("renown_peak"), names):
		return false
	if mode == "duoming":
		return not battle.register_held and ACTION_COUNTS.all(func(key): return battle[key] == 0)
	return not battle.register_held or (reason not in REGISTER_LOST and names > 0)

static func _valid_counts(row: Dictionary) -> bool:
	return ACTION_COUNTS.all(func(key): return _integer(row.get(key))) and row.empty_god_count <= row.borrow_god_count

static func _valid_rules(value: Variant) -> bool:
	if not value is Dictionary or not value.get("endings") is Dictionary or not value.get("acts") is Array or not value.get("epilogues") is Dictionary:
		return false
	if value.acts.size() != 3 or value.get("automatic_order") not in [["E01", "E02"], ["E02", "E01"]] or value.endings.size() != ENDING_IDS.size():
		return false
	var recruits: Variant = value.get("battle_recruits")
	if not recruits is Dictionary or not recruits.has_all(["H10", "H13"]) or not recruits.values().all(func(price): return _number(price, 0.01)):
		return false
	var previous := -1
	for act in value.acts:
		if not act is Dictionary or not _integer(act.get("from_depth"), previous + 1) or not _strings_present(act, ["title_key", "shouxiang_key", "duoming_key"]):
			return false
		previous = int(act.from_depth)
	if int(value.acts[0].from_depth) != 0:
		return false
	for id in ENDING_IDS:
		if not value.endings.get(id) is Dictionary or not _strings_present(value.endings[id], ["title_key", "text_key"]):
			return false
	var restore: Dictionary = value.endings.E01
	if not ["renown_min", "renown_peak_min", "exorcise_min", "exorcise_to_slay_ratio", "empty_god_max", "or_borrow_max"].all(func(key): return _number(restore.get(key))):
		return false
	var release: Dictionary = value.endings.E02
	if not _number(release.get("renown_min"), 0.001) or not _number(release.get("renown_max"), float(release.renown_min)) or not _integer(release.get("release_or_recruit_min"), 1) or release.get("finished_seize_night") != true:
		return false
	var listing: Dictionary = value.endings.E03
	if not listing.get("ritual") is String or not listing.get("unit") is String or not _number(listing.get("names_cost"), 0.001) or not _number(listing.get("max_hp_ratio"), 0.001) or float(listing.max_hp_ratio) >= 1.0:
		return false
	for epilogue in value.epilogues.values():
		if not epilogue is Dictionary or not _strings_present(epilogue, ["text_key"]):
			return false
		if epilogue.has("ending") and epilogue.ending not in ENDING_IDS:
			return false
	return true

static func _strings_present(row: Dictionary, keys: Array) -> bool:
	for key in keys:
		var value: Variant = row.get(key)
		if not value is String or value.is_empty() or str(TranslationServer.translate(value)) == value:
			return false
	return true

static func _number(value: Variant, minimum := 0.0) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum

static func _integer(value: Variant, minimum := 0) -> bool:
	return _number(value, float(minimum)) and floorf(float(value)) == float(value)
