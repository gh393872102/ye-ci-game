extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.title_shell_enabled = true
	host.save_path = "/tmp/ye-r3-menu-%d.json" % OS.get_process_id()
	root.add_child(host)
	var shell: Node = host.shell
	shell.title_buttons.start.pressed.emit()
	var ok: bool = shell.faction_picker.selected == 0 and not shell.faction_detail.visible
	for i in range(1,5):
		shell.faction_picker.select(i)
		shell.faction_picker.item_selected.emit(i)
		var names := []
		for portrait in shell.faction_portraits:
			ok = ok and portrait.texture != null and portrait.is_visible_in_tree() and shell.faction_detail.text.contains(portrait.tooltip_text)
			names.append(portrait.tooltip_text)
		print(shell.faction_picker.get_item_metadata(i), " ", names)
	for i in [1,2,0]:
		shell.night_kind.select(i)
		shell.night_kind.item_selected.emit(i)
		ok = ok and shell.faction_detail.visible == (i == 0)
	shell.title_buttons.duoming.pressed.emit()
	ok = ok and host.run.state.mode == "duoming" and not host.run.state.has("opening_faction")
	shell.title_buttons.shouxiang.pressed.emit()
	host.choose_node("n01")
	var first: Node = host.combat
	if is_instance_valid(first):
		first.get_node("Simulation").advance(1.0/60)
		var before: float = first.get_node("Simulation").simulation_time
		host.save_run()
		host.continue_run()
		ok = ok and is_instance_valid(host.combat) and first != host.combat and host.run.state.opening_faction == "奇人司"
		if is_instance_valid(host.combat):
			var sim: Node = host.combat.get_node("Simulation")
			ok = ok and is_equal_approx(sim.simulation_time,before) and sim.humans.size() == 2 and host.combat.get_node("Session").growth.state.get("defense_objective") == "hold_register"
	else: ok = false
	print("menu and mid-battle restore: ",ok)
	DirAccess.remove_absolute(host.save_path)
	host.free()
	await create_timer(0.5).timeout
	quit(0 if ok else 1)
