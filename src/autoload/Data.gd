extends Node
const Table = preload("res://src/data/CsvTable.gd")
const CHARACTER_COLUMNS = ["id", "姓名", "所属", "定位", "专属技能", "特性", "标签", "生命", "攻击", "防御", "速度", "技能香耗", "数值备注"]
const GHOST_COLUMNS = ["id", "名称", "谱系", "定位", "专属技能", "特性", "标签", "典型变异或融契", "生命", "攻击", "防御", "速度", "变异花费", "数值备注"]
const TROOP_COLUMNS = ["id", "姓名", "定位", "生命", "攻击", "防御", "速度", "技能香耗", "备注"]
const SAMPLE_IDS = ["H01", "H09", "H17", "G01", "G09", "G12"]
var errors: Array[String] = []
var units: Dictionary = {}
var combat_profiles: Dictionary = {}
var skills: Dictionary = {}
var traits: Dictionary = {}
var tide_rules: Dictionary = {}
var battle_rules: Dictionary = {}
var night_rules: Dictionary = {}
var mode_rules: Dictionary = {}
var growth_rules: Dictionary = {}
var growth_templates: Dictionary = {}
var roster_rules: Dictionary = {}
var appearance_rules: Dictionary = {}
var ritual_rules: Dictionary = {}
var codex_store: RefCounted

func _ready() -> void:
	_load_strings()
	for spec in [["characters", CHARACTER_COLUMNS], ["ghosts", GHOST_COLUMNS], ["troops", TROOP_COLUMNS]]:
		var result: Dictionary = Table.read_table("res://data/units/%s.csv" % spec[0], PackedStringArray(spec[1]))
		for error in result.errors:
			errors.append(error)
		for id in result.rows:
			if units.has(id):
				errors.append("Duplicate cross-table id: " + id)
			units[id] = result.rows[id]
	for id in SAMPLE_IDS:
		if not units.has(id):
			errors.append("Missing required unit: " + id)
	units.make_read_only()
	var catalog: Dictionary = preload("res://src/data/CombatCatalog.gd").read_catalog("res://data/units/p2_combat.json", units)
	var growth_profiles: Dictionary = preload("res://src/data/CombatCatalog.gd").read_catalog("res://data/units/p7_combat.json", units)
	for section in ["profiles","skills","traits"]:
		catalog[section].merge(growth_profiles[section],false)
	for error in growth_profiles.errors:
		# The supplementary catalog deliberately inherits the required G0 identities.
		if not str(error).begins_with("Missing P2 combat profile:"):
			catalog.errors.append(error)
	combat_profiles = catalog.profiles
	skills = catalog.skills
	traits = catalog.traits
	for error in catalog.errors:
		errors.append(error)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/reference_gate_court.json"))
	var tide: Dictionary = preload("res://src/data/TideCatalog.gd").read_config("res://data/levels/p3_tide.json",layout)
	tide_rules = tide.config
	for error in tide.errors:
		errors.append(error)
	var battle: Dictionary = preload("res://src/data/BattleCatalog.gd").read_config("res://data/levels/p4_battle.json",combat_profiles)
	battle_rules = battle.rules
	for error in battle.errors:
		errors.append(error)
	var night: Dictionary = preload("res://src/data/NightCatalog.gd").read_config("res://data/nights/example_night.json",combat_profiles)
	night_rules = night.rules
	for error in night.errors:
		errors.append(error)
	var modes: Dictionary = preload("res://src/data/ModeCatalog.gd").read_config("res://data/modes/p6_modes.json",combat_profiles)
	mode_rules = modes.rules
	for error in modes.errors:
		errors.append(error)
	var growth_catalog: Dictionary = preload("res://src/data/GrowthCatalog.gd").read_config("res://data/items",units,combat_profiles)
	growth_rules = growth_catalog.rules
	for error in growth_catalog.errors:
		errors.append(error)
	if not growth_rules.is_empty():
		var growth_night = preload("res://src/growth/GrowthNight.gd")
		for error in growth_night.validate_config(growth_night.table()): errors.append(error)
		var templates = JSON.parse_string(FileAccess.get_file_as_string("res://data/modes/p7_growth_templates.json"))
		var template_errors: Array[String] = growth_night.validate_templates(templates)
		for error in template_errors: errors.append(error)
		if template_errors.is_empty(): growth_templates = templates
	var roster_catalog: Dictionary = preload("res://src/data/RosterCatalog.gd").read_config(units)
	roster_rules = roster_catalog.rules
	for error in roster_catalog.errors: errors.append(error)
	# Historical scenarios keep their original base profiles; P8 applies its explicit
	# visual scale and departure flags at configuration time on the same actor type.
	for id in roster_rules.profiles:
		if not combat_profiles.has(id): combat_profiles[id] = roster_rules.profiles[id].duplicate(true)
	for key in roster_rules.skills:
		if not skills.has(key): skills[key] = roster_rules.skills[key].duplicate(true)
	for key in roster_rules.traits:
		if not traits.has(key): traits[key] = roster_rules.traits[key].duplicate(true)
	if FileAccess.file_exists("res://data/units/p8_appearance.json"):
		var appearance = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/p8_appearance.json"))
		if appearance is Dictionary: appearance_rules = appearance
	var ceremonies: Dictionary = load("res://src/data/RitualCatalog.gd").read_table()
	ritual_rules = ceremonies.rows
	errors.append_array(ceremonies.errors)
	for id in roster_rules.profiles:
		var collection: String = "allowed_ghosts" if str(id).begins_with("G") else "allowed_humans"
		if mode_rules.get(collection) is Array and id not in mode_rules[collection]: mode_rules[collection].append(id)
	errors.append_array(preload("res://src/night/P10NightPlan.gd").validate_catalog())
	codex_store = preload("res://src/progression/CodexStore.gd").new()
	codex_store.load_save()
	for error in errors:
		push_error(error)

func get_unit(id: String) -> Dictionary:
	return units.get(id, {})

func _load_strings() -> void:
	var translation := Translation.new()
	translation.locale = "zh_CN"
	for path in ["res://data/strings/zh_CN.csv", "res://data/strings/p10_zh_CN.csv", "res://data/strings/p4_zh_CN.csv", "res://data/strings/p5_zh_CN.csv", "res://data/strings/p6_zh_CN.csv", "res://data/strings/p7_zh_CN.csv", "res://data/strings/p8_ui_zh_CN.csv", "res://data/strings/p9_zh_CN.csv", "res://data/strings/p9_battle_zh_CN.csv", "res://data/strings/p9_night_zh_CN.csv", "res://data/strings/p9_shell_zh_CN.csv", "res://data/strings/p10_ritual_zh_CN.csv", "res://data/strings/p10_stage_zh_CN.csv"]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("Cannot open localization table: " + path)
			continue
		file.get_csv_line()
		while not file.eof_reached():
			var row := file.get_csv_line()
			if row.size() == 2:
				translation.add_message(row[0], row[1])
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale("zh_CN")
