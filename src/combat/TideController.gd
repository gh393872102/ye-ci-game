extends RefCounted
## Deterministic waves, floor/lane buckets and measured arrival. No player orders.
signal effect_emitted(kind: String, point: Vector2, detail: String)
const GhostAI = preload("res://src/ai/GhostBrain.gd")
var sim: Node2D
var config: Dictionary
var preset := ""
var elapsed := 0.0
var arrival := -1.0
var arrived_by := ""
var wave_index := 0
var pending: Array[String] = []
var leaders: Dictionary = {}
var buckets: Dictionary = {}
var effects: Array[Dictionary] = []
var milestones: Array[Dictionary] = []
var spawn_count := 0
var spawning_pending := false

func _init(simulation: Node2D) -> void:
	sim = simulation
	config = Data.tide_rules.duplicate(true)

func reset(name: String) -> void:
	preset = name
	elapsed = 0
	arrival = -1
	arrived_by = ""
	wave_index = 0
	spawn_count = 0
	pending.clear()
	leaders.clear()
	buckets.clear()
	effects.clear()
	milestones.clear()
	config.erase("chunk_source_used")
	config.erase("chunk_source_next")
	for door in sim.world.doors:
		door.max_durability = float(config.door_durability.get(door.name, door.max_durability))
		door.set_durability(door.max_durability)
	for object in sim.world.obstacles:
		if object.max_durability > 0:
			object.max_durability = float(object.get_meta("tide_max_durability", config.obstacle_durability))
			object.set_durability(object.max_durability)
	if name == "preset_empty_path":
		for human in sim.humans:
			human.attacks_enabled = false
			human.motion_enabled = false
		sim.world.set_all_doors_open(true)
		for object in sim.world.obstacles:
			object.set_occupied(false)
		var unit := spawn("G01", 3, 0)
		unit.attacks_enabled = false
	elif name == "preset_hold_g0":
		_schedule()
		_spawn_pending()

func speed(unit: Node2D) -> float:
	if preset == "preset_empty_path":
		return Rules.WALK_SPEED_REF
	if unit.unit_id == "G12":
		return float(config.large_speed)
	return clampf(config.speed_body_anchor + (unit.speed_stat - config.speed_stat_anchor) * config.speed_stat_step, Rules.WALK_SPEED_MIN, Rules.WALK_SPEED_MAX)

func spawn(id: String, lane: int, x: float) -> Node2D:
	if sim.targets.size() >= int(config.capacity) or (not id in ["G01", "G09", "G12"] and (sim.growth_engine()==null or not Data.combat_profiles.has(id) or not id.begins_with("G"))):
		return null
	var unit: Node2D = sim.Unit.new()
	sim.serial += 1
	unit.configure(id, "%s_tide_%d" % [id, sim.serial], sim)
	unit.lane_index = lane
	unit.position = Vector2(x, sim.world.floor_y(0) + config.lane_offsets[lane])
	unit.current_post = "ghost_main_path"
	unit.brain = GhostAI.new(sim, unit, self)
	unit.set_state("Advance")
	sim.add_child(unit)
	sim.targets.append(unit)
	if sim.growth_engine()!=null:sim.growth_engine().apply_starting_loadout(unit)
	if sim.roster_engine()!=null: sim.roster_engine().ensure(unit)
	sim.unit_spawned.emit(unit)
	spawn_count += 1
	sim._update_units()
	return unit

func visual(count: int) -> void:
	# Controlled visual fixture, clearly separate from source-origin time trials.
	for object in sim.world.obstacles:
		if object.position.x < Rules.HALL_X:
			object.set_occupied(false)
	for door in sim.world.doors:
		if door.position.x < Rules.HALL_X:
			door.receive_damage(door.max_durability)
	var columns := ceili(float(count) / 4)
	var front := Rules.HALL_X - 100
	var spacing := minf(92, 820.0 / maxf(1, columns - 1))
	for index in count:
		var lane := index % 4
		var column := index / 4
		var id := "G12" if index == 6 else ("G09" if index in [10, 18] else "G01")
		spawn(id, lane, front - column * spacing - lane * 13)
	# Human defense still runs its ordinary P2 retreat policy after lines are broken.

func _schedule() -> void:
	var ritual: RefCounted = sim.session.ritual if sim.session != null else null
	if ritual != null:
		var opening: Dictionary = ritual.opening_wave(elapsed)
		for id in opening:
			for count in int(opening[id]):
				# Preserve the order of actors carried into battle from the preceding stop.
				pending.append(str(id))
	while wave_index < config.waves.size() and config.waves[wave_index].at <= elapsed:
		var wave: Dictionary = config.waves[wave_index]
		var ids := ["G01", "G12", "G09"]
		for id in wave:
			if str(id).begins_with("G") and not ids.has(id) and Data.combat_profiles.has(id):
				ids.append(id)
		for id: String in ids:
			for count in int(wave.get(id, 0)):
				if not config.get("night_queue_cap", false) or sim.targets.size() + pending.size() < int(config.capacity):
					pending.append(ritual.weighted_ghost(id) if ritual != null else id)
		wave_index += 1

