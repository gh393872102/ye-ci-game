extends "res://tools/faction_baseline/FamilyFirstNight.gd"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["渡口","灯市","秋社"] or args[1] not in ["early","late","paper","ground","bow","reader","bow35","bow40","bow45","bow60"]:
		quit(2)
		return
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.title_shell_enabled = true
	host.save_path = "user://window-timing-%d.json" % OS.get_process_id()
	root.add_child(host)
	host.shell.title_buttons.start.pressed.emit()
	host.shell.seed_input.text = args[0]
	host.shell.family_picker.select(1)
	host.shell.title_buttons.duoming.pressed.emit()
	host.choose_node("n01")
	var sim: Node = host.combat.get_node("Simulation")
	sim.set_physics_process(false)
	var book := {"seed":args[0],"second":args[1],"family":"无名潮","arrivals":{},"foreign":[],"orders":[],"scouts":{}}
	attach(sim,book)
	sim.unit_spawned.connect(func(unit):
		if unit.unit_id=="G07":
			book.scouts[unit.instance_id]={"spawn":sim.simulation_time,"hits":{},"entry":null,"register":null})
	sim.event_recorded.connect(func(kind,unit,_detail):
		if kind=="roster_paper_stopped_bolt" and book.scouts.has(unit.instance_id):
			book.scouts[unit.instance_id].blocked=sim.simulation_time
		if kind=="roster_window_entered" and book.scouts.has(unit.instance_id):
			book.scouts[unit.instance_id].entry=sim.simulation_time)
	sim.lethal_hit.connect(func(unit,attacker,kind,amount,hp):
		if book.scouts.has(unit.instance_id):
			book.scouts[unit.instance_id].fallen={"time":sim.simulation_time,"floor":unit.floor_id,"x":roundi(unit.position.x),"source":attacker.unit_id if is_instance_valid(attacker) else "","kind":kind,"damage":amount,"hp":hp})
	book.contest={"ticks":0,"unopposed_ticks":0,"peak_occupation":0.0,"guards":{},"first_hud":""}
	var second_at: float = {"late":75.0,"bow35":35.0,"bow40":40.0,"bow45":45.0,"bow60":60.0}.get(args[1],0.0)
	for tick in 10802:
		var session: Node = sim.session
		if tick==0 or (book.orders.size()==1 and session.reinforce_left<=0 and session.incense>=session.rules.reinforce.cost and sim.simulation_time>=second_at):
			var cash: float = session.incense
			var choice := "paper" if book.orders.size()==1 and args[1]=="paper" else "window"
			if book.orders.size()==1 and args[1]=="ground": choice=""
			if book.orders.size()==1 and args[1].begins_with("bow"): choice="window_bow"
			if book.orders.size()==1 and args[1]=="reader": choice="window_reader"
			var result: Dictionary = session.execute_for("duoming","reinforce",{"formation":choice},"player")
			if not result.ok:
				push_error(str(result))
				quit(3)
				return
			book.orders.append({"seconds":sim.simulation_time,"cost":cash-session.incense})
		sim.advance(1.0/60.0)
		if session.register_attackers>0:
			if session.register_guards.is_empty(): book.contest.unopposed_ticks+=1
			else:
				book.contest.ticks+=1
				if book.contest.first_hud=="":
					var panel: Node = host.combat.get_node("Decisions")
					panel._update_warnings()
					book.contest.first_hud=panel.register_warning.text
				for guard in sim.humans:
					if guard.dead or sim.world.room_at(guard.position,guard.floor_id)!="register": continue
					var record: Dictionary = book.contest.guards.get(guard.instance_id,{"name":guard.display_name,"ticks":0,"first_hp":guard.hp,"min_hp":guard.hp,"post":guard.current_post})
					if args[1] in ["bow","reader","early"]:
						for scout in sim.targets:
							if scout.dead or scout.unit_id!="G07" or scout.floor_id!=guard.floor_id or sim.world.room_at(scout.position,scout.floor_id)!="register": continue
							var contact: Dictionary = record.get("contact",{})
							var pair: Dictionary = contact.get(scout.instance_id,{"min_px":INF,"in_range_ticks":0})
							pair.min_px=minf(pair.min_px,scout.position.distance_to(guard.position))
							if sim.can_attack(scout,guard): pair.in_range_ticks+=1
							contact[scout.instance_id]=pair
							record.contact=contact
					record.ticks+=1
					record.min_hp=minf(record.min_hp,guard.hp)
					book.contest.guards[guard.instance_id]=record
		book.contest.peak_occupation=maxf(book.contest.peak_occupation,session.occupation)
		for i in range(sim.damage_log.size()-1,-1,-1):
			var hit: Dictionary = sim.damage_log[i]
			if hit.time!=sim.simulation_time: break
			if book.scouts.has(hit.attacker):
				var hits: Dictionary = book.scouts[hit.attacker].hits
				var target := str(hit.target)
				hits[target]=int(hits.get(target,0))+1
		for unit in sim.targets:
			if unit.unit_id=="G07" and not unit.dead and book.scouts[unit.instance_id].register==null and sim.world.room_at(unit.position,unit.floor_id)=="register":
				book.scouts[unit.instance_id].register=sim.simulation_time
		if not session.running: break
	book.result=sim.session.result.duplicate(true)
	host._process(0)
	book.phase=host.run.state.phase
	var path := "res://tools/faction_baseline/window-timing-%s-%s.json" % [args[0],args[1]]
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(book,"\t")+"\n")
	var ok: bool = book.orders.size()==2 and book.orders.all(func(o):return o.cost==10) and book.scouts.size()==(4 if args[1] in ["paper","ground"] else 8) and book.foreign.is_empty() and host.run.state.roster.all(func(u):return root.get_node("Data").get_unit(u.id)["谱系"]=="无名潮") and not book.result.is_empty()
	print("WINDOW ",ok," ",book.orders," ",book.result.reason)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(.3).timeout
	quit(0 if ok else 1)
