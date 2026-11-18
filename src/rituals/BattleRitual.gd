extends RefCounted
## Holds only live battle state for the selected ceremony.
const Catalog = preload("res://src/data/RitualCatalog.gd")
var _session: WeakRef
var row: Dictionary:
	get: return Catalog.row(id)
var id := "R01"
var rng := RandomNumberGenerator.new()
var ward_id := ""
var upper_occupation := 0.0
var opening_wave_queued := true

func _init(session: Node) -> void:
	_session = weakref(session)

func reset() -> void:
	id = "R01"
	ward_id = ""
	upper_occupation = 0.0
	opening_wave_queued = true

func configure(ritual_id: String, seed_text: String, first_battle: bool, ward_hp: float) -> bool:
	var chosen := Catalog.row(ritual_id)
	if chosen.is_empty():
		return false
	var session: Node = _session.get_ref()
	var sim: Node = session.simulation
	var flags: Array = chosen.flags
	if "bridge_reinforcements" in flags:
		var bridge_id := str(sim.world.layout.get("bridge_object",""))
		if bridge_id.is_empty() or not sim.world.has_node(bridge_id):
			return false
	if "protect_ward" in flags:
		var post: String = chosen.params.ward_post
		if not sim.world.can_deploy_at(post):
			return false
		var ward: Node2D = sim.spawn_human(str(chosen.params.ward_unit),post)
		if ward == null:
			return false
		ward_id = ward.instance_id
		ward.display_name = session.tr("P10_WARD_NAME")
		if ward_hp >= 0.0:
			ward.hp = minf(ward_hp,ward.max_hp)
		ward.sync_meta()
	id = str(chosen.id)
	rng.seed = (seed_text + ":" + id).hash()
	opening_wave_queued = not first_battle or not has_flag("early_nameless")
	if has_flag("bridge_reinforcements"):
		sim.tide.config.bridge_reinforcements = true
	# Keep the earlier growth test flags and the current battle's rules consistent.
	if session.growth.enabled:
		var flag: String = {"R03":"jizao","R05":"kaimian","R07":"jinsheng","R09":"hanshi","R11":"youshen"}.get(id,"")
		if not flag.is_empty():
			session.growth.state.ritual_flag = flag
	return true

func has_flag(flag: String) -> bool:
	return flag in row.get("flags",[])

func param(key: String, fallback: Variant) -> Variant:
	return row.get("params",{}).get(key,fallback)

func ward_status() -> Dictionary:
	if ward_id.is_empty():
		return {}
	var session: Node = _session.get_ref()
	var actor := ward()
	return {"id":str(param("ward_unit","")), "name":session.tr("P10_WARD_NAME"),
		"alive":is_instance_valid(actor) and not actor.dead and actor.hp > 0,
		"hp":actor.hp if is_instance_valid(actor) else 0.0,"max_hp":actor.max_hp if is_instance_valid(actor) else 0.0}

func ward() -> Node2D:
	if ward_id.is_empty():
		return null
	var sim: Node = _session.get_ref().simulation
	for unit in sim.humans + sim.targets + sim.corpses:
		if unit.instance_id == ward_id:
			return unit
	return null

func wards(unit: Node2D) -> bool:
	return not ward_id.is_empty() and unit.instance_id == ward_id

func advance(delta: float) -> String:
	if id == "R01":
		return ""
	var session: Node = _session.get_ref()
	match id:
		"R04":
			if not ward_status().get("alive",false):
				return "P10_END_WARD_LOST"
		"R10":
			var sim: Node = session.simulation
			var defended_floors := {}
			for unit in sim.humans:
				if not unit.dead and sim.world.is_upper_floor(unit.floor_id) and sim.world.inside_base(unit.position):
					defended_floors[unit.floor_id] = true
			var lost := false
			for unit in sim.targets:
				if not unit.dead and sim.world.is_upper_floor(unit.floor_id) and sim.world.inside_base(unit.position) and not defended_floors.has(unit.floor_id):
					lost = true
					break
			upper_occupation = upper_occupation + delta if lost else 0.0
			if upper_occupation >= float(param("upper_hold_seconds",6.0)):
				return "P10_END_UPPER_LOST"
		"R12":
			var before: float = session.names
			session.names = maxf(0.0,session.names - float(param("seep_names_per_second",0.0)) * delta)
			if before > 0 and session.names <= 0 and session.roster.enabled:
				session.roster.state.last_erased_by = ""
	return ""

func weighted_ghost(base_id: String) -> String:
	if base_id != "G01":
		return base_id
	var weights: Dictionary = param("wave_replacements",{})
	if weights.is_empty():
		return base_id
	var roll := rng.randf()
	for ghost in weights:
		roll -= float(weights[ghost])
		if roll < 0:
			return str(ghost)
	return base_id

func opening_wave(elapsed: float) -> Dictionary:
	if opening_wave_queued or elapsed < float(param("early_wave_seconds",0)):
		return {}
	opening_wave_queued = true
	return param("early_wave",{})

func water_drag_multiplier(unit: Node2D) -> float:
	return float(param("water_drag_multiplier",1.0)) if _water_ghost_in_alley(unit) else 1.0

func damage_multiplier(attacker: Node2D, kind: String) -> float:
	if kind in param("physical_kinds",[]):
		return float(param("physical_multiplier",1.0))
	if is_instance_valid(attacker) and _water_ghost_in_alley(attacker):
		return float(param("water_attack_multiplier",1.0))
	return 1.0

func _water_ghost_in_alley(unit: Node2D) -> bool:
	if not has_flag("water_tide") or unit.unit_id != param("water_ghost",""):
		return false
	var world: Node2D = unit.simulation.world
	return world.has_method("chunk_at") and world.chunk_at(unit.position,unit.floor_id) == param("water_chunk","")

func light_fear_duration(target: Node2D, duration: float) -> float:
	if target.roster.get("face_state","faced") == "faceless":
		return duration * float(param("faceless_fear_multiplier",1.0))
	return duration

func snapshot() -> Dictionary:
	if id == "R01":
		return {}
	return {"id":id,"rng_state":str(rng.state),"ward_id":ward_id,"upper_occupation":upper_occupation,
		"opening_wave_queued":opening_wave_queued}

static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if not value.get("id") is String or Catalog.row(value.id).is_empty():
		return false
	if not value.get("rng_state") is String or not value.rng_state.is_valid_int():
		return false
	if not value.get("ward_id") is String or (value.id == "R04") == value.ward_id.is_empty():
		return false
	var occupation: Variant = value.get("upper_occupation")
	return value.get("opening_wave_queued") is bool and typeof(occupation) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(occupation)) and float(occupation) >= 0

func restore(value: Dictionary) -> void:
	reset()
	if value.is_empty():
		return
	id = value.id
	rng.state = int(value.rng_state)
	ward_id = value.ward_id
	upper_occupation = float(value.upper_occupation)
	opening_wave_queued = value.opening_wave_queued