func _spawn_pending() -> void:
	if bridge_supply_cut():
		pending.clear()
		return
	for lane in 4:
		if pending.is_empty():
			break
		var free := true
		for unit in sim.targets:
			if unit.lane_index == lane and unit.floor_id == 0 and unit.position.x < config.spacing:
				free = false
		if free:
			spawning_pending = true
			var actor := spawn(pending[0], lane, 0)
			spawning_pending = false
			if actor != null:
				pending.pop_front()

func bridge_supply_cut() -> bool:
	if not bool(config.get("bridge_reinforcements", false)):
		return false
	var id: String = sim.world.layout.get("bridge_object", "")
	var bridge: Node2D = sim.world.get_node_or_null(id) if not id.is_empty() else null
	return bridge == null or bridge.durability <= 0

func _spawn_chunk_source() -> void:
	var source: Dictionary = sim.world.layout.get("chunk_source", {})
	if source.is_empty() or preset != "preset_hold_g0":
		return
	var used := int(config.get("chunk_source_used", 0))
	if used >= int(source.limit) or elapsed < float(config.get("chunk_source_next", source.first)):
		return
	var growth = sim.growth_engine()
	if growth != null and growth.state.seals.has(source.door):
		return
	var x := Rules.body_to_px(source.x)
	var lane := used % 4
	for unit in sim.targets:
		if unit.lane_index == lane and unit.floor_id == 0 and absf(unit.position.x - x) < float(config.spacing):
			return
	if spawn(str(config.get("supply_id",source.id)), lane, x) != null:
		config["chunk_source_used"] = used + 1
		config["chunk_source_next"] = elapsed + float(source.interval)
		effect("fissure_spawn", Vector2(x, sim.world.floor_y(0)), str(source.door))

func has_chunk_supply() -> bool:
	var source: Dictionary = sim.world.layout.get("chunk_source", {})
	return not source.is_empty() and int(config.get("chunk_source_used", 0)) < int(source.limit)

func before_step(delta: float) -> void:
	elapsed += delta
	if preset == "preset_hold_g0":
		_schedule()
	_spawn_pending()
	_spawn_chunk_source()
	leaders.clear()
	buckets.clear()
	for unit in sim.targets:
		if unit.dead or unit.lane_index < 0:
			continue
		var key := "%d:%d:%s" % [unit.floor_id,unit.lane_index,unit.brain.segment_key()]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(unit)
	for key in buckets:
		var lane: Array = buckets[key]
		lane.sort_custom(func(a,b): return a.position.x > b.position.x)
		for index in range(1,lane.size()):
			leaders[lane[index].instance_id] = lane[index - 1]
	for index in range(effects.size() - 1, -1, -1):
		effects[index].left -= delta
		if effects[index].left <= 0:
			effects.remove_at(index)

func after_step() -> void:
	if arrival >= 0:
		return
	var register_start := 104.0
	if sim.world.layout.has("chunk_ids"):
		for room in sim.world.layout.rooms:
			if room.id == "register":
				register_start = float(room.start)
				break
	for unit in sim.targets:
		# Room entry uses body's leading edge, on ground, never an upper-floor x alone.
		if not unit.dead and unit.floor_id == 0 and unit.position.x + unit.hit_rect().size.x / 2 >= Rules.body_to_px(register_start) and unit.position.y >= Rules.HORIZON_Y - Rules.WALK_BAND_DEPTH_PX:
			arrival = elapsed
			arrived_by = unit.unit_id
			milestones.append({"kind":"register_entry", "time":elapsed, "unit":unit.unit_id,"position":[unit.position.x,unit.position.y],"floor":unit.floor_id})
			return

func front_limit(unit: Node2D, spacing: float) -> float:
	var other = leaders.get(unit.instance_id)
	if not is_instance_valid(other) or other.dead:
		return INF
	return other.position.x - spacing

func door_bonus(unit: Node2D, door: Node2D) -> float:
	var count := 0
	for other in sim.floor_units.get(unit.floor_id, []):
		if other.side == "yegui" and other.unit_id == "G01" and not other.dead and other.attacks_enabled and absf(sim.barrier_left(door) - other.position.x) <= Rules.body_to_px(other.profile.range_body) and other.position.x <= door.position.x:
			count += 1
	var skill: Dictionary = Data.skills.yong_men
	return 1.0 + minf(skill.max_bonus, maxf(0,count - 1) * skill.per_ally)

func effect(kind: String, point: Vector2, detail: String) -> void:
	effects.append({"kind":kind,"point":point,"left":0.6})
	milestones.append({"kind":kind,"time":elapsed,"detail":detail})
	if milestones.size() > 200:
		milestones.pop_front()
	effect_emitted.emit(kind, point, detail)
