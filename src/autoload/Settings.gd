extends Node
## The editor supplies defaults through InputMap. Only committed local preferences affect play.
const PATH := "user://settings.cfg"
const RESOLUTIONS := [
	Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)
]
const AUDIO_BUSES := ["Master", "SFX", "Music", "Ritual"]
const MENU_ACTIONS := ["ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right"]
const BATTLE_ACTIONS := [
	"pause", "pause_menu", "command_wheel", "select_previous", "select_next",
	"speed_one", "speed_two", "camera_left", "camera_right", "buy", "deploy",
	"upgrade", "register", "repair", "equipment", "reinforce", "recall", "codex"
]
const GAMEPAD_REQUIRED := ["pause", "pause_menu", "command_wheel", "select_previous", "select_next"]
const BINDING_ALIASES := {"ui_cancel": "cancel", "upgrade": "mutate", "register": "fusion"}
const MAC_FULLSCREEN_ANIMATION_MS := 900
const KEY_LABELS := {
	KEY_ESCAPE: "ESCAPE", KEY_TAB: "TAB", KEY_BACKTAB: "TAB", KEY_BACKSPACE: "BACKSPACE",
	KEY_ENTER: "ENTER", KEY_KP_ENTER: "NUM_ENTER", KEY_SPACE: "SPACE",
	KEY_INSERT: "INSERT", KEY_DELETE: "DELETE", KEY_HOME: "HOME", KEY_END: "END",
	KEY_PAGEUP: "PAGEUP", KEY_PAGEDOWN: "PAGEDOWN",
	KEY_UP: "UP", KEY_DOWN: "DOWN", KEY_LEFT: "LEFT", KEY_RIGHT: "RIGHT",
	KEY_KP_ADD: "NUM_PLUS", KEY_KP_SUBTRACT: "NUM_MINUS", KEY_KP_DIVIDE: "NUM_DIVIDE",
	KEY_KP_MULTIPLY: "NUM_MULTIPLY", KEY_KP_PERIOD: "NUM_PERIOD"
}

signal changed

var defaults: Dictionary
var values: Dictionary
var mouse_pan_active := true
var _modal_surface: WeakRef
var _pause_surface: WeakRef
var _window_revision := 0
var _fullscreen_wait_until := 0

func _ready() -> void:
	var bindings := {"keyboard": {}, "gamepad": {}}
	for action in MENU_ACTIONS + BATTLE_ACTIONS:
		bindings.keyboard[action] = _current_codes(action, "keyboard")
		bindings.gamepad[action] = _current_codes(action, "gamepad")
	defaults = {
		"fullscreen": false, "resolution": Vector2i(1280, 720), "edge_scroll": false,
		"volumes": {"Master": 100, "SFX": 100, "Music": 100, "Ritual": 100},
		"bindings": bindings
	}
	values = defaults.duplicate(true)
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for key in ["fullscreen", "resolution", "edge_scroll"]:
		values[key] = config.get_value("display", key, defaults[key])
	for bus in AUDIO_BUSES:
		values.volumes[bus] = config.get_value("audio", bus, defaults.volumes[bus])
	for family in ["keyboard", "gamepad"]:
		for action in bindings[family]:
			values.bindings[family][action] = config.get_value(family, action, bindings[family][action])
	values = _normalized(values)
	_apply_bindings()
	_apply_audio()
	_apply_display()

func commit(draft: Dictionary) -> bool:
	var next := _normalized(draft)
	var config := ConfigFile.new()
	for key in ["fullscreen", "resolution", "edge_scroll"]:
		config.set_value("display", key, next[key])
	for bus in AUDIO_BUSES:
		config.set_value("audio", bus, next.volumes[bus])
	for family in next.bindings:
		for action in next.bindings[family]:
			if next.bindings[family][action] != defaults.bindings[family][action]:
				config.set_value(family, action, next.bindings[family][action])
	var temporary := PATH + ".tmp"
	if config.save(temporary) != OK:
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(PATH)) != OK:
		return false
	var display_changed: bool = next.fullscreen != values.fullscreen or next.resolution != values.resolution
	var current_mode := get_window().mode
	var native_fullscreen := current_mode == Window.MODE_FULLSCREEN or current_mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	var bindings_changed: bool = next.bindings != values.bindings
	values = next
	if bindings_changed:
		_apply_bindings()
	_apply_audio()
	if display_changed or native_fullscreen != values.fullscreen:
		_apply_display()
	changed.emit()
	return true

