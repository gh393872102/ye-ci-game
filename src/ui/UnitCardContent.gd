extends RefCounted
## Shared display values. Codex unlocks decide which of these fields are visible.
const Codex = preload("res://src/progression/CodexStore.gd")

static func format(unit_id: String, live_unit: Node2D = null) -> Dictionary:
	var row: Dictionary = Data.get_unit(unit_id)
	if row.is_empty(): return {}
	var name := Codex.unit_text(unit_id, "NAME", str(row.get("姓名", row.get("名称", unit_id))))
	var hp := float(row["生命"])
	var max_hp := hp
	var attack := float(row["攻击"])
	var defense := float(row["防御"])
	var speed := int(row["速度"])
	var skill := Codex.unit_text(unit_id, "SKILL", str(row.get("专属技能", "")))
	var trait_text := Codex.unit_text(unit_id, "TRAIT", str(row.get("特性", "")))
	var cost := int(row.get("技能香耗", 0))
	var tags: PackedStringArray = Codex.unit_text(unit_id, "TAGS", str(row.get("标签", ""))).split(";", false)
	var affiliation := Codex.unit_text(unit_id, "AFFILIATION", str(row.get("所属", row.get("谱系", TranslationServer.translate("P9_TROOP")))))
	var role := Codex.unit_text(unit_id, "ROLE", str(row.get("定位", "")))
	var side := "yegui" if unit_id.begins_with("G") else "xianghuo"
	var state := ""
	var slots := {}
	var legacy_gear := ""
	if is_instance_valid(live_unit):
		if live_unit.display_name != row.get("姓名", row.get("名称", unit_id)):
			name = live_unit.display_name
		hp = live_unit.hp
		max_hp = live_unit.max_hp
		attack = live_unit.attack
		defense = live_unit.defense
		speed = live_unit.speed_stat
		if live_unit.skill_text != row.get("专属技能", ""):
			skill = live_unit.skill_text
		if live_unit.trait_text != row.get("特性", ""):
			trait_text = live_unit.trait_text
		cost = live_unit.skill_cost
		if live_unit.tags != str(row.get("标签", "")).split(";", false):
			tags = live_unit.tags
		side = live_unit.side
		slots = live_unit.growth.get("slots", {})
		legacy_gear = live_unit.equipment_id
		state = TranslationServer.translate("P4_CARD_STATE") % [TranslationServer.translate(live_unit.current_post.to_upper()), live_unit.floor_id, TranslationServer.translate(live_unit.ai_state)]
	return {
		"title": TranslationServer.translate("P9_CARD_TITLE") % [name, unit_id],
		"affiliation": TranslationServer.translate("P9_CARD_ROLE") % [affiliation, role],
		"stats": TranslationServer.translate("P4_CARD_STATS") % [hp, max_hp, attack, defense, speed],
		"skill": TranslationServer.translate("P4_CARD_SKILL") % [cost, skill if skill else TranslationServer.translate("P4_NO_SKILL")],
		"trait": TranslationServer.translate("P4_CARD_TRAIT") % (trait_text if trait_text else TranslationServer.translate("P4_NO_TRAIT")),
		"tags": TranslationServer.translate("P4_CARD_TAGS") % [TranslationServer.translate("P4_SEAT_DUOMING" if side == "yegui" else "P4_SEAT_SHOUXIANG"), " / ".join(tags)],
		"slots": slot_text(slots, legacy_gear),
		"state": state
	}

static func slot_text(slots: Dictionary, legacy_gear := "") -> String:
	var arts: Array = slots.get("arts", ["", ""])
	var items: Array = [slots.get("censer", ""), arts[0], arts[1], slots.get("nameplate", "")]
	var names: Array[String] = []
	for id in items:
		names.append(str(Data.growth_rules.items.get(id, {}).get("name", id)) if id else str(TranslationServer.translate("P4_EMPTY")))
	if slots.is_empty() and not legacy_gear.is_empty():
		names[0] = TranslationServer.translate("P4_GEAR_NAME")
	return TranslationServer.translate("P7_FOUR_SLOTS") % names
