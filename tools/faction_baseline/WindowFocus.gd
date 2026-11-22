extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path = "user://window-focus-%d.json" % OS.get_process_id()
	root.add_child(host)
	host.start_p10_night("duoming","example","渡口","R01",[],"无名潮")
	host.choose_node("n01")
	var sim: Node = host.combat.get_node("Simulation")
	sim.set_physics_process(false)
	var session: Node = sim.session
	var ok: bool = not session.reinforce("unknown").ok and not session.roster.state.has("window_focus")
	var receipt: Dictionary = session.execute_for("duoming","reinforce",{"formation":"window_bow"},"player")
	ok = ok and receipt.ok and session.incense==6 and session.roster.state.window_focus=="window_bow"
	ok = ok and not session.reinforce("window_reader").ok and session.roster.state.window_focus=="window_bow"
	ok = ok and host._save_state().ok
	host.continue_run()
	sim = host.combat.get_node("Simulation")
	sim.set_physics_process(false)
	session = sim.session
	ok = ok and session.roster.state.get("window_focus")=="window_bow" and session.reinforce_count==1
	for tick in 1820: sim.advance(1.0/60.0)
	var capacity: int = sim.tide.config.capacity
	sim.tide.config.capacity = sim.targets.size()+sim.tide.pending.size()
	var cash: float = session.incense
	ok = ok and not session.reinforce("window").ok and session.incense==cash and session.roster.state.get("window_focus")=="window_bow"
	sim.tide.config.capacity=capacity
	ok = ok and session.reinforce("window").ok and not session.roster.state.has("window_focus") and session.incense==cash-10
	print("WINDOW FOCUS guards, restore, reset: ",ok)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(.3).timeout
	quit(0 if ok else 1)