func _normalized(source: Dictionary) -> Dictionary:
	var clean := defaults.duplicate(true)
	for key in ["fullscreen", "edge_scroll"]:
		if source[key] is bool:
			clean[key] = source[key]
	if source.resolution is Vector2i and source.resolution in RESOLUTIONS:
		clean.resolution = source.resolution
	for bus in AUDIO_BUSES:
		if source.volumes[bus] is int:
			clean.volumes[bus] = clampi(source.volumes[bus], 0, 100)
	for family in clean.bindings:
		for action in clean.bindings[family]:
			var codes = source.bindings[family][action]
			if not codes is Array or codes.size() > 4:
				continue
			if codes.is_empty() and binding_required(family, action):
				continue
			if codes.all(func(code): return code is int and _valid_code(family, code)):
				clean.bindings[family][action] = codes.duplicate()
	return clean

func _current_codes(action: String, family: String) -> Array:
	var codes := []
	for event in InputMap.action_get_events(action):
		if family == "keyboard" and event is InputEventKey:
			codes.append(int(event.physical_keycode if event.physical_keycode else event.keycode))
		elif family == "gamepad" and event is InputEventJoypadButton:
			codes.append(int(event.button_index))
	return codes

func _apply_bindings() -> void:
	for family in values.bindings:
		for action in values.bindings[family]:
			var codes: Array = values.bindings[family][action]
			_replace_events(action, family, codes)
			if BINDING_ALIASES.has(action):
				_replace_events(BINDING_ALIASES[action], family, codes)

func _replace_events(action: String, family: String, codes: Array) -> void:
	if _current_codes(action, family) == codes:
		return
	Input.action_release(action)
	for event in InputMap.action_get_events(action):
		if (family == "keyboard" and event is InputEventKey) or (family == "gamepad" and event is InputEventJoypadButton):
			InputMap.action_erase_event(action, event)
	for code in codes:
		if family == "keyboard":
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(action, key)
		else:
			var button := InputEventJoypadButton.new()
			button.device = -1
			button.button_index = code
			InputMap.action_add_event(action, button)

func binding_required(family: String, action: String) -> bool:
	return family == "keyboard" or action in MENU_ACTIONS or action in GAMEPAD_REQUIRED

func remap(draft: Dictionary, family: String, action: String, code: int) -> Dictionary:
	var group: Dictionary = draft.bindings[family]
	if not _valid_code(family, code):
		return {"reason": "P9_BIND_UNSUPPORTED"}
	if code in group[action]:
		return {"reason": "P9_BIND_ASSIGNED"}
	var taken := []
	for other in group:
		if code in group[other]:
			taken.append(other)
	if taken.is_empty():
		group[action] = [code]
		return {"reason": "P9_BIND_ASSIGNED"}
	var other: String = taken[0]
	var previous: Array = group[action]
	if taken.size() > 1 or (previous.is_empty() and binding_required(family, other)):
		return {"reason": "P9_BIND_CONFLICT", "action": other}
	for entry in group:
		if entry != action and entry != other and previous.any(func(value): return value in group[entry]):
			return {"reason": "P9_BIND_CONFLICT", "action": other}
	group[other] = previous
	group[action] = [code]
	return {"reason": "P9_BIND_SWAPPED", "action": other}

func _valid_code(family: String, code: int) -> bool:
	if family == "gamepad":
		return code >= 0 and code < JOY_BUTTON_MAX
	return (
		(code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9)
		or (code >= KEY_EXCLAM and code <= KEY_ASCIITILDE)
		or code in KEY_LABELS or (code >= KEY_KP_0 and code <= KEY_KP_9)
		or (code >= KEY_F11 and code <= KEY_F35)
	)

func action_label(action: String) -> String:
	return tr("P9_BIND_" + action.to_upper())

