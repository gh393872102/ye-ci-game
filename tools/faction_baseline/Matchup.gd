extends SceneTree
## One row of a controlled, full-duration matchup matrix. Usage in README.md.
const HUMAN := ["守香司","武卫司","符法司","奇人司"]
const GHOST := ["无名潮","习俗厉","大形","无册谱"]
const SEED_TEXT := "YECI-FACTION-BASELINE-01"
const STEP := 1.0 / 60.0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [1, 2] or not args[0].is_valid_int() or int(args[0]) not in range(4) or (args.size() == 2 and args[1] not in ["equal", "hold", "equal-hold", "equal-rear-hold"]):
		push_error("Pass a defending faction index from 0 to 3 after --")
		quit(1)
		return
	var index := int(args[0])
	var variant := args[1] if args.size() == 2 else "row"
	var rows := []
	for ghost in GHOST:
		var row: Dictionary = await matchup(HUMAN[index], ghost, variant)
		if not row.has("winner"):
			push_error(str(row))
			quit(1)
			return
		print(row.human, " vs ", row.ghost, " => ", row.winner, " ", row.reason, " ", row.elapsed)
		rows.append(row)
	var file := FileAccess.open("res://tools/faction_baseline/%s-%d.json" % [variant, index], FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(rows, "\t") + "\n")
	file.close()
	await create_timer(0.5).timeout
	quit()

func matchup(human: String, ghost: String, variant: String) -> Dictionary:
	var data := root.get_node("Data")
	var scene: Node = load("res://scenes/combat/Combat.tscn").instantiate()
	root.add_child(scene)
	var sim: Node = scene.get_node("Simulation")
	var session: Node = scene.get_node("Session")
	sim.set_physics_process(false)
	session.running = false
	session.start_battle("shouxiang")
	for unit in sim.humans + sim.targets + sim.corpses + sim.projectiles:
		unit.free()
	sim.humans.clear()
	sim.targets.clear()
	sim.corpses.clear()
	sim.projectiles.clear()
	sim.tide.pending.clear()
	sim.tide.config.waves = []
	sim.tide.wave_index = 0
	session.configure_dual(session.rules.starting_incense, "")
	session.configure_roster(SEED_TEXT)
	if variant.ends_with("hold"):
		session.growth.state.defense_objective = "hold_register"
	var guard_posts := {}
	var ghosts := []
	var ineligible := []
	for id in data.units.keys():
		var card: Dictionary = data.get_unit(id)
		if card.get("所属","") == human:
			var posts: Array = session.legal_posts(id)
			if posts.is_empty():
				ineligible.append(id)
				continue
			var post: String = posts.front()
			if variant == "equal-rear-hold":
				for preferred in ["post_register", "post_hall_door", "post_inner_gate"]:
					if preferred in posts:
						post = preferred
						break
			guard_posts[id] = post
			sim.spawn_human(id, post)
		if card.get("谱系","") == ghost:
			ghosts.append(id)
	if ghosts.size() != 8 or guard_posts.is_empty():
		return {"error":"Unexpected faction catalogue"}
	if variant.begins_with("equal"):
		var subset := []
		for index in guard_posts.size():
			subset.append(ghosts[floori(float(index) * ghosts.size() / guard_posts.size())])
		ghosts = subset
	for index in ghosts.size():
		sim.tide.spawn(ghosts[index], index % 4, -floori(index / 4.0) * float(sim.tide.config.spacing))
	if sim.targets.size() != ghosts.size():
		return {"error":"Unexpected initial roster", "guards":guard_posts, "ghosts":ghosts}
	sim._update_units()
	var result: Dictionary = {"human":human, "ghost":ghost, "seed":SEED_TEXT, "guard_posts":guard_posts, "ineligible_guards":ineligible, "ghost_ids":ghosts}
	var max_steps := ceili(float(session.rules.duration) / STEP) + 2
	for tick in max_steps:
		sim.advance(STEP)
		if not session.running:
			break
		if tick % 120 == 0:
			await process_frame
	if session.result.has("winner"):
		for key in ["winner","reason","elapsed","humans_alive","tide_alive","names"]:
			result[key] = session.result[key]
	result.elapsed = snappedf(float(result.get("elapsed",0.0)), 0.001)
	scene.queue_free()
	await process_frame
	await process_frame
	return result
