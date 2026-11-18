extends SceneTree
## Native screenshot and atlas checks. Run with tools/p9_verify.py --native --script tools/p11r_unit_art_smoke.gd.
const CORE := ["C01", "C03", "C04"]
var output: String
var appearance: Script
var combat: Node2D
var sim: Node2D
var session: Node
var camera: Camera2D
var results: Array[Dictionary] = []
var shots: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else ""
	var data := root.get_node("Data")
	if not output.begins_with("/private/tmp/ye-ci-p9-") or data.codex_store.path != output.path_join("state/codex.json"):
		printerr("Use the isolated P9 verification runner.")
		quit(2)
		return
	appearance = load("res://src/units/UnitAppearance.gd")
	_verify_catalog()
	if not _check(DisplayServer.get_name() != "headless" and data.errors.is_empty(), "Native viewport and production data"):
		_finish()
		return
	root.size = Vector2i(1920, 1080)
	AudioServer.set_bus_mute(0, true)
	combat = load("res://scenes/combat/Combat.tscn").instantiate()
	if not _check(combat.configure_chunks(CORE), "The authored court, main hall, upper rooms and ledger compose"):
		_finish()
		return
	root.add_child(combat)
	camera = combat.get_node("BattleCamera")
	camera.make_current()
	sim = combat.get_node("Simulation")
	session = combat.get_node("Session")
	sim.set_physics_process(false)
	var decisions := combat.get_node("Decisions")
	decisions.managed_by_night = true
	decisions.prebattle.hide()
	sim.tide.config.waves.clear()
	if not _check(session.start_battle("shouxiang").ok, "The battle uses the combat scene entry point"):
		_finish()
		return
	for actor in sim.humans:
		actor.free()
	sim.humans.clear()
	session.configure_roster("p11r-unit-native")
	session.configure_dual({"shouxiang": 60.0, "duoming": 60.0}, "shouxiang")
	var holds := [["H09", "post_hall_door"], ["H01", "post_table_hall"],
		["H17", "post_window_1"], ["T02", "post_window_2"], ["H06", "post_window_2"]]
	var defenders := {}
	for row in holds:
		var actor: Node2D = sim.spawn_human(row[0], row[1])
		if not _check(actor != null and session.deployment_reason(row[1], "").is_empty(), "Legal cover post for " + row[0]):
			_finish()
			return
		actor.position = sim.post_destination(actor, row[1])
		actor.brain.settled_position = actor.position
		actor.motion_enabled = false
		defenders[row[0]] = actor
	for column in 11:
		for lane in 4:
			var id := "G01"
			if lane == 0 and column in [2, 7]:
				id = "G09"
			elif lane == 1 and column == 8:
				id = "G11"
			elif lane == 3 and column == 6:
				id = "G12"
			elif lane == 0 and column == 5:
				id = "G17"
			var x: float = camera.left() + 40.0 + column * 78.0 + lane * 11.0
			sim.tide.spawn(id, lane, x)
	var lane_y := {}
	for ghost in sim.targets:
		lane_y[ghost.lane_index] = ghost.position.y
	_check(sim.targets.size() == 44 and lane_y.size() == 4, "44 real tide actors occupy four authored lane levels", lane_y)
	var inside := defenders.values().all(func(actor):
		return sim.world.inside_base(actor.position) and not sim.world.is_open_court(actor.position)
	)
	_check(inside, "The defenders are on indoor side of doors, windows and tables")
	var model_heights := {}
	for actor in sim.humans + sim.targets:
		model_heights[actor.unit_id] = actor.height_px
	_check(model_heights.H01 == 80.0 and model_heights.G01 == 80.0
		and model_heights.G12 == float(data.roster_rules.profiles.G12.height_px)
		and model_heights.G17 == float(data.roster_rules.profiles.G17.height_px) and model_heights.G17 > 120.0,
		"Ordinary actors and the stone mountain giant keep their roster heights", model_heights)
	for actor in sim.humans:
		actor.attacks_enabled = false
	for index in 7:
		sim.advance(1.0 / 60.0)
	await _shot("01-unit-roles-and-tide")
	var reader: Node2D = defenders.H01
	var thief: Node2D = sim.tide.spawn("G28", 1, reader.position.x + 56.0)
	thief.floor_id = reader.floor_id
	thief.position.y = reader.position.y
	thief.sync_meta()
	sim._update_units()
	var answer: Dictionary = session.execute_for("duoming", "unit_skill", {
		"unit_id": thief.instance_id, "target_id": reader.instance_id
	}, "ai")
	_check(answer.ok and appearance.face_state(reader) == "faceless", "Real face theft updates the illustrated reader")
	await _shot("02-live-face-theft")
	var masker: Node2D = sim.spawn_human("H32", reader.current_post)
	masker.position = reader.position + Vector2(105.0, 0.0)
	sim._update_units()
	answer = session.execute_for("shouxiang", "unit_skill", {
		"unit_id": masker.instance_id, "target_id": reader.instance_id
	}, "player")
	_check(answer.ok and appearance.face_state(reader) == "faced", "Real mask restoration returns the illustrated face")
	await _shot("03-live-face-restored")
	if shots.size() == 3:
		var first: String = shots["01-unit-roles-and-tide"].reader_pixels
		var blank: String = shots["02-live-face-theft"].reader_pixels
		var recovered: String = shots["03-live-face-restored"].reader_pixels
		_check(first != blank and first == recovered, "Face pixels change on theft and restore while simulation is still paused")
	combat.free()
	await process_frame
	_finish()

