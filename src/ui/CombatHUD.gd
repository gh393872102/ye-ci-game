extends Control

const MiniMap = preload("res://src/ui/Minimap.gd")
const StageOptions = preload("res://src/data/StageOptions.gd")
const INK := Color("0b0f11")
const PANEL := Color("12191a")
const RULE := Color("354340")
const PAPER := Color("e6dfcc")
const MUTED := Color("aab5ac")
const COPPER := Color("b7a67f")
const ALERT := Color("f1ad91")
const COMMANDS := {
	"shouxiang": [
		["BUY", "P9_BUY_COMMAND", "buy"], ["DEPLOY", "P9_DEPLOY_COMMAND", "deploy"],
		["UPGRADE", "P9_UPGRADE_COMMAND", "upgrade"], ["REGISTER_ACTION", "P9_RITUAL_COMMAND", "register"],
		["REPAIR", "P9_REPAIR_COMMAND", "repair"], ["EQUIPMENT", "P9_EQUIPMENT_COMMAND", "equipment"]
	],
	"duoming": [
		["UPGRADE", "P9_MUTATE_COMMAND", "upgrade"], ["REGISTER_ACTION", "P9_FUSION_COMMAND", "register"],
		["BUY", "P9_REINFORCE_COMMAND", "reinforce"]
	]
}

var session: Node
var decisions: CanvasLayer
var camera: Camera2D
var world: Node2D
var debug: Node2D
var simulation: Node2D
var minimap: Control
var resources_label: Label
var goal_label: Label
var upper_status: Label
var door_status: Label
var phase_label: Label
var status: Label
var stopwatch: Label
var debug_text: Label
var feedback: Label
var ritual: Label
var ward_status: Label
var register_status: Label
var incense: Label
var names: Label
var door_heading: Label
var roster: Label
var roster_detail: Label
var command_title: Label
var command_hint: Label
var command_bar: HBoxContainer
var status_symbols: Control
var feedback_left := 0.0
var buttons: Dictionary = {}
var command_seat := "-"
var register_danger := false
var door_danger := false
var stage_title: Label
var stage_pressure: Label
var stage_modifiers: Label
var stage_event: Label

