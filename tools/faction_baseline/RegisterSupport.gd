extends "res://tools/faction_baseline/OrdinaryOpening.gd"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var focus_pair := args.size()==3 and args[2]=="focus-pair"
	if args.size()!=2 and not focus_pair:
		quit(2)
		return
	var rows := []
	var choices := ["free","focus","free-window","focus-window"] if focus_pair else ["","H17","H22","H22-relay"]
	for choice in choices:
		var recruit: String = "H22" if focus_pair or choice=="H22-relay" else choice
		var night: RefCounted = load("res://src/night/NightRun.gd").new()
		if not night.load_save(args[0]).ok or night.state.opening_faction!="符法司":
			quit(2)
			return
		if choice=="H22-relay" and not night.reserve_post(night.state.roster[0].uid,"post_hall_door").ok:
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
		var row := {"seed":night.state.seed,"choice":choice,"recruit":recruit,"cash":session.incense,"paid":0,"events":[],"hits":[],"guards":[],"occupation":-1.0}
		foreign_units.clear()
		sim.unit_spawned.connect(func(u): observe(u,"符法司"))
		sim.unit_allegiance_changed.connect(func(u,_from,_to): observe(u,"符法司"))
		if recruit!="":
			row.posts = session.legal_posts(recruit)
			var offered: Dictionary = session.purchase(recruit)
			if not offered.ok:
				row.rejected = offered.reason
				if not is_equal_approx(session.incense,row.cash):
					quit(2)
					return
				rows.append(row)
				bridge.recording.stop()
				scene.free()
				await process_frame
				continue
			var post := "post_window_1" if str(choice).ends_with("-window") else "post_register"
			if post not in row.posts or not session.deploy_at(post).ok:
				quit(2)
				return
			row.paid = row.cash-session.incense
			if not is_equal_approx(row.paid,10.0):
				quit(2)
				return
		for u in sim.humans:
			observe(u,"符法司")
			row.guards.append({"id":u.unit_id,"uid":u.instance_id,"post":u.current_post,"hp":u.hp})
		var breaker: Node2D
		if focus_pair:
			row.shots = []
			row.guard_roles = {}
			for u in sim.humans: row.guard_roles[u.instance_id]=u.role
			sim.event_recorded.connect(func(kind,u,detail):
				if kind=="projectile_fired" and u.side=="xianghuo":
					row.shots.append({"time":sim.simulation_time,"actor":u.instance_id,"aim":detail}))
		var open_seals := {}
		var lit := {}
		var offset: int = session.growth.state.events.size()
		for tick in 21602:
			if not session.running: break
			if focus_pair and not row.has("target"):
				for foe in sim.targets:
					if foe.unit_id!="G12" or foe.dead: continue
					for guard in sim.humans:
						if guard.role not in ["crossbow","talisman"] or not sim.can_attack(guard,foe): continue
						breaker=foe
						row.target=foe.instance_id
						row.first_shootable=sim.simulation_time
						row.hp_at_order=foe.hp
						if str(choice).begins_with("focus") and not session.execute_for("shouxiang","mark_target",{"target_id":row.target,"focus_fire":true},"player").ok:
							quit(2)
							return
						break
					if row.has("target"): break
			sim.advance(1.0/60)
			if is_instance_valid(breaker):
				row.target_hp = breaker.hp
				if breaker.dead and not row.has("target_death"): row.target_death=sim.simulation_time
				if row.occupation<0 and session.occupation>0: row.occupation_hp=breaker.hp
			if not row.has("seal_opportunity"):
				for u in sim.humans:
					if u.dead or u.unit_id!="H17" or session.roster.near(u,4).is_empty(): continue
					var doors := []
					for door in sim.world.doors:
						if door.floor_id==u.floor_id:
							doors.append({"id":str(door.name),"distance_px":u.position.distance_to(door.position),"broken":door.destroyed})
					row.seal_opportunity={"time":sim.simulation_time,"doors":doors,"range_px":root.get_node("Rules").body_to_px(session.roster.params(u).radius_body),"cash":session.incense}
					break
			if row.occupation<0 and session.occupation>0: row.occupation=sim.simulation_time
			var events: Array = session.growth.state.events
			while offset < events.size():
				var e: Dictionary = events[offset]
				if e.kind in ["seal_created","seal_absorbed","lamp_reveal"]:
					row.events.append({"time":sim.simulation_time,"kind":e.kind,"actor":e.unit_id,"target":e.detail})
				if e.kind=="seal_created": open_seals[e.detail]=e.unit_id
				if e.kind=="lamp_reveal": lit[e.detail]=e.unit_id
				offset+=1
			for door in open_seals.keys():
				if not session.growth.state.seals.has(door):
					row.events.append({"time":sim.simulation_time,"kind":"seal_end","actor":open_seals[door],"target":door})
					open_seals.erase(door)
			for id in lit.keys():
				var ghost: Node2D = session.roster.actor(id)
				if not is_instance_valid(ghost) or ghost.dead or not ghost.growth.statuses.has("stun"):
					row.events.append({"time":sim.simulation_time,"kind":"stun_end","actor":lit[id],"target":id})
					lit.erase(id)
			for i in range(sim.damage_log.size()-1,-1,-1):
				var hit: Dictionary = sim.damage_log[i]
				if hit.time!=sim.simulation_time: break
				row.hits.append(hit.duplicate())
		row.foreign=foreign_units.duplicate()
		row.result=session.result.duplicate(true)
		if not row.foreign.is_empty() or row.result.is_empty() or not night.accept_battle(bridge.collect(scene,night)).ok:
			quit(2)
			return
		rows.append(row)
		bridge.recording.stop()
		scene.free()
		await process_frame
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify({"map_sha256":FileAccess.get_sha256(args[0]),"trials":rows}))
	quit(0)
