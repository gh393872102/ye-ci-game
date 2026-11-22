extends RefCounted
## Four-lane monotone route flow. Only G09 takes the explicit wall/upper/rear links.
var sim: Node2D
var unit: Node2D
var tide: RefCounted
var stage := "main"
var gap_route: Array[Dictionary] = []
var landing_left := 0.0

func _init(simulation: Node2D, actor: Node2D, controller: RefCounted) -> void:
	sim = simulation
	unit = actor
	tide = controller
	var world: Node2D = sim.world
	for id in world.layout.get("ghost_routes", {}):
		var route: Dictionary = world.layout.ghost_routes[id]
		if unit.floor_id == int(world.stair_link(route.entry).to_floor):
			stage = "chunk_path:" + id
			break

func segment_key() -> String:
	return stage

func advance(delta: float) -> void:
	unit.current_speed = 0
	unit.velocity = Vector2.ZERO
	landing_left = maxf(0,landing_left - delta)
	if _follow_chunk_link(delta):
		return
	if _window_bypass(delta) or _mechanism_side_route(delta): return
	if stage in ["climb", "descend"]:
		_climb(delta)
		return
	var barrier: Node2D = sim.next_barrier(unit.position.x,unit.floor_id)
	var in_reach: bool = barrier != null and sim.barrier_left(barrier) - unit.position.x <= Rules.body_to_px(unit.profile.range_body)
	# 愚力 prioritizes the nearest structure within reach, even if a human is close.
	if in_reach and unit.unit_id == "G12":
		_strike(barrier)
		return
	var priority := _register_target()
	var human: Node2D = priority if priority!=null else sim.nearest_human(unit,Rules.body_to_px(unit.profile.range_body))
	if human != null and sim.can_attack(unit,human) and unit.attacks_enabled:
		unit.set_state("Engage")
		if sim.perform_attack(unit,human) and priority==human:
			human.roster.window_strike_at = sim.simulation_time
			human.queue_redraw()
		return
	if in_reach and sim.roster_engine()!=null and unit.unit_id=="G24" and str(barrier.name) in Data.roster_rules.routes.mechanism_side_route.front_doors:
		unit.set_state("WaitForSideAccess")
		return
	if in_reach and unit.attacks_enabled:
		_strike(barrier)
		return
	if not unit.motion_enabled:
		return
	var maximum: float = maxf(Rules.REGISTER_X,priority.position.x) if priority!=null else Rules.REGISTER_X
	if barrier != null:
		maximum = minf(maximum,sim.barrier_left(barrier) - Rules.FOOT_RADIUS_PX)
	var spacing: float = tide.config.dense_spacing if barrier != null and sim.barrier_left(barrier) - unit.position.x < 400 else tide.config.spacing
	maximum = minf(maximum,tide.front_limit(unit,spacing))
	var transfer: Dictionary = _chunk_transfer()
	var transfer_x := INF
	if not transfer.is_empty():
		transfer_x = Rules.body_to_px(transfer.link.from_x)
		maximum = minf(maximum, transfer_x)
	var branch_x: float = Rules.body_to_px(tide.config.climb.from_x if stage == "main" else tide.config.descent.from_x)
	if _climber() and stage in ["main","upper"]:
		maximum = minf(maximum,branch_x)
	var previous: Vector2 = unit.position
	var speed: float = Rules.body_to_px(tide.speed(unit))
	var growth = sim.growth_engine()
	var multiplier: float = growth.speed_multiplier(unit) if growth != null else 1.0
	if sim.roster_engine() != null: multiplier = sim.roster_engine().speed_multiplier(unit,multiplier)
	speed *= multiplier
	# Existing facility gaps remain walkable; destructible barricades are attacked above.
	if gap_route.is_empty() and unit.position.x >= Rules.BASE_START_X:
		for object in sim.world.obstacles:
			if object.floor_id == unit.floor_id and object.occupied and object.blocks_walk and object.max_durability == 0 and object.position.x > unit.position.x and object.position.x - unit.position.x < 110:
				var end := Vector2(object.position.x + object.width + Rules.PATH_CLEARANCE_PX,sim.world.floor_y(unit.floor_id) + tide.config.lane_offsets[unit.lane_index])
				gap_route = sim.world.navigation.horizontal_path(unit.position,end,unit.floor_id,true)
				for step in gap_route:
					if is_equal_approx(step.point.y,sim.world.floor_y(unit.floor_id) - Rules.GAP_LANE_OFFSET_PX):
						step.point.y = sim.world.floor_y(unit.floor_id) - 42 - unit.lane_index * 6
				break
	if not gap_route.is_empty():
		var destination: Vector2 = gap_route[0].point
		var next: Vector2 = unit.position.move_toward(destination,speed * delta)
		if next.x <= maximum + 0.01 and not sim.world.segment_blocked(unit.position,next,unit.floor_id):
			unit.position = next
			if next.distance_to(destination) < 0.01:
				gap_route.pop_front()
	else:
		unit.position.x = maxf(unit.position.x,minf(maximum,unit.position.x + speed * delta))
	_motion(previous,delta)
	unit.set_state("Advance" if unit.current_speed > 0 else "Queue")
	if not transfer.is_empty() and unit.position.x >= transfer_x - 0.01:
		stage = transfer.stage
		return
	if _climber() and stage in ["main","upper"] and unit.position.x >= branch_x - 0.01:
		stage = "climb" if stage == "main" else "descend"
		tide.effect("climb_start",unit.position,unit.instance_id)
		unit.set_state("Climb" if stage == "climb" else "Descend")

