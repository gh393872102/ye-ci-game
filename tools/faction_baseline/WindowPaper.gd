extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path="user://paper-guard-%d.json" % OS.get_process_id()
	root.add_child(host)
	host.start_p10_night("duoming","example","渡口","R01",[],"无名潮")
	host.choose_node("n01")
	var sim: Node = host.combat.get_node("Simulation")
	sim.set_physics_process(false)
	var session: Node = sim.session
	var ok: bool = not session.reinforce("paper").ok and session.incense==16 and session.reinforce_count==0
	var scouts := []
	for i in range(5):
		scouts.append(sim.tide.spawn("G07",i%4,100+i*100))
	var shooter: Node
	var mage: Node
	for human in sim.humans:
		if human.unit_id=="T02": shooter=human
		if human.unit_id=="H17": mage=human
	var success: Dictionary = session.execute_for("duoming","reinforce",{"formation":"paper"},"player")
	ok = ok and success.ok and session.incense==6 and session.reinforce_count==1 and not session.reinforce("window").ok
	ok = ok and not scouts[0].roster.has("window_paper") and session.paper_armor_targets()==[scouts[0]]
	var tested_id: String = scouts[4].instance_id
	var scout: Node = scouts[4]
	var hp: float = scout.hp
	scout.receive_damage(1,mage,"projectile")
	scout.receive_damage(1,shooter,"melee")
	ok = ok and scout.hp==hp-2 and scout.roster.window_paper=="ready"
	var old_sim: int = sim.get_instance_id()
	ok = ok and host._save_state().ok
	host.continue_run()
	sim = host.combat.get_node("Simulation")
	scout = sim.session.roster.actor(tested_id)
	ok = ok and sim.get_instance_id()!=old_sim and scout.roster.window_paper=="ready" and sim.session.reinforce_count==1
	for human in sim.humans:
		if human.unit_id=="T02": shooter=human
	scout.receive_damage(8,shooter,"projectile")
	ok = ok and scout.hp==hp-2 and scout.roster.window_paper=="spent" and scout not in sim.session.paper_armor_targets()
	scout.receive_damage(3,shooter,"projectile")
	ok = ok and scout.hp==hp-5 and host._save_state().ok
	host.continue_run()
	sim = host.combat.get_node("Simulation")
	scout = sim.session.roster.actor(tested_id)
	ok = ok and scout.roster.window_paper=="spent" and scout not in sim.session.paper_armor_targets() and sim.session.roster.state.window_bolts_blocked==1
	ok = ok and host.bridge.recording.actions.any(func(action):return action.action=="reinforce" and action.arguments=={"formation":"paper"})
	print("paper targets, price, cooldown, damage counter, broken paper and two restores: ",ok)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(0.3).timeout
	quit(0 if ok else 1)
