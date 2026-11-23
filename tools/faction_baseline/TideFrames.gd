extends SceneTree
## Wall-clock presentation probe in the ordinary n01 scene with an injected four-lane crowd.
const SAMPLES := 180

func _initialize() -> void:
	run.call_deferred()

func percentiles(values: Array) -> Dictionary:
	var ordered := values.duplicate()
	ordered.sort()
	var result := {}
	for pct in [50,95,99]:
		result[str(pct)] = ordered[ceili(pct * ordered.size() / 100.0) - 1]
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("A native display and renderer are required")
		quit(2)
		return
	root.size = Vector2i(1920,1080)
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.title_shell_enabled = true
	host.save_path = "/tmp".path_join("ye-tide-%d.json" % OS.get_process_id())
	root.add_child(host)
	var shell: Node = host.shell
	shell.title_buttons.start.pressed.emit()
	var martial := OS.get_cmdline_user_args().has("--martial-watch")
	var opening := 2 if martial else 3
	shell.faction_picker.select(opening)
	shell.faction_picker.item_selected.emit(opening)
	shell.seed_input.text = "渡口"
	shell.title_buttons.shouxiang.pressed.emit()
	var swap := {}
	if martial: swap = await probe_swap(host)
	var rear := {}
	var table := OS.get_cmdline_user_args().has("--table-probe")
	if table or OS.get_cmdline_user_args().has("--rear-probe"):
		rear = await probe_rear(host,"post_table_hall" if table else "post_rear")
	host.choose_node("n01")
	var battle: Node = host.combat
	var sim: Node = battle.get_node("Simulation")
	var camera: Node = battle.get_node("BattleCamera")
	var decisions: Node = battle.get_node("Decisions")
	var cards := {}
	if martial:
		for actor in sim.humans:
			if actor.unit_id not in ["H10","H11"]: continue
			decisions.select_unit(actor)
			await RenderingServer.frame_post_draw
			cards[actor.unit_id] = decisions._martial_trait_readout().strip_edges()
			if cards[actor.unit_id] not in decisions.details.text: cards.erase(actor.unit_id)
			if actor.unit_id=="H11": root.get_texture().get_image().save_webp("/tmp/ye35-card.webp",false,0.83)
		decisions.close_panel()
		root.get_node("Clock").set_paused(false)
	var actors := ["G01","G09","G11","G12"]
	for column in 11:
		for lane in 4:
			sim.tide.spawn(actors[lane],lane,camera.left()+55+column*105+lane*10)
	for warmup in 30: await RenderingServer.frame_post_draw
	var frames := []
	var visible_min := 99999
	var visible_max := 0
	var sim_start: float = sim.simulation_time
	var before := Time.get_ticks_usec()
	for i in SAMPLES:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append((now-before)/1000.0)
		before = now
		var visible_count := 0
		for ghost in sim.targets:
			if not ghost.dead and root.get_visible_rect().has_point(ghost.get_global_transform_with_canvas().origin):
				visible_count += 1
		visible_min = mini(visible_min,visible_count)
		visible_max = maxi(visible_max,visible_count)
	var sim_end: float = sim.simulation_time
	var shot := root.get_texture().get_image()
	var size := shot.get_size()
	var colors := {}
	for y in range(0,size.y,80):
		for x in range(0,size.x,80): colors[shot.get_pixel(x,y).to_html()] = true
	var capture := OS.get_cmdline_user_args().has("--capture")
	if capture: shot.save_webp("/tmp/ye-r5-tide.webp",false,0.82)
	var input_ms := []
	var pay_visible := false
	var hall_probe := OS.get_cmdline_user_args().has("--hall-probe")
	var lamp_probe := OS.get_cmdline_user_args().has("--lamp-probe")
	var recruit := "H09" if martial else ("H19" if lamp_probe else "H22")
	var deploy_probe := lamp_probe or hall_probe or OS.get_cmdline_user_args().has("--deploy-probe")
	var destination := "post_hall_door" if hall_probe else "post_register"
	var deploy_feedback := {}
	for trial in 12:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_Q
		key.pressed = true
		var sent := Time.get_ticks_usec()
		Input.parse_input_event(key)
		for timeout_frame in 12:
			await RenderingServer.frame_post_draw
			if decisions.current_panel == "purchase" and decisions.panel.is_visible_in_tree():
				input_ms.append((Time.get_ticks_usec()-sent)/1000.0)
				break
		if trial == 11 and decisions.current_panel == "purchase":
			decisions.buttons.purchase_scope.pressed.emit()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var button: Button = decisions.content.find_child("buy_"+recruit,true,false)
			pay_visible = is_instance_valid(button) and not button.disabled and decisions.panel_scroll.get_global_rect().encloses(button.get_global_rect())
			if capture: root.get_texture().get_image().save_webp("/tmp/ye-r5-shop.webp",false,0.82)
		if deploy_probe and trial == 11 and pay_visible:
			var session: Node = battle.get_node("Session")
			var cash: float = session.incense
			decisions.buttons["buy_"+recruit].pressed.emit()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var quick: Button = decisions.content.find_child("defend_hall" if hall_probe else "defend_register",true,false)
			if is_instance_valid(quick):
				var rect := quick.get_global_rect()
				var sent_click := Time.get_ticks_usec()
				for down in [true,false]:
					var mouse := InputEventMouseButton.new()
					mouse.button_index = MOUSE_BUTTON_LEFT
					mouse.position = rect.get_center()
					mouse.pressed = down
					root.push_input(mouse,true)
				var paid: float = cash - session.incense
				await RenderingServer.frame_post_draw
				deploy_feedback = {"post":destination,"feedback":decisions.feedback.text,"milliseconds":(Time.get_ticks_usec()-sent_click)/1000.0,"paid":paid,"placed":sim.humans.any(func(actor): return actor.unit_id==recruit and actor.current_post==destination),"inside_viewport":root.get_visible_rect().encloses(rect)}
		key = key.duplicate()
		key.pressed = false
		Input.parse_input_event(key)
		await RenderingServer.frame_post_draw
		decisions.close_panel()
		root.get_node("Clock").set_paused(false)
		await RenderingServer.frame_post_draw
	var passed := size == Vector2i(1920,1080) and colors.size() > 12 and visible_min >= 30 and sim_end > sim_start and input_ms.size() == 12 and pay_visible
	var result := {"passed":passed,"filtered_pay_button_visible":pay_visible,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"pixels":[size.x,size.y],"grid_colors":colors.size(),"fixture":"ordinary n01, talisman pair, 44 added actors in four lanes, live physics","warmup_frames":30,"visible_ghost_min_max":[visible_min,visible_max],"sim_seconds":[sim_start,sim_end],"frame_ms":frames,"frame_percentile_ms":percentiles(frames),"injected_q_to_purchase_frame_ms":input_ms}
	if not input_ms.is_empty(): result.input_percentile_ms = percentiles(input_ms)
	if deploy_probe:
		passed = passed and deploy_feedback.get("placed",false) and deploy_feedback.get("paid") == 10 and deploy_feedback.get("inside_viewport",false)
		if hall_probe: passed = passed and "主殿门厅" in str(deploy_feedback.get("feedback",""))
		result.passed = passed
		result.deploy_feedback = deploy_feedback
	var filename := "native-deploy.json" if deploy_probe else "native-tide.json"
	if hall_probe: filename = "native-hall.json"
	if lamp_probe:
		filename = "native-lamp.json"
		result.passed = passed and "问灯" in str(deploy_feedback.get("feedback",""))
		passed = result.passed
	if OS.get_cmdline_user_args().has("--training-target") or OS.get_cmdline_user_args().has("--last-guard") or OS.get_cmdline_user_args().has("--relief-probe") or OS.get_cmdline_user_args().has("--train-probe"):
		result.relief = await probe_relief(host)
		passed = passed and result.relief.passed
		result.passed = passed
		filename = "native-train.json" if OS.get_cmdline_user_args().has("--train-probe") else "native-relief.json"
	if OS.get_cmdline_user_args().has("--training-target"): filename = "native-training-target.json"
	if OS.get_cmdline_user_args().has("--last-guard"): filename = "native-last-guard.json"
	if OS.get_cmdline_user_args().has("--guard-gear"):
		result.guard_gear = await probe_guard_gear(host)
		passed = passed and result.guard_gear.passed
		result.passed = passed
		filename = "native-guard-gear.json"
	if OS.get_cmdline_user_args().has("--repair-quote"):
		filename = "native-repair.json"
		result.repair = await probe_repair(battle)
		passed = passed and result.repair.passed
		result.passed = passed
	if OS.get_cmdline_user_args().has("--post-cover") or OS.get_cmdline_user_args().has("--boss-brief"):
		result.cover = await probe_post_cover(host)
		passed = passed and result.cover.passed
		result.passed = passed
		filename = "native-post-cover.json"
		if OS.get_cmdline_user_args().has("--boss-brief"): filename = "native-boss-brief.json"
	if martial:
		filename = "native-martial-watch.json"
		result.fixture = "ordinary n01, martial pair after swap, 44 added actors in four lanes, live physics"
		result.swap = swap
		result.cards = cards
		result.stones = await probe_stones(host)
		passed = passed and result.stones.passed
		passed = passed and swap.passed and "孤刀" in result.cards.get("H10","") and "根深" in result.cards.get("H11","")
		result.passed = passed
	if OS.get_cmdline_user_args().has("--martial-final"):
		filename = "native-martial-final.json"
		result.final_map = await probe_final_map(host)
		passed = passed and result.final_map.passed
		result.passed = passed
	if OS.get_cmdline_user_args().has("--iron-preview"):
		filename = "native-iron-preview.json"
		result.iron_preview = await probe_iron(host)
		result.patrol = await probe_iron(host,true)
		passed = passed and result.iron_preview.passed and result.patrol.passed
		result.passed = passed
	if OS.get_cmdline_user_args().has("--camp-brace"):
		filename = "native-camp-brace.json"
	if OS.get_cmdline_user_args().has("--relief-budget"):
		filename = "native-relief-budget.json"
	if OS.get_cmdline_user_args().has("--last-watch"):
		filename = "native-last-watch-tide.json"
	if OS.get_cmdline_user_args().has("--camp-health"):
		result.camp = await probe_camp_health(host)
		result.passed = passed and result.camp.passed
		passed = result.passed
		filename = "native-camp-health.json"
	if OS.get_cmdline_user_args().has("--last-camp"):
		result.camp = await probe_last_camp(host)
		passed = passed and result.camp.passed
		result.passed = passed
		filename = "native-last-camp.json"
	if not rear.is_empty():
		result.rear = rear
		passed = passed and rear.passed
		result.passed = passed
		filename = "native-table.json" if table else "native-rear.json"
	if table:
		result.ritual_panel = await probe_range(battle)
		passed = passed and result.ritual_panel.passed
		result.passed = passed
	FileAccess.open("res://tools/faction_baseline/"+filename,FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("NATIVE ",passed," frames ",result.frame_percentile_ms," visible ",visible_min,"..",visible_max," input samples ",input_ms.size())
	DirAccess.remove_absolute(host.save_path)
	host.free()
	await create_timer(0.65).timeout
	quit(0 if passed else 1)

func click(button: Button) -> void:
	for down in [true,false]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = button.get_global_rect().get_center()
		mouse.pressed = down
		root.push_input(mouse,true)

func probe_relief(host: Node) -> Dictionary:
	var sim: Node = host.combat.get_node("Simulation")
	var session: Node = host.combat.get_node("Session")
	var panel: Node = host.combat.get_node("Decisions")
	sim.set_physics_process(false)
	# Isolate warning -> panel -> payment feedback from the preceding live crowd sample.
	session.register_attackers = 1
	session.register_guards.clear()
	session.occupation = 2
	var last_guard := OS.get_cmdline_user_args().has("--last-guard")
	if last_guard:
		session.register_guards.assign(["守军"])
		session.occupation = 0
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var target_probe := OS.get_cmdline_user_args().has("--training-target")
	var training := target_probe or OS.get_cmdline_user_args().has("--train-probe")
	if training: session.incense = 20.0
	var cash: float = session.incense
	var row := {"passed":false,"fixture":"paused simulation updates, one reported attacker, no guard, 2 s occupation"}
	if last_guard:
		row.fixture = "one reported attacker and one remaining guard, no occupation, simulation stopped for UI check"
		root.get_texture().get_image().save_webp("/tmp/r22-last-guard.webp",false,0.88)
	if not panel.relief_button.is_visible_in_tree(): return row
	var sent := Time.get_ticks_usec()
	click(panel.relief_button)
	await RenderingServer.frame_post_draw
	row.warning_to_panel_ms = (Time.get_ticks_usec()-sent)/1000.0
	if not panel.register_relief or not root.get_node("Clock").paused: return row
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_webp("/tmp/r17-relief.webp",false,0.87)
	var buy: Button = panel.content.find_child("prepare_H22" if training else "buy_H22",true,false)
	if not is_instance_valid(buy) or buy.disabled or not panel.panel_scroll.get_global_rect().encloses(buy.get_global_rect()): return row
	sent = Time.get_ticks_usec()
	click(buy)
	row.paid = cash-session.incense
	await RenderingServer.frame_post_draw
	row.payment_to_feedback_ms = (Time.get_ticks_usec()-sent)/1000.0
	row.feedback = panel.feedback.text
	if training:
		row.fixture += ", 20 incense for 10 recruitment and 8 optional training"
		if row.paid!=10 or panel.current_panel!="upgrade" or not root.get_node("Clock").paused or panel.selected.unit_id!="H22": return row
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg("/tmp/r18-training.jpg",0.74)
		if target_probe:
			var recruit: Node = panel.selected
			var picker: OptionButton = panel.content.get_node("TrainingRoster/TrainingTarget")
			var index := (picker.selected+1) % picker.item_count
			if picker.item_count < 2: return row
			var target_id: String = picker.get_item_metadata(index)
			var other: Node = panel._find_unit(target_id)
			var recruit_hp: float = recruit.hp
			var other_level: int = other.upgrade_level
			other.hp = other.max_hp-9.0
			row.fixture += ", target starts nine HP below maximum for the UI check"
			var balance: float = session.incense
			click(picker)
			await RenderingServer.frame_post_draw
			var popup := picker.get_popup()
			row.menu_open = popup.visible
			if not popup.visible: return row
			popup.hide()
			await RenderingServer.frame_post_draw
			click(panel.buttons.next_guard)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			row.selected = panel.selected.instance_id
			row.prepaid = balance-session.incense
			if panel.selected != other or row.prepaid != 0: return row
			row.confirm_visible = panel.panel_scroll.get_global_rect().encloses(panel.buttons.upgrade_confirm.get_global_rect())
			if not row.confirm_visible: return row
			root.get_texture().get_image().save_webp("/tmp/r24-training-target.webp",false,0.88)
			var before_hp: float = other.hp
			sent = Time.get_ticks_usec()
			click(panel.buttons.upgrade_confirm)
			await RenderingServer.frame_post_draw
			row.confirm_to_frame_ms = (Time.get_ticks_usec()-sent)/1000.0
			row.training_paid = balance-session.incense
			row.hp_before = before_hp
			row.hp_after = other.hp
			row.max_after = other.max_hp
			row.hp_gain = other.hp-before_hp
			row.recruit_hp_change = recruit.hp-recruit_hp
			row.passed = row.training_paid==8 and row.hp_gain==15 and row.recruit_hp_change==0 and other.upgrade_level==other_level+1
			return row
		var hp: float = panel.selected.hp
		var balance: float = session.incense
		click(panel.buttons.upgrade_confirm)
		await RenderingServer.frame_post_draw
		row.training_paid = balance-session.incense
		row.hp_gain = panel.selected.hp-hp
		row.passed = row.training_paid==8 and row.hp_gain==15 and panel.selected.current_post=="post_register"
		return row
	row.passed = row.paid==10 and sim.humans.any(func(u):return u.unit_id=="H22" and u.current_post=="post_register") and "三戒" in row.feedback and not root.get_node("Clock").paused and session.pending_purchase.is_empty()
	return row

func probe_rear(host: Node, destination: String) -> Dictionary:
	var row := {"passed":false}
	var money: float = host.run.state.incense
	row.destination = destination
	for target in [destination,"post_register"]:
		var picker: OptionButton = host.panel.find_child("ReservePost",true,false)
		var selected := -1
		for index in range(1,picker.item_count):
			var move: Dictionary = picker.get_item_metadata(index)
			if move.id=="H21" and move.to==target: selected=index
		if selected<0: return row
		picker.item_selected.emit(selected)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not host.run.state.roster.any(func(u):return u.id=="H21" and u.post==target): return row
		if target==destination:
			host.continue_run()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			if not host.run.state.roster.any(func(u):return u.id=="H21" and u.post==target): return row
			var map_image := root.get_texture().get_image()
			if target=="post_table_hall":
				if map_image.save_webp("/tmp/r20-table.webp",false,0.84)!=OK: return row
			else:
				map_image.save_jpg("/tmp/r18-map.jpg",0.74)
	row.passed = money==host.run.state.incense
	return row

func probe_guard_gear(host: Node) -> Dictionary:
	var row := {"passed":false,"click_ms":[],"fixture":"ordinary 渡口 n10 H02, actual carried stock, paused equipment panel"}
	var packed := FileAccess.get_file_as_bytes("res://tools/faction_baseline/rear-final-map.json.gz")
	var save := FileAccess.open(host.save_path,FileAccess.WRITE)
	save.store_buffer(packed.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP))
	save.close()
	host.continue_run()
	host.choose_node("n10")
	var sim: Node = host.combat.get_node("Simulation")
	sim.set_physics_process(false)
	var session: Node = host.combat.get_node("Session")
	var decisions: Node = host.combat.get_node("Decisions")
	var guard: Node = sim.humans[0]
	decisions.select_unit(guard)
	decisions.open_growth()
	var panel: Node = decisions.growth_panel
	var balance: float = session.incense
	for id in ["I08","Y11"]:
		for button_id in ["inspect_register_item","equip_item"]:
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var button: Button = panel.buttons.get(button_id)
			if not is_instance_valid(button) or button.disabled or not panel.scroll.get_global_rect().encloses(button.get_global_rect()):
				row.blocked = {"button":button_id,"panel":decisions.current_panel,"objective":session.growth.state.get("defense_objective",""),"stock":session.growth.state.inventory,"keys":panel.buttons.keys(),"clip":str(panel.scroll.get_global_rect()),"rect":str(button.get_global_rect()) if is_instance_valid(button) else ""}
				return row
			var sent := Time.get_ticks_usec()
			click(button)
			await RenderingServer.frame_post_draw
			row.click_ms.append((Time.get_ticks_usec()-sent)/1000.0)
			if button_id == "inspect_register_item" and (panel.selected_item!=id or session.growth.has(guard,id) or session.growth.state.inventory[id]!=1): return row
			if button_id == "equip_item" and (not session.growth.has(guard,id) or session.growth.state.inventory[id]!=0 or not panel.buttons.equip_item.disabled or not panel.selected_item.is_empty()): return row
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg("/tmp/r19-equipment.jpg",0.82)
	row.slots = guard.growth.slots.duplicate(true)
	row.paid = balance-session.incense
	var armed: bool = guard.unit_id=="H02" and row.paid==0 and root.get_node("Clock").paused and panel.content.find_children("*","Label",true,false).any(func(label):return "已就绪" in label.text)
	if not armed: return row
	decisions.close_panel()
	root.get_node("Clock").set_paused(false)
	var camera: Node = host.combat.get_node("BattleCamera")
	camera.make_current()
	camera.set_left(guard.position.x-960)
	for tick in 2400:
		sim.advance(1.0/60)
		for field in session.growth.state.fields:
			if field.kind!="paper_brace" or field.left>0.44: continue
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var shot := root.get_texture().get_image()
			row.effect_at = sim.simulation_time
			var stamp: Node2D = sim.vfx.get_node("TalismanSeal")
			var point := Vector2(field.point[0],field.point[1]-112)
			var center := Vector2i(stamp.get_global_transform_with_canvas()*point)
			var area := Rect2i(center-Vector2i(90,50),Vector2i(180,100)).intersection(Rect2i(Vector2i.ZERO,shot.get_size()))
			stamp.hide()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var control := root.get_texture().get_image()
			var changed := 0
			for y in range(area.position.y,area.end.y):
				for x in range(area.position.x,area.end.x):
					if shot.get_pixel(x,y)!=control.get_pixel(x,y): changed+=1
			stamp.show()
			row.stamp_changed_pixels = changed
			row.passed = changed>=80 and shot.get_size()==Vector2i(1920,1080) and shot.save_jpg("/tmp/r19-paper.jpg",0.84)==OK
			return row
		if not session.running: break
	return row

