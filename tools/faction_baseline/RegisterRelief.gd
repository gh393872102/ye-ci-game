extends SceneTree
## Checks edge cases through the ordinary battle UI. These states do not count as route outcomes.
var failed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failed += 1

func run() -> void:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path = "user://relief-test.json"
	root.add_child(host)
	host.start_p10_night("shouxiang","example","渡口","R01",[],"守香司")
	host.choose_node("n01")
	var sim := host.combat.get_node("Simulation") as Node
	sim.set_physics_process(false)
	var session: Node = sim.session
	var panel: Node = host.combat.get_node("Decisions")
	var clock := root.get_node("Clock")
	clock.set_paused(false)
	session.register_attackers = 1
	session.register_guards.assign(["霜盏","青笺"])
	panel._update_warnings()
	check(not panel.relief_button.visible,"Two guards hold the room without a relief prompt")
	session.register_guards.assign(["霜盏"])
	panel._update_warnings()
	check(panel.relief_button.visible,"The last guard can call relief before occupation begins")
	session.register_guards.clear()
	panel._update_warnings()
	check(panel.relief_button.visible,"An undefended room under attack exposes ordinary relief")
	session.occupation = 2.0
	panel._update_warnings()
	check(panel.occupation_bar.visible and panel.occupation_bar.value == 2.0 and panel.register_warning.text.contains("夺册还需"),"Occupation meter and remaining-time text follow the live timer")
	var money: float = session.incense
	panel.previous_casualties["H01"] = true
	panel.relief_button.pressed.emit()
	check(panel.register_relief and clock.paused and panel.content.find_child("buy_H01",true,false)==null,"Pause and exclude a prior casualty")
	panel.buttons.close.pressed.emit()
	check(not clock.paused and session.incense==money and session.pending_purchase.is_empty(),"Cancel restores running state without a charge")
	panel.previous_casualties.clear()
	session.incense = 0
	panel._open_register_relief()
	check(panel.content.find_children("buy_*","Button",true,false).is_empty() and panel._empty_relief_hint().contains("可用香火 0") and panel._empty_relief_hint().contains("晚"),"No budget lists the available wallet, vacancies and priced allies")
	panel.buttons.purchase_scope.pressed.emit()
	check(not panel.register_relief and not panel.recruitable_faction_only,"Full catalogue restores ordinary staged deployment")
	panel.close_panel()
	session.incense = money
	clock.set_paused(true)
	panel._open_register_relief()
	var buy := panel.content.find_child("buy_H01",true,false) as Button
	if buy:
		# Fill the last two vacancies after the card was offered.
		sim.spawn_human("H02","post_register")
		sim.spawn_human("H08","post_register")
		buy.pressed.emit()
	check(buy != null and session.incense==money and session.pending_purchase.is_empty() and panel.current_panel=="purchase" and panel.content.find_children("buy_*","Button",true,false).is_empty(),"Late full post atomically refunds reservation and refreshes the cards")
	panel.close_panel()
	check(clock.paused,"Cancel preserves an initially paused clock")
	session.register_attackers = 0
	panel._update_warnings()
	check(not panel.relief_button.visible,"Attacker withdrawal removes relief")
	host.start_p10_night("shouxiang","example","渡口","R01",[],"守香司")
	host.choose_node("n01")
	panel=host.combat.get_node("Decisions")
	session=host.combat.get_node("Session")
	session.register_attackers=1
	session.register_guards.clear()
	session.incense=12
	panel._open_register_relief()
	panel.buttons.prepare_H01.pressed.emit()
	check(panel.current_panel=="upgrade" and clock.paused and panel.selected.unit_id=="H01" and panel.selected.current_post=="post_register","Recruit opens the selected guard's paused training preview")
	check(session.incense==0 and panel.buttons.upgrade_confirm.disabled,"Exact recruitment price leaves training unavailable")
	panel.close_panel()
	check(session.incense==0 and session.pending_purchase.is_empty() and panel.selected.upgrade_level==0,"Leaving training keeps only the confirmed recruit")
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://relief-test.json"))
	await create_timer(0.3).timeout
	quit(1 if failed else 0)
