extends SceneTree
## Use tools/p9_verify.py --native --script tools/p9_shell_smoke.gd.
## Give the second process --state <first output>/state to exercise a cold reload.
var output := ""
var state := ""
var host: Node
var settings: Node
var clock: Node
var results: Array[Dictionary] = []
var screenshots: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	results.append({"ok": ok, "label": label})
	print(("PASS " if ok else "FAIL ") + label)
	return ok

func _frames(count := 3) -> void:
	for _index in count:
		await process_frame

func _shot(name: String) -> void:
	await _frames()
	RenderingServer.force_draw(true)
	var frame := root.get_texture().get_image()
	if _check(frame != null and not frame.is_empty(), "Screenshot renders: " + name):
		var path := output.path_join(name + ".png")
		var saved := frame.save_png(path)
		screenshots[name] = {"file": path.get_file(), "width": frame.get_width(),
			"height": frame.get_height(), "sha256": FileAccess.get_sha256(path)}
		_check(saved == OK, "Screenshot writes: " + name)

func _tap_pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 2
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
		await _frames()

func _tap_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event, true)
		await _frames()

func _click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
		await _frames()

func _click(control: Control, x_fraction := 0.5) -> void:
	var rectangle := control.get_global_rect()
	await _click_at(rectangle.position + rectangle.size * Vector2(x_fraction, 0.5))

func _native_mode(expected: Window.Mode) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while int(DisplayServer.window_get_mode()) != int(expected) and Time.get_ticks_msec() < deadline:
		await process_frame
	return int(DisplayServer.window_get_mode()) == int(expected)

func _native_size(expected: Vector2i) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while root.size != expected and Time.get_ticks_msec() < deadline:
		await process_frame
	return root.size == expected

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else ""
	settings = root.get_node("Settings")
	clock = root.get_node("Clock")
	state = settings.PATH.get_base_dir()
	var isolated: bool = output.begins_with("/private/tmp/ye-ci-p9-") and state.begins_with("/private/tmp/ye-ci-p9-") and state.get_file() == "state"
	isolated = isolated and root.get_node("Data").codex_store.path == state.path_join("codex.json")
	if not _check(isolated and DisplayServer.get_name() != "headless", "Isolated state with native window"):
		quit(1)
		return
	var cold_reload := FileAccess.file_exists(settings.PATH)
	change_scene_to_file("res://scenes/boot/Boot.tscn")
	await _frames(12)
	host = current_scene
	if not _check(is_instance_valid(host) and host.has_method("open_pause_menu") and host.save_path == state.path_join("night_save.json"), "Boot enters the real Night host with an isolated save"):
		_finish(cold_reload)
		return
	if not _check(is_instance_valid(host.shell) and host.shell.title.visible, "Actual Boot presents the new title"):
		_finish(cold_reload)
		return
	if cold_reload:
		await _verify_reload()
	else:
		await _exercise_menus()
	_finish(cold_reload)

