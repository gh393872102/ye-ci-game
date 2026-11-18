extends SceneTree
## Run with tools/p9_verify.py --script tests/P10SaveSuite.gd in its disposable copy.
const NIGHT := "res://scenes/night/Night.tscn"
const COMBAT := "res://scenes/combat/Combat.tscn"
const POST := "post_side_gate"
const SEED := "AUDIT-8"
var output := ""
var clock: Node
var save: Script
var results: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	output = str(args[0]) if not args.is_empty() else ""
	if not (output.begins_with("/tmp/ye-ci-p9-") or output.begins_with("/private/tmp/ye-ci-p9-")) or root.get_node("Data").codex_store.path != output.path_join("state/codex.json"):
		print("FAIL P10 saves require an isolated project copy")
		quit(2)
		return
	clock = root.get_node("Clock")
	save = load("res://src/night/NightSave.gd")
	var host: Node = load(NIGHT).instantiate()
	root.add_child(host)
	host.start_p10_night("shouxiang","fierce",SEED,"R01",[])
	if not check(host.run.state.get("phase") == "map", "Fierce night starts through the actual host"):
		_finish()
		return
	host.choose_node("n01")
	if not check(is_instance_valid(host.combat) and host.combat.get_node("ReferenceMap").can_deploy_at(POST), "Seed opens a real battle with a legal optional side post"):
		_finish()
		return
	var door: Node2D = host.combat.get_node("ReferenceMap/door_side")
	door.receive_damage(door.durability - 321.0)
	host.save_run()
	var live: Node = host.combat
	host.continue_run()
	check(host.combat != live and host.combat.get_node("ReferenceMap/door_side").durability == 321.0, "A valid disk save restores the damaged side gate")
	var clean: Dictionary = save.load_save(host.save_path)
	if not check(clean.ok, "Healthy battle save loads with a matching checksum"):
		_finish()
		return
	for damage in ["missing", "duplicate", "mistyped"]:
		_reject_bad_structures(host, clean.state, damage)
	check(save.save(host.save_path,clean.state).ok, "Original isolated save is restored after validation fixtures")
	_carried_post(host)
	host.free()
	var idle: Node2D = load(COMBAT).instantiate()
	root.add_child(idle)
	var panel: Node = idle.get_node("Decisions")
	var highlighter: Node2D = panel.highlights
	check(idle.configure_chunks(["C01","C03","C04","C02"]) and is_instance_valid(highlighter) and panel.highlights == highlighter, "Replay preparation preserves the external decision highlighter")
	idle.free()
	_finish()

func _reject_bad_structures(host: Node, clean: Dictionary, damage: String) -> void:
	var fixture := clean.duplicate(true)
	var snapshot: Dictionary = fixture.battle_snapshot
	var exact: Dictionary = bytes_to_var(Marshalls.base64_to_raw(snapshot.bridge.current_exact))
	for version in [snapshot,exact]:
		var index: int = version.structures.find_custom(func(spec): return spec.name == "door_side")
		match damage:
			"missing": version.structures.remove_at(index)
			"duplicate": version.structures[index] = version.structures[0].duplicate(true)
			"mistyped": version.structures[index].kind = "obstacle"
	snapshot.bridge.current_exact = Marshalls.raw_to_base64(var_to_bytes(exact))
	var live: Node = host.combat
	if save.save(host.save_path,fixture).ok:
		host.continue_run()
	check(host.combat == live and host.combat.get_node("ReferenceMap/door_side").durability == 321.0, "Rejects a %s structure in a matching-checksum save without replacing the live battle" % damage)

func _carried_post(host: Node) -> void:
	clock.set_paused(true)
	var session: Node = host.combat.get_node("Session")
	var sim: Node = host.combat.get_node("Simulation")
	var bought: Dictionary = session.execute_for("shouxiang","purchase",{"id":"T01"},"player")
	var deployed: Dictionary = session.execute_for("shouxiang","deploy_at",{"post_id":POST},"player")
	if not check(bought.ok and deployed.ok, "Official purchase and deployment can use the optional side post"):
		return
	var uid: String = str(deployed.unit.get_meta("night_uid"))
	# Shorten only this fixture's wait. The real battle, settlement and save paths still run.
	session.remaining = 0.01
	sim.advance(1.0/60)
	host._process(1.0/60)
	if not check(host.run.state.phase == "reward" and host.run.state.roster.any(func(unit): return unit.uid == uid and unit.post == POST), "A live side-post survivor reaches the normal reward phase"):
		return
	host.continue_run()
	check(host.run.state.phase == "reward" and host.run.state.roster.any(func(unit): return unit.uid == uid and unit.post == POST), "The reward-phase disk save preserves the optional home post")
	for card in host.run.reward_options():
		if card.requires_target:
			continue
		host.select_reward(str(card.id))
		if host.run.state.phase == "map": break
	if not check(host.run.state.phase == "map", "Actual night reward closes the encounter"):
		return
	host.choose_node("n02")
	match host.run.state.phase:
		"market": host.leave_node()
		"rest": host.finish_rest()
		"event":
			for choice in host.run.event_options():
				host.resolve_event(str(choice.id))
				if host.run.state.phase == "map": break
	if not check(host.run.state.phase == "map", "The authored non-combat stop completes normally"):
		return
	host.choose_node("n03")
	if not check(is_instance_valid(host.combat) and not host.combat.get_node("ReferenceMap").has_node(POST), "Next seeded battle omits the optional side post"):
		return
	var world: Node = host.combat.get_node("ReferenceMap")
	var survivors: Array = host.combat.get_node("Simulation").humans.filter(func(unit): return unit.get_meta("night_uid", "") == uid)
	check(survivors.size() == 1 and world.can_deploy_at(survivors[0].current_post) and survivors[0].get_meta("night_home_post") == POST, "Carries the same survivor to a real fallback cover while preserving their home post")

func check(value: bool, label: String) -> bool:
	results.append({"check":label,"passed":value})
	print(("PASS " if value else "FAIL ") + label)
	return value

func _finish() -> void:
	var failures := results.filter(func(row): return not row.passed).size()
	var file := FileAccess.open(output.path_join("p10-save-results.json"),FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify({"checks":results.size(),"failures":failures,"results":results},"\t") + "\n")
	file.close()
	quit(0 if failures == 0 else 1)
