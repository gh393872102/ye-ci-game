extends "res://tools/faction_baseline/FamilyFirstNight.gd"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var families: Array = load("res://src/night/FactionOpening.gd").FAMILIES.keys()
	if args.size()!=2 or args[0] not in ["渡口","灯市","秋社"] or args[1] not in families:
		quit(2)
		return
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.title_shell_enabled = true
	host.save_path = "user://family-route-%d.json" % OS.get_process_id()
	root.add_child(host)
	host.shell.title_buttons.start.pressed.emit()
	host.shell.seed_input.text = args[0]
	host.shell.family_picker.select(1+families.find(args[1]))
	host.shell.title_buttons.duoming.pressed.emit()
	var night: RefCounted = host.run
	var report := {"family":args[1],"seed":args[0],"steps":[]}
	for step in 60:
		var phase: String = night.state.phase
		var row := {"phase":phase,"cash":night.state.incense}
		report.steps.append(row)
		if phase in ["ended","mercy"]: break
		if phase == "map":
			row.node = night.available_nodes()[0].id
			host.choose_node(row.node)
		elif phase == "battle":
			row.family = args[1]
			row.arrivals = {}
			row.foreign = []
			var sim: Node = host.combat.get_node("Simulation")
			sim.set_physics_process(false)
			attach(sim,row)
			for tick in ceili(sim.session.remaining*60)+2:
				sim.advance(1.0/60.0)
				if not sim.session.running: break
			row.result = sim.session.result.duplicate(true)
			host._process(0)
			await process_frame
			print(night.state.current_node_id," ",row.result.get("outcome")," ",row.foreign)
		elif phase == "reward":
			for offer in night.reward_options():
				if not offer.allowed or offer.effect.kind in ["recruit","mutate"]: continue
				var targets: Array = night.target_options(offer.id)
				if offer.requires_target and targets.is_empty(): continue
				row.choice = offer.id
				host.select_reward(offer.id,targets[0].uid if offer.requires_target else "")
				break
		elif phase == "market": host.leave_node()
		elif phase == "event":
			for ev in night.event_options():
				if ev.allowed:
					row.choice = ev.id
					host.resolve_event(ev.id)
					break
		elif phase == "rest": host.finish_rest()
		if night.state.phase == phase: break
		if not night.state.roster.all(func(u): return root.get_node("Data").get_unit(u.id).get("谱系")==args[1]):
			row.foreign_roster = true
			break
	report.outcome = night.state.outcome
	report.phase = night.state.phase
	report.reason = night.state.reason
	FileAccess.open("res://tools/faction_baseline/family-route-%s-%s.json"%[args[0],args[1]],FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print(report.phase," ",report.outcome," ",report.reason)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(0.4).timeout
	var pure: bool = report.steps.all(func(s): return s.get("foreign",[]).is_empty() and not s.get("foreign_roster",false))
	quit(0 if pure and report.phase in ["mercy","ended"] else 1)
