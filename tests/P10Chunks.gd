extends SceneTree
## Run through tools/p9_verify.py --script tests/P10Chunks.gd inside its isolated copy.
const CATALOG_PATH := "res://src/data/ChunkCatalog.gd"
const COMBAT_PATH := "res://scenes/combat/Combat.tscn"
const CORE := ["C01", "C03", "C04"]
const SAMPLE_SEEDS := ["4101", "4105", "4110"]
const STEP := 1.0 / 60.0

var output := ""
var failures := 0
var checks: Array[Dictionary] = []
var maps: Array[Dictionary] = []
var timings: Array[Dictionary] = []
var screenshots := []
var catalog: Script
var clock: Node
var rules: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	output = str(args[0]) if not args.is_empty() else ""
	var data := root.get_node("Data")
	if not (output.begins_with("/tmp/ye-ci-p9-") or output.begins_with("/private/tmp/ye-ci-p9-")) or data.codex_store.path != output.path_join("state/codex.json"):
		print("FAIL P10 chunk checks require an isolated copy")
		quit(2)
		return
	catalog = load(CATALOG_PATH)
	clock = root.get_node("Clock")
	rules = root.get_node("Rules")
	clock.set_paused(true)
	check(data.errors.is_empty(), "Data autoload accepts current source tables")
	var all: Array[String] = []
	for index in range(1, 13):
		var id := "C%02d" % index
		all.append(id)
		var spec: Dictionary = catalog.read_chunk(id)
		check(not spec.is_empty(), id + " authored data and PackedScene exist")
		if not spec.is_empty():
			var piece: Node = load(spec.scene).instantiate()
			check(piece.chunk_id == id, id + " standalone scene identifies its source data")
			piece.free()
	var cases := {}
	check(catalog.compose(["C01", "C04"]).is_empty() and catalog.compose(CORE + ["C99"]).is_empty(), "Incomplete and unknown maps are rejected")
	check(catalog.compose(CORE + ["C04"]).is_empty(), "Duplicate blocks are rejected")
	var expanded: Dictionary = catalog.compose(all)
	check(not expanded.is_empty() and expanded.pieces.size() == 12, "All twelve fixtures can coexist in one legal spatial layout")
	for seed in range(4101, 4111):
		var weights := {"C05":2.2, "C08":1.6, "C09":1.5, "C11":1.4}
		var text := str(seed)
		var plan: Dictionary = catalog.generate(text, weights)
		check(not plan.is_empty(), "Seed %s yields a legal map" % text)
		if plan.is_empty():
			continue
		var again: Dictionary = catalog.generate(text, weights)
		check(plan.chunk_ids == again.chunk_ids, "Seed %s deterministically selects the same layout" % text)
		cases[text] = plan.chunk_ids
		maps.append({"seed":text,"chunk_ids":plan.chunk_ids,"attempts":plan.attempts})
	check(_unique_maps() >= 4, "Consecutive seeds produce at least four distinct maps")
	var required: Dictionary = catalog.generate("祭桥", {"C07":0.01}, ["C07"])
	check(not required.is_empty() and "C07" in required.chunk_ids, "A mandatory block survives very low random weight")
	for node in data.night_rules.nodes:
		if node.type in ["battle", "boss"]:
			check(not catalog.compose(node.get("chunk_ids", [])).is_empty(), "Authored example encounter %s is legal" % str(node.id))
	if not expanded.is_empty():
		await _interactions(all)
	for seed in SAMPLE_SEEDS:
		if cases.has(seed):
			await _timed_map(seed, cases[seed])
	_finish()

func _unique_maps() -> int:
	var signature := {}
	for map in maps:
		signature["-".join(map.chunk_ids)] = true
	return signature.size()

func _new_combat(ids: Array, decisions_enabled := false) -> Node2D:
	var combat: Node2D = load(COMBAT_PATH).instantiate()
	combat.decisions_enabled = decisions_enabled
	if not combat.configure_chunks(ids):
		combat.free()
		return null
	root.add_child(combat)
	if not combat.has_node("Simulation"):
		combat.free()
		return null
	combat.get_node("Simulation").set_physics_process(false)
	return combat

