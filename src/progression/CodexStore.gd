extends RefCounted
## Four books unlock from battle events; there are no permanent combat-stat bonuses.
const Save = preload("res://src/night/NightSave.gd")
const Story = preload("res://src/night/NightStory.gd")
const BOOKS := ["humans","ghosts","items","customs"]
var path := ""
var autosave := false
var progress: Dictionary = {}
var failures: Array = []
var catalog: Dictionary = {}

func _init(save_path := "user://codex.json", save_automatically := true) -> void:
	path = save_path
	autosave = save_automatically
	for id in Data.units:
		if str(id).begins_with("T"): continue
		var row: Dictionary = Data.units[id]
		catalog[id] = {"id":str(id), "book":"humans" if str(id).begins_with("H") else "ghosts",
			"name":unit_text(id, "NAME", str(row.get("姓名", row.get("名称", id)))),
			"skill_text":unit_text(id, "SKILL", str(row.get("专属技能", ""))),
			"trait_text":unit_text(id, "TRAIT", str(row.get("特性", ""))), "source":row.duplicate(true)}
	for id in Data.growth_rules.get("items",{}):
		if not str(id).begins_with("I"): continue
		var item: Dictionary = Data.growth_rules.items[id]
		catalog[id] = {"id":str(id), "book":"items", "name":localized("P11_ITEM_%s_NAME" % id, str(item.get("name", id))),
			"skill_text":localized("P11_ITEM_%s_DETAIL" % id, str(item.get("description", ""))), "trait_text":"", "source":item.duplicate(true)}
	var customs = JSON.parse_string(FileAccess.get_file_as_string("res://data/codex/customs.json"))
	if customs is Dictionary:
		for item in customs.get("entries",[]):
			var id := str(item.id)
			var prefix := "P11_CUSTOM_%s" % id.to_upper()
			catalog[id] = {"id":id, "book":"customs", "name":localized(prefix + "_NAME", str(item.name)),
				"skill_text":localized(prefix + "_DETAIL", str(item.description)), "trait_text":"", "source":item.duplicate(true)}

static func localized(key: String, fallback: String) -> String:
	var translated := str(TranslationServer.translate(key))
	return fallback if translated == key else translated

static func unit_text(id: String, field: String, fallback: String) -> String:
	return localized("P11_UNIT_%s_%s" % [id, field], fallback)

func entry(id: String) -> Dictionary:
	if not catalog.has(id): return {}
	var item: Dictionary = catalog[id].duplicate(true)
	var stage := int(progress.get(id,0))
	item.stage = stage
	item.portrait_state = ["silhouette","line","color","named"][stage]
	if stage == 0: item.name = str(TranslationServer.translate("P9_CODEX_UNKNOWN"))
	if stage < 2:
		item.skill_text = str(TranslationServer.translate("P9_CODEX_UNREAD"))
		item.trait_text = item.skill_text
	if stage == 3:
		var epilogue: Dictionary = Story.rules().get("epilogues", {}).get(id, {})
		if epilogue.has("text_key"):
			item.epilogue = str(TranslationServer.translate(epilogue.text_key))
	return item

func entries(book: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in catalog:
		if catalog[id].book == book: rows.append(entry(str(id)))
	rows.sort_custom(func(a,b): return str(a.id) < str(b.id))
	return rows

func encounter(id: String) -> bool:
	return _advance(id,1)

func resolve(id: String, _reason := "defeated") -> bool:
	return _advance(id,2)

func list_name(id: String) -> bool:
	if int(progress.get(id,0)) < 2: return false
	return _advance(id,3)

func _advance(id: String, stage: int) -> bool:
	if not catalog.has(id) or int(progress.get(id,0)) >= stage: return false
	progress[id] = stage
	if autosave: save()
	return true

func record_failure(seed_text: String, killer_id: String, reason: String) -> bool:
	if seed_text.is_empty() or reason.is_empty() or not killer_id.is_empty() and not Data.units.has(killer_id): return false
	for record in failures:
		if record.seed == seed_text and record.reason == reason and record.killer_id == killer_id: return false
	failures.append({"seed":seed_text,"killer_id":killer_id,"reason":reason})
	if not killer_id.is_empty(): encounter(killer_id)
	if autosave: save()
	return true

func snapshot() -> Dictionary:
	return {"version":1,"progress":progress.duplicate(true),"failures":failures.duplicate(true)}

func restore(value: Dictionary) -> Dictionary:
	if not valid(value,catalog): return {"ok":false,"reason":"P8_CODEX_INVALID"}
	progress = value.progress.duplicate(true)
	failures = value.failures.duplicate(true)
	return {"ok":true,"reason":"P8_CODEX_RESTORED"}

func merge(value: Dictionary) -> Dictionary:
	if not valid(value,catalog): return {"ok":false,"reason":"P8_CODEX_INVALID"}
	for id in value.progress: progress[id] = maxi(int(progress.get(id,0)),int(value.progress[id]))
	for record in value.failures:
		if not record in failures: failures.append(record.duplicate(true))
	if autosave: return save()
	return {"ok":true,"reason":"P8_CODEX_RESTORED"}

func save() -> Dictionary:
	if path.is_empty(): return {"ok":false,"reason":"P8_CODEX_NO_PATH"}
	return Save.save(path,snapshot())

func load_save() -> Dictionary:
	var loaded := Save.load_save(path)
	if not loaded.ok: return loaded
	return restore(loaded.state)

static func valid(value: Variant, entries_by_id: Dictionary) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("progress") is Dictionary or not value.get("failures") is Array: return false
	for id in value.progress:
		var stage = value.progress[id]
		if not entries_by_id.has(id) or not typeof(stage) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(stage)) or float(stage) != floorf(float(stage)) or int(stage) < 0 or int(stage) > 3: return false
	for failure in value.failures:
		if not failure is Dictionary or not failure.get("seed") is String or not failure.get("reason") is String or not failure.get("killer_id") is String: return false
		if not str(failure.killer_id).is_empty() and not Data.units.has(failure.killer_id): return false
	return true
