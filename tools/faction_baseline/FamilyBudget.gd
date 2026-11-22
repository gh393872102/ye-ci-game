extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var opening: Script = load("res://src/night/FactionOpening.gd")
	var night_script: Script = load("res://src/night/NightRun.gd")
	var data := root.get_node("Data")
	var ok := true
	for family in opening.FAMILIES:
		var entry: Dictionary = opening.FAMILIES[family]
		var waves: Array = opening.family_waves([{"at":0,"G01":1},{"at":10,"G01":4,"G12":3}],entry)
		ok = ok and waves.size()==2 and waves[0].at==0 and waves[1].at==10 and (waves[0][entry.id]+waves[1][entry.id])*entry.slots==8
		for bonus in [0,2,4]:
			var host: Node = load("res://scenes/night/Night.tscn").instantiate()
			host.save_path = "user://family-budget-%d.json" % OS.get_process_id()
			root.add_child(host)
			host.start_p10_night("duoming","example","渡口","R01",[],family)
			host.run.state.build.reinforce_count_delta = bonus
			host.choose_node("n01")
			var sim: Node = host.combat.get_node("Simulation")
			var expected: int = floori(float(data.battle_rules.reinforce.count)/entry.slots)+bonus
			if bonus == 0:
				var snapshot: Dictionary = host.bridge.snapshot(host.combat)
				ok = ok and host.bridge._valid_bridge_state(host.combat,host.run,snapshot)
				snapshot.tide.config.supply_slots = 0
				ok = ok and not host.bridge._valid_bridge_state(host.combat,host.run,snapshot)
			var pending: int = sim.tide.pending.size()
			var receipt: Dictionary = sim.session.reinforce()
			ok = ok and receipt.ok and sim.tide.pending.size()-pending==expected and sim.tide.pending.slice(pending).all(func(id): return id==entry.id)
			ok = ok and not sim.session.reinforce().ok and sim.session.incense==6
			DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
			host.free()
	var guard: RefCounted = night_script.new()
	ok = ok and not guard.new_p10_run("duoming","fierce","渡口","R01",[],"","无册谱").ok and not guard.new_p10_run("shouxiang","example","渡口","R01",[],"","大形").ok
	print("4 families x 3 reinforcement bonuses, wave remainder, cooldown, cost and seat scope: ",ok)
	await create_timer(0.4).timeout
	quit(0 if ok else 1)