func _interactions(all: Array) -> void:
	var combat := _new_combat(all, true)
	check(combat != null, "Configured combat instantiates before attach")
	if combat == null:
		return
	var world := combat.get_node("ReferenceMap")
	var sim := combat.get_node("Simulation")
	var session := combat.get_node("Session")
	session.enter_debug()
	check(world.chunk_pieces.size() == 12, "All twelve PackedScenes are children of the running world")
	var routes := true
	for index in range(1, world.layout.retreat_line.size()):
		var from: Node2D = world.get_node(world.layout.retreat_line[index - 1])
		var to: Node2D = world.get_node(world.layout.retreat_line[index])
		routes = routes and not world.navigation.route(from.position, int(from.get_meta("floor_id")), to.position, int(to.get_meta("floor_id")), true).is_empty()
	check(routes and world.posts.all(func(post): return world.can_deploy_at(str(post.name)) and not world.is_outside_gate(post.position.x)), "Every authored post is in base and the full ground/upper retreat route is connected")
	check(world.is_upper_floor(3) and not world.is_upper_floor(4) and not world.is_upper_floor(5) and not world.is_upper_floor(6), "Low side lanes do not count as upstairs")
	var beam: Node2D = world.get_node("beam_span")
	check(world.path_is_open("stair_beam") and beam.durability == 300, "Beam route starts with authored durability")
	beam.receive_damage(beam.durability)
	check(not world.path_is_open("stair_beam") and world.path_is_open("stair_rear"), "Breaking the beam disconnects only its crossing")
	sim.reset_preset("fixture")
	var side: Node2D = world.get_node("door_side")
	check(side.floor_id == 4 and is_equal_approx(side.max_durability / world.get_node("door_outer").max_durability, 0.7), "Side gate runs on the side route at 70 percent main gate durability")
	var ghost: Node2D = sim.tide.spawn("G12", 2, rules.body_to_px(74))
	if ghost != null:
		for _index in 480:
			sim.advance(STEP)
	check(ghost != null and ghost.floor_id == 4 and side.durability < side.max_durability, "G12 takes the side route and actually damages its gate")
	sim.reset_preset("fixture")
	var rim: Node2D = world.get_node("outer_a")
	rim.receive_damage(rim.durability)
	ghost = sim.tide.spawn("G01", 3, rules.body_to_px(58.0))
	if ghost != null:
		ghost.attacks_enabled = false
		for _index in 12:
			sim.advance(STEP)
	check(ghost != null and sim.events.any(func(event): return event.kind == "well_fall"), "Crossing a breached well rim emits a fall in the real simulation")
	sim.reset_preset("preset_hold_g0")
	sim.tide.config["bridge_reinforcements"] = true
	var bridge: Node2D = world.get_node("stone_bridge")
	check(not sim.tide.bridge_supply_cut() and world.path_is_open("stair_stone_entry"), "Stone bridge starts as a connected main reinforcement route")
	var bridge_x: float = rules.body_to_px(57.5)
	ghost = sim.tide.spawn("G12", 2, bridge_x)
	if ghost != null:
		ghost.attacks_enabled = false
		for _index in 300:
			if ghost.floor_id == 6:
				break
			sim.advance(STEP)
	check(ghost != null and ghost.floor_id == 6, "R06 routes even a non-bridge lane onto the actual bridge floor")
	bridge.receive_damage(bridge.durability)
	var spawned_before: int = sim.tide.spawn_count
	sim.tide.pending.append("G01")
	sim.tide._spawn_pending()
	check(sim.tide.bridge_supply_cut() and not world.path_is_open("stair_stone_entry") and not world.path_is_open("stair_stone_exit") and sim.tide.spawn_count == spawned_before and sim.tide.pending.is_empty(), "Breaking the bridge cuts both links and the route's pending reinforcements")
	sim.tide.config.erase("bridge_reinforcements")
	check(world.chunk_at(Vector2(rules.body_to_px(65),world.floor_y(5)),5) == "C05" and world.chunk_at(Vector2(rules.body_to_px(100),world.floor_y(2)),2) == "C12", "Water and silence special rules query authored areas")
	sim.reset_preset("fixture")
	session.configure_growth("water-test")
	for human in sim.humans:
		human.attacks_enabled = false
	ghost = sim.tide.spawn("G10", 2, rules.body_to_px(51))
	if ghost != null:
		ghost.attacks_enabled = false
		for _index in 300:
			if ghost.floor_id == 5:
				break
			sim.advance(STEP)
	var water_route: bool = is_instance_valid(ghost) and ghost.floor_id == 5 and session.growth.in_environment(ghost,"water")
	check(water_route, "A live G10 takes the water lane and acquires its environment")
	var normal_waves: Array = sim.tide.config.waves.duplicate(true)
	sim.tide.config.waves.clear()
	sim.reset_preset("preset_hold_g0")
	session.configure_growth("fissure-test")
	var source: Dictionary = world.layout.chunk_source
	sim.tide.before_step(float(source.first) - STEP)
	check(sim.targets.is_empty() and sim.tide.has_chunk_supply(), "Fissure reserves timed supply even after the other waves end")
	var seal := world.get_node("door_fissure")
	session.growth.seal_door(sim.humans[0], seal)
	sim.advance(2 * STEP)
	check(sim.targets.is_empty(), "A real temporary ward blocks the fissure's scheduled spawn")
	for _index in 1500:
		if not sim.targets.is_empty():
			break
		sim.advance(STEP)
	check(sim.tide.config.get("chunk_source_used", 0) == 1 and sim.tide.milestones.any(func(event): return event.kind == "fissure_spawn"), "When the ward expires the live fissure spawns a limited wave")
	sim.tide.config.waves = normal_waves
	if DisplayServer.get_name() != "headless":
		combat.get_node("Decisions").prebattle.hide()
		session.start_battle("shouxiang")
		clock.set_paused(true)
		var camera := combat.get_node("BattleCamera")
		root.size = Vector2i(1920, 1080)
		for x in [4330, 6080, 7680]:
			camera.set_left(x)
			await process_frame
			await RenderingServer.frame_post_draw
			var name := "p10-chunks-%d.png" % x
			if root.get_texture().get_image().save_png(output.path_join(name)) == OK:
				screenshots.append(name)
		session.enter_debug()
	check(not session.running and combat.configure_chunks([]) and world.layout.id == "reference_gate_court", "Idle restore can switch the prepared world back to the legacy map")
	combat.free()

