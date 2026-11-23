extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Play the ordinary final encounter from a saved map. Purchases use the live register menu.

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [2,3] or (args.size()==3 and args[2] not in ["--rotation","--cadence","--holdout","--gear","--limits","--axe-limit","--axe-three","--axe-wallet","--watch-veteran","--watch-wallet","--watch-gear","--watch-budget","--watch","--watch-repeat","--watch-pair"]):
		quit(2)
		return
	var plans := [
		{"id":"open","opening":true,"limit":1,"train":true},
		{"id":"two","guards":2,"limit":1,"train":true},
		{"id":"one","guards":1,"limit":1,"train":true},
		{"id":"empty","guards":0,"limit":1,"train":true},
		{"id":"repeat_two","guards":2,"limit":5,"train":false},
		{"id":"repeat_one","guards":1,"limit":5,"train":false},
	]
	var suffix := ""
	if args.size()==3 and args[2]=="--rotation":
		suffix = "-rotation"
		plans = [
			{"id":"rotation50","guards":2,"limit":20,"train":false,"rotation":true,"budget":50},
			{"id":"rotation","guards":2,"limit":20,"train":false,"rotation":true,"budget":150},
			{"id":"late_rotation","guards":1,"limit":20,"train":false,"rotation":true,"budget":150},
		]
	if args.size()==3 and args[2] in ["--cadence","--holdout"]:
		suffix = "-"+args[2].trim_prefix("--")
		plans.clear()
		var intervals := [1,3,5] if args[2]=="--cadence" else [3]
		for seconds in intervals:
			plans.append({"id":"check_%ds" % seconds,"guards":2,"limit":20,"train":false,"rotation":true,"budget":150,"interval_ticks":seconds*60})
	if args.size()==3 and args[2]=="--limits":
		suffix = "-limits"
		plans = [
			{"id":"no_rehire","guards":2,"limit":20,"train":false,"rotation":true,"budget":150,"interval_ticks":180,"no_rehire":true},
			{"id":"check_10s","guards":2,"limit":20,"train":false,"rotation":true,"budget":150,"interval_ticks":600},
			{"id":"check_15s","guards":2,"limit":20,"train":false,"rotation":true,"budget":150,"interval_ticks":900},
		]
	if args.size()==3 and args[2] in ["--watch","--watch-repeat","--watch-pair"]:
		suffix = "-"+args[2].trim_prefix("--")
		plans.clear()
		var drills := [[],["H11"],["H09"],["H11","H11","H11"],["H09","H09","H09"]] if suffix=="-watch" else [[],["H11"],["H09"]]
		if suffix=="-watch-pair": drills = [["H11","H11"],["H09","H09"],["H11","H09"]]
		for drill in drills:
			plans.append({"id":"watch_"+("_".join(drill) if not drill.is_empty() else "baseline"),"guards":2,"limit":20,"train":false,"rotation":true,"budget":91,"interval_ticks":180,"first_drill":drill})
	if args.size()==3 and args[2] in ["--axe-limit","--axe-three","--axe-wallet"]:
		suffix = "-"+args[2].trim_prefix("--")
		plans.clear()
		var limits := [1,2,3,4] if suffix=="-axe-limit" else [0,1,2]
		if suffix=="-axe-three": limits = [3]
		for limit in limits:
			plans.append({"id":"axe_max%d" % limit,"guards":2,"limit":20,"train":false,"rotation":true,"budget":150 if suffix=="-axe-wallet" else 91,"interval_ticks":180,"axe_limit":limit})
	if args.size()==3 and args[2] in ["--watch-budget","--watch-wallet","--watch-veteran"]:
		suffix = "-"+args[2].trim_prefix("--")
		plans.clear()
		var caps := [81,89] if suffix=="-watch-budget" else [150]
		var targets := [[],["H11"]] if suffix=="-watch-budget" else [["H11"],["H11","H11","H11"],["H09","H09","H09"]]
		if suffix=="-watch-veteran": targets = [["H11","H11","H11"]]
		for cap in caps:
			for drill in targets:
				var label := "_".join(drill) if not drill.is_empty() else "base"
				if suffix=="-watch-budget" and not drill.is_empty(): label = "stone"
				plans.append({"id":"cap%d_%s" % [cap,label],"guards":2,"limit":20,"train":false,"rotation":true,"budget":cap,"interval_ticks":180,"first_drill":drill})
	if args.size()==3 and args[2] in ["--gear","--watch-gear"]:
		suffix = "-"+args[2].trim_prefix("--")
		var start: RefCounted = load("res://src/night/NightRun.gd").new()
		if not start.load_save(args[1]).ok:
			quit(2)
			return
		plans.clear()
		for gear in [["I08"],["Y11"],["I08","Y11"]]:
			if gear.all(func(id):return start.state.growth.inventory.get(id,0)>0):
				plans.append({"id":"stone_"+str(gear[0])+str(gear.size()),"gear":gear,"guards":2,"limit":20,"train":false,"rotation":true,"budget":150,"interval_ticks":180})
		if suffix=="-watch-gear":
			for plan in plans:
				plan.first_drill = ["H11"]
				plan.budget = 91
	var rows := []
	for plan in plans:
		var row := await measure_relief(args[0],args[1],plan)
		if not row.get("ok",false):
			printerr("Incomplete ",plan," ",row)
			quit(2)
			return
		rows.append(row)
		print(plan.id," ",row.result.outcome," ",row.result.elapsed," cost ",row.spent)
	var output := {"seed":args[0],"save_sha256":FileAccess.get_sha256(args[1]),"trials":rows}
	FileAccess.open("res://tools/faction_baseline/martial-relief-"+args[0]+suffix+".json",FileAccess.WRITE).store_string(JSON.stringify(output,"\t")+"\n")
	quit()

