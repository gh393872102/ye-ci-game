extends SceneTree
## Run against an ordinary n10 save. Dispatch viewport clicks and retain the payment feedback.
func _initialize() -> void:
	run.call_deferred()

func press_visible(button: Button) -> bool:
	await process_frame
	await process_frame
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		return false
	var rect := button.get_global_rect()
	if not root.get_visible_rect().encloses(rect):
		return false
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = rect.get_center()
		event.pressed = down
		root.push_input(event,true)
	return true

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=2:
		quit(2)
		return
	root.size = Vector2i(1920,1080)
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path = "user://replacement-input.json"
	root.add_child(host)
	var ok := DirAccess.copy_absolute(args[0],ProjectSettings.globalize_path(host.save_path)) == OK
	if not ok:
		quit(2)
		return
	host.continue_run()
	host.choose_node("n10")
	var sim: Node = host.combat.get_node("Simulation")
	var session: Node = sim.session
	var panel: Node = host.combat.get_node("Decisions")
	sim.set_physics_process(false)
	for tick in 3600:
		sim.advance(1.0/60.0)
		if session.register_attackers > 0: break
	panel._update_warnings()
	var cash: float = session.incense
	var row := {"display":DisplayServer.get_name(),"seed":host.run.state.seed,"attackers":session.register_attackers,"guards":session.register_guards.duplicate(),"warning_time":sim.simulation_time}
	ok = await press_visible(panel.relief_button)
	row.opened = panel.register_relief
	row.hidden_at_open = panel.content.find_child("buy_H24",true,false) == null
	ok = ok and await press_visible(panel.content.find_child("replacement_scope",true,false))
	while ok and not panel.content.find_child("buy_H24",true,false) and not panel.buttons.purchase_next.disabled:
		var old_page: int = panel.purchase_page
		ok = await press_visible(panel.buttons.purchase_next) and panel.purchase_page > old_page
	row.browsing_cost = cash-session.incense
	if ok: ok = await press_visible(panel.content.find_child("buy_H24",true,false))
	row.paid = cash-session.incense
	row.feedback = panel.feedback.text
	row.arrived = is_instance_valid(panel.arriving_guard) and panel.arriving_guard.unit_id == "H24" and panel.arriving_guard.current_post == "post_register"
	row.passed = ok and row.opened and row.hidden_at_open and row.browsing_cost == 0 and row.arrived and is_equal_approx(row.paid,8.0) and "新兵骨针已守册" in row.feedback and panel.current_panel.is_empty()
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(row,"\t")+"\n")
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://replacement-input.json"))
	quit(0 if row.passed else 1)