func _verify_catalog() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/p11_sprite_atlas.json"))
	var ids := 0
	var animated := 0
	var unique := {}
	for id: String in catalog.units:
		if id.begins_with("F"):
			continue
		ids += 1
		var row: Dictionary = catalog.units[id]
		var texture: Texture2D = appearance._sprite_sheet(row.sheet)
		if row.frames.size() == 3:
			animated += 1
		var all_in_bounds := texture != null
		for frame: Array in row.frames:
			var key := "%s/%d/%d" % [row.sheet, int(frame[0]), int(frame[1])]
			if unique.has(key) or int(frame[0]) not in range(4) or int(frame[1]) not in range(3):
				all_in_bounds = false
			unique[key] = true
		_check(all_in_bounds, "Independent in-bounds atlas cell for " + id)
	_check(ids == 68 and animated >= 20, "The full 32 + 32 + 4 roster and at least 20 pose sets cover live combat",
		{"identities": ids, "three_pose_sets": animated})
	for id in ["G11", "G17", "G19", "G32"]:
		var texture: Texture2D = appearance.portrait_texture(id)
		_check(texture != null and texture.get_size() == Vector2(1024, 1536), "Revised panel portrait loads through production entry " + id)
	for id in ["F01", "F02", "F03"]:
		var fusion: Dictionary = appearance._sprite_spec(id)
		_check(fusion.get("sheet") == "fusion_poses" and fusion.frames.size() == 3,
			"Dedicated inherited-height fusion sprite for " + id)

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(true)
	var frame := root.get_texture().get_image()
	if _check(frame != null and frame.get_size() == Vector2i(1920, 1080)
			and camera.zoom == Vector2.ONE and camera.left() == 6080.0, "Native default crop " + name):
		var path := output.path_join(name + ".png")
		var reader: Node2D = sim.humans.filter(func(actor): return actor.unit_id == "H01")[0]
		var sprite: Array = appearance._sprite_spec("H01").frames[0]
		var location := reader.position + Vector2(-float(sprite[2]), float(sprite[3]))
		var head: Vector2 = camera.get_canvas_transform() * location
		var pixels := frame.get_region(Rect2i(Vector2i(head) - Vector2i(3, 3), Vector2i(7, 7)))
		_check(frame.save_png(path) == OK, "Screenshot writes " + name)
		shots[name] = {"resolution": [1920, 1080], "zoom": 1.0, "camera_left": 6080.0,
			"reader_head_xy": [head.x, head.y], "sha256": FileAccess.get_sha256(path),
			"reader_pixels": pixels.get_data().hex_encode().sha256_text()}

func _check(ok: bool, label: String, observed: Variant = null) -> bool:
	results.append({"ok": ok, "check": label, "observed": observed})
	print(("PASS " if ok else "FAIL ") + label)
	return ok

func _finish() -> void:
	var failed := results.filter(func(row): return not row.ok).size()
	var file := FileAccess.open(output.path_join("unit-art-results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info().string,
		"checks": results.size(), "failed": failed, "results": results, "shots": shots}, "  ", false) + "\n")
	file.close()
	quit(0 if failed == 0 else 1)
