extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1920,1080)
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.title_shell_enabled = true
	host.save_path = "user://family-frames-%d.json" % OS.get_process_id()
	root.add_child(host)
	var shell: Node = host.shell
	shell.title_buttons.start.pressed.emit()
	var paper := "--paper" in OS.get_cmdline_user_args()
	var bow := "--bow" in OS.get_cmdline_user_args()
	var window := bow or paper or "--window" in OS.get_cmdline_user_args()
	var family := 1 if window else 3
	shell.family_picker.select(family)
	shell.family_picker.item_selected.emit(family)
	await RenderingServer.frame_post_draw
	var portrait_ok: bool = shell.family_portrait.texture != null and shell.family_note.text.contains("白衣" if window else "山魅") and shell.family_portrait.is_visible_in_tree()
	if not window: root.get_texture().get_image().save_webp("res://docs/optimization/mountain-opening.webp",true,0.80)
	shell.seed_input.text = "渡口"
	shell.title_buttons.duoming.pressed.emit()
	host.choose_node("n01")
	var sim: Node = host.combat.get_node("Simulation")
	var panel: Node = host.combat.get_node("Decisions")
	var camera: Node = host.combat.get_node("BattleCamera")
	if paper:
		sim.set_physics_process(false)
		if not sim.session.reinforce("window").ok:
			quit(2)
			return
		for tick in 1820: sim.advance(1.0/60.0)
		camera.set_left(sim.session.paper_armor_targets()[0].position.x-600)
		sim.set_physics_process(true)
	for column in 11:
		for lane in 4: sim.tide.spawn("G01" if window else "G17",lane,camera.left()+55+column*105+lane*10)
	for warmup in 30: await RenderingServer.frame_post_draw
	var samples := []
	var low := 999
	var high := 0
	var before := Time.get_ticks_usec()
	for i in 180:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		samples.append((now-before)/1000.0)
		before = now
		var count := 0
		for g in sim.targets:
			if not g.dead and root.get_visible_rect().has_point(g.get_global_transform_with_canvas().origin): count += 1
		low = mini(low,count)
		high = maxi(high,count)
	panel.open_reinforce()
	await RenderingServer.frame_post_draw
	if window and not paper and not bow: root.get_texture().get_image().save_webp("res://docs/optimization/window-supply.webp",true,0.80)
	var button: Button = panel.buttons.window_reinforce if window else panel.buttons.reinforce
	var scouts: Array = []
	if paper:
		button = panel.buttons.window_paper
		scouts = sim.session.paper_armor_targets()
		if scouts.is_empty() or button.disabled:
			quit(3)
			return
		camera.set_left(scouts[0].position.x-800)
	if bow:
		var focus: OptionButton = panel.find_child("WindowFocus",true,false)
		focus.select(1)
	var rect := button.get_global_rect()
	var session: Node = sim.session
	var cash: float = session.incense
	var started := Time.get_ticks_usec()
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = rect.get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,true)
	await RenderingServer.frame_post_draw
	var ms := (Time.get_ticks_usec()-started)/1000.0
	var paid: float = cash-session.incense
	var queued: Array = sim.tide.pending.duplicate()
	var ordered := samples.duplicate()
	ordered.sort()
	var ok: bool = portrait_ok and low >= 30 and is_equal_approx(cash-session.incense,10) and session.reinforce_count == (2 if paper else 1)
	if paper:
		ok = ok and scouts.all(func(u):return u.roster.get("window_paper")=="ready") and panel.feedback.text.contains("已披纸甲")
		root.get_texture().get_image().save_webp("res://docs/optimization/window-paper.webp",true,0.80)
	else:
		ok = ok and (sim.tide.pending.slice(-4)==["G07","G07","G07","G07"] if window else sim.tide.pending.slice(-2)==["G17","G17"])
	if bow:
		ok = ok and session.roster.state.get("window_focus")=="window_bow" and panel.feedback.text.contains("先打弩手")
		root.get_texture().get_image().save_webp("res://docs/optimization/window-focus.webp",true,0.80)
	if window and not paper and not bow: ok = ok and panel.feedback.text.contains("4只童亡")
	var broken := ""
	if paper:
		panel.close_panel()
		sim.set_physics_process(false)
		for tick in 3600:
			sim.advance(1.0/60.0)
			if sim.session.roster.state.get("window_bolts_blocked",0)>0:
				for scout in scouts:
					if is_instance_valid(scout) and scout.roster.get("window_paper")=="spent":
						broken = scout.instance_id
						camera.set_left(scout.position.x-900)
						break
				break
		ok = ok and not broken.is_empty()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_webp("res://docs/optimization/window-paper-break.webp",true,0.80)
	var result := {"passed":ok,"portrait":portrait_ok,"resolution":[1920,1080],"visible":[low,high],"frame_ms":samples,"frame_percentiles":[ordered[89],ordered[170],ordered[178]],"click_feedback_ms":ms,"feedback":panel.feedback.text,"renderer":RenderingServer.get_video_adapter_name(),"paid":paid,"queued":queued}
	if paper: result.first_broken = broken
	FileAccess.open("res://tools/faction_baseline/native-%s.json" % ("bow" if bow else ("paper" if paper else ("window" if window else "family"))),FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("NATIVE ",ok," ",result.frame_percentiles," ",ms)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(0.4).timeout
	quit(0 if ok else 1)
