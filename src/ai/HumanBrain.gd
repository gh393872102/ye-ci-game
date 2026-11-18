extends RefCounted
const Policy = preload("res://src/ai/GuardPolicy.gd")
const Excursion = preload("res://src/ai/BaseExcursion.gd")
const Channel = preload("res://src/combat/skills/DianCe.gd")
var simulation: Node2D
var unit: Node2D
var route: Array[Dictionary] = []
var target_post := ""
var purpose := ""
var pressure_elapsed := 0.0
var hold_left := 0.0
var last_reason := ""
var channel: RefCounted = Channel.new()
var excursion: RefCounted = Excursion.new()
var last_channel_target := ""
var visited_posts: Array[String] = []
var settled_position := Vector2.ZERO
var repair_door: Node2D = null

func _init(sim: Node2D, actor: Node2D) -> void:
	simulation = sim
	unit = actor
	visited_posts.append(unit.current_post)
	settled_position = unit.position

func advance(delta: float) -> void:
	if delta <= 0 or unit.dead:
		return
	unit.current_speed = 0
	unit.velocity = Vector2.ZERO
	if excursion.active:
		excursion.advance(simulation, unit, delta)
		return
	if not route.is_empty():
		if channel.active:
			channel.cancel("P4_RITUAL_INTERRUPTED_MOVEMENT")
		_move(delta)
		return
	if repair_door != null:
		unit.set_state("Repair")
		return
	if hold_left > 0:
		hold_left -= delta
		if hold_left <= 0:
			unit.set_state("IdleAtPost")
		return
	var hard_break: bool = simulation.post_broken(unit.current_post)
	var ratio: bool = simulation.overwhelmed(unit)
	pressure_elapsed = pressure_elapsed + delta if ratio else 0.0
	if hard_break or (pressure_elapsed >= Rules.PRESSURE_SECONDS and not unit.hold_lock):
		if retreat("structure" if hard_break else "pressure"):
			return
	if unit.role == "ritual":
		_ritual(delta)
	elif unit.role in ["crossbow", "talisman"]:
		_ranged()
	else:
		_guard()

func retreat(reason: String) -> bool:
	var next: String = simulation.next_post(unit.current_post)
	if next.is_empty():
		# Register is the final stronghold in P2; win/loss is owned by P4/P5.
		return false
	var post: Marker2D = simulation.world.get_node(next)
	var destination: Vector2 = simulation.post_destination(unit, next)
	var path: Array[Dictionary] = simulation.world.navigation.route(unit.position, unit.floor_id, destination, int(post.get_meta("floor_id")), true)
	if path.is_empty():
		last_reason = "route_blocked"
		return false
	channel.cancel("CHANNEL_RETREAT")
	route = path
	target_post = next
	purpose = "retreat"
	last_reason = reason
	pressure_elapsed = 0
	unit.set_state("StepBack" if reason == "near" else "RetreatToNext")
	simulation.record_event("retreat", unit, "%s -> %s (%s)" % [unit.current_post, next, reason])
	return true

