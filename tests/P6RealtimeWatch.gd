extends SceneTree
## Wall-clock evidence: normal native game loop, no direct simulation advancement.
var host: Node
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks.append({"check":label,"passed":ok})
	print(("PASS " if ok else "FAIL ") + label)
func _run() -> void:
	await process_frame
	load("res://src/replay/ReplayArchive.gd").directory = "/tmp/ye-ci-p6-realtime-fixtures"
	host = load("res://scenes/modes/Observatory.tscn").instantiate()
	root.add_child(host)
	var config: Dictionary = root.get_node("Data").mode_rules.defaults.duplicate(true)
	config.seed = "P6-WATCH-ACTUAL-120S"
	config.profile_id = "upper"
	host.start_observation(config)
	root.get_node("Clock").set_speed(1.0)
	check(host.controller != null and host.combat.get_node("Session").player_seat == "","Native host starts actual two-AI watch")
	var started := Time.get_ticks_msec()
	var safe := true
	for second in 126:
		await create_timer(1.0,true,false,true).timeout
		var sim: Node = host.combat.get_node("Simulation")
		for human in sim.humans:
			safe = safe and human.position.x >= root.get_node("Rules").BASE_START_X and sim.world.can_deploy_at(human.current_post)
		if second % 20 == 19 or second == 125:
			samples.append({"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"simulation_seconds":sim.simulation_time,"actions":host.controller.recording.actions.size(),"ai_decisions":host.controller.status().ai_decisions})
	var elapsed := (Time.get_ticks_msec()-started)/1000.0
	var sim: Node = host.combat.get_node("Simulation")
	var actions: Array = host.controller.recording.actions
	check(elapsed >= 125,"Actual wall clock observed continuously for at least 125 seconds")
	check(sim.simulation_time >= 120,"Ordinary engine physics advances at least 120 combat seconds")
	check(root.get_node("Clock").resume_scale == 1.0 and Engine.time_scale == 1.0,"Watch uses 1x speed and unchanged engine time scale")
	check(actions.any(func(item): return item.seat == "shouxiang" and item.origin == "ai"),"Defender submits successful paid decisions in normal loop")
	check(actions.any(func(item): return item.seat == "duoming" and item.origin == "ai"),"Attacker submits successful paid decisions in normal loop")
	check(safe,"Every sampled human remains inside base at legal cover")
	root.get_node("Clock").set_paused(true)
	await process_frame
	RenderingServer.force_draw(true)
	var screenshot := "res://docs/phase-reports/p6-shots/08-realtime-watch-126s.png"
	check(root.get_texture().get_image().save_png(screenshot) == OK,"Native 126-second watch screenshot is written")
	var failures := checks.filter(func(item): return not item.passed).size()
	var report := {"phase":"P6","kind":"native_wall_clock_watch","engine":Engine.get_version_info().string,"checks":checks.size(),"failures":failures,"wall_seconds":elapsed,"simulation_seconds":sim.simulation_time,"config":config,"samples":samples,"actions":actions,"results":checks,"screenshot":screenshot,"note":"Real 1x host _physics_process / Clock loop. No direct advance(), actor reposition, rule changes, HP edits or accelerated fixed-FPS flags."}
	FileAccess.open("res://docs/phase-reports/p6-realtime-watch-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	if DirAccess.dir_exists_absolute("/tmp/ye-ci-p6-realtime-fixtures"):
		for filename in DirAccess.get_files_at("/tmp/ye-ci-p6-realtime-fixtures"):
			if filename.ends_with(".json"): DirAccess.remove_absolute("/tmp/ye-ci-p6-realtime-fixtures/"+filename)
	print("P6Realtime RESULT: %d checks, %d failures" % [checks.size(),failures])
	quit(1 if failures else 0)
