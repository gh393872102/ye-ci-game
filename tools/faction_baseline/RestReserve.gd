extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var probe := "--input-probe" in OS.get_cmdline_user_args()
	var samples := []
	var passed := true
	if probe and (DisplayServer.get_name() == "headless" or root.get_visible_rect().size != Vector2(1920,1080)):
		quit(2)
		return
	for faction in ["守香司","武卫司","符法司","奇人司"]:
		var host: Node = load("res://scenes/night/Night.tscn").instantiate()
		host.save_path = "/tmp/ye-ci-rest-%d.json" % OS.get_process_id()
		root.add_child(host)
		host.panel.show_intro = false
		var night: RefCounted = host.run
		passed = passed and night.new_p10_run("shouxiang","example","渡口","R01",[],"",faction).ok
		# Domain/UI fixture; the OrdinaryRoute runs below use the earned night state.
		night.state.phase = "rest"
		night.state.current_node_id = "n06"
		passed = passed and night.rest_reserve_options().is_empty()
		var before: Dictionary = night.state.duplicate(true)
		night.state.roster.pop_back()
		passed = passed and night.rest_reserve_options().is_empty()
		var solo: Dictionary = night.state.duplicate(true)
		night.state.roster[0].hp = 2.0
		night.state.incense = 11
		var wounded: Array = night.rest_reserve_options()
		passed = passed and wounded.size() == 2 and wounded.all(func(o): return not o.allowed)
		night.state.incense = 12
		host.refresh()
		var heal_text: String = host.panel.buttons.rest.text
		passed = passed and ("%.2f → %.2f" % [2.0,night.rest_health_after(night.state.roster[0])]) in heal_text
		var names_at_camp: float = night.state.names
		var accepted: Dictionary = night.finish_rest(wounded[0].id) if not wounded.is_empty() else {"ok":false}
		passed = passed and accepted.ok and night.state.incense == 0 and night.state.names == names_at_camp and night.state.roster.size() == 2 and night.state.roster[0].hp == 2.0
		night.state = solo
		night.state.current_node_id = "n09"
		night.state.roster[0].hp = 2.0
		night.state.incense = 12
		var offers: Array = night.rest_reserve_options()
		var old_names: float = night.state.names
		passed = passed and offers.size() == 2 and night.finish_rest(offers[0].id).ok
		passed = passed and night.state.incense == 0 and night.state.names == old_names and night.state.roster.size() == 2 and night.state.roster[0].hp == 2.0
		night.state = before
		night.state.roster.clear()
		night.state.incense = 11
		host.refresh()
		night.state.erase("opening_faction")
		passed = passed and night.rest_reserve_options().is_empty()
		night.state.opening_faction = faction
		var options: Array = night.rest_reserve_options()
		passed = passed and options.size() == 2
		for offer in options:
			var id: String = offer.id
			passed = passed and root.get_node("Data").get_unit(id)["所属"] == faction and host.panel.buttons["reserve_"+id].disabled
			passed = passed and not night.finish_rest(id).ok and night.state.incense == 11
		night.state.incense = 12
		host.refresh()
		var rest: Button = host.panel.buttons.rest
		var first: Button = host.panel.buttons["reserve_"+str(options[0].id)]
		var second: Button = host.panel.buttons["reserve_"+str(options[1].id)]
		passed = passed and rest.get_node(rest.focus_neighbor_top) == first and first.get_node(first.focus_neighbor_right) == second and second.get_node(second.focus_neighbor_bottom) == rest
		passed = passed and first.text == "请援 · 12香火" and not second.disabled
		night.state.fallen.append({"id":options[0].id})
		night.state.fallen.append({"id":options[1].id})
		passed = passed and night.rest_reserve_options().is_empty()
		night.state.fallen.pop_back()
		host.refresh()
		var id: String = options[1].id
		var names: float = night.state.names
		passed = passed and not night.finish_rest(options[0].id).ok and not night.finish_rest("bad").ok
		var hire: Button = host.panel.buttons["reserve_"+id]
		if probe:
			await RenderingServer.frame_post_draw
			var rect := hire.get_global_rect()
			var start := Time.get_ticks_usec()
			for down in [true,false]:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.position = rect.get_center()
				click.pressed = down
				root.push_input(click,true)
			await RenderingServer.frame_post_draw
			samples.append({"faction":faction,"id":id,"input_to_frame_ms":(Time.get_ticks_usec()-start)/1000.0,"phase":night.state.phase,"paid":12-night.state.incense,"inside_viewport":root.get_visible_rect().encloses(rect)})
			passed = passed and samples.back().inside_viewport
		else:
			hire.pressed.emit()
		passed = passed and night.state.phase == "map" and night.state.roster.size() == 1 and night.state.roster[0].id == id and night.state.incense == 0 and night.state.names == names and not night.finish_rest(id).ok
		host.free()
		DirAccess.remove_absolute("/tmp/ye-ci-rest-%d.json" % OS.get_process_id())
	if probe:
		var result := {"passed":passed,"fixture":"empty four-faction rest menus, first reserve fallen; click remaining reserve, 12 incense","renderer":RenderingServer.get_video_adapter_name(),"pixels":[1920,1080],"samples":samples}
		FileAccess.open("res://tools/faction_baseline/native-rest-click.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("Four faction rest menus, exact cost, insufficient funds, fallen and duplicate requests: ",passed)
	await create_timer(0.5).timeout
	quit(0 if passed else 1)
