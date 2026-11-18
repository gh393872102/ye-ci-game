extends RefCounted
## Explicit floor intervals and stair links, never a free-space/grid shortcut outside base.
var world: Node2D

func _init(map: Node2D) -> void:
	world = map

func route(from: Vector2, from_floor: int, target: Vector2, target_floor: int, ignore_doors := false) -> Array[Dictionary]:
	if not world.is_walkable(from, from_floor) or not world.is_walkable(target, target_floor):
		return []
	var nodes: Array[Dictionary] = [{"point": from, "floor": from_floor}, {"point": target, "floor": target_floor}]
	var stair_pairs: Dictionary = {}
	for stair in world.layout.stairs:
		if not world.path_is_open(str(stair.id)): continue
		var a := nodes.size()
		nodes.append({"point": Vector2(Rules.body_to_px(stair.from_x), world.floor_y(int(stair.from_floor))), "floor": int(stair.from_floor)})
		nodes.append({"point": Vector2(Rules.body_to_px(stair.to_x), world.floor_y(int(stair.to_floor))), "floor": int(stair.to_floor)})
		stair_pairs[Vector2i(a, a + 1)] = stair.id
		stair_pairs[Vector2i(a + 1, a)] = stair.id
	var distances: Array[float] = []
	var previous: Dictionary = {}
	var paths: Dictionary = {}
	var visited: Array[int] = []
	distances.resize(nodes.size())
	distances.fill(INF)
	distances[0] = 0
	for iteration in nodes.size():
		var best := -1
		for i in nodes.size():
			if not visited.has(i) and (best < 0 or distances[i] < distances[best]):
				best = i
		if best < 0 or distances[best] == INF:
			break
		if best == 1:
			break
		visited.append(best)
		for next in nodes.size():
			if next == best or visited.has(next):
				continue
			var path: Array[Dictionary] = []
			if stair_pairs.has(Vector2i(best, next)):
				var step := {"point": nodes[next].point, "floor": nodes[next].floor, "stair": true}
				if world.layout.has("chunk_ids"):
					step["link"] = stair_pairs[Vector2i(best, next)]
				path.append(step)
			elif nodes[best].floor == nodes[next].floor:
				path = horizontal_path(nodes[best].point, nodes[next].point, nodes[best].floor, ignore_doors)
			if path.is_empty():
				continue
			var length := 0.0
			var last: Vector2 = nodes[best].point
			for step in path:
				length += last.distance_to(step.point) / (Rules.STAIR_SPEED_FACTOR if step.stair else 1.0)
				last = step.point
			if distances[best] + length < distances[next]:
				distances[next] = distances[best] + length
				previous[next] = best
				paths[next] = path
	if not previous.has(1):
		return []
	var result: Array[Dictionary] = []
	var index := 1
	while index != 0:
		var head: Array[Dictionary] = paths[index].duplicate()
		head.append_array(result)
		result = head
		index = previous[index]
	return result

func horizontal_path(from: Vector2, target: Vector2, floor_id: int, ignore_doors: bool) -> Array[Dictionary]:
	if not world.same_band(from, target, floor_id):
		return []
	if not ignore_doors:
		for door in world.doors:
			if door.floor_id == floor_id and not door.is_open and _crosses_x(from.x, target.x, door.position.x):
				return []
	var points: Array[Vector2] = []
	var ascending := target.x >= from.x
	var barriers: Array = []
	for object in world.obstacles:
		if object.floor_id == floor_id and object.occupied and object.blocks_walk and maxf(from.x, target.x) > object.position.x - Rules.PATH_CLEARANCE_PX and minf(from.x, target.x) < object.position.x + object.width + Rules.PATH_CLEARANCE_PX:
			barriers.append(object)
	barriers.sort_custom(func(a, b): return a.position.x < b.position.x if ascending else a.position.x > b.position.x)
	var floor_y: float = world.floor_y(floor_id)
	for object in barriers:
		var entry: float = object.position.x - Rules.PATH_CLEARANCE_PX if ascending else object.position.x + object.width + Rules.PATH_CLEARANCE_PX
		var leave: float = object.position.x + object.width + Rules.PATH_CLEARANCE_PX if ascending else object.position.x - Rules.PATH_CLEARANCE_PX
		entry = clampf(entry, minf(from.x, target.x), maxf(from.x, target.x))
		leave = clampf(leave, minf(from.x, target.x), maxf(from.x, target.x))
		points.append(Vector2(entry, from.y if points.is_empty() else floor_y))
		points.append(Vector2(entry, floor_y - Rules.GAP_LANE_OFFSET_PX))
		points.append(Vector2(leave, floor_y - Rules.GAP_LANE_OFFSET_PX))
		points.append(Vector2(leave, target.y if is_equal_approx(leave, target.x) else floor_y))
	points.append(target)
	var result: Array[Dictionary] = []
	var last := from
	for point in points:
		if not world.is_walkable(point, floor_id) or world.segment_blocked(last, point, floor_id, ignore_doors):
			return []
		if not point.is_equal_approx(last):
			result.append({"point": point, "floor": floor_id, "stair": false})
		last = point
	if result.is_empty():
		result.append({"point": target, "floor": floor_id, "stair": false})
	return result

func _crosses_x(a: float, b: float, x: float) -> bool:
	return minf(a, b) <= x and maxf(a, b) >= x
