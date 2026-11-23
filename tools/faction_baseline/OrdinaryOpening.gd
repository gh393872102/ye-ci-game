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

func fight(night: RefCounted, faction: String, seed_text: String, upgrade_pair := false, aid_post := "", fill_watch := false, ordered_id := "", track_register := false, train_aid := false, upgrade_rounds := 1, carried_items: Array = [], lamp_recruit := false, relief_delay := -1.0, train_id := "", gear_owner := "", order_readings := false, read_tag := "", read_after := 0.0, last_guard_relief := false) -> Dictionary:
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
	if track_register and row.node == "n10":
		row.opening_guards = sim.humans.map(func(u): return {"id":u.unit_id,"hp":u.hp,"max_hp":u.max_hp,"post":u.current_post,"slots":u.growth.get("slots",{}).duplicate(true)})
	row.roster_price = 0
	foreign_units.clear()
	for unit in sim.humans:
		observe(unit,faction)
		row.posts[unit.unit_id] = unit.current_post
		row.roster_price += session.rules.purchases.get(unit.unit_id,0)
	if track_register and row.node in ["n08","n10"]:
		row.same_faction_offers = []
		for offer in session.purchase_options():
			if root.get_node("Data").get_unit(offer.id).get("所属","") != faction: continue
			row.same_faction_offers.append({"id":offer.id,"cost":offer.cost,"allowed":offer.allowed,"reason":offer.reason,"posts":session.legal_posts(offer.id),"previously_fallen":night.state.fallen.any(func(member): return member.id == offer.id)})
	var started_growth_time: float = session.growth.state.get("time",0.0)
	for carried_item in carried_items:
		var matches: Array = sim.humans.filter(func(u): return gear_owner.is_empty() or u.unit_id==gear_owner)
		if matches.is_empty():
			row.gear_error = "missing wearer "+gear_owner
			break
		var guard: Node = matches[0]
		var index := 0
		if root.get_node("Data").growth_rules.items[carried_item].slot == "art":
			index = maxi(0,guard.growth.slots.arts.find(""))
		var clock := root.get_node("Clock")
		var cost_before: float = session.incense
		var qty_before: int = session.growth.state.inventory.get(carried_item,0)
		clock.set_paused(true)
		var gear: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":guard.instance_id,"item_id":carried_item,"slot_index":index},"player")
		clock.set_paused(false)
		if not row.has("gear"): row.gear = []
		row.gear.append({"id":carried_item,"owner":guard.unit_id,"instance":guard.instance_id,"ok":gear.ok,"before":qty_before,"after":session.growth.state.inventory.get(carried_item,0),"paid":cost_before-session.incense,"slots":guard.growth.slots.duplicate(true)})
	if upgrade_pair:
		row.upgrades = []
		for level in upgrade_rounds:
			for unit in sim.humans:
				var before: float = session.incense
				var receipt: Dictionary = session.upgrade(unit)
				row.upgrades.append({"id":unit.unit_id, "ok":receipt.ok, "paid":before-session.incense})
	var id: String = {"守香司":"H01","武卫司":"H09","符法司":"H17","奇人司":"H25"}[faction]
	if not ordered_id.is_empty(): id = ordered_id
	if fill_watch:
		for offer in session.purchase_options():
			if not offer.allowed or root.get_node("Data").get_unit(offer.id).get("所属","") != faction: continue
			if night.state.fallen.any(func(unit): return unit.id == offer.id): continue
			var legal: Array = session.legal_posts(offer.id)
			for post in ["post_register","post_hall_door","post_inner_gate"]:
				if post in legal:
					id = offer.id
					aid_post = post
					break
			if not aid_post.is_empty(): break
	if not aid_post.is_empty():
		var before: float = session.incense
		var purchase: Dictionary = session.purchase(id)
		var placed := false
		var recruit: Node
		if purchase.ok:
			var deployment: Dictionary = session.deploy_at(aid_post)
			placed = deployment.ok
			if placed: recruit = deployment.unit
			if not placed: session.cancel_purchase()
		row.aid = {"id":id,"post":aid_post,"placed":placed,"paid":before-session.incense}
		if placed and lamp_recruit:
			var clock := root.get_node("Clock")
			clock.set_paused(true)
			var qty: int = session.growth.state.inventory.get("I08",0)
			var cash: float = session.incense
			var receipt: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":recruit.instance_id,"item_id":"I08","slot_index":0},"player")
			clock.set_paused(false)
			row.recruit_gear = {"ok":receipt.ok,"before":qty,"after":session.growth.state.inventory.get("I08",0),"paid":cash-session.incense}
		if placed and train_aid:
			var cash: float = session.incense
			var training: Dictionary = session.upgrade(recruit)
			row.aid_upgrade = {"id":id,"ok":training.ok,"paid":cash-session.incense}
		for unit in sim.humans: observe(unit,faction)
	sim.unit_spawned.connect(func(unit): observe(unit,faction))
	sim.unit_allegiance_changed.connect(func(unit,_old,_new): observe(unit,faction))
	row.first_occupation = {}
	var inside := {}
	if track_register:
		row.register_guards = {}
		for guard in sim.humans:
			if sim.world.room_at(guard.position,guard.floor_id) == "register":
				inside[guard.instance_id] = guard
				row.register_guards[guard.instance_id] = {"id":guard.unit_id,"first_change":"held"}
		sim.unit_fallen.connect(func(unit):
			if inside.erase(unit.instance_id):
				row.register_guards[unit.instance_id].merge({"first_change":"fallen","seconds":sim.simulation_time},true)
		)
	if not train_id.is_empty() and sim.humans.any(func(u): return u.unit_id==train_id and not u.dead):
		row.target_training = train_guard(session,sim,train_id)
	var capture_pin := train_aid and OS.get_environment("YE_CI_CAPTURE_PIN") == "1" and DisplayServer.get_name() != "headless"
	var reader: Node2D
	if order_readings:
		for unit in sim.humans:
			if unit.unit_id=="H01": reader=unit
		row.read_orders = []
	for tick in ceili(session.rules.duration * 60.0) + 2:
		sim.advance(1.0/60.0)
		if order_readings and not row.read_orders.is_empty():
			var latest: Dictionary = row.read_orders.back()
			if not latest.has("ended") and (not is_instance_valid(reader) or reader.dead or not reader.brain.channel.active):
				latest.ended = sim.simulation_time
				latest.end_reason = "fallen" if not is_instance_valid(reader) or reader.dead else reader.brain.channel.last_result
		if order_readings and sim.simulation_time>=read_after and tick % 60 == 0 and row.read_orders.size()<2 and session.running and is_instance_valid(reader) and not reader.dead:
			var target: Node2D
			for enemy in sim.targets:
				if not read_tag.is_empty() and read_tag not in enemy.tags: continue
				if not session.preview_ritual(reader,enemy).reason.is_empty(): continue
				if target==null or ("破门" in enemy.tags and "破门" not in target.tags): target=enemy
			if is_instance_valid(target):
				var balance: float = session.incense
				var answer: Dictionary = session.execute_for("shouxiang","start_ritual",{"caster_id":reader.instance_id,"target_id":target.instance_id},"player")
				row.read_orders.append({"seconds":sim.simulation_time,"ok":answer.ok,"paid":balance-session.incense,"target":target.unit_id,"instance":target.instance_id})
		if relief_delay >= 0 and not row.has("relief") and session.running and session.occupation >= relief_delay and session.register_attackers > 0 and (session.register_guards.is_empty() or (last_guard_relief and session.register_guards.size() == 1)):
			var holding: Array = session.register_guards.duplicate()
			row.relief = request_register_relief(scene,night,faction,id,train_id=="H01")
			row.relief.guards_at_request = holding
			if row.relief.has("training"): row.target_training = row.relief.training
		if capture_pin:
			for effect in session.roster.state.get("effects",[]):
				if effect.kind != "bone_pin" or effect.left > effect.duration * 0.80: continue
				var camera := scene.get_node("BattleCamera")
				camera.make_current()
				camera.set_left(float(effect.point[0]) - root.size.x / 2.0)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var shot := root.get_texture().get_image()
				shot.save_jpg("/tmp/ye-ci-bone-pin.jpg",0.88)
				print("BONE PIN ",row.node," ",sim.simulation_time," ",shot.get_size()," ",effect.point)
				capture_pin = false
				break
		if not inside.is_empty():
			for key in inside.keys():
				var guard: Node2D = inside[key]
				var room: String = sim.world.room_at(guard.position,guard.floor_id)
				if room != "register":
					row.register_guards[key].merge({"first_change":"left_room","seconds":sim.simulation_time,"room":room,"post":guard.current_post,"purpose":guard.brain.purpose,"last_reason":guard.brain.last_reason},true)
					inside.erase(key)
		if session.occupation > 0 and row.first_occupation.is_empty():
			var guards := []
			for unit in sim.humans:
				if not unit.dead:
					guards.append({"id":unit.unit_id,"room":sim.world.room_at(unit.position,unit.floor_id),"post":unit.current_post})
			var intruders := []
			for unit in sim.targets:
				if not unit.dead and sim.world.room_at(unit.position,unit.floor_id) == "register": intruders.append(unit.unit_id)
			row.first_occupation = {"seconds":sim.simulation_time,"guards":guards,"intruders":intruders}
		for unit in sim.humans: observe(unit,faction)
		if not session.running: break
	if order_readings and not row.read_orders.is_empty():
		var last_read: Dictionary = row.read_orders.back()
		if not last_read.has("ended") and is_instance_valid(reader) and reader.brain.channel.active:
			var channel: RefCounted = reader.brain.channel
			last_read.observed_until = sim.simulation_time
			last_read.channel_seconds = channel.elapsed
			last_read.required_seconds = channel.duration
	if not carried_items.is_empty() or order_readings:
		row.reading_events = session.growth.state.events.filter(func(e): return e.kind in ["channel_guard","ritual_release"] and float(e.time)>started_growth_time)
	if not carried_items.is_empty():
		row.brace_events = session.growth.state.events.filter(func(entry): return entry.kind == "paper_brace")
	row.foreign_units = foreign_units.duplicate()
	row.result = session.result.duplicate(true)
	var report: Dictionary = bridge.collect(scene,night)
	if row.node == "n10" or order_readings:
		row.fatal_hits = []
		for fallen in report.fallen:
			row.fatal_hits.append({"id":fallen.id,"hit":fallen.get("fatal_hit",{})})
		row.lamp_events = session.growth.state.events.filter(func(e): return e.kind == "lamp_reveal")
	var settled: Dictionary = night.accept_battle(report)
	row.settled = settled.ok
	row.phase = night.state.phase
	row.hold = session.growth.state.get("defense_objective") == "hold_register"
	print(faction," ",seed_text," ",row.result.get("outcome")," ",row.foreign_units)
	bridge.recording.stop()
	scene.free()
	await process_frame
	return row