func probe_range(battle: Node) -> Dictionary:
	var sim: Node = battle.get_node("Simulation")
	var panel: Node = battle.get_node("Decisions")
	var camera: Node = battle.get_node("BattleCamera")
	var session: Node = battle.get_node("Session")
	var row := {"passed":false}
	var readers: Array = sim.humans.filter(func(u):return u.unit_id=="H21" and not u.dead)
	if readers.is_empty(): return row
	var reader: Node = readers[0]
	sim.set_physics_process(false)
	camera.set_left(reader.position.x-960)
	panel.select_unit(reader)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var cash: float = session.incense
	var sent := Time.get_ticks_usec()
	click(panel.buttons.card_ritual)
	await RenderingServer.frame_post_draw
	row.click_ms = (Time.get_ticks_usec()-sent)/1000.0
	if panel.current_panel!="ritual": return row
	row.bare_conditions = panel.content.get_node("RitualConditions").text
	var inventory_before: int = session.growth.state.inventory.get("I17",0)
	var equipped: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":reader.instance_id,"item_id":"I17","slot_index":0},"player")
	if not equipped.ok: return row
	panel.open_ritual()
	row.needle_conditions = panel.content.get_node("RitualConditions").text
	row.needle_used = inventory_before-int(session.growth.state.inventory.get("I17",0))
	row.hint = panel.target_hint.text
	row.cost = cash-session.incense
	row.targets = panel.legal_ritual_targets.size()
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var reach := float(session.rules.ritual.range_body)*float(root.get_node("Rules").BODY_PX)
	var point: Vector2 = reader.position+Vector2(-reach,-8)
	var center := Vector2i(panel.highlights.get_global_transform_with_canvas()*point)
	panel.highlights.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var control := root.get_texture().get_image()
	var changed := 0
	var area := Rect2i(center-Vector2i(3,11),Vector2i(8,18)).intersection(Rect2i(Vector2i.ZERO,shot.get_size()))
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			if shot.get_pixel(x,y)!=control.get_pixel(x,y): changed+=1
	panel.highlights.show()
	row.endpoint_pixels = changed
	row.passed = "受击或离位" in row.bare_conditions and "30%" in row.needle_conditions and row.needle_used==1 and row.targets==0 and row.cost==0 and "身位" in row.hint and panel.buttons.ritual_confirm.disabled and changed>=10 and shot.save_webp("/tmp/r20-range.webp",false,0.84)==OK
	return row