func _move(delta: float) -> void:
	if not unit.motion_enabled:
		return
	var remaining := delta
	var before: Vector2 = unit.position
	while remaining > 0 and not route.is_empty():
		var step: Dictionary = route[0]
		if step.has("link") and not simulation.world.path_is_open(str(step.link)):
			_return_from_broken_link(str(step.link), remaining)
			break
		var speed := Rules.body_to_px(Rules.RETREAT_SPEED if purpose == "retreat" else Rules.WALK_SPEED_REF)
		var growth = simulation.growth_engine()
		var multiplier: float = growth.speed_multiplier(unit) if growth != null else 1.0
		var roster = simulation.roster_engine()
		if roster != null:
			multiplier = roster.speed_multiplier(unit,multiplier)
			if purpose == "support" and unit.unit_id == "H15": speed = Rules.body_to_px(float(roster.params(unit).support_speed))
		speed *= multiplier
		if speed <= 0: break
		if step.stair:
			speed *= growth.stair_factor(unit,Rules.STAIR_SPEED_FACTOR) if growth != null else Rules.STAIR_SPEED_FACTOR
		unit.current_speed = speed
		var distance: float = unit.position.distance_to(step.point)
		var movement := minf(distance, speed * remaining)
		var destination: Vector2 = unit.position.move_toward(step.point, movement)
		if not simulation.world.inside_base(destination):
			route.clear()
			last_reason = "base_rejected"
			unit.set_state("IdleAtPost")
			break
		if not step.stair:
			if purpose in ["retreat", "repair", "repair_return", "support"]:
				simulation.open_passage(unit.position, destination, unit.floor_id)
			if simulation.world.segment_blocked(unit.position, destination, unit.floor_id):
				# A door can close after planning; never tunnel through it.
				route.clear()
				last_reason = "route_blocked"
				unit.set_state("IdleAtPost")
				break
		unit.position = destination
		remaining -= movement / speed
		if distance <= movement + 0.001:
			unit.floor_id = int(step.floor)
			route.pop_front()
		else:
			break
	unit.velocity = (unit.position - before) / delta
	if route.is_empty() and last_reason != "route_blocked" and last_reason != "base_rejected":
		if purpose in ["retreat","support"]:
			unit.current_post = target_post
			settled_position = unit.position
			visited_posts.append(target_post)
			hold_left = 0.2
			unit.set_state("HoldNewPost")
		else:
			unit.set_state("IdleAtPost")
		unit.current_speed = 0
	unit.sync_meta()

func _return_from_broken_link(id: String, delta: float) -> void:
	var link: Dictionary = simulation.world.stair_link(id)
	var x: float = link.from_x if int(link.from_floor) == unit.floor_id else link.to_x
	var landing := Vector2(Rules.body_to_px(x), simulation.world.floor_y(unit.floor_id))
	unit.position = unit.position.move_toward(landing, Rules.body_to_px(Rules.RETREAT_SPEED) * delta)
	if unit.position.distance_to(landing) < 0.01:
		route.clear()
		last_reason = "route_blocked"
		unit.set_state("IdleAtPost")

func _guard() -> void:
	var target: Node2D = simulation.nearest_enemy(unit, Rules.body_to_px(Rules.HUMAN_CHASE_LIMIT + unit.profile.range_body), true)
	if target != null and simulation.can_attack(unit, target):
		unit.set_state("Engage")
		simulation.perform_attack(unit, target)
		return
	if target != null:
		var destination: Dictionary = Policy.chase_destination(simulation.world, unit, target)
		if not destination.is_empty():
			var path: Array[Dictionary] = simulation.world.navigation.route(unit.position, unit.floor_id, destination.point, unit.floor_id)
			if not path.is_empty() and unit.position.distance_to(destination.point) > 1:
				route = path
				purpose = "chase"
				last_reason = ""
				unit.set_state("Engage")
				return
	_return_to_post()

func _return_to_post() -> void:
	if unit.position.distance_to(settled_position) > 1:
		var path: Array[Dictionary] = simulation.world.navigation.route(unit.position, unit.floor_id, settled_position, unit.floor_id)
		if not path.is_empty():
			route = path
			purpose = "return"
			last_reason = ""
			unit.set_state("StepBack")
			return
	unit.set_state("IdleAtPost")

func _ranged() -> void:
	var close: Node2D = simulation.nearest_enemy(unit, Rules.body_to_px(Rules.CLOSE_THREAT_BODY), true)
	if close != null and retreat("near"):
		return
	var target: Node2D = simulation.nearest_shootable(unit)
	if target != null:
		unit.set_state("Engage")
		simulation.perform_attack(unit, target)
	else:
		unit.set_state("IdleAtPost")

func _ritual(delta: float) -> void:
	if channel.active:
		channel.advance(simulation, unit, delta)
		if not channel.active:
			unit.set_state("IdleAtPost")
		return
	if simulation.session != null and simulation.session.active:
		unit.set_state("IdleAtPost")
		return
	for target in simulation.targets:
		if target.instance_id != last_channel_target and channel.valid_target(simulation, unit, target):
			request_channel(target)
			return
	unit.set_state("IdleAtPost")

func request_channel(target: Node2D) -> bool:
	if simulation.session != null and simulation.session.active:
		return bool(simulation.session.start_ritual(unit, target).ok)
	if not route.is_empty() or unit.dead:
		return false
	if channel.start(simulation, unit, target):
		last_channel_target = target.instance_id
		return true
	return false
