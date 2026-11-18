extends Control

signal closed

const TABS := ["display", "keyboard", "gamepad"]
const CAPTURE_SECONDS := 8.0

var draft: Dictionary
var tab := "display"
var buttons: Dictionary = {}
var binding_buttons: Dictionary = {}
var body: Control
var status: Label
var resolution_buttons: Array[Button] = []
var resolution_note: Label
var capture_action := ""
var capture_until := 0
var _tab_group := ButtonGroup.new()

func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()
	set_process(false)
	_label(self, "P9_TITLE_SETTINGS", Rect2(112, 43, 800, 72), 54)
	for index in TABS.size():
		var id: String = TABS[index]
		var key: String = "P9_SETTINGS_GENERAL" if id == "display" else "P9_SETTINGS_" + id.to_upper()
		var button := _button(self, key, Rect2(112 + index * 272, 141, 252, 62), _switch_tab.bind(id))
		button.toggle_mode = true
		button.button_group = _tab_group
		buttons[id] = button
	body = Control.new()
	body.position = Vector2(112, 246)
	body.size = Vector2(1696, 670)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	status = _label(self, "", Rect2(112, 927, 1696, 46), 23, Color("c8ae77"))
	buttons.reset = _button(self, "P9_SETTINGS_RESET", Rect2(112, 987, 254, 57), _reset)
	buttons.back = _button(self, "P9_TITLE_RETURN", Rect2(1272, 987, 246, 57), close)
	buttons.apply = _button(self, "P9_SETTINGS_APPLY", Rect2(1542, 987, 266, 57), _apply)
	buttons.apply.add_theme_color_override("font_color", Color("eed2a0"))

func open() -> void:
	if visible:
		return
	draft = Settings.values.duplicate(true)
	_switch_tab("display")
	status.text = ""
	show()
	buttons.display.grab_focus()

func close() -> void:
	capture_action = ""
	set_process(false)
	hide()
	closed.emit()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0f171a"))
	draw_rect(Rect2(0, 228, 1920, 700), Color("131e20"))
	draw_line(Vector2(112, 226), Vector2(1808, 226), Color("6c6956"), 1.0)
	draw_line(Vector2(112, 978), Vector2(1808, 978), Color("5a5d4e"), 1.0)

func _switch_tab(id: String) -> void:
	tab = id
	buttons[id].set_pressed_no_signal(true)
	capture_action = ""
	set_process(false)
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	binding_buttons.clear()
	if tab == "display":
		_build_display()
	else:
		_build_bindings()
	_mark_dirty()

func _build_display() -> void:
	_label(body, "P9_SETTINGS_SCREEN", Rect2(0, 16, 700, 58), 34)
	_label(body, "P9_SETTINGS_AUDIO", Rect2(956, 16, 700, 58), 34)
	_label(body, "P9_SETTINGS_WINDOW", Rect2(0, 114, 360, 58), 25)
	var modes := ButtonGroup.new()
	for index in 2:
		var fullscreen := index == 1
		var id := "fullscreen" if fullscreen else "windowed"
		var mode := _choice("P9_SETTINGS_" + id.to_upper(), Rect2(390 + index * 185, 114, 177, 58), modes, fullscreen == draft.fullscreen, _choose_display_mode.bind(fullscreen))
		buttons["mode_" + id] = mode
	_label(body, "P9_SETTINGS_RESOLUTION", Rect2(0, 205, 360, 58), 25)
	var sizes := ButtonGroup.new()
	resolution_buttons.clear()
	for index in Settings.RESOLUTIONS.size():
		var choice: Vector2i = Settings.RESOLUTIONS[index]
		var cell := Rect2(390 + (index % 2) * 185, 205 + floorf(index / 2.0) * 55, 177, 48)
		var size_button := _choice("%d × %d" % [choice.x, choice.y], cell, sizes, choice == draft.resolution, _select_resolution.bind(choice))
		resolution_buttons.append(size_button)
	resolution_note = _label(body, "", Rect2(0, 374, 752, 48), 20, Color("b8bca8"))
	_update_resolution_note()
	_label(body, "P9_SETTINGS_SCROLL", Rect2(0, 438, 360, 58), 25)
	var edge := CheckButton.new()
	edge.position = Vector2(390, 438)
	edge.size = Vector2(362, 58)
	edge.button_pressed = draft.edge_scroll
	edge.text = tr("P9_SETTINGS_ON" if draft.edge_scroll else "P9_SETTINGS_OFF")
	edge.toggled.connect(_toggle_edge)
	body.add_child(edge)
	buttons.edge = edge
	_label(body, "P9_SETTINGS_LANGUAGE", Rect2(0, 529, 360, 58), 25)
	_label(body, "P9_SETTINGS_SIMPLIFIED", Rect2(390, 529, 360, 58), 25, Color("cccab2"))
	for index in Settings.AUDIO_BUSES.size():
		_audio_slider(Settings.AUDIO_BUSES[index], 114 + index * 92)

