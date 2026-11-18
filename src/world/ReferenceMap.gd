extends Node2D
## P1 explicit spatial model; rendering and navigation share the same geometry.
const Door = preload("res://src/world/WorldDoor.gd")
const Obstacle = preload("res://src/world/WorldObstacle.gd")
const Walker = preload("res://src/debug/DebugWalker.gd")
const Navigation = preload("res://src/world/WalkNetwork.gd")
const Drawing = preload("res://src/world/MapDrawing.gd")
var layout: Dictionary
var posts: Array[Marker2D] = []
var placeholders: Array[Node2D] = []
var doors: Array[StaticBody2D] = []
var obstacles: Array[StaticBody2D] = []
var navigation: RefCounted
var drawing: RefCounted
var font: Font = preload("res://resources/p9_theme.tres").default_font
var spawn_placeholders := true
var combatants: Array[Node2D] = []
var chunk_pieces: Array[Node2D] = []
var _geometry_nodes: Array[Node] = []

func _ready() -> void:
	if layout.is_empty():
		layout = _reference_layout()
	_build_layout()

func configure_layout(next_layout: Dictionary) -> void:
	layout = next_layout if not next_layout.is_empty() else _reference_layout()
	if not is_node_ready():
		return
	for child in _geometry_nodes:
		child.free()
	_geometry_nodes.clear()
	posts.clear()
	placeholders.clear()
	doors.clear()
	obstacles.clear()
	chunk_pieces.clear()
	_build_layout()

func _reference_layout() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/reference_gate_court.json"))

func _build_layout() -> void:
	for spec in layout.floor_bands:
		var band := StaticBody2D.new()
		band.name = "FloorBand%d" % spec.floor_id
		band.add_to_group("floors")
		band.set_meta("floor_id", int(spec.floor_id))
		band.collision_layer = 1
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(Rules.body_to_px(spec.end - spec.start), 16)
		collision.shape = shape
		collision.position = Vector2(Rules.body_to_px((spec.start + spec.end) / 2.0), floor_y(int(spec.floor_id)) + 8)
		band.add_child(collision)
		_add_geometry(band)
	for spec in layout.doors:
		var door := Door.new()
		door.configure(spec, floor_y(int(spec.floor_id)))
		_add_geometry(door)
		door.state_changed.connect(redraw_geometry)
		doors.append(door)
	for spec in layout.obstacle_slots + layout.facilities:
		var object := Obstacle.new()
		object.configure(spec, floor_y(int(spec.floor_id)))
		_add_geometry(object)
		obstacles.append(object)
	for spec in layout.posts:
		var post := Marker2D.new()
		post.name = spec.id
		post.position = Vector2(Rules.body_to_px(spec.x), floor_y(int(spec.floor_id)))
		for field in ["floor_id", "room_id", "allowed_roles", "default_deployment", "cover_kind"]:
			post.set_meta(field, spec[field])
		post.add_to_group("cover_posts")
		_add_geometry(post)
		posts.append(post)
	for spec in layout.placeholders if spawn_placeholders else []:
		var unit := Walker.new()
		unit.name = spec.id
		unit.world = self
		unit.position = Vector2(Rules.body_to_px(spec.x), Rules.HORIZON_Y)
		unit.set_meta("unit_id", spec.id)
		unit.set_meta("side", spec.side)
		unit.set_meta("floor_id", 0)
		unit.set_meta("current_post", spec.post)
		unit.set_meta("ai_state", "P1_IDLE")
		unit.add_to_group("units")
		_add_geometry(unit)
		placeholders.append(unit)
	navigation = Navigation.new(self)
	drawing = Drawing.new(self)
	for spec in layout.get("pieces", []):
		var piece: Node2D = load(spec.scene).instantiate()
		piece.spec = spec
		piece.world = self
		_add_geometry(piece)
		chunk_pieces.append(piece)
	queue_redraw()

func _add_geometry(node: Node) -> void:
	add_child(node)
	_geometry_nodes.append(node)

func redraw_geometry() -> void:
	queue_redraw()
	for piece in chunk_pieces:
		piece.queue_redraw()

func _draw() -> void:
	if drawing != null:
		drawing.draw_map()

func floor_y(floor_id: int) -> float:
	for band in layout.floor_bands:
		if int(band.floor_id) == floor_id:
			return Rules.HORIZON_Y - band.offset * Rules.STORY_HEIGHT_PX
	return INF

func is_outside_gate(x: float) -> bool:
	return x < Rules.BASE_START_X

func inside_base(point: Vector2) -> bool:
	return not is_outside_gate(point.x) and point.x <= Rules.REFERENCE_MAP_WIDTH_PX

func is_open_court(point: Vector2) -> bool:
	if point.y < Rules.HORIZON_Y - Rules.WALK_BAND_DEPTH_PX or point.y > Rules.HORIZON_Y:
		return false
	for interval in layout.base_region.court_intervals:
		if point.x >= Rules.body_to_px(interval[0]) and point.x < Rules.body_to_px(interval[1]):
			return true
	return false

func is_cover_post(point: Vector2) -> bool:
	for post in posts:
		if post.position.distance_to(point) <= 10 and can_deploy_at(post.name):
			return true
	return false

func can_deploy_at(post_id: String) -> bool:
	for post in posts:
		if post.name == post_id:
			return bool(post.get_meta("default_deployment")) and inside_base(post.position) and is_walkable(post.position, int(post.get_meta("floor_id")))
	return false

