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
	shell.faction_picker.select(3)
	shell.faction_picker.item_selected.emit(3)
	shell.seed_input.text = "渡口"
	shell.title_buttons.shouxiang.pressed.emit()
	var rear := {}
	if OS.get_cmdline_user_args().has("--rear-probe"):
		rear = await probe_rear(host)
	host.choose_node("n01")
	var battle: Node = host.combat
	var sim: Node = battle.get_node("Simulation")
	var camera: Node = battle.get_node("BattleCamera")
	var decisions: Node = battle.get_node("Decisions")
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
	var recruit := "H19" if lamp_probe else "H22"
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
	if OS.get_cmdline_user_args().has("--relief-probe") or OS.get_cmdline_user_args().has("--train-probe"):
		result.relief = await probe_relief(host)
		passed = passed and result.relief.passed
		result.passed = passed
		filename = "native-train.json" if OS.get_cmdline_user_args().has("--train-probe") else "native-relief.json"
	if OS.get_cmdline_user_args().has("--guard-gear"):
		result.guard_gear = await probe_guard_gear(host)
		passed = passed and result.guard_gear.passed
		result.passed = passed
		filename = "native-guard-gear.json"
	if not rear.is_empty():
		result.rear = rear
		passed = passed and rear.passed
		result.passed = passed
		filename = "native-rear.json"
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
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var training := OS.get_cmdline_user_args().has("--train-probe")
	if training: session.incense = 20.0
	var cash: float = session.incense
	var row := {"passed":false,"fixture":"paused simulation updates, one reported attacker, no guard, 2 s occupation"}
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

func probe_rear(host: Node) -> Dictionary:
	var row := {"passed":false}
	var money: float = host.run.state.incense
	for target in ["post_rear","post_register"]:
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
		if target=="post_rear":
			host.continue_run()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			if not host.run.state.roster.any(func(u):return u.id=="H21" and u.post==target): return row
			root.get_texture().get_image().save_jpg("/tmp/r18-map.jpg",0.74)
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
