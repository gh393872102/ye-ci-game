extends CanvasLayer
## Unit selection is read-only and pauses combat. F7 tools are developer-only, not player orders.
var session: Node
var decision_panel: CanvasLayer
var simulation: Node2D
var world: Node2D
var selected: Node2D
var panel: PanelContainer
var inspector: PanelContainer
var stats: Label
var feedback: Label
var target_picker: OptionButton
var buttons: Dictionary = {}
var enabled := false
var target_ids: Array[String] = []

func _ready() -> void:
	layer = 6
	panel = _panel(Vector2(24, 80), 700)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_label(box, tr("TIDE_PANEL") if simulation.tide_enabled else tr("AI_PANEL"))
	_label(box, tr("AI_PANEL_HELP"))
	var row := HBoxContainer.new()
	box.add_child(row)
	_button(row, "reset", "AI_PRESET", func(): clear_selection(); simulation.reset_preset(); feedback.text = tr("AI_PRESET_DONE"))
	_button(row, "source", "AI_SOURCE", func(): simulation.spawn_source_targets(12); feedback.text = tr("AI_TARGETS_SPAWNED"))
	_button(row, "pressure", "AI_PRESSURE", _pressure)
	var toggles := HBoxContainer.new()
	box.add_child(toggles)
	_button(toggles, "hold", "AI_HOLD", _hold)
	_button(toggles, "clear", "TIDE_CLEAR" if simulation.tide_enabled else "AI_CLEAR", func(): simulation.clear_targets(); feedback.text = tr("AI_TARGETS_CLEARED"))
	_button(toggles, "probe", "AI_PROBE", func(): simulation.spawn_exception_probe(); feedback.text = tr("AI_PROBE_STARTED"))
	var channel_row := HBoxContainer.new()
	box.add_child(channel_row)
	target_picker = OptionButton.new()
	target_picker.focus_mode = Control.FOCUS_NONE
	channel_row.add_child(target_picker)
	_button(channel_row, "channel", "AI_CHANNEL", _channel)
	if simulation.tide_enabled:
		var tide_row := HBoxContainer.new()
		box.add_child(tide_row)
		_button(tide_row,"empty","TIDE_EMPTY",func(): _tide_preset("preset_empty_path"))
		_button(tide_row,"hold_g0","TIDE_HOLD",func(): _tide_preset("preset_hold_g0"))
		_button(tide_row,"visual40","TIDE_40",func(): _visual(40))
		_button(tide_row,"visual80","TIDE_80",func(): _visual(80))
		var elite_row := HBoxContainer.new()
		box.add_child(elite_row)
		_button(elite_row,"G12","TIDE_G12",func(): simulation.tide.pending.append("G12"))
		_button(elite_row,"G09","TIDE_G09",func(): simulation.tide.pending.append("G09"))
	feedback = _label(box, tr("AI_IDLE"))
	if simulation.tide_enabled:
		for id in ["source","pressure","probe"]:
			buttons[id].hide()
	panel.hide()
	inspector = _panel(Vector2(1120, 80), 776)
	var details := VBoxContainer.new()
	inspector.add_child(details)
	_label(details, tr("TIDE_INSPECTOR") if simulation.tide_enabled else tr("AI_INSPECTOR"))
	stats = _label(details, "")
	stats.custom_minimum_size = Vector2(740, 0)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(details, "close", "AI_CLOSE", clear_selection)
	inspector.hide()

func _panel(at: Vector2, width: float) -> PanelContainer:
	var result := PanelContainer.new()
	result.position = at
	result.custom_minimum_size.x = width
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("142328")
	skin.border_color = Color("5b7873")
	skin.set_border_width_all(1)
	skin.set_content_margin_all(16)
	result.add_theme_stylebox_override("panel", skin)
	var ui_theme := Theme.new()
	ui_theme.default_font = world.font
	ui_theme.default_font_size = 20
	result.theme = ui_theme
	add_child(result)
	return result

func _label(parent: Control, content: String) -> Label:
	var label := Label.new()
	label.text = content
	parent.add_child(label)
	return label