func request_register_relief(scene: Node, night: RefCounted, faction: String, id: String, inspect_training := false) -> Dictionary:
	var session := scene.get_node("Session")
	var sim := scene.get_node("Simulation")
	var menu := scene.get_node("Decisions")
	menu.managed_by_night = true
	menu.preferred_faction = faction
	for member in night.state.fallen: menu.previous_casualties[member.id] = true
	menu._update_warnings()
	var cash: float = session.incense
	var receipt := {"time":sim.simulation_time,"occupation":session.occupation,"balance_before":cash,"vacancies":session.post_vacancies("post_register"),"offered":false,"id":id,"post":"post_register"}
	if menu.relief_button.visible:
		menu.relief_button.pressed.emit()
		receipt.available = []
		while true:
			for candidate in menu.content.find_children("buy_*","Button",true,false):
				if not candidate.disabled: receipt.available.append(str(candidate.name).trim_prefix("buy_"))
			if menu.buttons.purchase_next.disabled: break
			menu.buttons.purchase_next.pressed.emit()
		if id == "@first" and not receipt.available.is_empty():
			id = receipt.available.front()
			receipt.id = id
		receipt.catalog_price = session.rules.purchases.get(id)
		if receipt.available.is_empty(): receipt.empty_hint = menu._empty_relief_hint()
		while menu.purchase_page > 0: menu.buttons.purchase_prev.pressed.emit()
		var button_name := ("prepare_" if inspect_training else "buy_")+id
		var buy: Button = menu.content.find_child(button_name,true,false)
		while buy == null and not menu.buttons.purchase_next.disabled:
			menu.buttons.purchase_next.pressed.emit()
			buy = menu.content.find_child(button_name,true,false)
		if is_instance_valid(buy) and not buy.disabled:
			receipt.offered = true
			buy.pressed.emit()
		if inspect_training and menu.current_panel=="upgrade" and menu.selected.unit_id==id:
			var unit: Node = menu.selected
			var before: float = session.incense
			var hp: float = unit.hp
			if not menu.buttons.upgrade_confirm.disabled: menu.buttons.upgrade_confirm.pressed.emit()
			receipt.training = {"id":id,"instance":unit.instance_id,"ok":unit.hp>hp,"paid":before-session.incense,"hp_before":hp,"hp_after":unit.hp,"via_panel":true}
		menu.close_panel()
	receipt.paid = cash-session.incense-float(receipt.get("training",{}).get("paid",0))
	receipt.placed = receipt.offered and sim.humans.any(func(actor): return not actor.dead and actor.unit_id==id and actor.current_post=="post_register")
	return receipt

func train_guard(session: Node, sim: Node, id: String) -> Dictionary:
	for unit in sim.humans:
		if unit.unit_id==id and not unit.dead:
			var cash: float = session.incense
			var hp: float = unit.hp
			var receipt: Dictionary = session.upgrade(unit)
			return {"id":id,"instance":unit.instance_id,"ok":receipt.ok,"paid":cash-session.incense,"hp_before":hp,"hp_after":unit.hp}
	return {"id":id,"ok":false}
