extends SceneTree
## Drive the normal title and night with viewport input only. Never invoke gameplay callbacks.
var output_dir: String
var mode: String
var trace: Array = []
var failures: Array = []
var seen_phases: Array[String] = []
var game
var spins := 0
var end_summary := {}
var pad_events := 0
var mouse_events := 0
var keyboard_events := 0
var exercised_battle := false

func _initialize() -> void:
	call_deferred("run")

func stop_with(message: String) -> void:
	failures.append(message)
	print("FAIL ", message)

func button_event(index: int) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = index
		event.pressed = pressed
		root.push_input(event, true)
		pad_events += 1
		await process_frame

func next_direction(from: Control, to: Control) -> int:
	# The driver may inspect layout but only d-pad events may change focus.
	var queue: Array = [[from, -1]]
	var seen := {}
	while not queue.is_empty():
		var step: Array = queue.pop_front()
		var here: Control = step[0]
		if seen.has(here): continue
		seen[here] = true
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			var neighbor: Control = here.find_valid_focus_neighbor(side)
			if not is_instance_valid(neighbor) or seen.has(neighbor): continue
			var direction: int = side if int(step[1]) < 0 else int(step[1])
			if neighbor == to: return direction
			queue.append([neighbor, direction])
	return -1

func click(control: BaseButton) -> void:
	for pressed in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = control.get_global_rect().get_center()
		mouse.pressed = pressed
		root.push_input(mouse, true)
		mouse_events += 1
		await process_frame

func activate(target: BaseButton, label: String) -> bool:
	if not is_instance_valid(target) or not target.is_visible_in_tree() or target.disabled:
		stop_with("Unavailable button: "+label)
		return false
	if mode == "pad":
		for attempt in 40:
			var focused := root.gui_get_focus_owner()
			if focused == target: break
			if not is_instance_valid(focused): break
			var direction := next_direction(focused,target)
			if direction < 0: break
			var codes := {SIDE_LEFT:JOY_BUTTON_DPAD_LEFT, SIDE_RIGHT:JOY_BUTTON_DPAD_RIGHT,
				SIDE_TOP:JOY_BUTTON_DPAD_UP, SIDE_BOTTOM:JOY_BUTTON_DPAD_DOWN}
			await button_event(codes[direction])
		if root.gui_get_focus_owner() != target:
			stop_with("D-pad cannot focus "+label+" from "+str(root.gui_get_focus_owner()))
			return false
		await button_event(JOY_BUTTON_A)
	else:
		await click(target)
	trace.append(label)
	for tick in 3: await process_frame
	return true

func by_caption(key: String) -> BaseButton:
	var caption := TranslationServer.translate(key)
	for button in root.find_children("*", "BaseButton", true, false):
		if button.is_visible_in_tree() and (button.text == caption or button.text.begins_with(str(caption)+"\n")): return button
	return null

func action_for(phase: String):
	var buttons: Dictionary = game.panel.buttons
	match phase:
		"map":
			for node in game.run.available_nodes():
				if buttons.has("node_"+str(node.id)): return buttons["node_"+str(node.id)]
		"reward","event":
			for key in buttons:
				if str(key).begins_with("reward_") or str(key).begins_with("event_"):
					if not buttons[key].disabled: return buttons[key]
		"market": return buttons.get("leave")
		"rest": return buttons.get("rest")
		"mercy": return buttons.get("decline")
	return null