func _button(parent: Control, id: String, key: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = tr(key)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	buttons[id] = button

func select_unit(unit: Node2D) -> void:
	if session != null and session.active:
		decision_panel.select_unit(unit)
		return
	clear_selection()
	if not is_instance_valid(unit) or unit.dead:
		return
	selected = unit
	selected.selected = true
	selected.queue_redraw()
	Clock.set_paused(true)
	inspector.show()
	_refresh_details()

func clear_selection() -> void:
	if is_instance_valid(selected):
		selected.selected = false
		selected.queue_redraw()
	selected = null
	if inspector != null:
		inspector.hide()

func _hold() -> void:
	if not is_instance_valid(selected) or selected.side != "xianghuo":
		feedback.text = tr("AI_SELECT_HUMAN")
		return
	selected.hold_lock = not selected.hold_lock
	feedback.text = tr("AI_HOLD_ON") if selected.hold_lock else tr("AI_HOLD_OFF")
	selected.queue_redraw()

func _pressure() -> void:
	simulation.clear_targets()
	for index in 6:
		simulation.spawn_target(Vector2(Rules.body_to_px(48.5 - index * 0.7), Rules.HORIZON_Y))
	feedback.text = tr("AI_PRESSURE_DONE")

func _channel() -> void:
	if target_picker.selected < 0 or target_picker.selected >= target_ids.size():
		feedback.text = tr("AI_NO_TARGET")
		return
	var candidate: Node2D
	for target in simulation.targets:
		if target.instance_id == target_ids[target_picker.selected]:
			candidate = target
	for human in simulation.humans:
		if human.unit_id == "H01":
			var accepted: bool = human.brain.request_channel(candidate)
			feedback.text = tr(human.brain.channel.last_result) if not accepted else tr("CHANNEL_STARTED")
			return
	feedback.text = tr("AI_NO_CASTER")

func _process(_delta: float) -> void:
	if is_instance_valid(selected) and not selected.dead:
		_refresh_details()
	elif selected != null:
		clear_selection()
	if simulation.tide_enabled and enabled:
		feedback.text = tr("TIDE_TIMER") % [simulation.tide.preset,simulation.tide.elapsed, str(snappedf(simulation.tide.arrival,0.01)) if simulation.tide.arrival >= 0 else tr("TIDE_WAIT")]
	if enabled:
		var ids: Array[String] = []
		for target in simulation.targets:
			ids.append(target.instance_id)
		if ids != target_ids:
			target_ids = ids
			target_picker.clear()
			for id in ids:
				target_picker.add_item(id)

func _refresh_details() -> void:
	var unit: Node2D = selected
	var row: Dictionary = Data.get_unit(unit.unit_id)
	var lines: Array[String] = []
	lines.append("%s  %s  ·  %s / %s" % [unit.unit_id, unit.display_name, row.get("所属", row.get("谱系", "杂兵")), row.get("定位", "")])
	lines.append(tr("AI_STATS") % [unit.hp, unit.max_hp, unit.attack, unit.defense, unit.speed_stat])
	lines.append(tr("AI_STATE") % [unit.current_post, unit.floor_id, unit.ai_state])
	lines.append(tr("AI_MOVEMENT") % [unit.current_speed, Rules.body_to_px(unit.profile.range_body)])
	lines.append(tr("AI_SKILL") % [unit.skill_id, unit.skill_cost, unit.skill_text if not unit.skill_text.is_empty() else tr("AI_NONE")])
	lines.append(tr("AI_TRAIT") % [unit.trait_id, unit.trait_text if not unit.trait_text.is_empty() else tr("AI_NONE")])
	lines.append(tr("AI_FLAGS") % [str(unit.hold_lock), str(unit.may_briefly_leave_base)])
	if unit.role == "ritual":
		lines.append(tr("AI_CHANNEL_STATUS") % [unit.brain.channel.elapsed, unit.brain.channel.duration, tr(unit.brain.channel.last_result) if not unit.brain.channel.last_result.is_empty() else tr("AI_NONE")])
	lines.append(tr("AI_PAUSE_HELP"))
	stats.text = "\n\n".join(lines)

func _tide_preset(name: String) -> void:
	if session != null:
		session.enter_debug()
	clear_selection()
	simulation.reset_preset(name)
	Clock.set_paused(false)

func _visual(count: int) -> void:
	_tide_preset("preset_visual_tide")
	simulation.tide.visual(count)

func _unhandled_input(event: InputEvent) -> void:
	if decision_panel != null and decision_panel.managed_by_night and (event.is_action_pressed("debug_f5") or event.is_action_pressed("debug_ai")):
		get_viewport().set_input_as_handled()
		return
	if simulation.tide_enabled and event.is_action_pressed("debug_f5"):
		_tide_preset("preset_empty_path")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("debug_ai"):
		if session != null:
			session.enter_debug()
		enabled = not enabled
		panel.visible = enabled
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_rays"):
		simulation.debug_rays = not simulation.debug_rays
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if session != null and session.active:
			return
		var point: Vector2 = world.get_global_transform_with_canvas().affine_inverse() * event.position
		for unit in world.visible_units():
			if unit.hit_rect().has_point(point):
				select_unit(unit)
				get_viewport().set_input_as_handled()
				return
