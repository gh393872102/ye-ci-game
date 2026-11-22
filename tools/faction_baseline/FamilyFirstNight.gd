extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func observe(actor: Node, row: Dictionary) -> void:
	if actor.side != "yegui": return
	row.arrivals[actor.instance_id] = actor.unit_id
	var family: String = root.get_node("Data").get_unit(actor.unit_id)["谱系"]
	if family != row.family and family not in row.foreign: row.foreign.append(family)

func attach(sim: Node, row: Dictionary) -> void:
	for actor in sim.targets: observe(actor,row)
	sim.unit_spawned.connect(func(actor): observe(actor,row))
	sim.unit_allegiance_changed.connect(func(actor,_from,_to): observe(actor,row))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["渡口","灯市","秋社"]:
		quit(2)
		return
	var rows := []
	for i in range(1,5):
		for paid in [false,true]:
			var host: Node = load("res://scenes/night/Night.tscn").instantiate()
			host.title_shell_enabled = true
			host.save_path = "user://family-first-%d.json" % OS.get_process_id()
			root.add_child(host)
			var shell: Node = host.shell
			shell.title_buttons.start.pressed.emit()
			shell.family_picker.select(i)
			var family: String = shell.family_picker.get_selected_metadata()
			shell.seed_input.text = args[0]
			shell.title_buttons.duoming.pressed.emit()
			var row := {"family":family,"seed":args[0],"paid":paid,"start":host.run.state.incense,"roster":host.run.state.roster.map(func(u): return u.id),"arrivals":{},"foreign":[]}
			host.choose_node("n01")
			var sim: Node = host.combat.get_node("Simulation")
			var session: Node = sim.session
			sim.set_physics_process(false)
			attach(sim,row)
			if paid:
				var before: float = session.incense
				row.receipt = session.reinforce()
				row.cost = before-session.incense
			for tick in 10802:
				if tick == 120:
					var previous_instance: int = sim.get_instance_id()
					var before: Array = sim.tide.pending.duplicate()
					if not host._save_state().ok:
						quit(3)
						return
					host.continue_run()
					sim = host.combat.get_node("Simulation")
					session = sim.session
					sim.set_physics_process(false)
					row.restored = sim.get_instance_id() != previous_instance and host.run.state.get("opening_family") == family and is_equal_approx(sim.simulation_time,2.0) and sim.tide.pending == before and session.reinforce_count == int(paid)
					attach(sim,row)
				sim.advance(1.0/60.0)
				if tick == 1799: row.at_30s = row.arrivals.size()
				if not session.running: break
			row.result = session.result.duplicate(true)
			host._process(0)
			row.phase = host.run.state.phase
			rows.append(row)
			print(family," ",paid," ",row.result," ",row.foreign," restored=",row.restored)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
			host.free()
			await process_frame
	var ok := rows.all(func(r): return r.restored and r.start == 16 and r.foreign.is_empty() and not r.result.is_empty() and r.phase != "battle" and (not r.paid or (r.receipt.ok and r.cost == 10)))
	FileAccess.open("res://tools/faction_baseline/family-first-"+args[0]+".json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t")+"\n")
	quit(0 if ok else 1)