func key_event(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		keyboard_events += 1
		await process_frame

func first_enabled(buttons: Dictionary, prefix: String) -> BaseButton:
	for id in buttons:
		var button = buttons[id]
		if str(id).begins_with(prefix) and is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled:
			return button
	return null

func exercise_battle() -> void:
	var combat = game.combat
	var decisions = combat.get_node("Decisions")
	var camera = combat.get_node("BattleCamera")
	var original_zoom: Vector2 = camera.zoom
	if mode == "pad":
		await button_event(JOY_BUTTON_X)
		if not await activate(decisions.buttons.get("command_BUY"),"command/buy"): return
	else:
		await key_event(KEY_Q)
	var offer := first_enabled(decisions.buttons, "buy_")
	for page in 10:
		if is_instance_valid(offer): break
		if not await activate(decisions.buttons.get("purchase_next"),"purchase/next"): return
		offer = first_enabled(decisions.buttons, "buy_")
	if not await activate(offer,"purchase/pay"): return
	if not await activate(first_enabled(decisions.buttons, "post_"),"deploy/indoor-post"): return
	if not is_instance_valid(decisions.selected) or decisions.current_panel != "unit" or not root.get_node("Clock").paused:
		stop_with("Deployment did not open paused unit card")
		return
	if camera.zoom != original_zoom or original_zoom != Vector2.ONE:
		stop_with("Opening a decision changed camera zoom")
		return
	if mode == "pad":
		await button_event(JOY_BUTTON_B)
		await button_event(JOY_BUTTON_START)
		await button_event(JOY_BUTTON_RIGHT_STICK)
	else:
		if not await activate(decisions.buttons.close,"card/close"): return
		await key_event(KEY_SPACE)
		await key_event(KEY_EQUAL)
	if root.get_node("Clock").paused or root.get_node("Clock").resume_scale != 2:
		stop_with("Battle could not resume at twice normal speed")
	trace.append("combat/resume-2x")

func run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not (str(args[0]).begins_with("/private/tmp/ye-ci-p9-") or str(args[0]).begins_with("/tmp/ye-ci-p9-")):
		quit(2)
		return
	output_dir = args[0]
	mode = args[1]
	if root.get_node("Data").codex_store.path != output_dir+"/state/codex.json":
		print("FAIL Isolation check")
		quit(2)
		return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for tick in 12: await process_frame
	game = current_scene
	if await activate(by_caption("P9_TITLE_ACTION"), "title/start"):
		await activate(by_caption("P9_TITLE_SHOUXIANG"), "seat/guard")
	while failures.is_empty() and spins < 130000:
		if game.run.state.is_empty():
			stop_with("Seat confirmation did not start a night")
			break
		var phase: String = game.run.state.phase
		if phase not in seen_phases: seen_phases.append(phase)
		if phase == "ended":
			end_summary = game.run.summary()
			break
		if phase == "battle":
			if not exercised_battle:
				exercised_battle = true
				await exercise_battle()
			# Only real engine physics advance the clock and actors.
			for tick in 120: await process_frame
			spins += 120
		else:
			var target = action_for(phase)
			await activate(target,phase+"/"+str(game.run.state.current_node_id))
			spins += 1
	if end_summary.get("outcome","") not in ["victory","defeat"]: stop_with("No final settlement")
	var returned_to_title := false
	if failures.is_empty() and await activate(game.panel.buttons.get("menu"), "settlement/return-to-title"):
		var start_button := by_caption("P9_TITLE_ACTION")
		returned_to_title = is_instance_valid(start_button)
		if not returned_to_title:
			stop_with("Returning from settlement did not show the title")
		elif mode == "pad" and root.gui_get_focus_owner() != start_button:
			stop_with("Title did not restore controller focus to Start")
	if mode == "pad" and (mouse_events != 0 or keyboard_events != 0): stop_with("Unexpected keyboard or mouse input")
	var result := {"mode":mode,"input_source":"Godot viewport device events","physical_devices":Input.get_connected_joypads(),
		"trace":trace,"phases":seen_phases,"pad_events":pad_events,"mouse_events":mouse_events,
		"keyboard_events":keyboard_events,"returned_to_title":returned_to_title,
		"outcome":end_summary.get("outcome",""),"reason":end_summary.get("reason",""),
		"seed":end_summary.get("seed",""),"battles":end_summary.get("battles",[]),"failures":failures}
	FileAccess.open(output_dir+"/input-night.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("P9 INPUT NIGHT ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
