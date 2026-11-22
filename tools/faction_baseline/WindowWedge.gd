extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var host: Node=load("res://scenes/night/Night.tscn").instantiate()
	host.save_path="user://wedge-%d.json" % OS.get_process_id()
	root.add_child(host)
	host.start_p10_night("duoming","example","渡口","R01",[],"无名潮")
	host.choose_node("n01")
	var sim: Node=host.combat.get_node("Simulation")
	sim.set_physics_process(false)
	var session: Node=sim.session
	var ok: bool=session.reinforce("wedge").reason=="WINDOW_WEDGE_NO_TARGET" and session.incense==16
	var scouts := []
	for i in 5: scouts.append(sim.tide.spawn("G07",i%4,100+i*100))
	var queued: Array=sim.tide.pending.duplicate()
	var receipt: Dictionary=session.execute_for("duoming","reinforce",{"formation":"wedge"},"player")
	ok=ok and receipt.ok and session.incense==6 and session.reinforce_count==1 and sim.tide.pending==queued and session.window_gear_targets("window_wedge")==[scouts[0]]
	var id: String=scouts[4].instance_id
	ok=ok and host._save_state().ok
	host.continue_run()
	sim=host.combat.get_node("Simulation")
	var actor: Node=sim.session.roster.actor(id)
	var door: Node=sim.world.get_node("door_outer")
	var before: float=door.durability
	sim.deal_damage(actor,sim.humans[0],"melee")
	ok=ok and actor.roster.get("window_wedge")=="ready"
	sim.deal_damage(actor,door,"structure")
	var charged: float=before-door.durability
	ok=ok and actor.roster.get("window_wedge")=="spent" and host._save_state().ok
	host.continue_run()
	sim=host.combat.get_node("Simulation")
	actor=sim.session.roster.actor(id)
	door=sim.world.get_node("door_outer")
	before=door.durability
	sim.deal_damage(actor,door,"structure")
	var ordinary: float=before-door.durability
	ok=ok and is_equal_approx(charged-ordinary,60.0) and actor not in sim.session.window_gear_targets("window_wedge") and host.bridge.recording.actions.any(func(a):return a.action=="reinforce" and a.arguments=={"formation":"wedge"})
	print("WEDGE ",ok," first=",charged," second=",ordinary)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(.3).timeout
	quit(0 if ok else 1)
