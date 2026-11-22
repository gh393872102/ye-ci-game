extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path = "user://register-break-%d.json" % OS.get_process_id()
	root.add_child(host)
	host.start_p10_night("duoming","example","渡口","R01",[],"无名潮")
	host.choose_node("n01")
	var sim: Node = host.combat.get_node("Simulation")
	sim.set_physics_process(false)
	var guard: Node
	for unit in sim.humans:
		if sim.world.room_at(unit.position,unit.floor_id)=="register":
			guard=unit
			break
	var scout: Node=sim.tide.spawn("G07",0,guard.position.x)
	scout.floor_id=guard.floor_id
	scout.position=guard.position
	sim.session.occupation=4
	sim.session.after_step(1.0/60.0)
	var record: Dictionary=sim.session.register_break.duplicate(true)
	var panel: Node=host.combat.get_node("Decisions")
	panel._update_warnings()
	var ok: bool=record.peak==4 and record.attackers==1 and guard.display_name in record.guards and panel.register_warning.text.contains("守军阻断")
	scout.position.x=10
	sim.session.after_step(1.0/60.0)
	panel._update_warnings()
	ok=ok and panel.register_warning.text.contains("攻方已撤空") and sim.session.register_break==record
	ok=ok and host._save_state().ok
	host.continue_run()
	sim=host.combat.get_node("Simulation")
	ok=ok and sim.session.register_break==record
	sim.session.occupation=6
	sim.session._finish("defeat","P4_END_DAYBREAK")
	var dawn: Dictionary=sim.session.result.get("register_break",{})
	ok=ok and dawn.get("at_dawn",false) and dawn.peak==6
	var fingerprint: Dictionary=load("res://src/replay/BattleRecord.gd").fingerprint(host.combat)
	ok=ok and not fingerprint.session.has("register_break") and not fingerprint.session.result.has("register_break")
	print("守军回房、攻方撤空、最佳进度、存读与天亮结算 ",ok)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(.3).timeout
	quit(0 if ok else 1)
