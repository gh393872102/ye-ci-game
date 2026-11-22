extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.title_shell_enabled = true
	host.save_path = "user://fatal-hit-%d.json" % OS.get_process_id()
	root.add_child(host)
	host.shell.title_buttons.start.pressed.emit()
	host.shell.faction_picker.select(3)
	host.shell.faction_picker.item_selected.emit(3)
	host.shell.title_buttons.shouxiang.pressed.emit()
	host.choose_node("n01")
	var sim: Node = host.combat.get_node("Simulation")
	var victim: Node = sim.humans[0]
	var uid: String = victim.get_meta("night_uid")
	var enemy: Node = sim.tide.spawn("G12",0,victim.position.x+32)
	victim.receive_damage(999,enemy,"melee")
	var ok: bool = host.bridge.tracked[uid].fatal_hit.source == "G12"
	sim.advance(1.0/60.0)
	ok = ok and host._save_state().ok
	var old: Node = host.combat
	host.continue_run()
	ok = ok and host.combat != old and host.bridge.tracked[uid].fatal_hit.source == "G12"
	host.combat.get_node("Session")._finish("defeat","P4_END_REGISTER_CAPTURED")
	host._process(0.0)
	ok = ok and host.run.state.phase == "mercy" and "力士尸近战" in host.panel._recent_loss()
	host.continue_run()
	ok = ok and "力士尸近战" in host.panel._recent_loss()
	for member in host.run.state.last_battle.get("fallen",[]): member.erase("fatal_hit")
	ok = ok and host.panel._recent_loss().is_empty()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	print("Fatal source retained across battle restore and mercy reload; legacy view: ",ok)
	await create_timer(0.4).timeout
	quit(0 if ok else 1)