func _exercise_menus() -> void:
	var shell: CanvasLayer = host.shell
	var title: Dictionary = shell.title_buttons
	_check(root.gui_get_focus_owner() == title.start and title.continue_run.disabled, "First focus is Start, Continue is unavailable without a save")
	root.size = Vector2i(1920, 1080)
	await _shot("01-title-1080")
	root.size = Vector2i(1280, 720)
	var nav_event := InputEventJoypadButton.new()
	nav_event.device = 2
	nav_event.button_index = JOY_BUTTON_DPAD_DOWN
	nav_event.pressed = true
	_check(nav_event.is_action_pressed("ui_down"), "Directional input matches from a non-primary controller slot")
	await _tap_pad(JOY_BUTTON_DPAD_DOWN)
	_check(root.gui_get_focus_owner() == title.codex, "Controller focus skips unavailable Continue")
	await _tap_pad(JOY_BUTTON_A)
	_check(host.codex_panel.surface.visible and settings.gameplay_modal_open(), "Controller A opens the actual Codex")
	await _tap_pad(JOY_BUTTON_B)
	_check(not host.codex_panel.surface.visible and root.gui_get_focus_owner() == title.codex, "Controller B closes Codex and restores focus")
	await _tap_pad(JOY_BUTTON_DPAD_DOWN)
	await _tap_pad(JOY_BUTTON_A)
	var menu: Control = shell.preferences
	if not _check(menu.visible and settings.gameplay_modal_open(), "Controller reaches Settings via title navigation"):
		return
	await _shot("02-settings-display-720")
	await _click(menu.resolution_buttons[0])
	_check(menu.draft.resolution == Vector2i(960, 540) and menu.resolution_buttons[0].button_pressed, "Clicking the preset changes the draft window resolution")
	await _click(menu.buttons.mode_fullscreen)
	_check(menu.resolution_buttons[0].disabled and menu.draft.fullscreen, "Fullscreen uses the desktop's resolution and keeps the saved window preset")
	await _click(menu.buttons.apply)
	_check(await _native_mode(Window.MODE_FULLSCREEN), "Applying fullscreen changes the native window")
	await _click(menu.buttons.mode_windowed)
	await _click(menu.buttons.apply)
	_check(await _native_mode(Window.MODE_WINDOWED), "Leaving fullscreen returns the native window")
	_check(await _native_size(settings.fit_resolution(Vector2i(960, 540))), "Saved window resolution is applied to the desktop client size")
	await _click(menu.buttons.edge)
	await _click(menu.buttons.volume_Master, 0.63)
	await _click(menu.buttons.volume_SFX, 0.44)
	await _click(menu.buttons.volume_Music, 0.27)
	await _click(menu.buttons.volume_Ritual, 0.08)
	await _click(menu.buttons.keyboard)
	await _click(menu.binding_buttons.pause)
	await _tap_key(KEY_P)
	_check(menu.draft.bindings.keyboard.pause == [KEY_P] and settings.values.bindings.keyboard.pause == [KEY_SPACE], "Keyboard capture stages a change until Save")
	await _shot("03-settings-keyboard-540")
	await _click(menu.buttons.gamepad)
	await _click(menu.binding_buttons.ui_accept)
	await _tap_pad(JOY_BUTTON_Y)
	_check(menu.draft.bindings.gamepad.ui_accept == [JOY_BUTTON_Y] and menu.draft.bindings.gamepad.upgrade == [JOY_BUTTON_A], "Used controller button swaps assignments without losing a command")
	await _shot("04-settings-gamepad-540")
	await _click(menu.buttons.apply)
	_check(FileAccess.file_exists(settings.PATH) and settings.values.edge_scroll, "Save writes the local settings and applies edge scrolling")
	for bus in settings.AUDIO_BUSES:
		var index := AudioServer.get_bus_index(bus)
		_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(index)), settings.values.volumes[bus] / 100.0) and settings.values.volumes[bus] < 100, bus + " slider changes the actual AudioServer bus")
	await _tap_pad(JOY_BUTTON_B)
	_check(not menu.visible and root.gui_get_focus_owner() == title.settings, "Settings dismissal restores controller focus to title")
	await _click(title.start)
	await _shot("05-start-example-540")
	_check(root.gui_get_focus_owner() == title.shouxiang and shell.night_kind.selected == 0, "Example mode defaults to the roster and focuses Guard Incense")
	await _tap_pad(JOY_BUTTON_Y)
	if not _check(host.run.state.get("roster_enabled", false) and host.run.state.phase == "map", "Remapped controller confirm starts the real example night"):
		return
	await _tap_pad(JOY_BUTTON_Y)
	if not _check(is_instance_valid(host.combat), "Controller confirm on the night map enters real combat"):
		return
	var camera: Camera2D = host.combat.get_node("BattleCamera")
	var shot_before: Rect2 = camera.world_rect()
	var zoom_before := camera.zoom
	_check(camera.edge_scroll, "New battle initializes camera edge scrolling from saved settings")
	await _tap_pad(JOY_BUTTON_BACK)
	_check(shell.pause.visible and clock.paused and settings.pause_menu_open(), "Controller Back opens the local pause menu and stops the combat clock")
	_check(camera.world_rect() == shot_before and camera.zoom == zoom_before, "Opening pause preserves camera scale and visible world rectangle")
	await _shot("06-pause-540")
	var initial_left: float = camera.left()
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_RIGHT_X
	motion.axis_value = -1.0
	Input.parse_input_event(motion)
	await _frames(14)
	motion.axis_value = 0.0
	Input.parse_input_event(motion)
	_check(camera.left() < initial_left and camera.zoom == zoom_before, "Right-stick events pan during pause while preserving scale")
	var world: Node2D = host.combat.get_node("ReferenceMap")
	var visible_actors: Array = world.visible_units()
	if not visible_actors.is_empty():
		var actor: Node2D = visible_actors[0]
		await _click_at(world.get_global_transform_with_canvas() * actor.hit_rect().get_center())
		_check(host.combat.get_node("Decisions").selected == actor and shell.pause.visible and clock.paused, "Clicking a visible unit still opens its card while the pause menu remains open")
		await _shot("07-pause-unit-540")
	else:
		_check(false, "Live battle has a selectable unit in the current camera slice")
	await _click(shell.pause_buttons.settings)
	_check(menu.visible and shell.pause.visible, "Battle Settings overlays the open pause menu")
	var in_settings: Rect2 = camera.world_rect()
	await _tap_key(KEY_P)
	_check(clock.paused and camera.world_rect() == in_settings and camera.zoom == zoom_before, "Settings blocks combat shortcuts and does not change the visible world")
	await _tap_pad(JOY_BUTTON_B)
	await _click(shell.pause_buttons.resume)
	_check(not clock.paused and not shell.pause.visible, "Continue closes the pause menu and resumes combat")
	await _tap_key(KEY_P)
	_check(clock.paused, "Remapped keyboard shortcut reaches the normal combat pause handler")
	await _tap_pad(JOY_BUTTON_BACK)
	await _click(shell.pause_buttons.exit)
	_check(shell.title.visible and not is_instance_valid(host.combat) and not title.continue_run.disabled, "Save and Return leaves a Continue entry for the real battle")