func _ready() -> void:
	add_to_group("hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel(Rect2(0, 0, Rules.DESIGN_WIDTH, Rules.TOP_BAR_HEIGHT), PANEL)
	_panel(Rect2(0, Rules.HORIZON_Y, Rules.DESIGN_WIDTH, Rules.DESIGN_HEIGHT - Rules.HORIZON_Y), INK)
	_panel(Rect2(0, Rules.TOP_BAR_HEIGHT - 1, Rules.DESIGN_WIDTH, 1), RULE)
	_panel(Rect2(0, Rules.HORIZON_Y, Rules.DESIGN_WIDTH, 2), Color("282e2a"))
	for x in [229, 413, 593, 743, 851, 1184, 1460]:
		_panel(Rect2(x, 10, 1, 34), RULE)
	ritual = _metric("P9_HUD_RITUAL", Rect2(26, 0, 190, 56), 21)
	goal_label = _metric("P9_HUD_DAWN", Rect2(247, 0, 154, 56), 20)
	register_status = _metric("P9_HUD_REGISTER", Rect2(455, 0, 131, 56), 18)
	incense = _metric("P9_HUD_INCENSE", Rect2(610, 0, 125, 56), 20)
	names = _metric("P9_HUD_NAMES", Rect2(760, 0, 79, 56), 20)
	door_heading = _line(self, tr("P9_HUD_DOORS"), Rect2(898, 4, 270, 21), 15, MUTED)
	door_status = _line(self, "", Rect2(898, 23, 274, 27), 17)
	upper_status = _metric("P9_HUD_UPPER", Rect2(1202, 0, 246, 56), 18)
	_button(self, "pause", tr("PAUSE_BUTTON"), _toggle_pause, Rect2(1478, 8, 132, 39))
	_button(self, "one", tr("P9_SPEED_ONE"), func(): Clock.set_speed(1.0), Rect2(1620, 8, 60, 39))
	_button(self, "two", tr("P9_SPEED_TWO"), func(): Clock.set_speed(2.0), Rect2(1688, 8, 60, 39))
	var menu := _button(self, "menu", tr("P9_HUD_MENU"), _open_menu, Rect2(1760, 8, 136, 39))
	menu.hide()
	ward_status = _line(self, "", Rect2(1370, 65, 526, 30), 20, PAPER)
	ward_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ward_status.hide()

	minimap = MiniMap.new()
	minimap.position = Vector2(24, 724)
	minimap.size = Vector2(512, 148)
	minimap.camera = camera
	minimap.world = world
	add_child(minimap)
	_panel(Rect2(24, 894, 512, 1), RULE)
	phase_label = _line(self, "", Rect2(26, 908, 490, 25), 18, COPPER)
	roster = _line(self, "", Rect2(26, 941, 504, 30), 22)
	roster_detail = _line(self, "", Rect2(26, 977, 504, 25), 17, MUTED)
	resources_label = _line(self, "", Rect2(26, 1011, 500, 25), 17, MUTED)
	status = _line(self, "", Rect2(26, 1044, 510, 24), 16, MUTED)

	command_title = _line(self, "", Rect2(558, 950, 700, 33), 18, COPPER)
	command_hint = _line(self, "", Rect2(1020, 950, 874, 36), 17, MUTED)
	command_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel(Rect2(558, 987, 1338, 1), RULE)
	command_bar = HBoxContainer.new()
	command_bar.position = Vector2(558, 999)
	command_bar.size = Vector2(1338, 48)
	command_bar.add_theme_constant_override("separation", 10)
	add_child(command_bar)
	debug_text = _line(self, "", Rect2(586, 746, 1280, 183), 18, MUTED)
	debug_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	stopwatch = _line(self, "", Rect2(26, 1011, 502, 24), 17, MUTED)
	feedback = _line(self, "", Rect2(560, 1050, 1318, 24), 17, COPPER)
	stage_title = _line(self, "", Rect2(1420, 829, 474, 29), 22, COPPER)
	stage_pressure = _line(self, "", Rect2(1420, 860, 474, 26), 17, PAPER)
	stage_modifiers = _line(self, "", Rect2(1420, 889, 474, 26), 17, MUTED)
	stage_event = _line(self, "", Rect2(1420, 918, 474, 26), 19, ALERT)
	status_symbols = Control.new()
	status_symbols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_symbols.draw.connect(_draw_status_symbols)
	add_child(status_symbols)
	Settings.changed.connect(_update_command_shortcuts)

func _metric(key: String, rect: Rect2, figure_size: int) -> Label:
	_line(self, tr(key), Rect2(rect.position.x, 4, rect.size.x, 21), 15, MUTED)
	return _line(self, "", Rect2(rect.position.x, 23, rect.size.x, 28), figure_size)

func _panel(rect: Rect2, color: Color) -> void:
	var panel := ColorRect.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.color = color
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

func _line(parent: Node, value: String, rect: Rect2, font_size: int, color := PAPER) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, id: String, value: String, callback: Callable, rect := Rect2()) -> Button:
	var button := Button.new()
	button.text = value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	button.add_theme_font_size_override("font_size", 19)
	parent.add_child(button)
	buttons[id] = button
	return button

func _toggle_pause() -> void:
	var host := _night_host()
	if host != null and Settings.pause_menu_open():
		host.resume_from_pause_menu()
	elif not Settings.gameplay_modal_open():
		Clock.toggle_pause()

func _open_menu() -> void:
	var host := _night_host()
	if host != null:
		host.open_pause_menu()

func _night_host() -> Node:
	var combat := world.get_parent()
	var parent := combat.get_parent()
	if parent != null and parent.has_method("open_pause_menu") and bool(parent.get("title_shell_enabled")):
		return parent
	return null

func _rebuild_commands(seat: String) -> void:
	if seat == command_seat:
		return
	command_seat = seat
	for button in command_bar.get_children():
		command_bar.remove_child(button)
		button.queue_free()
	var entries: Array = COMMANDS.get(seat, [])
	if seat == "debug":
		entries = COMMANDS.shouxiang
	for entry in entries:
		var callback: Callable = _placeholder_feedback if seat == "debug" else decisions.show_command.bind(entry[0])
		var button := _button(command_bar, entry[0], tr(entry[1]), callback)
		button.custom_minimum_size = Vector2(210, 48)
		button.size_flags_horizontal = Control.SIZE_FILL if seat == "duoming" else Control.SIZE_EXPAND_FILL
	_update_command_shortcuts()
	command_bar.show()
	command_title.text = tr("P9_COMMANDS") if not seat.is_empty() else ""
	command_title.visible = not seat.is_empty()
	command_hint.visible = not seat.is_empty()