func _audio_slider(bus: String, top: float) -> void:
	_label(body, "P9_SETTINGS_AUDIO_" + bus.to_upper(), Rect2(956, top, 208, 58), 25)
	var slider := HSlider.new()
	slider.position = Vector2(1182, top + 6)
	slider.size = Vector2(390, 44)
	slider.step = 1
	slider.value = draft.volumes[bus]
	slider.focus_mode = Control.FOCUS_ALL
	body.add_child(slider)
	buttons["volume_" + bus] = slider
	var amount := _label(body, "%d%%" % int(slider.value), Rect2(1594, top, 88, 58), 23, Color("e4c994"))
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(_change_volume.bind(bus, amount))

func _choice(key: String, rect: Rect2, group: ButtonGroup, selected: bool, apply: Callable) -> Button:
	var button := _button(body, key, rect, apply)
	button.toggle_mode = true
	button.button_group = group
	button.set_pressed_no_signal(selected)
	return button

func _choose_display_mode(fullscreen: bool) -> void:
	draft.fullscreen = fullscreen
	_update_resolution_note()
	_mark_dirty()

func _select_resolution(choice: Vector2i) -> void:
	draft.resolution = choice
	_update_resolution_note()
	_mark_dirty()

func _update_resolution_note() -> void:
	for button in resolution_buttons:
		button.disabled = draft.fullscreen
		button.focus_mode = Control.FOCUS_NONE if draft.fullscreen else Control.FOCUS_ALL
	var actual := Settings.fit_resolution(draft.resolution)
	resolution_note.text = ""
	if draft.fullscreen:
		resolution_note.text = tr("P9_SETTINGS_FULLSCREEN_HINT")
	elif actual != draft.resolution:
		resolution_note.text = tr("P9_SETTINGS_WINDOW_FIT") % [actual.x, actual.y]

func _toggle_edge(enabled: bool) -> void:
	draft.edge_scroll = enabled
	buttons.edge.text = tr("P9_SETTINGS_ON" if enabled else "P9_SETTINGS_OFF")
	_mark_dirty()

func _change_volume(value: float, bus: String, amount: Label) -> void:
	draft.volumes[bus] = int(value)
	amount.text = "%d%%" % int(value)
	_mark_dirty()

func _build_bindings() -> void:
	_label(body, "P9_SETTINGS_KEYBOARD_HINT" if tab == "keyboard" else "P9_SETTINGS_CONTROLLER_HINT", Rect2(0, 0, 1696, 45), 23, Color("b8bca8"))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 65)
	scroll.size = Vector2(1696, 596)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 52)
	scroll.add_child(columns)
	_binding_column(columns, "P9_BIND_SECTION_MENU", Settings.MENU_ACTIONS)
	_binding_column(columns, "P9_BIND_SECTION_BATTLE", Settings.BATTLE_ACTIONS)

func _binding_column(columns: HBoxContainer, heading: String, actions: Array) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	columns.add_child(column)
	var title := Label.new()
	title.text = tr(heading)
	title.custom_minimum_size.y = 57
	title.add_theme_font_size_override("font_size", 33)
	column.add_child(title)
	for action in actions:
		_binding_row(column, action)

