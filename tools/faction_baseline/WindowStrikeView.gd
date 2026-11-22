extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	root.size=Vector2i(1920,1080)
	var host: Node=load("res://scenes/night/Night.tscn").instantiate()
	host.save_path="user://window-strike-%d.json"%OS.get_process_id()
	root.add_child(host)
	host.start_p10_night("duoming","example","渡口","R01",[],"无名潮")
	host.choose_node("n01")
	var sim: Node=host.combat.get_node("Simulation")
	sim.set_physics_process(false)
	var target: Node
	for tick in 10800:
		if tick==0: sim.session.reinforce("window")
		if tick==1802: sim.session.reinforce("window_bow")
		sim.advance(1.0/60.0)
		for guard in sim.humans:
			if guard.role=="crossbow" and not guard.dead and guard.roster.has("window_strike_at"):
				target=guard
				break
		if target!=null: break
	var ok: bool=target!=null and target.hp<target.max_hp
	if ok:
		var camera: Node=host.combat.get_node("BattleCamera")
		camera.set_left(target.position.x-900)
		var panel: Node=host.combat.get_node("Decisions")
		panel._update_warnings()
		await RenderingServer.frame_post_draw
		ok=camera.world_rect().has_point(target.aim_point())
		root.get_texture().get_image().save_webp("res://docs/optimization/window-strike.webp",true,0.77)
		print("WINDOW STRIKE ",ok," ",sim.simulation_time," ",target.instance_id," ",target.hp)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(.3).timeout
	quit(0 if ok else 1)