func probe_repair(battle: Node) -> Dictionary:
	var sim: Node = battle.get_node("Simulation")
	var session: Node = battle.get_node("Session")
	var panel: Node = battle.get_node("Decisions")
	sim.set_physics_process(false)
	var door: Node2D = sim.world.get_node("door_inner")
	door.set_durability(door.max_durability-300)
	var row := {"passed":false,"fixture":"post-crowd UI check: damaged inner door, added H09 with J01, wallet set to discounted price"}
	var worker: Node2D = sim.spawn_human("H09","post_gate_inner")
	if worker == null: return row
	root.get_node("Clock").set_paused(true)
	worker.growth.job_tags.assign(["J01"])
	for item in ["I10","Y09"]:
		session.growth.state.inventory[item] = 1
		var equipped: Dictionary = session.execute_for("shouxiang","equip_item",{"unit_id":worker.instance_id,"item_id":item,"slot_index":0},"player")
		if not equipped.ok: return row
	row.fixture += ", equipped I10 and Y09 from fixture inventory"
	session.incense = session.growth.repair_cost(worker,session.rules.repair.cost)
	var offer: Dictionary = session.preview_repair("door_inner")
	if not offer.ok:
		row.reason = offer.reason
		return row
	var cash: float = session.incense
	panel.open_repair()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var button: Button = panel.buttons.repair_door_inner
	row.caption = button.text
	row.worker = offer.unit.unit_id
	row.quote = offer.cost
	row.heal = offer.heal
	row.duration = offer.duration
	row.prepaid = cash-session.incense
	row.visible = panel.panel_scroll.get_global_rect().encloses(button.get_global_rect())
	if button.disabled or not row.visible: return row
	root.get_texture().get_image().save_webp("/tmp/r25-repair.webp",false,0.85)
	var sent := Time.get_ticks_usec()
	click(button)
	await RenderingServer.frame_post_draw
	row.feedback_ms = (Time.get_ticks_usec()-sent)/1000.0
	row.paid = cash-session.incense
	row.passed = row.prepaid==0 and row.quote<6 and row.paid==row.quote and session.repair_jobs.size()==1 and session.repair_jobs[0].unit==offer.unit and panel.buttons.repair_door_inner.disabled and is_equal_approx(row.heal,210) and row.duration==2.25 and session.repair_jobs[0].duration==row.duration and is_equal_approx(session.repair_jobs[0].heal,row.heal)
	return row

