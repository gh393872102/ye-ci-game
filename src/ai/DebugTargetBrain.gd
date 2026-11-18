extends RefCounted
## P2 only: a ground-lane walking target. No tide formation, elites, climbing or spawning AI.
var simulation: Node2D
var unit: Node2D
var gap_route: Array[Dictionary] = []

func _init(sim: Node2D, actor: Node2D) -> void:
	simulation = sim
	unit = actor

func advance(delta: float) -> void:
	if unit.dead or delta <= 0:
		return
	unit.current_speed = 0
	unit.velocity = Vector2.ZERO
	var victim: Node2D = simulation.nearest_human(unit, Rules.body_to_px(unit.profile.range_body))
	if victim != null and simulation.can_attack(unit, victim):
		unit.set_state("Engage")
		simulation.perform_attack(unit, victim)
		return
	var barrier: Node2D = simulation.next_barrier(unit.position.x, unit.floor_id)
	if barrier != null and simulation.barrier_left(barrier) - unit.position.x <= Rules.body_to_px(unit.profile.range_body):
		unit.set_state("AttackBarrier")
		simulation.perform_attack(unit, barrier)
		return
	if not unit.motion_enabled:
		return
	var old: Vector2 = unit.position
	var maximum_x: float = Rules.REGISTER_X
	if barrier != null:
		maximum_x = minf(maximum_x, simulation.barrier_left(barrier) - Rules.FOOT_RADIUS_PX)
	for other in simulation.targets:
		if other != unit and not other.dead and other.floor_id == unit.floor_id and other.position.x > unit.position.x:
			maximum_x = minf(maximum_x, other.position.x - Rules.TARGET_SPACING_PX)
	var speed := Rules.body_to_px(Rules.WALK_SPEED_REF)
	if gap_route.is_empty() and unit.position.x >= Rules.BASE_START_X:
		for object in simulation.world.obstacles:
			if object.floor_id == unit.floor_id and object.occupied and object.max_durability == 0 and object.position.x > unit.position.x and object.position.x - unit.position.x < 100:
				var end := Vector2(object.position.x + object.width + Rules.PATH_CLEARANCE_PX, simulation.world.floor_y(unit.floor_id))
				gap_route = simulation.world.navigation.horizontal_path(unit.position, end, unit.floor_id, true)
				break
	if not gap_route.is_empty():
		var destination: Vector2 = gap_route[0].point
		var next: Vector2 = unit.position.move_toward(destination, speed * delta)
		if next.x <= maximum_x + 0.01 and not simulation.world.segment_blocked(unit.position, next, unit.floor_id):
			unit.position = next
			if next.distance_to(destination) < 0.01:
				gap_route.pop_front()
	else:
		unit.position.x = maxf(unit.position.x, minf(unit.position.x + speed * delta, maximum_x))
	unit.velocity = (unit.position - old) / delta
	unit.current_speed = unit.velocity.length()
	unit.set_state("Advance" if unit.current_speed > 0 else "WaitingAtRegister")
	unit.sync_meta()
