extends SceneTree
## Stock 10d8719 save, seed compat-P10, R01/n01, outer door damaged by 77.
## Snapshot made on a new isolated profile, using its original script fingerprint.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	await process_frame
	var output := OS.get_cmdline_user_args()[0]
	if root.get_node("Data").codex_store.path != output + "/state/codex.json":
		quit(2)
		return
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	root.add_child(host)
	var save_io := load("res://src/night/NightSave.gd")
	var archive := load("res://src/replay/ReplayArchive.gd")
	var fixture: Dictionary = save_io.load_save("res://tests/fixtures/p11/p10-stock-battle.json")
	var checks := {}
	host.save_path = output + "/state/p10-compat.json"
	if not fixture.ok:
		quit(2)
		return
	var original: Dictionary = fixture.state
	checks["P10 archive requires original rules"] = not archive.validate_checkpoint(original.battle_snapshot.bridge.recording).ok
	save_io.save(host.save_path,original)
	host.continue_run()
	var battle: Node = host.combat
	checks["P10 battle resumed"] = is_instance_valid(battle)
	if is_instance_valid(battle):
		checks["Original node and damaged gate retained"] = host.run.state.current_node_id == "n01" and battle.get_node("ReferenceMap/door_outer").durability == 873.0
		checks["Old progress opens with new unearned counts at zero"] = host.run.state.story.flags.exorcise_count == 0
		var cp: Dictionary = host.bridge.recording.checkpoint()
		checks["Fresh validated replay starts at resumed position"] = cp.metadata.source == "night_resume_fragment" and cp.steps.is_empty() and archive.validate_checkpoint(cp).ok
		for damage in ["rules_hash", "initial_exact"]:
			var broken := original.duplicate(true)
			broken.battle_snapshot.bridge.recording[damage] = "unrecognized" if damage == "rules_hash" else original.battle_snapshot.bridge.recording.steps_exact
			save_io.save(host.save_path,broken)
			host.continue_run()
			checks["Reject damaged " + damage + " and keep live battle"] = host.combat == battle
	host.free()
	await process_frame
	var failures := 0
	for label in checks:
		print(("PASS " if checks[label] else "FAIL ") + str(label))
		if not checks[label]: failures += 1
	FileAccess.open(output + "/compatibility.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks.size(),"failures":failures,"results":checks,"source_commit":"10d8719","fixture_sha256":FileAccess.get_sha256("res://tests/fixtures/p11/p10-stock-battle.json")},"\t")+"\n")
	quit(0 if failures==0 else 1)