func _binding_row(column: VBoxContainer, action: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 51
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var caption := Label.new()
	caption.text = Settings.action_label(action)
	caption.custom_minimum_size.x = 290
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_theme_font_size_override("font_size", 23)
	row.add_child(caption)
	var button := Button.new()
	button.text = Settings.binding_text(tab, action, draft)
	button.custom_minimum_size.x = 333
	button.tooltip_text = caption.text
	button.pressed.connect(_begin_capture.bind(action))
	row.add_child(button)
	binding_buttons[action] = button
	var clear_slot := Control.new()
	clear_slot.custom_minimum_size.x = 120
	row.add_child(clear_slot)
	if not Settings.binding_required(tab, action):
		var clear := _button(clear_slot, "P9_BIND_CLEAR", Rect2(0, 0, 118, 51), _clear_binding.bind(action))
		clear.disabled = draft.bindings[tab][action].is_empty()
		binding_buttons[action + "_clear"] = clear

func _clear_binding(action: String) -> void:
	draft.bindings[tab][action] = []
	_refresh_bindings()
	binding_buttons[action].grab_focus()
	_mark_dirty()

func _refresh_bindings() -> void:
	for action in Settings.MENU_ACTIONS + Settings.BATTLE_ACTIONS:
		binding_buttons[action].text = Settings.binding_text(tab, action, draft)
		if binding_buttons.has(action + "_clear"):
			binding_buttons[action + "_clear"].disabled = draft.bindings[tab][action].is_empty()

func _begin_capture(action: String) -> void:
	capture_action = action
	capture_until = Time.get_ticks_msec() + roundi(CAPTURE_SECONDS * 1000.0)
	set_process(true)
	_process(0.0)

func _process(_delta: float) -> void:
	var seconds := ceili((capture_until - Time.get_ticks_msec()) / 1000.0)
	if seconds <= 0:
		capture_action = ""
		status.text = tr("P9_BIND_CANCELLED")
		set_process(false)
		return
	var hint := "P9_BIND_CAPTURE_KEY" if tab == "keyboard" else "P9_BIND_CAPTURE_PAD"
	status.text = Settings.action_label(capture_action) + "  /  " + tr(hint) % seconds

func _input(event: InputEvent) -> void:
	if not visible or capture_action.is_empty() or not event.is_pressed() or event.is_echo():
		return
	var code := -1
	if event is InputEventKey and tab == "keyboard":
		if not event.is_command_or_control_pressed() and not event.alt_pressed:
			code = int(event.physical_keycode if event.physical_keycode else event.keycode)
	elif event is InputEventJoypadButton and tab == "gamepad":
		code = int(event.button_index)
	else:
		return
	get_viewport().set_input_as_handled()
	var answer := Settings.remap(draft, tab, capture_action, code)
	capture_action = ""
	set_process(false)
	_refresh_bindings()
	status.text = tr(answer.reason)
	if answer.has("action"):
		status.text = status.text % Settings.action_label(answer.action)

func _mark_dirty() -> void:
	status.text = "" if draft == Settings.values else tr("P9_SETTINGS_DIRTY")

func _reset() -> void:
	draft = Settings.defaults.duplicate(true)
	_switch_tab(tab)
	buttons.reset.grab_focus()

func _apply() -> void:
	if not Settings.commit(draft):
		status.text = tr("P9_SETTINGS_FAILED")
		return
	draft = Settings.values.duplicate(true)
	status.text = tr("P9_SETTINGS_SAVED")

func _button(parent: Control, key: String, rectangle: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = tr(key)
	button.position = rectangle.position
	button.size = rectangle.size
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Control, key: String, rectangle: Rect2, pixels: int, color := Color("e0dfcb")) -> Label:
	var label := Label.new()
	label.text = tr(key)
	label.position = rectangle.position
	label.size = rectangle.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
