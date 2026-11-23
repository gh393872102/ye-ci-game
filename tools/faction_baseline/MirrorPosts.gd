extends "res://tools/faction_baseline/OrdinaryOpening.gd"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=2:
		quit(2)
		return
	var rows := []
	var ok := true
	for post in ["post_register","post_hall_door"]:
		for wearer in ["","H18","H19"]:
			var night: RefCounted = load("res://src/night/NightRun.gd").new()
			if not night.load_save(args[0]).ok or night.state.opening_faction!="符法司" or not night.finish_rest("H18").ok:
				quit(2)
				return
			for member in night.state.roster:
				if member.id=="H18" and post!="post_register" and not night.reserve_post(member.uid,post).ok:
					quit(2)
					return
			if not night.choose_node("n10").ok:
				quit(2)
				return
			var scene: Node = load("res://scenes/combat/Combat.tscn").instantiate()
			scene.configure_chunks(night.current_node().chunk_ids)
			root.add_child(scene)
			var sim: Node = scene.get_node("Simulation")
			var session: Node = scene.get_node("Session")
			sim.set_physics_process(false)
			var bridge: RefCounted = load("res://src/night/NightBattleBridge.gd").new()
			if not bridge.start(scene,night).ok:
				quit(2)
				return
			foreign_units.clear()
			var labels := {}
			var row := {"seed":night.state.seed,"post":post,"wearer":wearer,"start_cash":session.incense,"guards":[],"events":[],"hits":[]}
			for unit in sim.humans:
				observe(unit,"符法司")
				labels[str(unit.name)] = unit.unit_id
				row.guards.append({"id":unit.unit_id,"uid":unit.instance_id,"hp":unit.hp,"post":unit.current_post})
				if unit.unit_id==wearer:
					var before: float = session.incense
					var qty: int = session.growth.state.inventory.get("Y11",0)
					root.get_node("Clock").set_paused(true)
					var receipt: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":unit.instance_id,"item_id":"Y11","slot_index":0},"player")
					root.get_node("Clock").set_paused(false)
					row.gear = {"ok":receipt.ok,"available":qty,"reason":receipt.get("reason",""),"used":qty-int(session.growth.state.inventory.get("Y11",0)),"cost":before-session.incense}
					if qty < 1:
						row.unavailable = true
						ok = ok and not receipt.ok and row.gear.used==0 and row.gear.cost==0
					else:
						ok = ok and receipt.ok and row.gear.used==1 and row.gear.cost==0
			if row.get("unavailable",false):
				rows.append(row)
				bridge.recording.stop()
				scene.free()
				await process_frame
				continue
			sim.unit_spawned.connect(func(u): observe(u,"符法司"))
			sim.unit_allegiance_changed.connect(func(u,_old,_new): observe(u,"符法司"))
			sim.event_recorded.connect(func(kind,u,detail):
				if u!=null and u.unit_id in ["H18","H19"] and str(kind).begins_with("roster_"):
					row.events.append({"time":sim.simulation_time,"id":u.unit_id,"kind":kind,"detail":detail,"cash":session.incense})
			)
			for tick in 21602:
				if not session.running: break
				sim.advance(1.0/60.0)
				for i in range(sim.damage_log.size()-1,-1,-1):
					var hit: Dictionary = sim.damage_log[i]
					if hit.time!=sim.simulation_time: break
					if labels.has(str(hit.target)) or str(hit.attacker).begins_with("H18_") or str(hit.attacker).begins_with("H19_"):
						row.hits.append(hit.duplicate())
			row.foreign = foreign_units.duplicate()
			row.result = session.result.duplicate(true)
			row.settled = night.accept_battle(bridge.collect(scene,night)).ok
			ok = ok and row.settled and not row.result.is_empty() and row.foreign.is_empty() and row.guards.size()==2
			rows.append(row)
			bridge.recording.stop()
			scene.free()
			await process_frame
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"map_sha256":FileAccess.get_sha256(args[0]),"trials":rows}))
	quit(0 if ok else 1)