func _chunk_transfer() -> Dictionary:
	if not sim.world.layout.has("ghost_routes"):
		return {}
	var entering: bool = stage == "main" and unit.floor_id == 0
	var id := ""
	if entering:
		id = sim.world.ghost_branch(unit.position.x, unit.lane_index, unit.unit_id, bool(tide.config.get("bridge_reinforcements", false)))
	elif stage.begins_with("chunk_path:"):
		id = stage.get_slice(":", 1)
	if id.is_empty():
		return {}
	var route: Dictionary = sim.world.layout.ghost_routes[id]
	var link: Dictionary = sim.world.stair_link(route.entry if entering else route.exit)
	return {"link":link, "stage":("chunk_entry:" if entering else "chunk_exit:") + id}

func _follow_chunk_link(delta: float) -> bool:
	if not stage.begins_with("chunk_"):
		return false
	var phase := stage.get_slice(":", 0)
	var id := stage.get_slice(":", 1)
	var route: Dictionary = sim.world.layout.get("ghost_routes", {}).get(id, {})
	if route.is_empty():
		stage = "main"
		return false
	var reachable: bool = sim.world.path_is_open(route.entry) and sim.world.path_is_open(route.exit)
	if phase == "chunk_path" and reachable:
		return false
	if not unit.motion_enabled:
		return true
	var target: Vector2
	var floor := 0
	var complete := "main"
	var lane_y: float = tide.config.lane_offsets[unit.lane_index]
	if reachable:
		var entering := phase == "chunk_entry"
		var link: Dictionary = sim.world.stair_link(route.entry if entering else route.exit)
		floor = int(link.to_floor)
		target = Vector2(Rules.body_to_px(link.to_x), sim.world.floor_y(floor) + lane_y)
		if entering:
			complete = "chunk_path:" + id
	else:
		stage = "chunk_drop:" + id
		target = Vector2(unit.position.x, sim.world.floor_y(0) + lane_y)
	var previous: Vector2 = unit.position
	var speed: float = Rules.body_to_px(tide.speed(unit)) * float(tide.config.climb_factor)
	unit.position = unit.position.move_toward(target, speed * delta)
	_motion(previous, delta)
	unit.set_state("Climb" if target.y < previous.y else "Descend")
	if unit.position.distance_to(target) < 0.01:
		unit.floor_id = floor
		stage = complete
		unit.sync_meta()
		tide.effect("chunk_enter" if complete.begins_with("chunk_path:") else "chunk_leave", unit.position, id)
	return true

func _register_target() -> Node2D:
	if unit.unit_id!="G07" or unit.side!="yegui" or sim.roster_engine()==null: return null
	var order: String = sim.roster_engine().state.get("window_focus","")
	if order not in ["window_bow","window_reader"] or sim.world.room_at(unit.position,unit.floor_id)!="register": return null
	var role := "crossbow" if order=="window_bow" else "ritual"
	var nearest: Node2D
	var distance := INF
	for guard in sim.floor_defenders.get(unit.floor_id,[]):
		if guard.dead or guard.role!=role or sim.world.room_at(guard.position,guard.floor_id)!="register": continue
		if not sim.can_attack(unit,guard) and guard.position.x<=unit.position.x: continue
		var gap: float = unit.position.distance_squared_to(guard.position)
		if gap<distance:
			distance=gap
			nearest=guard
	return nearest

func _strike(barrier: Node2D) -> void:
	unit.set_state("AttackBarrier")
	sim.perform_attack(unit,barrier)

func _climb(delta: float) -> void:
	if not unit.motion_enabled:
		return
	var spec: Dictionary = tide.config.climb if stage == "climb" else tide.config.descent
	var destination := Vector2(Rules.body_to_px(spec.to_x),sim.world.floor_y(int(spec.to_floor)) + tide.config.lane_offsets[unit.lane_index])
	var previous: Vector2 = unit.position
	var multiplier: float = sim.growth_engine().speed_multiplier(unit) if sim.growth_engine()!=null else 1.0
	if sim.roster_engine()!=null: multiplier = sim.roster_engine().speed_multiplier(unit,multiplier)
	unit.position = unit.position.move_toward(destination,Rules.body_to_px(tide.speed(unit)) * multiplier * (sim.growth_engine().stair_factor(unit,float(tide.config.climb_factor)) if sim.growth_engine()!=null else tide.config.climb_factor) * delta)
	_motion(previous,delta)
	unit.set_state("Climb" if stage == "climb" else "Descend")
	if unit.position.distance_to(destination) < 0.01:
		unit.floor_id = int(spec.to_floor)
		stage = "upper" if stage == "climb" else "rear"
		unit.current_post = "upper_entry" if stage == "upper" else "register_entry"
		if stage == "rear":
			landing_left = sim.growth_engine().landing_duration(unit,float(Data.traits.jing_xian.landing_seconds)) if sim.growth_engine()!=null else Data.traits.jing_xian.landing_seconds
		tide.effect("upper_entry" if stage == "upper" else "landed",unit.position,unit.instance_id)
		if stage=="rear" and sim.growth_engine()!=null:sim.growth_engine().on_landed(unit)
		unit.sync_meta()