func probe_post_cover(host: Node) -> Dictionary:
	var row := {"passed":false,"labels":[]}
	var source := OS.get_environment("YE_CI_POST_MAP")
	if source.is_empty() or DirAccess.copy_absolute(source,host.save_path) != OK: return row
	host.continue_run()
	if OS.get_cmdline_user_args().has("--boss-brief"):
		var terminal: Button = host.panel.buttons.node_n10
		terminal.grab_focus()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		row.brief = host.panel._node_note.text
		if not host.panel._boss_portrait.is_visible_in_tree() or host.panel._boss_portrait.texture == null or not ("6%" in row.brief and "力士尸" in row.brief and "4" in row.brief): return row
		root.get_texture().get_image().save_webp("/tmp/r27-brief.webp",true,0.87)
	var cash: float = host.run.state.incense
	for target in ["post_rear","post_register"]:
		await RenderingServer.frame_post_draw
		var picker: OptionButton = host.panel.find_child("ReservePost",true,false)
		if not is_instance_valid(picker):
			row.failure = "missing picker"
			return row
		if not root.get_visible_rect().encloses(picker.get_global_rect()):
			row.failure = str(picker.get_global_rect())
			return row
		var index := -1
		for i in range(1,picker.item_count):
			var move: Dictionary = picker.get_item_metadata(i)
			if move.id == "H01" and move.to == target: index = i
		if index < 0:
			row.failure = "missing option " + target
			return row
		var caption := picker.get_item_text(index)
		var hp_pair: Dictionary = host.run.state.roster.filter(func(u): return u.uid==picker.get_item_metadata(index).uid)[0]
		if picker.get_item_icon(index)==null or ("%.0f/%.0f" % [hp_pair.hp,hp_pair.max_hp]) not in caption: return row
		row.labels.append(caption)
		var origin := picker.get_item_tooltip(index)
		if ("到岗后 1/3 人" if target=="post_rear" else "到岗后 2/3 人") not in origin: return row
		row.get_or_add("tooltips",[]).append(origin)
		if ("祝禧" if target=="post_rear" else "无人驻守") not in origin: return row
		if ("独守" if target=="post_rear" else "与祝禧合守") not in caption: return row
		picker.show_popup()
		await RenderingServer.frame_post_draw
		if not is_instance_valid(picker) or not picker.get_popup().visible:
			row.failure = "popup closed"
			return row
		if target == "post_register":
			root.get_texture().get_image().save_webp("/tmp/r26-post.webp",true,0.85)
		var popup := picker.get_popup()
		popup.set_focused_item(index)
		var sent := Time.get_ticks_usec()
		var first_frame_ms := 0.0
		for down in [true,false]:
			var key := InputEventKey.new()
			key.keycode = KEY_ENTER
			key.physical_keycode = KEY_ENTER
			key.pressed = down
			Input.parse_input_event(key)
			await RenderingServer.frame_post_draw
			if first_frame_ms == 0 and host.run.state.roster.any(func(u): return u.id=="H01" and u.post==target):
				first_frame_ms = (Time.get_ticks_usec()-sent)/1000.0
		if first_frame_ms == 0:
			await RenderingServer.frame_post_draw
			if not host.run.state.roster.any(func(u): return u.id=="H01" and u.post==target): return row
			first_frame_ms = (Time.get_ticks_usec()-sent)/1000.0
		row.get_or_add("enter_to_post_frame_ms",[]).append(first_frame_ms)
		host.continue_run()
		if not host.run.state.roster.any(func(unit): return unit.id=="H01" and unit.post==target): return row
	row.passed = is_equal_approx(cash,host.run.state.incense)
	return row

