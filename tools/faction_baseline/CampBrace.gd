extends "res://tools/faction_baseline/OrdinaryOpening.gd"

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=2:
		quit(2)
		return
	purify_only = true
	probe_boss_gate = true
	reading_limit = 2
	use_breaker_shortcut = true
	var rows := []
	var plans := ["reserve_H08","brace_hall","rest","brace_forward","reserve_forward"]
	if DisplayServer.get_name()!="headless": plans = ["brace_hall"]
	for plan in plans:
		var choice: String = {"brace_forward":"brace_hall","reserve_forward":"reserve_H08"}.get(plan,plan)
		var host: Node = load("res://scenes/night/Night.tscn").instantiate()
		host.save_path = "user://camp-brace.json"
		root.add_child(host)
		var night: RefCounted = host.run
		if not night.load_save(args[1]).ok or night.state.seed!=args[0] or night.state.phase!="rest":
			quit(2)
			return
		if not night.save(host.save_path).ok:
			quit(2)
			return
		# An unaffordable order must leave the saved camp decision available.
		if choice=="brace_hall":
			var old_cash: float = night.state.incense
			night.state.incense = 11.5
			if night.brace_hall_at_rest().ok or night.state.phase!="rest" or night.state.incense!=11.5:
				quit(2)
				return
			night.state.incense = old_cash
		host.continue_run()
		night = host.run
		var button: Button = host.panel.buttons.get(choice)
		if not is_instance_valid(button) or button.disabled:
			printerr("Missing camp choice ",choice)
			quit(2)
			return
		var cash: float = night.state.incense
		var hp: Array = night.state.roster.map(func(u):return [u.uid,u.hp,u.post])
		var click_ms := -1.0
		if choice=="brace_hall" and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_webp("/tmp/ye34-brace.webp",false,0.84)
			var sent := Time.get_ticks_usec()
			for down in [true,false]:
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_LEFT
				event.position = button.get_global_rect().get_center()
				event.pressed = down
				root.push_input(event,true)
			await RenderingServer.frame_post_draw
			click_ms = (Time.get_ticks_usec()-sent)/1000.0
		else:
			button.pressed.emit()
		if not night.load_save(host.save_path).ok or night.state.phase!="map":
			quit(2)
			return
		var paid: float = cash-night.state.incense
		var after: Array = night.state.roster.map(func(u):return [u.uid,u.hp,u.post])
		if choice=="brace_hall" and (paid!=12 or after!=hp or night.brace_hall_at_rest().ok):
			quit(2)
			return
		host.free()
		for guard in night.state.roster:
			var post := "post_hall_door" if str(plan).ends_with("forward") and guard.id=="H03" else "post_register"
			if guard.post!=post and not night.reserve_post(guard.uid,post).ok:
				quit(2)
				return
		if not night.choose_node("n10").ok:
			quit(2)
			return
		var b := await fight(night,"守香司",args[0],false,"",false,"",true,false,1,[],false,-1,"","",true,"破门")
		if not b.get("settled",false) or not b.foreign_units.is_empty() or not is_equal_approx(b.gate.initial_hp,339 if choice=="brace_hall" else 39):
			printerr("Unexpected gate or battle: ",b.get("gate"))
			quit(2)
			return
		rows.append({"plan":plan,"choice":choice,"before":hp,"after":after,"starting_cash":cash,"net_cost":paid,"click_ms":click_ms,"battle":b})
	var suffix := "-native" if DisplayServer.get_name()!="headless" else ""
	FileAccess.open("res://tools/faction_baseline/camp-brace-"+args[0]+suffix+".json",FileAccess.WRITE).store_string(JSON.stringify({"camp_sha256":FileAccess.get_sha256(args[1]),"trials":rows},"\t")+"\n")
	quit()
