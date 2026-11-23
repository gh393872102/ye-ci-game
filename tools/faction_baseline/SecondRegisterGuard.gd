extends "res://tools/faction_baseline/OrdinaryOpening.gd"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=2:
		quit(2)
		return
	var rows := []
	var passed := true
	for id in ["H11","H24"]:
		var host: Node = load("res://scenes/night/Night.tscn").instantiate()
		host.save_path = "user://second-register.json"
		root.add_child(host)
		if DirAccess.copy_absolute(args[0],ProjectSettings.globalize_path(host.save_path))!=OK:
			quit(2)
			return
		host.continue_run()
		host.choose_node("n10")
		var battle: Node = host.combat
		var sim: Node = battle.get_node("Simulation")
		var session: Node = sim.session
		var menu: Node = battle.get_node("Decisions")
		sim.set_physics_process(false)
		var row := {"seed":host.run.state.seed,"second_id":id}
		foreign_units.clear()
		for unit in sim.humans: observe(unit,"符法司")
		sim.unit_spawned.connect(func(u): observe(u,"符法司"))
		sim.unit_allegiance_changed.connect(func(u,_a,_b): observe(u,"符法司"))
		inspect_replacements=true
		for tick in 21601:
			sim.advance(1.0/60.0)
			if not session.running: break
			if session.register_guards.is_empty() and session.register_attackers>0:
				if not row.has("first") and session.occupation>=7:
					row.first = await request_register_relief(battle,host.run,"符法司","H24")
				elif row.has("first") and not row.has("second"):
					if not row.has("vacancy"):
						row.vacancy = {"time":sim.simulation_time,"balance":session.incense,"hint":menu._empty_relief_hint()}
					if session.incense < session.rules.purchases[id]: continue
					var before: float = session.incense
					if id=="H24":
						row.second = await request_register_relief(battle,host.run,"符法司",id)
					else:
						menu._update_warnings()
						menu.relief_button.pressed.emit()
						menu.buttons.purchase_scope.pressed.emit()
						var card: Button = menu.content.find_child("buy_H11",true,false)
						while not card and not menu.buttons.purchase_next.disabled:
							menu.buttons.purchase_next.pressed.emit()
							card = menu.content.find_child("buy_H11",true,false)
						if card and not card.disabled: card.pressed.emit()
						var confirm: Button = menu.content.find_child("defend_register",true,false)
						if confirm: confirm.pressed.emit()
						row.second = {"time":sim.simulation_time,"paid":before-session.incense,"placed":sim.humans.any(func(u): return u.unit_id==id and not u.dead and u.current_post=="post_register")}
		row.foreign = foreign_units.duplicate()
		row.result = session.result.duplicate(true)
		row.passed = row.get("first",{}).get("placed",false) and row.get("second",{}).get("placed",false) and is_equal_approx(row.second.paid,7 if id=="H11" else 8) and (row.foreign.is_empty() if id=="H24" else "H11" in row.foreign.values()) and not row.result.is_empty()
		passed = passed and row.passed
		rows.append(row)
		host.free()
		await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://second-register.json"))
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"trials":rows}))
	quit(0 if passed else 1)