func probe_camp_health(host: Node) -> Dictionary:
	var row := {"passed":false,"forecasts":[]}
	var source := OS.get_environment("YE_CI_CAMP_MAP")
	if source.is_empty() or DirAccess.copy_absolute(source,host.save_path) != OK: return row
	host.continue_run()
	await RenderingServer.frame_post_draw
	var rows: Node = host.panel.find_child("RestHealthForecast",true,false)
	if rows == null or rows.get_child_count()!=host.run.state.roster.size(): return row
	var expected := {}
	var selected_care: Button
	var cash: float = host.run.state.incense
	var names: float = host.run.state.names
	for i in rows.get_child_count():
		var line: Node = rows.get_child(i)
		var unit: Dictionary = host.run.state.roster[i]
		var after: float = host.run.rest_health_after(unit)
		if line.get_child(0).texture == null or ("%.2f → %.2f" % [unit.hp,after]) not in line.get_child(1).text: return row
		row.forecasts.append(line.get_child(1).text)
		expected[unit.uid] = unit.hp
		if unit.id=="H01" and line.get_child_count()==3:
			selected_care = line.get_child(2)
			expected[unit.uid] = host.run.treatment_health_after(unit)
	if selected_care==null or selected_care.disabled: return row
	var button: Button = selected_care
	if not button.is_visible_in_tree() or not root.get_visible_rect().encloses(button.get_global_rect()): return row
	root.get_texture().get_image().save_webp("/tmp/r30-rest.webp",false,0.86)
	var start := Time.get_ticks_usec()
	click(button)
	await RenderingServer.frame_post_draw
	row.click_to_map_ms = (Time.get_ticks_usec()-start)/1000.0
	if host.run.state.phase!="map": return row
	host.continue_run()
	row.balance_after = host.run.state.incense
	row.paid = cash-host.run.state.incense
	row.passed = row.paid==4 and host.run.state.names==names and host.run.state.phase=="map" and expected.size()==host.run.state.roster.size() and host.run.state.roster.all(func(u):return expected.has(u.uid) and is_equal_approx(u.hp,expected[u.uid]))
	return row

