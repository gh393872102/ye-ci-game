extends RefCounted
## Explicit opt-in extension point. P2 uses a temporary debug probe, never the G0 three.
## Guike's marked strike and Sunmao's repair effects are not implemented here.
var active := false
var remaining := 0.0
var origin := Vector2.ZERO
var destination := Vector2.ZERO
var returning := false
var completed := false

func request(sim: Node2D, unit: Node2D, point: Vector2, marked: bool) -> bool:
	if not unit.may_briefly_leave_base or unit.return_after <= 0 or not marked or unit.floor_id != 0:
		return false
	if unit.current_post != "post_gate_inner" or point.y != sim.world.floor_y(0):
		return false
	if point.x < Rules.BASE_START_X - Rules.body_to_px(Rules.HUMAN_CHASE_LIMIT) or point.x >= Rules.BASE_START_X:
		return false
	if sim.world.segment_blocked(unit.position,point,0):
		return false
	origin = unit.position
	destination = point
	remaining = unit.return_after
	returning = false
	completed = false
	active = true
	unit.set_state("ExceptionOutbound")
	sim.record_event("exception_start",unit,"marked debug destination")
	return true

func advance(sim: Node2D, unit: Node2D, delta: float) -> void:
	if not active or delta <= 0 or unit.dead:
		return
	remaining = maxf(0, remaining - delta)
	if remaining <= 0:
		returning = true
	var goal := origin if returning else destination
	var speed := Rules.body_to_px(Rules.WALK_SPEED_REF)
	var next: Vector2 = unit.position.move_toward(goal,speed * delta)
	if returning:
		sim.open_passage(unit.position,next,0)
	if sim.world.segment_blocked(unit.position,next,0):
		returning = true
		return
	unit.velocity = (next - unit.position) / delta
	unit.current_speed = unit.velocity.length()
	unit.position = next
	unit.set_state("ExceptionReturn" if returning else "ExceptionOutbound")
	if next.distance_to(goal) < 0.01:
		if returning:
			active = false
			completed = true
			unit.current_speed = 0
			unit.set_state("HoldNewPost")
			sim.record_event("exception_returned",unit,unit.current_post)
		else:
			# Job finished: return immediately, even if the deadline has not expired.
			returning = true