func is_walkable(point: Vector2, floor_id: int) -> bool:
	if not inside_base(point):
		return false
	for band in layout.floor_bands:
		if int(band.floor_id) == floor_id:
			return point.x >= Rules.body_to_px(band.start) and point.x <= Rules.body_to_px(band.end) and point.y <= floor_y(floor_id) + 0.01 and point.y >= floor_y(floor_id) - Rules.WALK_BAND_DEPTH_PX
	return false

func same_band(a: Vector2, b: Vector2, floor_id: int) -> bool:
	return is_walkable(a, floor_id) and is_walkable(b, floor_id)

func room_at(point: Vector2, floor_id: int) -> String:
	for room in layout.rooms:
		if int(room.floor_id) == floor_id and point.x >= Rules.body_to_px(room.start) and point.x < Rules.body_to_px(room.end):
			return room.id
	return ""

func chunk_at(point: Vector2, floor_id: int) -> String:
	var area := chunk_area_at(point, floor_id)
	return str(area.get("chunk_id", ""))

func chunk_area_at(point: Vector2, floor_id: int) -> Dictionary:
	var areas: Array = layout.get("areas", [])
	for index in range(areas.size() - 1, -1, -1):
		var area: Dictionary = areas[index]
		if int(area.floor_id) == floor_id and point.x >= Rules.body_to_px(area.start) and point.x < Rules.body_to_px(area.end):
			return area
	return {}

func is_upper_floor(floor_id: int) -> bool:
	return floor_id in [2, 3] if layout.has("chunk_ids") else floor_id > 0

func stair_link(id: String) -> Dictionary:
	for stair in layout.stairs:
		if stair.id == id:
			return stair
	return {}

func path_is_open(id: String) -> bool:
	if id in get_meta("broken_paths", []):
		return false
	var target_id: String = layout.get("path_targets", {}).get(id, "")
	var target := get_node_or_null(target_id) if not target_id.is_empty() else null
	return target == null or target.durability > 0

func break_path_structure(id: String) -> void:
	var target_id: String = layout.get("path_targets", {}).get(id, "")
	if not target_id.is_empty():
		var target := get_node_or_null(target_id)
		if target != null:
			target.receive_damage(target.durability)

func ghost_branch(x: float, lane: int, unit_id: String, bridge_only: bool) -> String:
	var routes: Dictionary = layout.get("ghost_routes", {})
	var chosen := ""
	var nearest := INF
	for id in routes:
		if bridge_only and id != "C07":
			continue
		var route: Dictionary = routes[id]
		if not bridge_only and not route.lanes.any(func(index): return int(index) == lane) and unit_id not in route.get("units", []):
			continue
		if unit_id in route.get("excluded_units", []):
			continue
		if not path_is_open(route.entry) or not path_is_open(route.exit):
			continue
		var start := Rules.body_to_px(stair_link(route.entry).from_x)
		if start >= x - 0.01 and start < nearest:
			chosen = id
			nearest = start
	return chosen

func apply_hazards(unit: Node2D, previous: Vector2, previous_floor: int) -> void:
	if previous_floor != unit.floor_id or is_equal_approx(previous.x, unit.position.x):
		return
	for hazard in layout.get("hazards", []):
		if int(hazard.floor_id) != unit.floor_id or unit.position.y < floor_y(unit.floor_id) - float(hazard.depth_px):
			continue
		var barrier := get_node_or_null(hazard.object)
		var x := Rules.body_to_px(hazard.x)
		if barrier != null and barrier.durability <= 0 and (previous.x < x) != (unit.position.x < x):
			unit.receive_damage(float(hazard.damage), null, "well_fall")
			unit.simulation.record_event("well_fall", unit, str(hazard.object))

func segment_blocked(a: Vector2, b: Vector2, floor_id: int, ignore_doors := false) -> bool:
	for object in obstacles:
		if object.floor_id == floor_id and object.occupied and object.blocks_walk and _hits_rect(a, b, object.blocking_rect().grow(Rules.FOOT_RADIUS_PX)):
			return true
	if not ignore_doors:
		for door in doors:
			if door.floor_id == floor_id and not door.is_open and _hits_rect(a, b, door.blocking_rect().grow(Rules.FOOT_RADIUS_PX)):
				return true
	return false

func _hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[index], corners[(index + 1) % 4]) != null:
			return true
	return false

func set_all_doors_open(value: bool) -> void:
	for door in doors:
		door.set_open(value)

func retreat_polyline() -> PackedVector2Array:
	var line := PackedVector2Array()
	for index in layout.retreat_line.size():
		var post: Marker2D = get_node(layout.retreat_line[index])
		if index == 0:
			line.append(post.position)
			continue
		var previous: Marker2D = get_node(layout.retreat_line[index - 1])
		var route: Array[Dictionary] = navigation.route(previous.position, int(previous.get_meta("floor_id")), post.position, int(post.get_meta("floor_id")), true)
		for step in route:
			line.append(step.point)
	return line

func ghost_path_length() -> float:
	var length := 0.0
	var previous := Vector2.ZERO
	for index in layout.ghost_main_path.size():
		var entry: Array = layout.ghost_main_path[index]
		var point := Vector2(Rules.body_to_px(entry[0]), floor_y(int(entry[1])))
		if index > 0:
			length += previous.distance_to(point)
		previous = point
	return length

func visible_units() -> Array[Node2D]:
	return placeholders if spawn_placeholders else combatants