func _update_command_shortcuts() -> void:
	for entry in COMMANDS.get(command_seat, []):
		buttons[entry[0]].tooltip_text = tr("P9_COMMAND_BINDING") % [tr(entry[1]), Settings.binding_text("keyboard", entry[2])]

func _process(real_delta: float) -> void:
	status.text = tr("PAUSED") if Clock.paused else tr("RUNNING") % Clock.time_scale
	buttons.pause.text = tr("P9_RESUME") if Clock.paused else tr("P9_PAUSE")
	buttons.one.modulate = PAPER if Clock.resume_scale == 1.0 else MUTED
	buttons.two.modulate = PAPER if Clock.resume_scale == 2.0 else MUTED
	var valid_session: bool = session != null and session.active
	buttons.menu.visible = valid_session and session.running and _night_host() != null
	debug_text.visible = not valid_session
	stopwatch.visible = not valid_session
	feedback.visible = not valid_session
	if valid_session:
		_update_battle()
	else:
		ward_status.hide()
		_rebuild_commands("debug")
		phase_label.text = tr("P3_SCOPE" if simulation != null and simulation.tide_enabled else "P2_SCOPE")
		roster.text = ""
		roster_detail.text = ""
		resources_label.text = ""
		stopwatch.text = tr("CLOCKS") % [Clock.combat_time, Clock.wall_time]
		goal_label.text = tr("P4_READY")
		ritual.text = tr("RITUAL")
		register_status.text = tr("P9_STATUS_EMPTY")
		upper_status.text = tr("P9_STATUS_EMPTY")
		names.text = tr("P9_STATUS_EMPTY")
		incense.text = tr("P9_STATUS_EMPTY")
		_update_debug()
	_update_stage(StageOptions.get_stage(session) if valid_session else null)
	_update_doors(valid_session)
	feedback_left = maxf(0, feedback_left - real_delta)
	if feedback_left == 0:
		feedback.text = ""
	var flame_low: bool = valid_session and (session.names <= float(session.rules.get("name_warning", 0)) or session.occupation > 0)
	if flame_low != register_danger:
		register_danger = flame_low
		status_symbols.queue_redraw()

