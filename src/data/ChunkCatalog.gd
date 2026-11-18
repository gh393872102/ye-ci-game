extends RefCounted
## Compiles the authored pieces into the same spatial model used by Combat.
const DIRECTORY := "res://data/levels/chunks/"
const CORE := ["C01", "C03", "C04"]
const OPTIONAL := ["C02", "C05", "C06", "C07", "C08", "C09", "C10", "C11", "C12"]
const GEOMETRY := ["sections", "floor_bands", "rooms", "posts", "doors", "stairs", "obstacle_slots", "facilities"]
const COVERS := ["door", "obstacle", "window", "pillar", "table", "stair", "register"]

static func read_chunk(id: String) -> Dictionary:
	if id not in CORE and id not in OPTIONAL:
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + id + ".json"))
	if not data is Dictionary or data.get("id") != id or data.get("scene") != DIRECTORY + id + ".tscn":
		return {}
	if not ResourceLoader.exists(data.scene):
		return {}
	for key in ["default_path", "destructibles", "rituals", "legal_posts", "areas"]:
		if not data.get(key) is Array:
			return {}
	for key in ["title", "upper_access", "failure_line"]:
		if not data.get(key) is String or data[key].is_empty():
			return {}
	if not data.get("layout") is Dictionary or not data.get("visual") is Dictionary or float(data.get("length_body", 0)) <= 0:
		return {}
	return data

static func compose(ids: Array) -> Dictionary:
	var optional: Array[String] = []
	var seen: Dictionary = {}
	for id in ids:
		if not id is String or (id not in CORE and id not in OPTIONAL) or seen.has(id):
			return {}
		seen[id] = true
		if id in OPTIONAL:
			optional.append(id)
	for id in CORE:
		if not seen.has(id):
			return {}
	optional.sort()
	var ordered := CORE + optional
	var layout := {"id":"p10-" + "-".join(ordered), "chunk_ids":ordered, "pieces":[], "ghost_routes":{},
		"areas":[], "path_targets":{}, "hazards":[], "placeholders":[]}
	for key in GEOMETRY:
		layout[key] = []
	for id in ordered:
		var piece := read_chunk(id)
		if piece.is_empty():
			return {}
		layout.pieces.append(piece)
		for section in piece.layout:
			if section not in GEOMETRY or not piece.layout[section] is Array:
				return {}
			layout[section].append_array(piece.layout[section])
		for area in piece.areas:
			var tagged: Dictionary = area.duplicate()
			tagged["chunk_id"] = id
			layout.areas.append(tagged)
		if piece.has("ghost_route"):
			layout.ghost_routes[id] = piece.ghost_route
		if piece.has("hazard"):
			layout.hazards.append(piece.hazard)
		if piece.has("path_targets"):
			layout.path_targets.merge(piece.path_targets)
		if piece.has("source"):
			layout["chunk_source"] = piece.source
		for key in ["base_region", "ghost_main_path", "retreat_line", "bridge_object"]:
			if piece.has(key):
				layout[key] = piece[key]
	for piece in layout.pieces:
		for section in piece.get("overrides", {}):
			if section not in GEOMETRY:
				return {}
			var key := "floor_id" if section == "floor_bands" else "id"
			for override in piece.overrides[section]:
				var original := _find(layout[section], key, override.get(key))
				if original.is_empty():
					return {}
				original.merge(override, true)
	return layout if _legal(layout) else {}

static func generate(seed: String, weights: Dictionary = {}, required: Array = []) -> Dictionary:
	var fixed := CORE.duplicate()
	for id in required:
		if id not in CORE and id not in OPTIONAL:
			return {}
		if id not in fixed:
			fixed.append(id)
	for attempt in range(1, 25):
		var rng := RandomNumberGenerator.new()
		rng.seed = (seed + ":" + str(attempt)).hash()
		var picked := fixed.duplicate()
		var available := OPTIONAL.filter(func(id): return id not in fixed and float(weights.get(id, 1)) > 0)
		while picked.size() < 5 and not available.is_empty():
			var total := 0.0
			for id in available:
				total += float(weights.get(id, 1))
			var draw := rng.randf() * total
			for index in available.size():
				draw -= float(weights.get(available[index], 1))
				if draw <= 0 or index == available.size() - 1:
					picked.append(available.pop_at(index))
					break
		var layout := compose(picked)
		if not layout.is_empty():
			return {"chunk_ids":layout.chunk_ids, "layout":layout, "attempts":attempt}
	return {}