func probe_last_camp(host: Node) -> Dictionary:
	var receipt := {"passed":false}
	if DirAccess.copy_absolute(OS.get_environment("YE_CI_LAST_CAMP_SAVE"),host.save_path) != OK: return receipt
	host.continue_run()
	await RenderingServer.frame_post_draw
	var button: Button = host.panel.buttons.get("reserve_H02")
	if not is_instance_valid(button) or button.disabled or host.run.state.roster.size()!=2: return receipt
	var bounds := button.get_global_rect()
	if not root.get_visible_rect().encloses(bounds): return receipt
	var cash: float = host.run.state.incense
	var names: float = host.run.state.names
	var hp := {}
	for unit in host.run.state.roster: hp[unit.uid] = unit.hp
	root.get_texture().get_image().save_jpg("/tmp/ye31-last-camp.jpg",0.82)
	var start := Time.get_ticks_usec()
	click(button)
	await RenderingServer.frame_post_draw
	receipt.click_to_map_ms = (Time.get_ticks_usec()-start)/1000.0
	host.continue_run()
	receipt.paid = cash-host.run.state.incense
	receipt.passed = host.run.state.phase=="map" and receipt.paid==12 and host.run.state.names==names and host.run.state.roster.size()==3 and host.run.state.roster.all(func(u): return (hp.has(u.uid) and u.hp==hp[u.uid]) or (not hp.has(u.uid) and u.id=="H02"))
	return receipt