func _update_battle() -> void:
	var seat: String = decisions.view_seat()
	var ended: bool = not session.result.is_empty()
	var interactive: bool = session.running and not ended and not decisions.read_only()
	_rebuild_commands(seat if interactive else "")
	var ritual_id := str(world.get_parent().get_meta("night_ritual", "example_incense"))
	var ritual_entry: Dictionary = Data.codex_store.catalog.get("ritual_" + ritual_id, {})
	ritual.text = str(session.ritual_row.get("title", tr("RITUAL"))) if session.ritual.id != "R01" else str(ritual_entry.get("name", tr("RITUAL")))
	var ward: Dictionary = session.ritual_ward_status()
	ward_status.visible = not ward.is_empty()
	if ward_status.visible:
		ward_status.text = tr("P10_WARD_ALIVE") % [ward.name,ceili(ward.hp),ceili(ward.max_hp)] if ward.alive else tr("P10_WARD_DEFEATED") % ward.name
		ward_status.add_theme_color_override("font_color", PAPER if ward.alive else ALERT)
	var remaining := ceili(session.remaining)
	goal_label.text = tr("P9_COUNTDOWN") % [remaining / 60, remaining % 60]
	if session.running and remaining <= 30:
		goal_label.text = tr("P9_DAWN_NEAR") % remaining
	elif ended:
		goal_label.text = tr("P4_END_VICTORY" if session.result.outcome == "victory" else "P4_END_DEFEAT")
		if decisions.observation_mode and session.result.has("winner"):
			goal_label.text = tr("P6_WINNER") % tr("P4_SEAT_" + str(session.result.winner).to_upper())
	elif not session.running:
		goal_label.text = tr("P4_READY")
	register_status.text = tr("P9_REGISTER_STABLE")
	if session.names <= 0:
		register_status.text = tr("P9_REGISTER_EXTINGUISHING") % ceili(session.extinguish_left)
	elif session.names <= float(session.rules.get("name_warning", 0)) or session.occupation > 0:
		register_status.text = tr("P9_REGISTER_CRITICAL")
	elif "P10_WARN_NAME_SEEP" in session.warnings:
		register_status.text = tr("P10_WARN_NAME_SEEP")
	register_status.add_theme_color_override("font_color", ALERT if register_status.text != tr("P9_REGISTER_STABLE") else PAPER)
	incense.text = tr("P9_WALLET_PAIR") % [session.incense_for("shouxiang"), session.incense_for("duoming")] if session.dual_enabled else str(floori(session.incense))
	names.text = "%.1f" % session.names
	var upper_ghosts := 0
	var alive_ghosts := 0
	var alive_humans := 0
	var specialists: Array[String] = []
	var elites := 0
	for ghost in simulation.targets:
		if ghost.dead:
			continue
		alive_ghosts += 1
		if world.is_upper_floor(ghost.floor_id):
			upper_ghosts += 1
		if ghost.unit_id != "G01":
			elites += 1
	for human in simulation.humans:
		if human.dead:
			continue
		alive_humans += 1
		if human.role == "ritual":
			specialists.append(human.display_name)
	upper_status.text = tr("P9_UPPER_STABLE") if upper_ghosts == 0 else tr("P9_UPPER_THREAT") % upper_ghosts
	if session.occupation > 0:
		upper_status.text = tr("P9_UPPER_OCCUPATION") % [session.occupation, session.rules.get("occupation_seconds", 8)]
	if session.ritual.upper_occupation > 0.0:
		upper_status.text = tr("P10_UPPER_OCCUPATION") % [session.ritual.upper_occupation,float(session.ritual_row.params.upper_hold_seconds)]
	upper_status.add_theme_color_override("font_color", ALERT if upper_ghosts > 0 or session.occupation > 0 else PAPER)
	phase_label.text = tr("P4_SEAT_" + seat.to_upper()) if not seat.is_empty() else tr("P6_WATCH")
	if decisions.observation_mode:
		phase_label.text = tr("P6_REPLAY" if decisions.replay_read_only else ("P6_WATCH" if decisions.read_only() else "P6_DUEL"))
	roster.text = tr("P9_ROSTER_DUOMING") % [alive_ghosts, elites] if seat == "duoming" else tr("P9_ROSTER_SHOU") % alive_humans
	roster_detail.text = tr("P9_ROSTER_NO_CASTER") if specialists.is_empty() else tr("P9_ROSTER_CASTERS") % "、".join(specialists)
	roster_detail.add_theme_color_override("font_color", ALERT if specialists.is_empty() and seat == "shouxiang" else MUTED)
	resources_label.text = tr("P9_TIDE_GAP") % session.reinforce_left if seat == "duoming" else (tr("P9_ROSTER_SELECTED") % decisions.selected.display_name if is_instance_valid(decisions.selected) else "")
	if session.dual_enabled:
		resources_label.text = tr("P6_WALLETS") % [session.incense_for("shouxiang"), session.incense_for("duoming"), session.names]
	if interactive:
		if seat == "shouxiang":
			var pending: String = session.pending_purchase
			buttons.DEPLOY.text = tr("P9_DEPLOY_RESERVED") if not pending.is_empty() else tr("P9_DEPLOY_COMMAND")
		status.text = tr("P9_STATUS_PAUSED") if Clock.paused else tr("P9_STATUS_RUNNING") % Clock.resume_scale
		var overlay: bool = decisions.panel.visible or decisions.growth_panel.surface.visible
		command_title.visible = not overlay
		command_hint.visible = not overlay
		command_hint.text = tr("P9_COMMAND_HINT")

func _update_stage(stage: Node2D) -> void:
	stage_title.text = stage.title_text() if stage != null else ""
	stage_pressure.text = stage.stage_text() if stage != null else ""
	stage_modifiers.text = stage.modifiers_text() if stage != null else ""
	stage_event.text = stage.feedback_text() if stage != null else ""
	if stage != null and stage.state.upper_lost:
		upper_status.text = tr("P10_UPPER_TOP_LOST")
		upper_status.add_theme_color_override("font_color", ALERT)

