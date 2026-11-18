extends Node2D
signal unit_spawned(unit: Node2D)
signal unit_fallen(unit: Node2D)
signal unit_allegiance_changed(unit: Node2D, old_side: String, new_side: String)
signal step_completed(delta: float)
signal event_recorded(kind: String, unit: Node2D, detail: String)
signal door_damaged(door: Node2D, previous_durability: float)
## Shared human/ghost combat; legacy targets remain isolated in P2 regression mode.
const Unit = preload("res://src/units/CombatUnit.gd")
const HumanAI = preload("res://src/ai/HumanBrain.gd")
const TargetAI = preload("res://src/ai/DebugTargetBrain.gd")
const Shot = preload("res://src/combat/Projectile.gd")
const Formula = preload("res://src/combat/Formula.gd")
const Effects = preload("res://scenes/combat/vfx/BattleEffects.tscn")
var world: Node2D
var humans: Array[Node2D] = []
var targets: Array[Node2D] = []
var projectiles: Array[Node2D] = []
var corpses: Array[Node2D] = []
var floor_units: Dictionary = {}
var floor_defenders: Dictionary = {}
var defense_data: Dictionary
var events: Array[Dictionary] = []
var damage_log: Array[Dictionary] = []
var traces: Array[Dictionary] = []
var passage_timers: Dictionary = {}
var simulation_time := 0.0
var step_index := 0
var serial := 0
var debug_rays := false
var auto_targets := true
var tide_enabled := true
var tide: RefCounted
var session: Node = null
var vfx: Node2D

func _ready() -> void:
	reload_defense_layout()
	if tide_enabled:
		tide = preload("res://src/combat/TideController.gd").new(self)
	vfx = Effects.instantiate()
	vfx.simulation = self
	add_child(vfx)
	reset_preset()

func reload_defense_layout() -> void:
	defense_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/p2_defense.json"))
	for post in world.layout.posts:
		if post.has("retreat"):
			defense_data.posts[post.id] = post.retreat

func _physics_process(_delta: float) -> void:
	advance(Clock.delta)

func reset_preset(preset := "preset_hold_g0") -> void:
	world.set_meta("broken_paths",[])
	simulation_time = 0
	step_index = 0
	for object in humans + targets + projectiles + corpses:
		object.free()
	humans.clear()
	targets.clear()
	projectiles.clear()
	corpses.clear()
	passage_timers.clear()
	events.clear()
	damage_log.clear()
	traces.clear()
	vfx.reset()
	for door in world.doors:
		door.destroyed = false
		door.set_durability(door.max_durability)
		door.set_open(door.starts_open)
	for object in world.obstacles:
		object.set_durability(object.max_durability)
		var occupied := true
		for spec in world.layout.obstacle_slots:
			if spec.id == object.name:
				occupied = spec.occupied
		object.set_occupied(occupied)
	for spec in defense_data.preset:
		spawn_human(spec.id, spec.post)
	if tide_enabled:
		tide.reset(preset)
	elif auto_targets:
		spawn_source_targets(12)
	_update_units()
	queue_redraw()

func spawn_human(id: String, post_id: String) -> Node2D:
	if not Data.combat_profiles.has(id) or not world.can_deploy_at(post_id):
		return null
	var unit := Unit.new()
	serial += 1
	unit.configure(id, "%s_%d" % [id, serial], self)
	unit.current_post = post_id
	unit.floor_id = int(world.get_node(post_id).get_meta("floor_id"))
	unit.position = world.get_node(post_id).position
	unit.brain = HumanAI.new(self, unit)
	unit.sync_meta()
	add_child(unit)
	humans.append(unit)
	if growth_engine()!=null:growth_engine().apply_starting_loadout(unit)
	if roster_engine()!=null: roster_engine().ensure(unit)
	unit_spawned.emit(unit)
	_update_units()
	return unit

func spawn_target(point: Vector2) -> Node2D:
	if targets.size() >= Rules.DEBUG_TARGET_LIMIT or point.x < 0 or point.x > Rules.REFERENCE_MAP_WIDTH_PX:
		return null
	var unit := Unit.new()
	serial += 1
	unit.configure("G01", "debug_target_%d" % serial, self)
	unit.current_post = "ghost_main_path"
	unit.position = point
	unit.brain = TargetAI.new(self, unit)
	unit.set_state("Advance")
	add_child(unit)
	targets.append(unit)
	if growth_engine()!=null:growth_engine().apply_starting_loadout(unit)
	_update_units()
	return unit

