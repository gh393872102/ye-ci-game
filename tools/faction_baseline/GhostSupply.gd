extends SceneTree
## Measure what the ordinary attacker's first encounter actually supplies.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var reports := []
	var valid := true
	for seed_text in ["渡口","灯市","秋社"]:
		for order in [false,true]:
			var host: Node = load("res://scenes/night/Night.tscn").instantiate()
			host.title_shell_enabled = true
			host.save_path = "user://ghost-supply-%d.json" % OS.get_process_id()
			root.add_child(host)
			host.shell.title_buttons.start.pressed.emit()
			host.shell.seed_input.text = seed_text
			host.shell.title_buttons.duoming.pressed.emit()
			host.choose_node("n01")
			var sim: Node = host.combat.get_node("Simulation")
			var session: Node = host.combat.get_node("Session")
			sim.set_physics_process(false)
			var row := {"seed":seed_text,"mode":session.mode,"ordered":order,"start":session.incense,"carried":host.run.state.roster.map(func(u): return u.id),"arrivals":{},"receipt":{}}
			var observe := func(actor):
				if actor.side == "yegui":
					row.arrivals[actor.instance_id] = {"id":actor.unit_id,"family":root.get_node("Data").get_unit(actor.unit_id).get("谱系",""),"at":sim.simulation_time}
			for actor in sim.targets: observe.call(actor)
			sim.unit_spawned.connect(observe)
			sim.unit_allegiance_changed.connect(func(actor,_from,_to): observe.call(actor))
			if order:
				var before: float = session.incense
				var result: Dictionary = session.reinforce()
				row.receipt = {"ok":result.ok,"reason":result.reason,"paid":before-session.incense}
			for tick in 1800:
				if not session.running: break
				sim.advance(1.0/60.0)
			row.seconds = sim.simulation_time
			row.pending = sim.tide.pending.duplicate()
			valid = valid and row.mode == "duoming" and row.seconds > 29.99 and row.arrivals.size() > 0 and host.run.state.seed == seed_text
			reports.append(row)
			host.free()
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ghost-supply-%d.json" % OS.get_process_id()))
	FileAccess.open("res://tools/faction_baseline/ghost-supply-opening.json",FileAccess.WRITE).store_string(JSON.stringify(reports,"\t")+"\n")
	print("Six ordinary duoming 30s openings ",valid)
	await create_timer(0.3).timeout
	quit(0 if valid else 1)
