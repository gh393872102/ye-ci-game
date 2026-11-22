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
	var picker: OptionButton = host.panel.find_child("ReservePost",true,false)
	var selected := -1
	for i in range(1,picker.item_count):
		var move: Dictionary = picker.get_item_metadata(i)
		if move.id == "H32" and move.to == "post_register": selected = i
	ok = ok and selected > 0
	if selected > 0:
		var order: Dictionary = picker.get_item_metadata(selected)
		var before_incense: float = host.run.state.incense
		picker.select(selected)
		picker.item_selected.emit(selected)
		ok = ok and host.run.state.incense == before_incense and not host.run.reserve_post(order.uid,order.to).ok
		host.continue_run()
		ok = ok and host.run.state.roster.all(func(member): return member.post == "post_register")
		ok = ok and not host.run.reserve_post(order.uid,"missing").ok
		# Isolated capacity fixture: three occupied slots reject a fourth actor.
		var baseline: Array = host.run.state.roster.duplicate(true)
		host.run.state.roster.append(host.run._unit("H25","post_register"))
		var fourth: Dictionary = host.run._unit("H09","post_hall_door")
		host.run.state.roster.append(fourth)
		ok = ok and not host.run.reserve_post(fourth.uid,"post_register").ok and fourth.post == "post_hall_door"
		host.run.state.roster = baseline
	host.choose_node("n01")
	ok = ok and host.run.reserve_post_options().is_empty()
	var first: Node = host.combat
	if is_instance_valid(first):
		first.get_node("Simulation").advance(1.0/60)
		var shop := first.get_node("Decisions")
		shop.open_purchase()
		ok = ok and shop.buttons.has("buy_H25") and shop.buttons.has("buy_H27") and shop.buttons.has("buy_H32") and not shop.buttons.has("buy_T01")
		shop.close_panel()
		var before: float = first.get_node("Simulation").simulation_time
		host.save_run()
		host.continue_run()
		ok = ok and is_instance_valid(host.combat) and first != host.combat and host.run.state.opening_faction == "奇人司"
		if is_instance_valid(host.combat):
			var sim: Node = host.combat.get_node("Simulation")
			ok = ok and is_equal_approx(sim.simulation_time,before) and sim.humans.size() == 2 and sim.humans.all(func(unit): return unit.current_post == "post_register") and host.combat.get_node("Session").growth.state.get("defense_objective") == "hold_register"
	else: ok = false
	shell.faction_picker.select(3)
	shell.faction_picker.item_selected.emit(3)
	shell.title_buttons.shouxiang.pressed.emit()
	host.choose_node("n01")
	var talisman_shop: Node = host.combat.get_node("Decisions")
	talisman_shop.open_purchase()
	var has_borrow_hint: bool = talisman_shop.content.find_children("*","Label",true,false).any(func(label): return label.text.contains("临时收编野鬼"))
	ok = ok and talisman_shop.buttons.has("buy_H19") and has_borrow_hint
	var battle_session: Node = host.combat.get_node("Session")
	var cash: float = battle_session.incense
	talisman_shop.buttons.purchase_scope.pressed.emit()
	var expected := []
	for offer in battle_session.purchase_options():
		if offer.allowed and root.get_node("Data").get_unit(offer.id).get("所属","") == "符法司" and not battle_session.legal_posts(offer.id).is_empty():
			expected.append(offer.id)
	expected.sort()
	var shown := []
	while true:
		for card in talisman_shop.content.find_children("buy_*","Button",true,false):
			shown.append(str(card.name).trim_prefix("buy_"))
		if talisman_shop.buttons.purchase_next.disabled: break
		talisman_shop.buttons.purchase_next.pressed.emit()
	ok = ok and shown == expected and "H19" in shown and "H22" in shown and not "H21" in shown
	ok = ok and is_equal_approx(battle_session.incense,cash) and battle_session.pending_purchase.is_empty()
	talisman_shop.buttons.purchase_scope.pressed.emit()
	ok = ok and talisman_shop.purchase_page == 0 and not talisman_shop.recruitable_faction_only
	battle_session.incense = 0
	talisman_shop.buttons.purchase_scope.pressed.emit()
	ok = ok and talisman_shop.offer_status.is_empty() and talisman_shop.buttons.purchase_prev.disabled and talisman_shop.buttons.purchase_next.disabled
	talisman_shop.buttons.purchase_scope.pressed.emit()
	ok = ok and not talisman_shop.offer_status.is_empty()
	battle_session.incense = cash
	talisman_shop.buttons.purchase_scope.pressed.emit()
	while not talisman_shop.offer_status.has("H22") and not talisman_shop.buttons.purchase_next.disabled:
		talisman_shop.buttons.purchase_next.pressed.emit()
	if talisman_shop.offer_status.has("H22"):
		talisman_shop.buttons.buy_H22.pressed.emit()
		ok = ok and battle_session.pending_purchase == "H22" and battle_session.incense == cash - 10
		talisman_shop.buttons.post_post_register.pressed.emit()
		ok = ok and battle_session.pending_purchase.is_empty() and host.combat.get_node("Simulation").humans.any(func(actor): return actor.unit_id=="H22" and actor.current_post=="post_register")
	else: ok = false
	print("menu, faction shop, purchase and mid-battle restore: ",ok," visible candidates: ",shown)
	DirAccess.remove_absolute(host.save_path)
	host.free()
	await create_timer(0.5).timeout
	quit(0 if ok else 1)
