extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	root.size=Vector2i(1920,1080)
	var host: Node=load("res://scenes/night/Night.tscn").instantiate()
	host.save_path="user://register-view-%d.json"%OS.get_process_id()
	root.add_child(host)
	host.start_p10_night("duoming","example","渡口","R01",[],"无名潮")
	host.choose_node("n01")
	var sim: Node=host.combat.get_node("Simulation")
	var panel: Node=host.combat.get_node("Decisions")
	var camera: Node=host.combat.get_node("BattleCamera")
	sim.set_physics_process(false)
	for tick in 10800:
		if tick in [0,1802]: sim.session.reinforce("window")
		sim.advance(1.0/60.0)
		if sim.session.register_attackers>0 and not sim.session.register_guards.is_empty(): break
	panel._update_warnings()
	await RenderingServer.frame_post_draw
	var notice: String=panel.register_warning.text
	var ok: bool=notice.contains("守方：") and panel.register_warning.is_visible_in_tree()
	camera.set_left(0)
	var where: Vector2=panel.register_warning.get_global_rect().get_center()
	var start:=Time.get_ticks_usec()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.position=where
		event.pressed=pressed
		root.push_input(event,true)
	await RenderingServer.frame_post_draw
	var ms: float=(Time.get_ticks_usec()-start)/1000.0
	ok=ok and camera.world_rect().has_point(sim.world.get_node("post_register").global_position-Vector2(0,Rules.UNIT_HEIGHT_PX/2.0)) and panel.feedback.text=="已定位册房"
	root.get_texture().get_image().save_webp("res://docs/optimization/register-contest.webp",true,0.78)
	print("click ",ok," camera ",camera.position," target ",sim.world.get_node("post_register").global_position," feedback ",panel.feedback.text)
	var saved: bool=host._save_state().ok
	host.continue_run()
	var restored: Node=host.combat.get_node("Simulation")
	print("restore ",saved," ",restored!=sim," ",restored.session.register_attackers," ",restored.session.register_guards," ",host.feedback.text)
	ok=ok and saved and restored!=sim and restored.session.register_attackers>0 and not restored.session.register_guards.is_empty()
	print("REGISTER VIEW ",ok," ",ms," ms ",notice)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(.3).timeout
	quit(0 if ok else 1)
