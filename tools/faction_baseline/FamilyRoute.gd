extends "res://tools/faction_baseline/FamilyFirstNight.gd"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var capture := "--capture" in args
	var capture_ending := capture
	if capture:
		if DisplayServer.get_name()=="headless":
			quit(2)
			return
		args.remove_at(args.find("--capture"))
		root.size=Vector2i(1920,1080)
	var families: Array = load("res://src/night/FactionOpening.gd").FAMILIES.keys()
	if args.size() not in [2,3] or (args.size()==3 and args[2] not in ["white","window","erase","bow","bow40","bow3"]) or args[0] not in ["渡口","灯市","秋社"] or args[1] not in families:
		quit(2)
		return
	var order := args[2] if args.size()==3 else ""
	if (order in ["window","white","bow","bow40","bow3"] and args[1]!="无名潮") or (order=="erase" and args[1]!="无册谱"):
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
		if phase in ["ended","mercy"]:
			if capture_ending and phase=="mercy":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_webp("res://docs/optimization/register-recap.webp",true,0.78)
			break
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
			if not order.is_empty():
				row.events = []
				sim.event_recorded.connect(func(kind,unit,detail):
					if kind in ["roster_window_entered","roster_window_route_started","roster_erase_name"]:
						row.events.append([sim.simulation_time,kind,unit.instance_id,detail]))
			if order in ["white","window"] and night.state.current_node_id=="n01":
				var cash: float = sim.session.incense
				var start_count: int = sim.tide.pending.size()
				var formation := {"formation":"window"} if order=="window" else {}
				var receipt: Dictionary = sim.session.execute_for("duoming","reinforce",formation,"player")
				row.paid = cash-sim.session.incense
				row.queued = sim.tide.pending.slice(start_count)
				if not receipt.ok or row.paid!=10:
					quit(2)
					return
			if order == "window": row.window_positions = []
			var later_battle: bool = night.state.current_node_id!="n01"
			var budget := 3 if later_battle and order=="bow3" else 2
			var second_at := 40.0 if later_battle and order=="bow40" else 0.0
			var last_occupation := 0.0
			var was_advancing := false
			if order.begins_with("bow"):
				row.interruptions = []
				row.orders = []
				row.register = {"scouts":[],"guards":{},"peak_occupation":0.0,"fighters_ticks":0}
			for tick in ceili(sim.session.remaining*60)+2:
				if order.begins_with("bow") and row.orders.size()<budget and (row.orders.is_empty() or sim.simulation_time>=second_at) and sim.session.reinforce_left<=0 and sim.session.incense>=sim.session.rules.reinforce.cost:
					var cash: float = sim.session.incense
					var formation := "window" if row.orders.is_empty() else "window_bow"
					var receipt: Dictionary = sim.session.execute_for("duoming","reinforce",{"formation":formation},"player")
					if not receipt.ok:
						push_error(str(receipt))
						quit(3)
						return
					row.orders.append({"time":sim.simulation_time,"before":cash,"cost":cash-sim.session.incense,"formation":formation})
				sim.advance(1.0/60.0)
				if order.begins_with("bow"):
					var advancing: bool = sim.session.occupation>last_occupation
					if was_advancing and not advancing:
						var panel: Node = host.combat.get_node("Decisions")
						panel._update_warnings()
						row.interruptions.append({"time":sim.simulation_time,"peak":last_occupation,"attackers":sim.session.register_attackers,"guards":sim.session.register_guards.duplicate(),"hud":panel.register_warning.text})
					if capture and later_battle and sim.session.occupation>=5:
						host.combat.get_node("BattleCamera").set_left(sim.world.get_node("post_register").position.x-900)
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_webp("res://docs/optimization/register-relay.webp",true,0.76)
						capture=false
					was_advancing=advancing
					last_occupation=sim.session.occupation
				if order.begins_with("bow") and sim.session.register_attackers>0:
					row.register.peak_occupation=maxf(row.register.peak_occupation,sim.session.occupation)
					row.register.fighters_ticks+=1
					for scout in sim.targets:
						if scout.unit_id=="G07" and not scout.dead and scout.instance_id not in row.register.scouts and sim.world.room_at(scout.position,scout.floor_id)=="register":
							row.register.scouts.append(scout.instance_id)
					for guard in sim.humans:
						if not guard.dead and sim.world.room_at(guard.position,guard.floor_id)=="register":
							row.register.guards[guard.instance_id]=minf(row.register.guards.get(guard.instance_id,guard.hp),guard.hp)
				if order == "window" and tick % 900 == 899:
					var scouts := []
					for actor in sim.targets:
						if actor.unit_id=="G07" and not actor.dead:
							scouts.append([actor.instance_id,actor.brain.stage,actor.floor_id,roundi(actor.position.x),roundi(actor.hp)])
					row.window_positions.append({"seconds":roundi(sim.simulation_time),"alive":scouts})
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
	var filename := "family-route-%s-%s" % [args[0],args[1]]
	if not order.is_empty(): filename += "-"+order
	FileAccess.open("res://tools/faction_baseline/"+filename+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print(report.phase," ",report.outcome," ",report.reason)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(0.4).timeout
	var pure: bool = report.steps.all(func(s): return s.get("foreign",[]).is_empty() and not s.get("foreign_roster",false))
	quit(0 if pure and report.phase in ["mercy","ended"] else 1)