func probe_swap(host: Node) -> Dictionary:
	var row := {"passed":false}
	var original: Array = host.run.state.roster.duplicate(true)
	if host.run.martial_swap_pair().size()!=2: return row
	var cash: float = host.run.state.incense
	if host.run.swap_martial_posts(original[1].uid,original[0].uid).ok: return row
	var button: Button = host.panel.buttons.get("swap_martial")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(button) or not root.get_visible_rect().encloses(button.get_global_rect()): return row
	row.preview = button.tooltip_text
	root.get_texture().get_image().save_webp("/tmp/ye35-map.webp",false,0.84)
	var sent := Time.get_ticks_usec()
	click(button)
	await RenderingServer.frame_post_draw
	row.click_to_map_ms = (Time.get_ticks_usec()-sent)/1000.0
	row.before = original
	row.clicked = host.run.state.roster.duplicate(true)
	host.continue_run()
	row.resumed = host.run.state.roster.duplicate(true)
	row.paid = cash-host.run.state.incense
	for i in 2:
		var actual: Dictionary = host.run.state.roster[i].duplicate(true)
		if actual.post != original[1-i].post: return row
		actual.post = original[i].post
		if actual!=JSON.parse_string(JSON.stringify(original[i])): return row
	row.passed = row.paid==0
	return row

func probe_stones(host: Node) -> Dictionary:
	var row := {"passed":false}
	host.start_p10_night("shouxiang","example","渡口","R01",[],"武卫司")
	host.choose_node("n01")
	var sim: Node = host.combat.get_node("Simulation")
	var camera: Node = host.combat.get_node("BattleCamera")
	var stone: Node2D = sim.humans.filter(func(u): return u.unit_id=="H11")[0]
	sim.set_physics_process(false)
	for tick in 1080: sim.advance(1.0/60.0)
	camera.make_current()
	camera.set_left(stone.position.x-960)
	stone.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var center := Vector2i(stone.get_global_transform_with_canvas().origin)
	var area := Rect2i(center-Vector2i(42,16),Vector2i(84,22)).intersection(Rect2i(Vector2i.ZERO,shot.get_size()))
	row.held = stone.roster.counters.stationary_seconds
	row.bonus = sim.roster_engine().humans.rooted_defense_bonus(stone)
	stone.roster.counters.stationary_seconds = 0.0
	stone.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var control := root.get_texture().get_image()
	stone.roster.counters.stationary_seconds = row.held
	stone.queue_redraw()
	var changed := 0
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			if shot.get_pixel(x,y)!=control.get_pixel(x,y): changed+=1
	row.changed_pixels = changed
	var panel: Node = host.combat.get_node("Decisions")
	panel.select_unit(stone)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	row.card = panel._martial_trait_readout().strip_edges()
	var card_ok: bool = "+5.0 / 5" in row.card and row.card in panel.details.text
	if card_ok: root.get_texture().get_image().save_webp("/tmp/ye35-card.webp",true,0.83)
	# A frozen proximity fixture checks the card against combat's actual multipliers.
	var blade: Node2D = sim.humans.filter(func(u): return u.unit_id=="H10")[0]
	var enemy: Node2D = sim.tide.spawn("G01",0,blade.position.x)
	var other: Node2D = sim.tide.spawn("G01",1,blade.position.x)
	stone.floor_id = blade.floor_id
	stone.position = blade.position
	for ghost in [enemy,other]:
		ghost.floor_id = blade.floor_id
		ghost.position = blade.position
	panel.select_unit(blade)
	var roster: RefCounted = sim.roster_engine()
	row.crowded_card = panel._martial_trait_readout().strip_edges()
	row.dealt_scale = roster.humans.damage_multiplier(blade,enemy,"melee")
	row.received_scale = roster.humans.before_receive(blade,10.0,enemy,"melee")/10.0
	var crowded_ok: bool = "有同伴" in row.crowded_card and "受击 ×1.2" in row.crowded_card and row.dealt_scale==1.0 and is_equal_approx(row.received_scale,1.2)
	row.passed = row.bonus==5 and changed>=60 and card_ok and crowded_ok and shot.save_webp("/tmp/ye35-stones.webp",true,0.84)==OK
	return row

