extends Node2D
## P1 test actor only. No autonomous AI, attacks or player movement action.
signal arrived
var world: Node2D
var route: Array[Dictionary] = []
var target_post := ""
var current_speed := 0.0
var selected := false
var last_rejection := ""

func _physics_process(_delta: float) -> void:
	advance(Clock.delta)

func request_post(post_id: String) -> bool:
	if not route.is_empty():
		last_rejection = "WALK_BUSY"
		return false
	if not world.can_deploy_at(post_id):
		last_rejection = "WALK_REJECT_TARGET"
		return false
	var post: Marker2D = world.get_node(post_id)
	var path: Array[Dictionary] = world.navigation.route(position, int(get_meta("floor_id")), post.position, int(post.get_meta("floor_id")))
	if path.is_empty():
		last_rejection = "WALK_BLOCKED"
		return false
	route = path
	target_post = post_id
	last_rejection = ""
	return true

func request_retreat() -> bool:
	if not route.is_empty():
		last_rejection = "WALK_BUSY"
		return false
	var line: Array = world.layout.retreat_line
	var start := line.find(str(get_meta("current_post")))
	if start < 0 or start == line.size() - 1:
		last_rejection = "WALK_REJECT_TARGET"
		return false
	var planned: Array[Dictionary] = []
	var last := position
	var floor_id := int(get_meta("floor_id"))
	for i in range(start + 1, line.size()):
		var post: Marker2D = world.get_node(line[i])
		var segment: Array[Dictionary] = world.navigation.route(last, floor_id, post.position, int(post.get_meta("floor_id")))
		if segment.is_empty():
			last_rejection = "WALK_BLOCKED"
			return false
		segment[-1]["post"] = line[i]
		planned.append_array(segment)
		last = post.position
		floor_id = int(post.get_meta("floor_id"))
	route = planned
	target_post = line[-1]
	last_rejection = ""
	return true

func advance(simulation_delta: float) -> void:
	if route.is_empty() or simulation_delta <= 0:
		current_speed = 0
		return
	var remaining := simulation_delta
	while remaining > 0 and not route.is_empty():
		var step: Dictionary = route[0]
		current_speed = Rules.body_to_px(Rules.WALK_SPEED_REF) * (Rules.STAIR_SPEED_FACTOR if step.stair else 1.0)
		var distance := position.distance_to(step.point)
		var movement := minf(distance, current_speed * remaining)
		var next := position.move_toward(step.point, movement)
		if not step.stair and world.segment_blocked(position, next, int(get_meta("floor_id"))):
			route.clear()
			current_speed = 0
			set_meta("ai_state", "P1_BLOCKED")
			last_rejection = "WALK_BLOCKED"
			return
		set_meta("ai_state", "P1_STAIRS" if step.stair else "P1_DEBUG_WALK")
		position = next
		remaining -= movement / current_speed
		if distance <= movement + 0.001:
			set_meta("floor_id", int(step.floor))
			if step.has("post"):
				set_meta("current_post", step.post)
			route.pop_front()
		else:
			break
	if route.is_empty():
		current_speed = 0
		set_meta("current_post", target_post)
		set_meta("ai_state", "P1_IDLE")
		arrived.emit()

func _draw() -> void:
	var h := float(Rules.UNIT_HEIGHT_PX)
	if selected:
		draw_arc(Vector2(0, -3), 27, 0, TAU, 20, Color("a3c9b3"), 2)
	if get_meta("side", "") == "xianghuo":
		draw_rect(Rect2(-12, -h, 24, 18), Color("c7c5af"))
		draw_rect(Rect2(-17, -62, 34, 45), Color("80524c"))
		draw_rect(Rect2(-15, -17, 11, 17), Color("adb0a7"))
		draw_rect(Rect2(4, -17, 11, 17), Color("adb0a7"))
		draw_rect(Rect2(-26, -70, 4, 70), Color("a79c7f"))
	else:
		draw_rect(Rect2(-10, -h, 20, 20), Color("d5d4c5"))
		draw_colored_polygon(PackedVector2Array([Vector2(-11, -60), Vector2(11, -60), Vector2(25, 0), Vector2(3, -10), Vector2(-23, 0)]), Color("acb8b7"))