func _update_doors(valid_session: bool) -> void:
	var names_and_values: Array[String] = []
	var danger := false
	var broken := false
	for id in ["door_outer", "door_inner", "door_hall"]:
		var door: StaticBody2D = world.get_node(id)
		names_and_values.append(tr("P9_DOOR_VALUE") % [tr(str(door.name).to_upper()), door.durability])
		broken = broken or door.destroyed
		if valid_session:
			danger = danger or door.durability / door.max_durability <= float(session.rules.get("door_warning_ratio", 0.2))
	door_status.text = "   ".join(names_and_values)
	door_status.add_theme_color_override("font_color", ALERT if danger else PAPER)
	door_heading.text = tr("P9_DOOR_LOST" if broken else ("P9_DOOR_CRACKING" if danger else "P9_HUD_DOORS"))
	if (danger or broken) != door_danger:
		door_danger = danger or broken
		status_symbols.queue_redraw()

func _update_debug() -> void:
	var lines: Array[String] = []
	if debug.flags[4]:
		lines.append(tr("CAMERA_DEBUG") % [camera.left(), camera.left() + Rules.CAMERA_WIDTH_PX])
	if debug.flags[5]:
		var length: float = world.ghost_path_length()
		lines.append(tr("PATH_DEBUG_P1") % [length / Rules.BODY_PX, length / Rules.body_to_px(Rules.WALK_SPEED_REF)])
	if simulation != null and simulation.tide_enabled:
		lines.append(tr("TIDE_TIMER") % [simulation.tide.preset, simulation.tide.elapsed, str(snappedf(simulation.tide.arrival, 0.01)) if simulation.tide.arrival >= 0 else tr("TIDE_WAIT")])
	if debug.flags[10]:
		lines.append(tr("P9_DEBUG_FPS") % [Engine.get_frames_per_second(), world.visible_units().size(), Clock.resume_scale, status.text])
	if debug.flags[6]:
		var samples: Array[String] = []
		for id in Data.SAMPLE_IDS:
			var unit := Data.get_unit(id)
			samples.append(tr("P9_DEBUG_UNIT") % [id, unit.get("姓名", unit.get("名称", "")), unit["生命"], str(unit["专属技能"]).split("：")[0]])
		for index in 3:
			lines.append(samples[index] + "     /     " + samples[index + 3])
	if lines.is_empty():
		lines.append(tr("DEBUG_HELP"))
	debug_text.text = "\n".join(lines)

func _unhandled_input(event: InputEvent) -> void:
	if decisions != null and session.active:
		return
	for action in ["buy", "deploy", "upgrade", "register", "repair", "mutate", "fusion", "reinforce", "codex", "command_wheel"]:
		if event.is_action_pressed(action):
			_placeholder_feedback()

func _placeholder_feedback() -> void:
	feedback.text = tr("P4_PENDING")
	feedback_left = 3.0

func _draw_status_symbols() -> void:
	var flame := Color("c4a775") if not register_danger else ALERT
	var origin := Vector2(432, 29)
	var outline := PackedVector2Array([Vector2(-7, 5), Vector2(-8, 1), Vector2(-3, -5), Vector2(0, -13), Vector2(3, -8), Vector2(4, -3), Vector2(7, 2), Vector2(6, 6), Vector2(0, 9)])
	for index in outline.size():
		outline[index] += origin
	status_symbols.draw_colored_polygon(outline, flame)
	status_symbols.draw_circle(origin + Vector2(0, 4), 2.6, PANEL)
	var lintel := Color("acaa91") if not door_danger else ALERT
	var gate := PackedVector2Array([Vector2(868, 37), Vector2(868, 20), Vector2(882, 20), Vector2(882, 37)])
	status_symbols.draw_polyline(gate, lintel, 2.0)
	status_symbols.draw_line(Vector2(864, 18), Vector2(886, 18), lintel, 2.0)
	status_symbols.draw_polyline(PackedVector2Array([Vector2(877, 20), Vector2(872, 27), Vector2(877, 29), Vector2(873, 37)]), lintel, 1.5)
