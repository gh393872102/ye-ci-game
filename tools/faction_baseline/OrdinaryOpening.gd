extends SceneTree
## Exercises the real title button, map save and first ordinary combat. Autonomy only.
var failures := 0
var foreign_units := {}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["0","1","2","3"]:
		quit(2)
		return
	var index := int(args[0])
	var faction: String = load("res://src/night/FactionOpening.gd").PAIRS.keys()[index]
	var rows := []
	for seed_text in ["渡口","灯市","秋社"]:
		rows.append(await measure(index,faction,seed_text))
	var path := "res://tools/faction_baseline/ordinary-opening-%d.json" % index
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(rows,"\t")+"\n")
	await create_timer(0.6).timeout
	quit(1 if failures or not rows.all(func(row): return row.get("passed",false)) else 0)

func observe(unit: Node, faction: String) -> void:
	if unit.side == "xianghuo" and root.get_node("Data").get_unit(unit.unit_id).get("所属","") != faction:
		foreign_units[unit.instance_id] = unit.unit_id

func measure(index: int, faction: String, seed_text: String) -> Dictionary:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.title_shell_enabled = true
	host.save_path = "/tmp/ye-opening-%d-%d-%s.json" % [OS.get_process_id(),index,seed_text]
	root.add_child(host)
	host.shell.title_buttons.start.pressed.emit()
	host.shell.faction_picker.select(index+1)
	host.shell.faction_picker.item_selected.emit(index+1)
	var hint_visible: bool = host.shell.faction_detail.visible and host.shell.faction_detail.text.contains("17")
	host.shell.seed_input.text = seed_text
	host.shell.title_buttons.shouxiang.pressed.emit()
	var night: RefCounted = load("res://src/night/NightRun.gd").new()
	var ok: bool = hint_visible and night.load_save(host.save_path).ok and night.state.get("opening_faction") == faction
	DirAccess.remove_absolute(host.save_path)
	host.free()
	var row := {"seed":seed_text,"faction":faction,"title_save_roundtrip":ok}
	if not ok or not night.choose_node("n01").ok:
		failures += 1
		return row
	var result := await fight(night,faction,seed_text)
	row.merge(result)
	row.passed = result.get("settled",false) and result.posts.size() == 2 and result.roster_price == 17 and result.incense == 20 and result.hold and result.foreign_units.is_empty()
	return row

func fight(night: RefCounted, faction: String, seed_text: String, upgrade_pair := false) -> Dictionary:
	var row := {"node":night.state.current_node_id}
	var scene: Node = load("res://scenes/combat/Combat.tscn").instantiate()
	scene.configure_chunks(night.current_node().chunk_ids)
	root.add_child(scene)
	var bridge: RefCounted = load("res://src/night/NightBattleBridge.gd").new()
	var sim := scene.get_node("Simulation")
	var session := scene.get_node("Session")
	sim.set_physics_process(false)
	var started: Dictionary = bridge.start(scene,night)
	row.start = started.reason
	if not started.ok:
		failures += 1
		scene.free()
		return row
	row.incense = session.incense
	row.posts = {}
	row.roster_price = 0
	foreign_units.clear()
	for unit in sim.humans:
		observe(unit,faction)
		row.posts[unit.unit_id] = unit.current_post
		row.roster_price += session.rules.purchases.get(unit.unit_id,0)
	if upgrade_pair:
		row.upgrades = []
		for unit in sim.humans:
			var before: float = session.incense
			var receipt: Dictionary = session.upgrade(unit)
			row.upgrades.append({"id":unit.unit_id, "ok":receipt.ok, "paid":before-session.incense})
	sim.unit_spawned.connect(func(unit): observe(unit,faction))
	sim.unit_allegiance_changed.connect(func(unit,_old,_new): observe(unit,faction))
	for tick in ceili(session.rules.duration * 60.0) + 2:
		sim.advance(1.0/60.0)
		for unit in sim.humans: observe(unit,faction)
		if not session.running: break
	row.foreign_units = foreign_units.duplicate()
	row.result = session.result.duplicate(true)
	var settled: Dictionary = night.accept_battle(bridge.collect(scene,night))
	row.settled = settled.ok
	row.phase = night.state.phase
	row.hold = session.growth.state.get("defense_objective") == "hold_register"
	print(faction," ",seed_text," ",row.result.get("outcome")," ",row.foreign_units)
	bridge.recording.stop()
	scene.free()
	await process_frame
	return row