static func _find(entries: Array, key: String, value: Variant) -> Dictionary:
	for spec in entries:
		if spec is Dictionary and spec.get(key) == value:
			return spec
	return {}

static func _on_floor(floors: Dictionary, floor_id: int, x: float) -> bool:
	return floors.has(floor_id) and x >= float(floors[floor_id].start) and x <= float(floors[floor_id].end)

static func _legal(layout: Dictionary) -> bool:
	var floors := {}
	for band in layout.floor_bands:
		var id := int(band.floor_id)
		if floors.has(id) or float(band.start) < 0 or float(band.end) > Rules.REFERENCE_MAP_WIDTH_BODY or band.start >= band.end:
			return false
		floors[id] = band
	var register := _find(layout.rooms, "id", "register")
	if register.is_empty() or register.end - register.start < 8 or not floors.has(0):
		return false
	if floors[0].start != 0 or floors[0].end != Rules.REFERENCE_MAP_WIDTH_BODY:
		return false
	var main: Array = layout.get("ghost_main_path", [])
	if main.size() < 2 or float(main.front()[0]) != 0.0 or int(main.front()[1]) != 0 or int(main.back()[1]) != 0 or main.back()[0] < register.start:
		return false
	var free_seconds := float(register.start) / Rules.WALK_SPEED_REF
	if free_seconds < 45.0 or free_seconds > 70.0 or layout.base_region.start < 20:
		return false
	var reachable := {0:true}
	for stair in layout.stairs:
		if not _on_floor(floors, int(stair.from_floor), stair.from_x) or not _on_floor(floors, int(stair.to_floor), stair.to_x):
			return false
	var extra_time := 0.0
	for route in layout.ghost_routes.values():
		var entry := _find(layout.stairs, "id", route.entry)
		var exit := _find(layout.stairs, "id", route.exit)
		if entry.is_empty() or exit.is_empty() or entry.from_floor != 0 or exit.to_floor != 0 or entry.to_floor != exit.from_floor:
			return false
		if entry.from_x > entry.to_x or entry.to_x >= exit.from_x or exit.from_x >= exit.to_x or exit.to_x >= register.start:
			return false
		for link in [entry, exit]:
			var dx := float(link.to_x - link.from_x)
			var dy := float(floors[int(link.to_floor)].offset - floors[int(link.from_floor)].offset) * Rules.STORY_HEIGHT_PX / Rules.BODY_PX
			extra_time += (Vector2(dx,dy).length() / Rules.STAIR_SPEED_FACTOR - dx) / Rules.WALK_SPEED_REF
	if free_seconds + extra_time > 70.0:
		return false
	for _pass in floors.size():
		for stair in layout.stairs:
			var from := int(stair.from_floor)
			var to := int(stair.to_floor)
			if reachable.has(from) or reachable.has(to):
				reachable[from] = true
				reachable[to] = true
	if not reachable.has(2) or not reachable.has(3):
		return false
	var objects := {}
	for spec in layout.posts + layout.doors + layout.obstacle_slots + layout.facilities:
		if objects.has(spec.id) or not _on_floor(floors, int(spec.floor_id), spec.x):
			return false
		objects[spec.id] = true
	var posts := {}
	for post in layout.posts:
		var room := _find(layout.rooms, "id", post.room_id)
		if post.x < layout.base_region.start or post.cover_kind not in COVERS or not reachable.has(int(post.floor_id)):
			return false
		if room.is_empty() or room.floor_id != post.floor_id or post.x < room.start or post.x >= room.end:
			return false
		posts[post.id] = true
	for id in layout.retreat_line:
		if not posts.has(id):
			return false
	for piece in layout.pieces:
		for id in piece.legal_posts:
			if not posts.has(id):
				return false
		for id in piece.destructibles:
			if not objects.has(id):
				return false
	var obstacle_count := 0
	for slot in layout.obstacle_slots:
		if slot.occupied and int(slot.floor_id) == 0:
			obstacle_count += 1
	return obstacle_count in [2, 3]