func _motion(previous: Vector2, delta: float) -> void:
	unit.velocity = (unit.position - previous) / delta
	unit.current_speed = unit.velocity.length()
	unit.progress += previous.distance_to(unit.position)
	unit.z_index = 10 + unit.lane_index
	unit.sync_meta()

func _climber() -> bool:
	return unit.unit_id == "G09" or (sim.growth_engine()!=null and unit.unit_id == "G07")

func _window_bypass(delta: float) -> bool:
	var roster = sim.roster_engine()
	if roster == null or unit.unit_id != "G07" or unit.floor_id != 0 or stage != "main": return false
	var spec: Dictionary = Data.roster_rules.routes.window_side_passage
	if unit.position.x >= Rules.body_to_px(float(spec.entry_x_body)) and not unit.roster.has("exterior_route"): return false
	roster.ensure(unit)
	if not unit.roster.has("exterior_route"):
		var y: float = sim.world.floor_y(0)
		var departure: float = maxf(unit.position.x,Rules.body_to_px(float(spec.departure_x_body)))
		var entry: float = Rules.body_to_px(float(spec.entry_x_body))
		unit.roster.exterior_route = [[departure,y],[departure,y-float(spec.ledge_offset_px)],[entry,y-float(spec.ledge_offset_px)],[entry,sim.world.floor_y(int(spec.entry_floor))]]
		roster.event("window_route_started",unit,"window_side_passage")
	if not unit.motion_enabled: return true
	var route: Array = unit.roster.exterior_route
	if route.is_empty(): return false
	var destination := Vector2(float(route[0][0]),float(route[0][1]))
	var previous: Vector2 = unit.position
	var multiplier: float = roster.speed_multiplier(unit,sim.growth_engine().speed_multiplier(unit))
	var next: Vector2 = unit.position.move_toward(destination,Rules.body_to_px(tide.speed(unit))*float(spec.speed_multiplier)*multiplier*delta)
	# The only special lane is above the ground-floor gates; collision remains live.
	if sim.world.segment_blocked(unit.position,next,0): return true
	unit.position = next
	_motion(previous,delta)
	unit.set_state("WindowCrawl" if unit.unit_id=="G07" else "SideDoorApproach")
	if next.distance_to(destination) < .01:
		route.pop_front()
		if route.is_empty():
			unit.roster.erase("exterior_route")
			unit.floor_id = int(spec.entry_floor)
			unit.current_post = "upper_entry"
			stage = "upper"
			roster.event("window_entered",unit,"post_window_1")
			roster.visual("narrow_window",unit)
	return true

func _mechanism_side_route(delta: float) -> bool:
	var roster = sim.roster_engine()
	if roster == null or unit.unit_id != "G24" or stage != "main": return false
	var spec: Dictionary = Data.roster_rules.routes.mechanism_side_route
	if not unit.roster.has("mechanism_route") and (unit.floor_id != 0 or unit.position.x < Rules.HALL_X): return false
	if not unit.roster.has("mechanism_route"):
		var post: Node2D = sim.world.get_node(str(spec.post_id))
		var planned: Array = sim.world.navigation.route(unit.position,unit.floor_id,post.position,int(post.get_meta("floor_id")),false)
		if planned.is_empty(): return false
		unit.roster.mechanism_route = []
		for point in planned: unit.roster.mechanism_route.append({"point":[point.point.x,point.point.y],"floor":point.floor,"stair":point.stair})
		roster.event("side_access_started",unit,str(spec.stair_id))
	if not unit.motion_enabled: return true
	var route: Array = unit.roster.mechanism_route
	if route.is_empty(): return false
	var point: Dictionary = route[0]
	var goal := Vector2(float(point.point[0]),float(point.point[1]))
	var previous: Vector2 = unit.position
	var factor: float = float(tide.config.climb_factor) if point.stair else 1.0
	var speed: float = Rules.body_to_px(tide.speed(unit))*roster.speed_multiplier(unit,sim.growth_engine().speed_multiplier(unit))*factor
	var next: Vector2 = unit.position.move_toward(goal,speed*delta)
	if not point.stair and sim.world.segment_blocked(unit.position,next,unit.floor_id): return true
	unit.position=next
	_motion(previous,delta)
	unit.set_state("SideDoorApproach")
	if next.distance_to(goal)<.01:
		unit.floor_id=int(point.floor)
		route.pop_front()
		if route.is_empty():
			unit.roster.erase("mechanism_route")
			stage="upper"
			unit.current_post=str(spec.post_id)
			roster.event("side_access_entered",unit,str(spec.post_id))
	return true
