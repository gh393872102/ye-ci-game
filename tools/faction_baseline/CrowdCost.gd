extends SceneTree
## Benchmarks the simulation step alone. No rendered frames or player input.
const STEP := 1.0 / 60.0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for count in [24, 72, 120]:
		var scene: Node = load("res://scenes/combat/Combat.tscn").instantiate()
		root.add_child(scene)
		var session: Node = scene.get_node("Session")
		var sim: Node = scene.get_node("Simulation")
		sim.set_physics_process(false)
		session.running = false
		session.start_battle("shouxiang")
		session.configure_roster("YECI-CROWD-01")
		for unit in sim.targets:
			unit.free()
		sim.targets.clear()
		sim.tide.pending.clear()
		sim.tide.config.waves = []
		sim.tide.wave_index = 0
		for i in count:
			sim.tide.spawn(["G01", "G09", "G12"][i % 3], i % 4, -floori(i / 4.0) * float(sim.tide.config.spacing))
		var samples: Array[int] = []
		var min_count: int = count
		for tick in 420:
			var started := Time.get_ticks_usec()
			sim.advance(STEP)
			var micros := Time.get_ticks_usec() - started
			if tick >= 60:
				samples.append(micros)
				min_count = mini(min_count, sim.targets.size())
		samples.sort()
		print("CROWD initial=%d minimum=%d steps=%d p50_us=%d p95_us=%d p99_us=%d" % [count, min_count, samples.size(), samples[179], samples[341], samples[356]])
		scene.queue_free()
		await process_frame
		await process_frame
	await create_timer(0.5).timeout
	quit()