func spawn_source_targets(count: int) -> void:
	var remaining := mini(count, Rules.DEBUG_TARGET_LIMIT - targets.size())
	for slot in 24:
		if remaining <= 0:
			break
		var point := Vector2(Rules.body_to_px(slot * 2), Rules.HORIZON_Y)
		var free := true
		for target in targets:
			if target.floor_id == 0 and target.position.distance_to(point) < Rules.TARGET_SPACING_PX:
				free = false
		if free:
			spawn_target(point)
			remaining -= 1

func spawn_exception_probe() -> Node2D:
	for unit in humans:
		if unit.get_meta("exception_probe", false):
			return unit
	var probe := spawn_human("T01", "post_gate_inner")
	probe.display_name = tr("AI_PROBE_NAME")
	probe.set_meta("exception_probe", true)
	probe.may_briefly_leave_base = true
	probe.return_after = 1.2
	probe.attacks_enabled = false
	world.get_node("door_outer").set_open(true)
	probe.brain.excursion.request(self, probe, Vector2(Rules.BASE_START_X - 120, Rules.HORIZON_Y), true)
	return probe

func clear_targets() -> void:
	for object in targets + projectiles:
		object.free()
	targets.clear()
	projectiles.clear()
	for human in humans:
		human.brain.channel.cancel("CHANNEL_CANCELLED")
	_update_units()

func advance(delta: float) -> void:
	if delta <= 0 or (session != null and session.active and not session.running):
		return
	if session != null and session.active:
		session.advance(delta)
	var growth = growth_engine()
	var roster = roster_engine()
	if roster != null: roster.advance(delta)
	if growth != null:growth.advance(delta)
	simulation_time += delta
	if tide_enabled:
		tide.before_step(delta)
	var has_hazards: bool = not world.layout.get("hazards", []).is_empty()
	for unit in humans + targets:
		unit.attack_left = maxf(0, unit.attack_left - delta)
		unit.hit_flash = maxf(0, unit.hit_flash - delta)
		if not unit.dead and (growth == null or growth.can_act(unit)) and (roster == null or roster.can_act(unit)):
			var before: Vector2 = unit.position
			var floor_before: int = unit.floor_id
			if roster == null or not roster.advance_actor(unit,delta): unit.brain.advance(delta)
			if has_hazards:
				world.apply_hazards(unit, before, floor_before)
		unit.queue_redraw()
	for shot in projectiles:
		shot.advance(delta)
	for index in range(projectiles.size() - 1, -1, -1):
		if projectiles[index].finished:
			projectiles[index].queue_free()
			projectiles.remove_at(index)
	for collection in [humans, targets]:
		for index in range(collection.size() - 1, -1, -1):
			var unit: Node2D = collection[index]
			if unit.dead:
				unit_fallen.emit(unit)
				if unit.side == "xianghuo":
					unit.brain.channel.cancel("CHANNEL_BROKEN")
				corpses.append(unit)
				collection.remove_at(index)
	for index in range(corpses.size() - 1, -1, -1):
		corpses[index].corpse_left -= delta
		if corpses[index].corpse_left <= 0:
			corpses[index].queue_free()
			corpses.remove_at(index)
	for door_id in passage_timers.keys():
		var door: Node2D = world.get_node(str(door_id))
		var nearby := false
		for human in humans:
			if not human.brain.route.is_empty() and human.floor_id == door.floor_id and human.position.distance_to(door.position) <= 64:
				nearby = true
		for actor in humans + targets:
			if actor.floor_id == door.floor_id and absf(actor.position.x - door.position.x) < 28:
				nearby = true
		passage_timers[door_id] = Rules.DOOR_PASSAGE_GRACE if nearby else passage_timers[door_id] - delta
		if passage_timers[door_id] <= 0:
			if not door.destroyed:
				door.set_open(false)
			passage_timers.erase(door_id)
	for index in range(traces.size() - 1, -1, -1):
		traces[index].left -= delta
		if traces[index].left <= 0:
			traces.remove_at(index)
	_update_units()
	if tide_enabled:
		tide.after_step()
	if session != null and session.active:
		session.after_step(delta)
	step_index += 1
	step_completed.emit(delta)
	queue_redraw()

func _update_units() -> void:
	world.combatants.assign(humans + targets)
	floor_units.clear()
	floor_defenders.clear()
	for unit in world.combatants:
		if not floor_units.has(unit.floor_id):
			floor_units[unit.floor_id] = []
		floor_units[unit.floor_id].append(unit)
		if unit.side == "xianghuo":
			if not floor_defenders.has(unit.floor_id):
				floor_defenders[unit.floor_id] = []
			floor_defenders[unit.floor_id].append(unit)