func probe_iron(host: Node, patrol := false) -> Dictionary:
	var row := {"passed":false}
	var recruit := "H12" if patrol else "H09"
	if patrol:
		if DirAccess.copy_absolute(OS.get_environment("YE_CI_PATROL_MAP"),host.save_path)!=OK: return row
		host.continue_run()
		host.choose_node("n05")
	else:
		host.start_p10_night("shouxiang","example","渡口","R01",[],"武卫司")
		host.choose_node("n01")
	var panel: Node = host.combat.get_node("Decisions")
	var sim: Node = host.combat.get_node("Simulation")
	sim.set_physics_process(false)
	var session: Node = host.combat.get_node("Session")
	var cash: float = session.incense
	for confirm in [false,true]:
		panel.open_purchase()
		if patrol and not panel.recruitable_faction_only: return row
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var buy: Button = panel.buttons.get("buy_"+recruit)
		if not is_instance_valid(buy) or buy.disabled: return row
		click(buy)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var hint: Label = panel.content.find_child("IronDeployment",true,false)
		if not is_instance_valid(hint): return row
		row.preview = hint.text
		row.visible = panel.panel_scroll.get_global_rect().encloses(hint.get_global_rect())
		row.reserved = cash-session.incense
		if not row.visible or row.reserved!=12: return row
		if patrol:
			if "巡夜" not in hint.text or "余1岗" not in hint.text: return row
		elif "断刃 75/75" not in hint.text or "石婆 95/95" not in hint.text or hint.text.count("余2岗")!=2: return row
		if confirm:
			root.get_texture().get_image().save_webp("/tmp/ye36-patrol.webp" if patrol else "/tmp/ye36-iron.webp",true,0.78)
		var start := Time.get_ticks_usec()
		click(panel.buttons.defend_register if confirm else panel.buttons.close)
		await RenderingServer.frame_post_draw
		if confirm: row.click_to_frame_ms = (Time.get_ticks_usec()-start)/1000.0
		elif session.incense!=cash or not session.pending_purchase.is_empty(): return row
	row.paid = cash-session.incense
	row.remaining_slots = session.post_vacancies("post_register")
	row.duplicate_reason = session.purchase(recruit).reason
	row.passed = row.paid==12 and row.remaining_slots==(0 if patrol else 1) and row.duplicate_reason=="P4_NAMED_PRESENT" and sim.humans.any(func(u):return u.unit_id==recruit and u.current_post=="post_register")
	return row

func probe_final_map(host: Node) -> Dictionary:
	var row := {"passed":false,"click_ms":[]}
	var source := OS.get_environment("YE_CI_FINAL_MAP_SAVE")
	if DirAccess.copy_absolute(source,host.save_path)!=OK: return row
	host.continue_run()
	var initial: Array = host.run.state.roster.duplicate(true)
	var stone: Array = initial.filter(func(u): return u.id=="H11" and u.post=="post_hall_door")
	if stone.size()!=1: return row
	var cash: float = host.run.state.incense
	var goods: Dictionary = host.run.state.growth.inventory.duplicate(true)
	for dest in ["post_register","post_hall_door"]:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var button: Button = host.panel.buttons.get("redeploy_"+str(stone[0].uid))
		if not is_instance_valid(button) or not root.get_visible_rect().encloses(button.get_global_rect()): return row
		if dest=="post_register":
			row.preview = host.panel._node_note.text
			if "6%" not in row.preview: return row
			root.get_texture().get_image().save_webp("/tmp/ye37-boss.webp",false,0.84)
		var start := Time.get_ticks_usec()
		click(button)
		await RenderingServer.frame_post_draw
		row.click_ms.append((Time.get_ticks_usec()-start)/1000.0)
		host.continue_run()
		var expected := initial.duplicate(true)
		for u in expected:
			if u.uid==stone[0].uid: u.post=dest
		if host.run.state.roster!=expected or host.run.state.incense!=cash or host.run.state.growth.inventory!=goods: return row
		if dest=="post_register" and not host.run.state.roster.all(func(u): return u.post=="post_register"): return row
	row.restored = true
	var camp := OS.get_environment("YE_CI_FINAL_CAMP_SAVE")
	if DirAccess.copy_absolute(camp,host.save_path)!=OK: return row
	host.continue_run()
	if not host.run.brace_hall_at_rest().ok or not host.run.save(host.save_path).ok: return row
	host.continue_run()
	await RenderingServer.frame_post_draw
	row.braced = host.panel._node_note.text
	if "339/650" not in row.braced: return row
	host.choose_node("n10")
	if not is_instance_valid(host.combat): return row
	row.actual_gate = host.combat.get_node("Simulation").world.get_node("door_hall").durability
	if row.actual_gate!=339 or DirAccess.copy_absolute(source,host.save_path)!=OK: return row
	host.continue_run()
	if not host.run.reserve_post(stone[0].uid,"post_register").ok: return row
	host.choose_node("n10")
	var sim: Node = host.combat.get_node("Simulation")
	var session: Node = host.combat.get_node("Session")
	sim.set_physics_process(false)
	var wearer: Node = sim.humans.filter(func(u): return u.unit_id=="H11")[0]
	root.get_node("Clock").set_paused(true)
	for item in ["I08","Y11"]:
		if not session.execute_for("shouxiang","equip_item",{"unit_id":wearer.instance_id,"item_id":item,"slot_index":0},"player").ok: return row
	root.get_node("Clock").set_paused(false)
	var camera: Node = host.combat.get_node("BattleCamera")
	camera.set_left(wearer.position.x-root.size.x/2.0)
	for tick in 3600:
		sim.advance(1.0/60.0)
		for field in session.growth.state.fields:
			if field.kind!="paper_brace" or field.left>0.53: continue
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			if not root.get_visible_rect().has_point(wearer.get_global_transform_with_canvas().origin) or field.end==[0,0]: return row
			row.paper = {"seconds":sim.simulation_time,"wearer":wearer.unit_id,"point":field.point,"attacker":field.end,"left":field.left,"hp":wearer.hp}
			root.get_texture().get_image().save_webp("/tmp/ye37-impact.webp",true,0.81)
			var decisions: Node = host.combat.get_node("Decisions")
			decisions._update_warnings()
			row.warnings = decisions.warnings.text
			row.passed = not wearer.dead and "守香司已倒下" not in row.warnings and "守册将领已尽" not in row.warnings
			return row
		if not session.running: break
	return row