func binding_text(family: String, action: String, source: Dictionary = {}) -> String:
	if source.is_empty():
		source = values
	var names := PackedStringArray()
	for code in source.bindings[family][action]:
		names.append(_code_text(family, code))
	return tr("P9_BIND_EMPTY") if names.is_empty() else " / ".join(names)

func _code_text(family: String, code: int) -> String:
	if family == "gamepad":
		var key := "P9_PAD_%d" % code
		return tr(key) if tr(key) != key else tr("P9_PAD_NUMBER") % (code + 1)
	if code in KEY_LABELS:
		return tr("P9_KEY_" + KEY_LABELS[code])
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return tr("P9_KEY_NUM_DIGIT") % (code - KEY_KP_0)
	var layout := code if DisplayServer.get_name() == "headless" else DisplayServer.keyboard_get_keycode_from_physical(code)
	return OS.get_keycode_string(code if layout == KEY_NONE else layout)

func _apply_audio() -> void:
	for bus in AUDIO_BUSES:
		var bus_index := AudioServer.get_bus_index(bus)
		if bus_index >= 0:
			var level := float(values.volumes[bus]) / 100.0
			AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(level, 0.001)))
			AudioServer.set_bus_mute(bus_index, is_zero_approx(level))

func fit_resolution(requested: Vector2i) -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return requested
	var work := DisplayServer.screen_get_usable_rect(get_window().current_screen).size
	if work.x <= 0 or work.y <= 0:
		return requested
	for index in range(RESOLUTIONS.size() - 1, -1, -1):
		var choice: Vector2i = RESOLUTIONS[index]
		if choice.x <= mini(requested.x, work.x) and choice.y <= mini(requested.y, work.y):
			return choice
	var width := mini(requested.x, mini(work.x, int(work.y * 16.0 / 9.0)))
	return Vector2i(width, roundi(width * 9.0 / 16.0))

func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_window_revision += 1
	_apply_window.call_deferred(_window_revision)

func _apply_window(revision: int) -> void:
	if not await _wait_for_native_transition(revision):
		return
	var window := get_window()
	var expected := Window.MODE_FULLSCREEN if values.fullscreen else Window.MODE_WINDOWED
	if window.mode != expected:
		window.mode = expected
		if OS.has_feature("macos"):
			# AppKit ignores a reversal while the preceding fullscreen animation is in flight.
			_fullscreen_wait_until = Time.get_ticks_msec() + MAC_FULLSCREEN_ANIMATION_MS
	if not values.fullscreen and await _wait_for_native_transition(revision):
		_resize_windowed()

func _wait_for_native_transition(revision: int) -> bool:
	while revision == _window_revision and Time.get_ticks_msec() < _fullscreen_wait_until:
		await get_tree().process_frame
	return revision == _window_revision

func _resize_windowed() -> void:
	var window := get_window()
	if window.mode != Window.MODE_WINDOWED:
		return
	window.min_size = fit_resolution(RESOLUTIONS[0])
	window.size = fit_resolution(values.resolution)
	var work := DisplayServer.screen_get_usable_rect(window.current_screen)
	var bottom_right := work.end - window.size
	window.position = Vector2i(
		clampi(window.position.x, work.position.x, maxi(work.position.x, bottom_right.x)),
		clampi(window.position.y, work.position.y, maxi(work.position.y, bottom_right.y))
	)

func set_gameplay_modal(surface: Control) -> void:
	_modal_surface = weakref(surface)

func set_pause_menu(surface: Control) -> void:
	_pause_surface = weakref(surface)

func gameplay_modal_open() -> bool:
	return _surface_visible(_modal_surface)

func pause_menu_open() -> bool:
	return _surface_visible(_pause_surface)

func _surface_visible(handle: WeakRef) -> bool:
	if handle == null:
		return false
	var surface := handle.get_ref() as Control
	return is_instance_valid(surface) and surface.is_visible_in_tree()

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		mouse_pan_active = false
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.28:
		mouse_pan_active = false
	elif event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length_squared() > 1.0):
		mouse_pan_active = true