func next_post(post_id: String) -> String:
	return defense_data.posts.get(post_id, {}).get("next", "")

func post_broken(post_id: String) -> bool:
	var section: Dictionary = defense_data.posts.get(post_id, {})
	for id in section.get("doors", []):
		if world.get_node(id).destroyed:
			return true
	var barriers: Array = section.get("obstacles", [])
	if not barriers.is_empty():
		var all_gone := true
		for id in barriers:
			if world.get_node(id).occupied:
				all_gone = false
		if all_gone:
			return true
	return false

func overwhelmed(unit: Node2D) -> bool:
	var anchor: Vector2 = world.get_node(unit.current_post).position
	var friendly := 0
	var hostile := 0
	for other in floor_units.get(unit.floor_id, []):
		if other.dead or absf(other.position.x - anchor.x) > Rules.body_to_px(Rules.PRESSURE_RADIUS_BODY):
			continue
		if other.side == unit.side:
			friendly += 1
		else:
			hostile += 1
	return hostile >= Rules.PRESSURE_RATIO * maxi(1, friendly)

func post_destination(unit: Node2D, post_id: String) -> Vector2:
	var post: Marker2D = world.get_node(post_id)
	var reservations: Array[Vector2] = []
	for other in humans:
		if other == unit:
			continue
		if not other.brain.route.is_empty() and other.brain.target_post == post_id and other.brain.purpose == "retreat":
			reservations.append(other.brain.route[-1].point)
		elif other.current_post == post_id and (other.brain.purpose != "retreat" or other.brain.route.is_empty()):
			reservations.append(other.brain.settled_position)
	# A post is an anchor with usable cover space, not a single stacked actor pixel.
	for offset in [Vector2.ZERO,Vector2(36,0),Vector2(-36,0),Vector2(72,0),Vector2(-72,0),Vector2(108,0),Vector2(144,0),Vector2(36,-48),Vector2(0,-48)]:
		var destination: Vector2 = post.position + offset
		if not world.is_walkable(destination,int(post.get_meta("floor_id"))) or world.segment_blocked(destination,destination,int(post.get_meta("floor_id"))):
			continue
		if world.is_open_court(destination) and offset.length() > Rules.body_to_px(Rules.COVER_LEASH_BODY):
			continue
		var available := true
		for reserved in reservations:
			if reserved.distance_to(destination) < 32:
				available = false
		if available:
			return destination
	return post.position

func open_passage(from: Vector2, to: Vector2, floor_id: int) -> void:
	for door in world.doors:
		if growth_engine()!=null and growth_engine().path_locked(str(door.name)):continue
		if door.floor_id == floor_id and not door.destroyed and world._hits_rect(from, to, door.blocking_rect().grow(Rules.FOOT_RADIUS_PX + 1)):
			door.set_open(true)
			passage_timers[door.name] = Rules.DOOR_PASSAGE_GRACE

func nearest_enemy(unit: Node2D, radius: float, same_floor: bool) -> Node2D:
	var best: Node2D
	var best_distance := radius
	var candidates: Array = floor_units.get(unit.floor_id, []) if same_floor else targets
	for target in candidates:
		if target.dead or target.side == unit.side:
			continue
		var distance: float = unit.position.distance_to(target.position)
		if distance <= best_distance:
			best = target
			best_distance = distance
	return best

func nearest_human(unit: Node2D, radius: float) -> Node2D:
	var best: Node2D
	var best_distance := radius
	for target in floor_defenders.get(unit.floor_id, []):
		if target.dead:
			continue
		var distance: float = unit.position.distance_to(target.position)
		if distance <= best_distance:
			best = target
			best_distance = distance
	return best

func nearest_shootable(unit: Node2D) -> Node2D:
	var best: Node2D
	var distance := INF
	for target in targets:
		if can_attack(unit, target) and unit.position.distance_to(target.position) < distance:
			best = target
			distance = unit.position.distance_to(target.position)
	return best

func can_attack(unit: Node2D, target: Node2D) -> bool:
	if unit.dead or not is_instance_valid(target) or target.dead or unit.side == target.side:
		return false
	var growth = growth_engine()
	if growth != null and growth.is_hidden(target) and not growth.has(unit,"N09") and not (roster_engine()!=null and unit.unit_id=="H29"):
		return false
	if unit.position.distance_to(target.position) > Rules.body_to_px(unit.profile.range_body):
		return false
	if unit.profile.projectile.is_empty() and unit.floor_id != target.floor_id:
		return false
	return world_hit(unit.aim_point(), target.aim_point()).is_empty()