func _verify_reload() -> void:
	var shell: CanvasLayer = host.shell
	_check(settings.values.edge_scroll and settings.values.resolution == Vector2i(960, 540) and not settings.values.fullscreen, "Cold Boot reloads edge scrolling, window mode and window resolution")
	_check(root.size == settings.fit_resolution(Vector2i(960, 540)), "Cold Boot applies the saved desktop window size")
	_check(settings.values.bindings.keyboard.pause == [KEY_P] and settings.values.bindings.gamepad.ui_accept == [JOY_BUTTON_Y], "Cold Boot applies saved keyboard and controller bindings")
	for bus in settings.AUDIO_BUSES:
		var index := AudioServer.get_bus_index(bus)
		_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(index)), settings.values.volumes[bus] / 100.0) and settings.values.volumes[bus] < 100, bus + " retains the committed level after quitting")
	await _tap_pad(JOY_BUTTON_DPAD_DOWN)
	_check(root.gui_get_focus_owner() == shell.title_buttons.continue_run, "Cold Boot restores Continue to the controller focus path")
	await _tap_pad(JOY_BUTTON_Y)
	_check(is_instance_valid(host.combat) and host.run.state.phase == "battle", "Remapped controller confirm restores the saved battle after a cold reboot")
	await _shot("08-continue-battle-540")

func _finish(cold_reload: bool) -> void:
	var failures := results.filter(func(item: Dictionary): return not item.ok).size()
	var report := {
		"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(),
		"cold_reload": cold_reload, "checks": results.size(), "failures": failures,
		"results": results, "screenshots": screenshots, "isolated_state": state,
		"scope": "Real desktop Godot windows and GUI. Keyboard, controller and mouse events injected through the Godot input system. First battle only. No physical controller was used."
	}
	var file := FileAccess.open(output.path_join("shell-results.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	quit(1 if failures else 0)
