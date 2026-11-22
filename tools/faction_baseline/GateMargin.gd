extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or args[0] not in ["30","40","55"]:
		quit(2)
		return
	var archive=load("res://src/replay/ReplayArchive.gd")
	var saved: Dictionary={}
	for entry in archive.list_seed("渡口"):
		if entry.node_id!="n08" or not entry.complete: continue
		var candidate: Dictionary=archive.load_record(entry.id)
		if candidate.ok and candidate.record.actions.size()==2 and candidate.record.actions[1].arguments.get("formation")=="ground_wedge":
			saved=candidate.record
			break
	if saved.is_empty():
		push_error("先用同一用户目录运行 FamilyRoute 渡口 无名潮 bowGate")
		quit(2)
		return
	var combat: Node=load("res://scenes/combat/Combat.tscn").instantiate()
	root.add_child(combat)
	var replay=load("res://src/replay/ReplayPlayer.gd").new()
	if not replay.start(combat,saved).ok:
		quit(2)
		return
	var sim: Node=combat.get_node("Simulation")
	# Continue the captured starting queue in a counterfactual battle.
	sim.session.input_locked=false
	var orders: Array=[]
	for tick in ceili(sim.session.remaining*60)+2:
		if tick==0 or (orders.size()==1 and sim.simulation_time>=float(args[0]) and sim.session.reinforce_left<=0):
			var before: float=sim.session.incense
			var form: String="window_bow" if tick==0 else "ground_wedge"
			if not sim.session.execute_for("duoming","reinforce",{"formation":form},"player").ok:
				quit(3)
				return
			orders.append({"time":sim.simulation_time,"cost":before-sim.session.incense,"formation":form})
		sim.advance(1.0/60)
		if not sim.session.running: break
	var out: Dictionary={"seed":"渡口","node":"n08","initial_hash":saved.initial_exact.sha256_text(),"orders":orders,"result":sim.session.result}
	FileAccess.open("res://tools/faction_baseline/gate-margin-"+args[0]+".json",FileAccess.WRITE).store_string(JSON.stringify(out,"\t")+"\n")
	var ok: bool=orders.size()==2 and orders.all(func(o):return o.cost==10) and not sim.session.result.is_empty()
	print("MARGIN ",ok," ",args[0]," ",out.result)
	combat.free()
	await create_timer(.3).timeout
	quit(0 if ok else 1)
