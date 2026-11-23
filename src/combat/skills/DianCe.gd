extends RefCounted
## Shared channel lifecycle. Active P4 delegates spending and purification rewards to Session.
var active := false
var elapsed := 0.0
var duration := 4.0
var target: Node2D
var completions := 0
var last_result := ""
var start_position := Vector2.ZERO
var damage_revision := 0
var paid := false
var purify_only := false

func valid_target(sim: Node2D, caster: Node2D, candidate: Node2D) -> bool:
	return target_reason(sim, caster, candidate).is_empty()

func target_reason(sim: Node2D, caster: Node2D, candidate: Node2D) -> String:
	if not is_instance_valid(candidate) or candidate.dead or candidate.side != "yegui":
		return "P9_RITUAL_PICK"
	if caster.dead or caster.role != "ritual" or not sim.world.inside_base(caster.position):
		return "P9_RITUAL_UNSAFE"
	if not sim.world.inside_base(candidate.position) or candidate.position.x < Rules.HALL_X:
		return "P9_RITUAL_WAIT_HALL"
	if sim.world.is_open_court(caster.position):
		return "P9_RITUAL_UNSAFE"
	var room: String = sim.world.room_at(caster.position, caster.floor_id)
	if room not in ["register", "incense", "hall"]:
		return "P9_RITUAL_UNSAFE"
	if sim.session != null and sim.session.active:
		if caster.floor_id != candidate.floor_id:
			return "P9_RITUAL_WRONG_FLOOR"
		if caster.position.distance_to(candidate.position) > Rules.body_to_px(float(sim.session.rules.ritual.range_body)):
			return "P9_RITUAL_DISTANCE"
		# Closed doors and full-height walls block the head-height sight line.
		var source: Vector2 = caster.position - Vector2(0, caster.height_px * 0.9)
		var destination: Vector2 = candidate.position - Vector2(0, candidate.height_px * 0.9)
		if not sim.world_hit(source, destination).is_empty():
			return "P9_RITUAL_OCCLUDED"
	return ""

func start(sim: Node2D, caster: Node2D, candidate: Node2D) -> bool:
	if not valid_target(sim, caster, candidate):
		last_result = "CHANNEL_REJECT_LOCATION"
		return false
	target = candidate
	purify_only = false
	elapsed = 0
	duration = float(Data.skills[caster.skill_id].get("duration",4.0))
	paid = sim.session != null and sim.session.active
	if paid:
		duration = sim.session.configured_ritual_duration(caster,candidate)
	else:
		var growth = sim.growth_engine()
		if growth != null: duration = growth.ritual_duration(caster,candidate,duration)
		if sim.roster_engine() != null: duration = sim.roster_engine().ritual_duration(caster,candidate,duration)
	start_position = caster.position
	damage_revision = caster.damage_revision
	active = true
	last_result = "CHANNEL_STARTED"
	caster.set_state("Channel")
	return true

func advance(sim: Node2D, caster: Node2D, delta: float) -> void:
	if not active or delta <= 0:
		return
	if paid and (caster.damage_revision != damage_revision or caster.position.distance_to(start_position) > 1 or not caster.brain.route.is_empty()):
		cancel("P4_RITUAL_INTERRUPTED_MOVEMENT" if caster.position.distance_to(start_position) > 1 else "P4_RITUAL_INTERRUPTED_DAMAGE")
		return
	if not valid_target(sim, caster, target):
		cancel("CHANNEL_CANCELLED")
		return
	elapsed = minf(duration, elapsed + delta)
	if elapsed >= duration:
		active = false
		completions += 1
		last_result = "CHANNEL_INTERFACE_DONE"
		sim.record_event("channel_complete", caster, target.instance_id)
		if paid:
			last_result = "P4_RITUAL_COMPLETED"
			sim.session.ritual_completed(caster, target)

func cancel(reason: String) -> void:
	active = false
	last_result = reason

func progress() -> float:
	return elapsed / duration