func measure_relief(seed_text: String, path: String, plan: Dictionary) -> Dictionary:
	var night: RefCounted = load("res://src/night/NightRun.gd").new()
	if not night.load_save(path).ok or night.state.get("seed")!=seed_text or night.state.get("opening_faction")!="武卫司": return {}
	for member in night.state.roster:
		if member.post!="post_register" and not night.reserve_post(member.uid,"post_register").ok: return {}
	if not night.choose_node("n10").ok: return {}
	var scene: Node = load("res://scenes/combat/Combat.tscn").instantiate()
	scene.configure_chunks(night.current_node().chunk_ids)
	root.add_child(scene)
	var sim := scene.get_node("Simulation")
	var session := scene.get_node("Session")
	var panel := scene.get_node("Decisions")
	sim.set_physics_process(false)
	var bridge: RefCounted = load("res://src/night/NightBattleBridge.gd").new()
	if not bridge.start(scene,night).ok: return {}
	panel.managed_by_night = true
	panel.preferred_faction = "武卫司"
	for member in night.state.fallen: panel.previous_casualties[member.id] = true
	var row := {"plan":plan,"start_cash":session.incense,"start_names":session.names,"roster":night.state.roster.map(func(u):return [u.uid,u.id,u.hp,u.post]),"spent":0.0,"orders":[],"executions":[],"breaker_entries":{},"deaths":[]}
	var enlisted := {}
	for member in night.state.roster: enlisted[member.id] = true
	foreign_units.clear()
	for unit in sim.humans: observe(unit,"武卫司")
	sim.unit_spawned.connect(func(unit): observe(unit,"武卫司"))
	sim.unit_allegiance_changed.connect(func(unit,_old,_new): observe(unit,"武卫司"))
	sim.unit_fallen.connect(func(u):
		if u.side=="xianghuo": row.deaths.append({"id":u.instance_id,"seconds":sim.simulation_time,"post":u.current_post}))
	sim.event_recorded.connect(func(kind,u,detail):
		if kind in ["roster_execution","roster_names_drained"] and is_instance_valid(u) and u.unit_id=="H13":
			row.executions.append({"kind":kind,"unit":u.instance_id,"detail":detail,"seconds":sim.simulation_time,"names":session.names}))
	if plan.has("gear"):
		row.gear = []
		var guard: Node = sim.humans.filter(func(u):return u.unit_id=="H11")[0]
		root.get_node("Clock").set_paused(true)
		for id in plan.gear:
			var qty: int = session.growth.state.inventory.get(id,0)
			var cost: float = session.incense
			var answer: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":guard.instance_id,"item_id":id,"slot_index":0},"player")
			if not answer.ok or session.growth.state.inventory.get(id,0)!=qty-1 or cost!=session.incense: return {"gear_error":id}
			row.gear.append({"item":id,"owner":guard.instance_id,"before":qty,"after":qty-1,"slots":guard.growth.slots.duplicate(true)})
		root.get_node("Clock").set_paused(false)
	if plan.get("opening",false):
		var balance: float = session.incense
		if not session.purchase("H13").ok: return {}
		var placed: Dictionary = session.deploy_at("post_register")
		if not placed.ok: return {}
		var training := train_guard(session,sim,"H13",panel)
		if not training.ok: return {}
		row.spent = balance-session.incense
		row.orders.append({"seconds":0,"instance":placed.unit.instance_id,"paid":row.spent,"training":training})
	for tick in ceili(session.rules.duration*60)+2:
		sim.advance(1.0/60)
		if not session.running: break
		if tick % 6 != 0: continue
		for enemy in sim.targets:
			if enemy.unit_id=="G12" and not enemy.dead and not row.breaker_entries.has(enemy.instance_id) and sim.world.room_at(enemy.position,enemy.floor_id)=="register":
				row.breaker_entries[enemy.instance_id] = sim.simulation_time
		if tick % int(plan.get("interval_ticks",6)) != 0: continue
		if row.orders.size() >= int(plan.limit) or session.register_attackers==0 or session.register_guards.size()>int(plan.get("guards",2)): continue
		if plan.has("first_drill") and not row.has("drills"):
			row.drills = []
			if not plan.first_drill.is_empty():
				panel._update_warnings()
				if not panel.relief_button.visible: return {"missing_watch":true}
				panel.relief_button.pressed.emit()
				for id in plan.first_drill:
					var unit: Node = sim.humans.filter(func(u):return u.unit_id==id and not u.dead)[0]
					var button: Button = panel.buttons.get("watch_train_"+unit.instance_id)
					var cash_before: float = session.incense
					var hp_before: float = unit.hp
					var defense_before: float = unit.defense
					if not is_instance_valid(button) or button.disabled: return {"missing_training":id}
					button.pressed.emit()
					var paid: float = cash_before-session.incense
					if paid!=session.rules.upgrade.cost or not is_equal_approx(unit.hp-hp_before,session.rules.upgrade.hp) or not is_equal_approx(unit.defense-defense_before,session.rules.upgrade.defense): return {"wrong_training":id}
					row.spent += paid
					row.drills.append({"uid":unit.instance_id,"id":id,"time":sim.simulation_time,"hp_before":hp_before,"hp_after":unit.hp,"defense_after":unit.defense,"paid":paid})
				panel.close_panel()
		var recruit := ""
		var choices: Array = ["H11","H09","H13"] if plan.get("rotation",false) else ["H13"]
		for id in choices:
			if id=="H13" and plan.has("axe_limit") and row.orders.filter(func(o):return o.id=="H13").size()>=plan.axe_limit: continue
			if plan.get("no_rehire",false) and enlisted.has(id): continue
			if panel.previous_casualties.has(id) or not session.deployment_reason("post_register",id).is_empty(): continue
			if row.spent+float(session.rules.purchases.get(id,0))>float(plan.get("budget",150)): continue
			if session.purchase_options().any(func(offer):return offer.id==id and offer.allowed):
				recruit=id
				break
		if recruit.is_empty(): continue
		var holding: Array = session.register_guards.duplicate()
		var balance: float = session.incense
		var order := await request_register_relief(scene,night,"武卫司",recruit,plan.train)
		if not order.get("placed",false) or (plan.train and not order.get("training",{}).get("ok",false)): return {"order_error":order}
		enlisted[recruit] = true
		order.guards = holding
		row.orders.append(order)
		row.spent += balance-session.incense
	if plan.has("gear"): row.paper_events = session.growth.state.events.filter(func(e):return e.kind=="paper_brace")
	row.foreign = foreign_units.duplicate()
	row.result = session.result.duplicate(true)
	var report: Dictionary = bridge.collect(scene,night)
	row.ok = row.foreign.is_empty() and night.accept_battle(report).ok and row.orders.size()>0
	if row.ok and row.result.outcome=="victory":
		for card in night.reward_options():
			if not card.allowed or card.effect.kind in ["recruit","mutate"]: continue
			var targets: Array = night.target_options(card.id)
			if card.requires_target and targets.is_empty(): continue
			if night.choose_reward(card.id,targets[0].uid if card.requires_target else "").ok: break
		var save_path := "user://completed-"+seed_text+"-"+str(plan.id)+".json"
		var restored: RefCounted = load("res://src/night/NightRun.gd").new()
		if night.state.phase!="ended" or not night.save(save_path).ok or not restored.load_save(save_path).ok: return {"ending_error":night.state.phase}
		var ending: Dictionary = restored.summary()
		row.ending = {"outcome":ending.outcome,"reason":ending.reason,"mercy":ending.mercy_used,"battles":ending.battles,"living":ending.roster.map(func(u):return [u.id,u.uid,u.hp]),"names":ending.names}
		row.ok = ending.outcome=="victory" and not ending.mercy_used and ending.battles.size()==5 and ending.battles.all(func(b):return b.outcome=="victory")
	bridge.recording.stop()
	scene.free()
	await process_frame
	return row