func perform_attack(attacker: Node2D, victim: Node2D) -> bool:
	if attacker.dead or not attacker.attacks_enabled or attacker.attack_left > 0:
		return false
	if victim.is_in_group("units") and not can_attack(attacker, victim):
		return false
	attacker.attack_left = Rules.ATTACK_INTERVAL
	if not attacker.profile.projectile.is_empty() and victim.is_in_group("units"):
		var shot := Shot.new()
		shot.configure(self, attacker, victim.aim_point())
		add_child(shot)
		projectiles.append(shot)
		traces.append({"a": attacker.aim_point(), "b": victim.aim_point(), "left": 1.5})
		record_event("projectile_fired", attacker, victim.instance_id)
	else:
		deal_damage(attacker, victim, "melee" if victim.is_in_group("units") else "structure")
	return true

func deal_damage(attacker: Node2D, victim: Node2D, kind: String, attack_override := -1.0) -> void:
	if not is_instance_valid(victim):
		return
	if session != null and kind in session.ritual.param("fire_kinds",[]):
		return
	var attack_value: float = attack_override if attack_override >= 0 else attacker.attack
	var is_unit: bool = victim.is_in_group("units")
	var multiplier := 1.0
	if tide_enabled and is_instance_valid(attacker) and attacker.side == "yegui":
		if not is_unit and attacker.unit_id == "G12":
			multiplier = Data.skills.zhuang_men.structure_multiplier
		elif not is_unit and attacker.unit_id == "G01" and victim.is_in_group("doors"):
			multiplier = tide.door_bonus(attacker,victim)
		elif attacker.unit_id == "G09":
			if attacker.floor_id == 3:
				multiplier = Data.traits.jing_xian.upper_attack_multiplier
			elif attacker.brain.landing_left > 0:
				multiplier = Data.traits.jing_xian.landing_attack_multiplier
	var growth = growth_engine()
	if growth != null:multiplier *= growth.damage_multiplier(attacker,victim,kind)
	if roster_engine() != null: multiplier *= roster_engine().damage_multiplier(attacker,victim,kind)
	if session != null: multiplier *= float(session.ritual.damage_multiplier(attacker,kind))
	var victim_defense:float = growth.defense_for(victim) if growth != null and is_unit else victim.defense
	if roster_engine() != null and is_unit: victim_defense = roster_engine().defense_for(victim,victim_defense)
	var amount := Formula.damage(attack_value, victim_defense, multiplier)
	if growth != null and not is_unit:amount = growth.before_structure_damage(attacker,victim,amount)
	if roster_engine() != null and not is_unit: amount = roster_engine().before_structure_damage(attacker,victim,amount)
	var before: float = victim.hp if is_unit else victim.durability
	if is_unit:victim.receive_damage(amount,attacker,kind)
	else:victim.receive_damage(amount)
	if growth != null:growth.after_damage(attacker,victim,amount,kind,before)
	if roster_engine() != null: roster_engine().after_damage(attacker,victim,amount,kind,before)
	if tide_enabled and not is_unit and before > 0 and victim.durability <= 0:
		tide.effect("door_break" if victim.is_in_group("doors") else "obstacle_break",victim.position,str(victim.name))
	if not is_unit and victim.is_in_group("doors") and victim.durability < before:
		door_damaged.emit(victim, before)
	damage_log.append({"time": simulation_time, "attacker": attacker.instance_id if is_instance_valid(attacker) else "departed_shooter", "target": victim.name, "kind": kind, "attack": attack_value, "defense": victim.defense, "damage": amount, "multiplier": multiplier, "before": before, "after": victim.hp if is_unit else victim.durability})
	if damage_log.size() > 200:
		damage_log.pop_front()

func next_barrier(x: float, floor_id: int) -> Node2D:
	var best: Node2D
	var left := INF
	for object in world.doors + world.obstacles:
		if object.floor_id != floor_id:
			continue
		var active: bool = not object.is_open and not object.destroyed if object.is_in_group("doors") else object.occupied and object.blocks_walk and object.max_durability > 0
		if active and barrier_left(object) >= x - 0.1 and barrier_left(object) < left:
			best = object
			left = barrier_left(object)
	return best

func barrier_left(object: Node2D) -> float:
	return object.position.x - 8 if object.is_in_group("doors") else object.position.x