func _timed_map(seed: String, ids: Array) -> void:
	var combat := _new_combat(ids)
	if combat == null:
		check(false, "Seed %s can instantiate the actual battle" % seed)
		return
	var world := combat.get_node("ReferenceMap")
	var sim := combat.get_node("Simulation")
	var inspector := combat.get_node("BattleInspector")
	var camera := combat.get_node("BattleCamera")
	check(camera.zoom == Vector2.ONE and absf(camera.left() - 6080) < 0.01, "Seed %s preserves the locked default camera" % seed)
	await process_frame
	await _key(KEY_F5)
	check(sim.tide.preset == "preset_empty_path", "Seed %s uses the actual F5 empty preset" % seed)
	var empty := _measure(sim, 90.0)
	check(empty >= 45.0 and empty <= 70.0, "Seed %s F5 first room entry %.2f s" % [seed, empty])
	var traversed: Array = sim.tide.milestones.filter(func(event): return event.kind == "chunk_enter").map(func(event): return str(event.detail))
	if "C02" in ids or "C07" in ids:
		check(not traversed.is_empty(), "Seed %s F5 actually travels on an authored side path" % seed)
	await _key(KEY_F7)
	check(inspector.enabled, "Seed %s uses the actual F7 hold controls" % seed)
	inspector.buttons.hold_g0.pressed.emit()
	var main_obstacles := 0
	for object in world.obstacles:
		if object.floor_id == 0 and object.occupied and object.max_durability > 0:
			main_obstacles += 1
	check(sim.tide.preset == "preset_hold_g0" and sim.humans.size() == 5 and main_obstacles in [2, 3], "Seed %s holds with default troops, doors and 2–3 main obstacles" % seed)
	var held := _measure(sim, 600.0)
	check(held >= 120.0 and held <= 600.0, "Seed %s hold first room entry %.2f s" % [seed, held])
	timings.append({"seed":seed,"chunk_ids":ids,"simulation_step":STEP,"f5_seconds":empty,"hold_seconds":held,
		"f5_traversed_chunks":traversed,"hold_arrived_by":sim.tide.arrived_by,"main_obstacles":main_obstacles,"awake_actors":sim.targets.size()})
	combat.free()

func _measure(sim: Node, limit: float) -> float:
	for _step in int(limit / STEP):
		if sim.tide.arrival >= 0:
			break
		sim.advance(STEP)
	return sim.tide.arrival

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame

func check(condition: bool, message: String) -> void:
	checks.append({"check":message,"passed":condition})
	failures += 0 if condition else 1
	print("%s %s" % ["PASS" if condition else "FAIL", message])

func _finish() -> void:
	var file := FileAccess.open(output.path_join("p10-chunks.json"), FileAccess.WRITE)
	if file == null:
		print("FAIL Could not write P10 chunk evidence")
		quit(2)
		return
	file.store_string(JSON.stringify({"checks":checks.size(),"failures":failures,"results":checks,
		"continuous_seeds":maps,"timings":timings,"native_screenshots":screenshots}, "\t") + "\n")
	file.close()
	quit(1 if failures > 0 else 0)
