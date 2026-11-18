extends SceneTree
## Native keyboard/mouse and real-time performance on an isolated copy of the game.
var output: String
var host: Node
var clock: Node
var rows: Array = []
var samples: Array = []

func _initialize() -> void:
	run.call_deferred()

func frames(count := 2) -> void:
	for i in count: await process_frame

func check(ok: bool, description: String) -> bool:
	rows.append({"passed":ok,"check":description})
	print(("PASS " if ok else "FAIL ") + description)
	return ok

func click(button: Control) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await frames()

func tap(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		root.push_input(event,true)
		await frames(1)

func run() -> void:
	await frames()
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): quit(2); return
	output = args[0]
	if not check(root.get_node("Data").codex_store.path == output+"/state/codex.json" and DisplayServer.get_name() != "headless" and not "--fixed-fps" in OS.get_cmdline_args(),"Isolated native window with wall-clock timing"):
		quit(2);return
	clock = root.get_node("Clock")
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames(14)
	host = current_scene
	root.size = Vector2i(1920,1080)
	await frames(6)
	await click(host.shell.title_buttons.start)
	await click(host.shell.title_buttons.shouxiang)
	if not check(host.run != null and host.run.state.get("kind") == "example","Default title enters example night"): finish();return
	await click(host.panel.buttons["node_"+str(host.run.available_nodes()[0].id)])
	var guide: Control = host.combat.get_node_or_null("CanvasLayer/ExampleTutorial")
	if not check(guide != null and guide.visible,"First battle shows decision tutorial"): finish();return
	RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(output+"/tutorial.png")
	await click(guide.next)
	await tap(KEY_ESCAPE)
	await click(host.shell.pause_buttons.exit)
	await click(host.shell.title_buttons.continue_run)
	guide = host.combat.get_node_or_null("CanvasLayer/ExampleTutorial")
	if not check(guide != null and guide.visible and guide.title.text.contains("购入"),"Save and continue retains current topic"): finish();return
	for word in ["购入","掩体","点册","失败线"]:
		check(guide.title.text.contains(word) and not guide.body.text.begins_with("P11_"),"Readable guard tutorial: "+word)
		await click(guide.next)
	check(not guide.visible,"Last topic dismisses the lesson")
	host.start_p10_night("duoming","example","113","R01",[])
	await click(host.panel.buttons["node_"+str(host.run.available_nodes()[0].id)])
	guide = host.combat.get_node_or_null("CanvasLayer/ExampleTutorial")
	if not check(guide != null,"Seize example has faction-specific guidance"): finish();return
	await click(guide.next)
	await click(guide.next)
	check(guide.body.text.contains("潮源"),"Seize describes actual source entry")
	await click(guide.skip)
	check(not guide.visible,"Skip immediately returns to battle")
	host.start_p10_night("shouxiang","fierce","114","R01",[])
	await click(host.panel.buttons["node_"+str(host.run.available_nodes()[0].id)])
	check(not host.combat.has_node("CanvasLayer/ExampleTutorial"),"Fierce night has no tutorial")
	for count in [40,80,150]:
		if not await measure(count): break
	finish()

func visible_count(sim: Node, camera: Camera2D) -> int:
	var count := 0
	for unit in sim.humans + sim.targets:
		if not unit.dead and unit.position.x >= camera.left() and unit.position.x < camera.left()+1920:
			count += 1
	return count

func measure(count: int) -> bool:
	host.start_p10_night("shouxiang","example","114","R01",[])
	await click(host.panel.buttons["node_"+str(host.run.available_nodes()[0].id)])
	var combat: Node = host.combat
	var guide: Control = combat.get_node("CanvasLayer/ExampleTutorial")
	await click(guide.skip)
	var sim: Node = combat.get_node("Simulation")
	var camera: Camera2D = combat.get_node("BattleCamera")
	clock.set_paused(true)
	# Keep the live example encounter, real AI and skills. Replace the opening
	# source queue with a reproducible on-screen crowd for each measurement.
	sim.clear_targets()
	sim.tide.pending.clear()
	sim.tide.wave_index = sim.tide.config.waves.size()
	sim.tide.config.capacity = 150
	var needed := count - visible_count(sim,camera)
	for n in needed:
		var x: float = camera.left()+220.0+float(n/4)*minf(85,890.0/maxf(1,(needed-1)/4.0))
		if sim.tide.spawn(["G01","G09","G12","G01"][n%4],n%4,x)==null:
			check(false,"Spawn full on-screen crowd")
			return false
	var start_visible := visible_count(sim,camera)
	check(start_visible == count,"Start with %d live on-screen units" % count)
	clock.set_paused(false)
	var start_sim: float = sim.simulation_time
	var start := Time.get_ticks_usec()
	var previous := start
	var times: Array[float] = []
	var min_visible := start_visible
	while Time.get_ticks_usec()-start < 8000000:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now-previous)/1000.0)
		previous = now
		min_visible = mini(min_visible,visible_count(sim,camera))
	var seconds := (previous-start)/1000000.0
	var sim_seconds: float = sim.simulation_time-start_sim
	var latency_start := Time.get_ticks_usec()
	await tap(KEY_SPACE)
	var keyboard_ms := (Time.get_ticks_usec()-latency_start)/1000.0
	var paused_time: float = sim.simulation_time
	await frames(3)
	check(clock.paused and is_equal_approx(sim.simulation_time,paused_time),"Space pauses live simulation at %d" % count)
	var hud: Node = combat.get_node("CanvasLayer/HUD")
	latency_start = Time.get_ticks_usec()
	await click(hud.buttons.pause)
	var mouse_ms := (Time.get_ticks_usec()-latency_start)/1000.0
	await physics_frame
	await frames(3)
	check(not clock.paused and sim.simulation_time > paused_time,"HUD mouse click resumes simulation at %d" % count)
	times.sort()
	samples.append({"target":count,"initial_visible":start_visible,"minimum_visible":min_visible,"frames":times.size(),"elapsed_sec":seconds,"simulated_sec":sim_seconds,"fps":times.size()/seconds,"p95_frame_ms":times[ceili(0.95*times.size())-1],"max_frame_ms":times.back(),"pause_key_press_release_ms":keyboard_ms,"resume_mouse_press_release_ms":mouse_ms})
	return true

func finish() -> void:
	var fails := rows.filter(func(row):return not row.passed).size()
	var report := {"checks":rows.size(),"failures":fails,"results":rows,"samples":samples,"engine":Engine.get_version_info().string,"os":OS.get_name()+" "+OS.get_version(),"cpu":OS.get_processor_name(),"logical_cpus":OS.get_processor_count(),"gpu":RenderingServer.get_video_adapter_name(),"ram_bytes":OS.get_memory_info().get("physical",0),"viewport":[root.size.x,root.size.y],"renderer":RenderingServer.get_current_rendering_method(),"native_display":DisplayServer.get_name(),"timing":"Wall-clock process frames, eight seconds per crowd; no fixed FPS. Input injected into native viewport. Key and mouse timings include release and frame waits."}
	FileAccess.open(output+"/experience.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	quit(0 if fails==0 else 1)