func world_hit(from: Vector2, to: Vector2) -> Dictionary:
	var hit: Dictionary = {}
	var first := INF
	for door in world.doors:
		if not door.is_open and not door.destroyed:
			var fraction := _rect_hit(from, to, door.blocking_rect())
			if fraction < first:
				first = fraction
				hit = {"point": from.lerp(to, fraction), "t": fraction, "object": door, "kind": "door"}
	for object in world.obstacles:
		if object.occupied and object.blocks_walk:
			var rect := Rect2(object.position - Vector2(0, Rules.TABLE_HEIGHT_PX), Vector2(object.width, Rules.TABLE_HEIGHT_PX))
			var fraction := _rect_hit(from, to, rect)
			if fraction < first:
				first = fraction
				hit = {"point": from.lerp(to, fraction), "t": fraction, "object": object, "kind": "obstacle"}
	# Match MapDrawing's real column silhouettes above each room opening.
	for room in world.layout.rooms:
		if room.start < 88:
			continue
		var y: float = world.floor_y(int(room.floor_id))
		var rect := Rect2(Rules.body_to_px(room.start), y - Rules.STORY_HEIGHT_PX + 8, 24, Rules.STORY_HEIGHT_PX - Rules.DOOR_HEIGHT_PX - 8)
		var fraction := _rect_hit(from, to, rect)
		if fraction < first:
			first = fraction
			hit = {"point": from.lerp(to, fraction), "t": fraction, "object": world, "kind": "pillar"}
	return hit

func projectile_hit(from: Vector2, to: Vector2, side: String) -> Dictionary:
	var hit: Dictionary = world_hit(from, to)
	var first: float = hit.get("t", INF)
	for unit in targets if side == "xianghuo" else humans:
		if unit.dead:
			continue
		var fraction := _rect_hit(from, to, unit.hit_rect())
		if fraction < first:
			first = fraction
			hit = {"point": from.lerp(to, fraction), "t": fraction, "unit": unit}
	return hit

func _rect_hit(from: Vector2, to: Vector2, rect: Rect2) -> float:
	if rect.has_point(from):
		return 0.0
	var length := from.distance_to(to)
	if length <= 0:
		return INF
	var first := INF
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in 4:
		var point = Geometry2D.segment_intersects_segment(from, to, corners[index], corners[(index + 1) % 4])
		if point != null:
			first = minf(first, from.distance_to(point) / length)
	return first

func record_event(kind: String, unit: Node2D, detail: String) -> void:
	events.append({"time": simulation_time, "kind": kind, "unit": unit.instance_id if is_instance_valid(unit) else "", "detail": detail})
	if events.size() > 300:
		events.pop_front()
	event_recorded.emit(kind, unit, detail)

func _draw() -> void:
	if world == null:
		return
	if debug_rays:
		for door in world.doors:
			var p: Vector2 = door.position - Vector2(40, Rules.DOOR_HEIGHT_PX + 28)
			draw_rect(Rect2(p, Vector2(80, 6)), Color("101a20"))
			draw_rect(Rect2(p, Vector2(80 * door.durability / door.max_durability, 6)), Color("ab9b78"))
			draw_string(world.font, p + Vector2(0,-5), "%d/%d" % [door.durability,door.max_durability], HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("bcbca3"))
		if tide_enabled:
			var rope_a := Vector2(Rules.body_to_px(tide.config.climb.from_x),Rules.HORIZON_Y - 30)
			var rope_b := Vector2(Rules.body_to_px(tide.config.climb.to_x),world.floor_y(2) - 30)
			draw_dashed_line(rope_a,rope_b,Color("788a81"),2,8)
	if tide_enabled:
		for effect in tide.effects:
			if effect.kind in ["door_break", "upper_entry", "purified"]:
				continue
			var ratio: float = 1.0 - effect.left / 0.6
			for index in 7:
				var offset := Vector2((index - 3) * 15 * ratio,-50 + sin(index * 2.0) * 55 * ratio)
				draw_rect(Rect2(effect.point + offset, Vector2(9,13)),Color(0.7,0.62,0.43,1.0-ratio))
	var growth = growth_engine()
	if growth != null:growth.draw_effects(self)
	if roster_engine()!=null:
		roster_engine().ghosts.draw_effects(self)
		roster_engine().humans.draw_effects(self)
	if debug_rays:
		for trace in traces:
			draw_dashed_line(trace.a, trace.b, Color("bdc69f"),2,9)

func growth_engine() -> RefCounted:
	if session != null and session.growth != null and session.growth.enabled:
		return session.growth
	return null

func roster_engine() -> RefCounted:
	if session != null and session.roster != null and session.roster.enabled: return session.roster
	return null
