extends RefCounted
## Hard movement policy; a target's location never becomes a legal human destination by itself.
static func can_stop(world: Node2D, unit: Node2D, point: Vector2, floor_id: int) -> bool:
	if not world.is_walkable(point, floor_id):
		return false
	if world.is_open_court(point):
		var anchor: Marker2D = world.get_node(unit.current_post)
		return anchor.position.distance_to(point) <= Rules.body_to_px(Rules.COVER_LEASH_BODY)
	return true

static func chase_destination(world: Node2D, unit: Node2D, target: Node2D) -> Dictionary:
	if target.floor_id != unit.floor_id or world.is_outside_gate(target.position.x):
		return {}
	var anchor: Marker2D = world.get_node(unit.current_post)
	if absf(target.position.x - anchor.position.x) > Rules.body_to_px(Rules.HUMAN_CHASE_LIMIT):
		return {}
	var reach := Rules.body_to_px(unit.profile.range_body) * 0.75
	var destination := Vector2(target.position.x + signf(unit.position.x - target.position.x) * reach, world.floor_y(unit.floor_id))
	if absf(destination.x - anchor.position.x) > Rules.body_to_px(Rules.HUMAN_CHASE_LIMIT):
		return {}
	if not can_stop(world, unit, destination, unit.floor_id):
		return {}
	return {"point": destination, "floor": unit.floor_id}
