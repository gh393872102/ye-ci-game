extends RefCounted

const Stage = preload("res://src/combat/P10Stage.gd")
const Table = preload("res://src/data/CsvTable.gd")
const BOSS_IDS := ["B01", "B02", "B03"]
const MODIFIER_IDS := ["N01", "N02", "N03"]
const MODIFIER_FIELDS := ["drain_per_second", "recovery_multiplier", "side_durability_ratio",
	"side_chunk_weight", "watch_probability", "watch_spawn_at"]

static var _bosses: Dictionary = {}
static var _modifiers: Dictionary = {}

static func bosses() -> Dictionary:
	if _bosses.is_empty():
		for id in BOSS_IDS:
			var row = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/bosses/%s.json" % id))
			if row is Dictionary and row.get("id") == id:
				_bosses[id] = row
	return _bosses

static func modifiers() -> Dictionary:
	if _modifiers.is_empty():
		var columns := PackedStringArray(["id", "name_key", "description_key"] + MODIFIER_FIELDS)
		var table := Table.read_table("res://data/rituals/nameless_modifiers.csv", columns)
		for id in table.rows:
			var row: Dictionary = table.rows[id].duplicate()
			for key in MODIFIER_FIELDS:
				row[key] = float(row[key])
			_modifiers[id] = row
	return _modifiers

static func valid(boss_id: Variant, modifier_ids: Variant) -> bool:
	if not boss_id is String or (not boss_id.is_empty() and not bosses().has(boss_id)):
		return false
	if not modifier_ids is Array or modifier_ids.size() > MODIFIER_IDS.size():
		return false
	var seen := {}
	for id in modifier_ids:
		if not id is String or id not in MODIFIER_IDS or not modifiers().has(id) or seen.has(id):
			return false
		seen[id] = true
	return true

static func required_chunks(boss_id: String, modifier_ids: Array) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(bosses().get(boss_id, {}).get("chunks", []))
	if "N02" in modifier_ids and "C02" not in ids:
		ids.append("C02")
	return ids

static func chunk_weights(modifier_ids: Array) -> Dictionary:
	return {"C02": float(modifiers()["N02"].side_chunk_weight)} if "N02" in modifier_ids else {}

static func get_stage(session: Node) -> Node2D:
	return session.simulation.get_node_or_null("P10Stage") if session != null and session.simulation != null else null

static func start(session: Node, boss_id: String, modifier_ids: Array, seed: String) -> bool:
	if not valid(boss_id, modifier_ids):
		return false
	if boss_id.is_empty() and modifier_ids.is_empty():
		clear(session)
		return true
	if not _valid_battle(session, boss_id, modifier_ids):
		return false
	var stage := _install(session, boss_id, modifier_ids, seed)
	stage.open()
	return true

static func capture(session: Node) -> Dictionary:
	var stage := get_stage(session)
	return stage.snapshot() if stage != null else {}

static func valid_snapshot(snapshot: Variant) -> bool:
	if not snapshot is Dictionary:
		return false
	if snapshot.is_empty():
		return true
	if not valid(snapshot.get("boss_id"), snapshot.get("modifier_ids")) or not snapshot.get("seed") is String:
		return false
	return Stage.valid_snapshot(snapshot, bosses().get(snapshot.boss_id, {}))

static func restore(session: Node, snapshot: Dictionary) -> bool:
	if not valid_snapshot(snapshot):
		return false
	if snapshot.is_empty():
		clear(session)
		return true
	var boss_id: String = snapshot.boss_id
	var modifier_ids: Array = snapshot.modifier_ids
	if not _valid_battle(session, boss_id, modifier_ids):
		return false
	var stage := _install(session, boss_id, modifier_ids, snapshot.seed)
	stage.resume(snapshot)
	return true

static func _valid_battle(session: Node, boss_id: String, modifier_ids: Array) -> bool:
	if (not boss_id.is_empty() or "N03" in modifier_ids) and not session.roster.enabled:
		return false
	var world: Node2D = session.simulation.world
	if "N02" in modifier_ids and not world.has_node("door_side"):
		return false
	for id in bosses().get(boss_id, {}).get("initial_doors", {}):
		if not world.has_node(str(id)):
			return false
	return true

static func clear(session: Node) -> void:
	var stage := get_stage(session)
	if stage != null:
		stage.detach()
		stage.free()
	if session.has_meta("p10_rekindle_multiplier"):
		session.remove_meta("p10_rekindle_multiplier")

static func _install(session: Node, boss_id: String, modifier_ids: Array, seed: String) -> Node2D:
	clear(session)
	var stage := Stage.new()
	stage.name = "P10Stage"
	var active_modifiers := {}
	for id in MODIFIER_IDS:
		if id in modifier_ids:
			active_modifiers[id] = modifiers()[id]
	session.simulation.add_child(stage)
	stage.setup(session, bosses().get(boss_id, {}), active_modifiers, seed)
	return stage
