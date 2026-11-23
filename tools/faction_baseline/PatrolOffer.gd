extends SceneTree
## Pass the n05 pre-battle save produced by YE_CI_PATROL_MAP.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var rows := []
	var args := OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(2)
		return
	for fixture in ["ordinary","without_guard","fallen_patrol"]:
		var night: RefCounted = load("res://src/night/NightRun.gd").new()
		if not night.load_save(args[0]).ok or not night.choose_node("n05").ok:
			quit(2)
			return
		if fixture=="without_guard":
			night.state.roster = night.state.roster.filter(func(u): return u.id!="H09")
		if fixture=="fallen_patrol":
			var fallen: Dictionary = night.state.roster[0].duplicate(true)
			fallen.merge({"id":"H12","hp":0,"uid":"fixture_fallen"},true)
			night.state.fallen.append(fallen)
		var scene: Node = load("res://scenes/combat/Combat.tscn").instantiate()
		scene.configure_chunks(night.current_node().chunk_ids)
		root.add_child(scene)
		var bridge: RefCounted = load("res://src/night/NightBattleBridge.gd").new()
		var started: Dictionary = bridge.start(scene,night)
		var session: Node = scene.get_node("Session")
		var row := {"fixture":fixture,"passed":started.ok,"quoted":session.rules.purchases.get("H12",0)}
		if fixture=="ordinary" and started.ok:
			var panel: Node = scene.get_node("Decisions")
			panel.preferred_faction = "武卫司"
			panel.open_purchase()
			row.with_patrol = first_page(panel)
			panel.buttons.purchase_scope.pressed.emit()
			row.full_first_page = first_page(panel)
			panel.close_panel()
			session.rules.purchases.erase("H12")
			panel.open_purchase()
			row.without_patrol = first_page(panel)
			panel.close_panel()
			session.rules.purchases["H12"] = row.quoted
			var cash: float = session.incense
			session.incense = 11.5
			row.shortfall = session.purchase("H12").reason
			session.incense = cash
			row.bought = session.purchase("H12").ok and session.deploy_at("post_register").ok
			var snap: Dictionary = bridge.snapshot(scene)
			var restored: Dictionary = bridge.restore(scene,night,snap)
			row.resumed = restored.ok
			row.count = scene.get_node("Simulation").humans.filter(func(u):return u.unit_id=="H12" and u.current_post=="post_register").size()
			row.paid = cash-session.incense
			row.passed = row.passed and "H12" in row.with_patrol and row.full_first_page==row.without_patrol and row.quoted==12 and row.shortfall=="P4_NO_INCENSE" and row.bought and row.resumed and row.count==1 and row.paid==12
		else:
			row.passed = row.passed and row.quoted==0
		rows.append(row)
		bridge.recording.stop()
		scene.free()
		await process_frame
	FileAccess.open("res://tools/faction_baseline/patrol-offer.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t")+"\n")
	print(rows)
	quit(0 if rows.all(func(r): return r.passed) else 1)

func first_page(panel: Node) -> Array:
	return panel.content.find_children("buy_*","Button",true,false).map(func(button): return str(button.name).trim_prefix("buy_"))
