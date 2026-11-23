extends Control
## NightRun owns all choices, money and outcomes. This surface displays its current phase.
const Ink = preload("res://src/ui/LedgerInk.gd")
const Appearance = preload("res://src/units/UnitAppearance.gd")
const Codex = preload("res://src/progression/CodexStore.gd")
const Story = preload("res://src/night/NightStory.gd")
const ROUTE_ASCENT := [188.0, 420.0, 652.0, 884.0, 1116.0]
const ROUTE_RETURN := [876.0, 648.0, 420.0, 192.0]
const SHEET := Rect2(0, 0, 1920, 1080)
const MAP_AREA := Rect2(64, 208, 1276, 638)
const ROUTE_COLORS := {"main":Color("c0a285"), "safe":Color("afbba0"), "risk":Color("e2a089"), "special":Color("c8b99d")}

var host: Node
var buttons: Dictionary = {}
var heading: Label
var status: Label
var seed_input: LineEdit
var kind_picker: OptionButton
var target_picker: OptionButton
var target_pickers: Dictionary = {}
var show_intro := true
var message := ""
var _page: Control
var _focus: Control
var _history := false
var _route_layer: Control
var _paths: Array[Dictionary] = []
var _boss_portrait: TextureRect
var _node_title: Label
var _node_note: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = SHEET.size
	mouse_filter = Control.MOUSE_FILTER_STOP

func render() -> void:
	var previous := get_viewport().gui_get_focus_owner()
	var focus_key := _button_key(previous)
	if is_instance_valid(_page):
		remove_child(_page)
		_page.queue_free()
	buttons.clear()
	target_pickers.clear()
	target_picker = null
	_focus = null
	_paths.clear()
	_page = Control.new()
	_page.size = SHEET.size
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page)
	Ink.box(_page, SHEET, Ink.DARK)
	var phase: String = str(host.run.state.get("phase", "")) if not show_intro else ""
	var centered := phase in ["reward", "market", "ended"] and not _history
	var setting := Ink.art("lantern-court") if centered else Ink.art("night-court")
	if setting == null:
		setting = Ink.art("night-court")
	if setting != null:
		Ink.texture(_page, setting, SHEET)
		Ink.box(_page, SHEET, Color("0d0b1070" if centered else "100d13a1"))
	Ink.binding(_page, SHEET.grow(-22), Color("544431"))
	if centered:
		heading = Ink.label(_page, "", Rect2(540, 34, 840, 89), 66, Ink.PAPER, true)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status = Ink.label(_page, "", Rect2(445, 130, 1030, 34), 19, Ink.MUTED)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Ink.ruling(_page, Rect2(657, 111, 606, 20), Ink.COPPER)
	else:
		Ink.box(_page, Rect2(23, 23, 1874, 163), Color("181417d9"))
		Ink.box(_page, Rect2(64, 50, 5, 72), Ink.SEAL)
		heading = Ink.label(_page, "", Rect2(88, 36, 934, 82), 61, Ink.PAPER, true)
		status = Ink.label(_page, "", Rect2(89, 128, 1050, 34), 21, Ink.MUTED)
		Ink.ruling(_page, Rect2(63, 174, 1794, 20))
	Ink.box(_page, Rect2(64, 994, 1792, 1), Ink.RULE)
	if host.run.state.is_empty() or show_intro:
		_history = false
		_intro()
	else:
		var state: Dictionary = host.run.state
		var node: Dictionary = host.run.current_node()
		_history = _history and state.phase == "ended"
		status.text = tr("P9_NIGHT_CONTEXT") % [tr("P4_SEAT_" + str(state.mode).to_upper()), host.run.config.title, state.visited.size(), host.run.config.nodes.size()]
		if _history:
			_map(true)
		else:
			match state.phase:
				"map": _map(false)
				"reward": _offers(false)
				"market": _offers(true)
				"event": _event()
				"rest": _rest()
				"mercy": _mercy()
				"ended": _summary()
				"battle":
					heading.text = tr("P5_BATTLE")
					_focus = _button("continue_battle", tr("P5_CONTINUE"), Rect2(700, 420, 520, 64), host.continue_run, true, true)
		if state.phase != "ended":
			_wallet(state, Rect2(1360, 115, 496, 44))
			_button("save", tr("P5_SAVE"), Rect2(1510, 50, 118, 44), host.save_run)
			_button("save_exit", tr("P5_SAVE_EXIT"), Rect2(1640, 50, 216, 44), host.save_and_exit)
		elif _history:
			_wallet(state, Rect2(1360, 115, 496, 44))
		if node.has("title") and state.phase not in ["map", "ended"]:
			status.text += "  /  " + str(node.title)
	if host.get("title_shell_enabled") == true and host.has_method("open_settings"):
		_button("settings", tr("P9_NIGHT_SETTINGS"), Rect2(1234, 50, 124, 44), host.open_settings)
	_button("codex", tr("P9_CODEX_TITLE"), Rect2(1372, 50, 124, 44), host.open_codex)
	var footer := Ink.label(_page, message, Rect2(64, 1004, 1520, 52), 19, Ink.MUTED)
	Ink.one_line(footer)
	var local := Ink.label(_page, tr("P5_LOCAL_SAVE"), Rect2(1590, 1004, 266, 52), 18, Ink.ASH)
	local.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_focus_default(focus_key)

func _button_key(control: Control) -> String:
	for id in buttons:
		if buttons[id] == control:
			return id
	return ""

func _intro() -> void:
	heading.text = tr("P5_BEGIN")
	status.text = tr("P5_SUBTITLE")
	Ink.box(_page, Rect2(440, 218, 926, 738), Color("161f20ed"), Ink.RULE)
	Ink.label(_page, tr("P5_BEGIN_HELP"), Rect2(478, 248, 850, 110), 25)
	Ink.label(_page, tr("P5_KIND"), Rect2(478, 380, 196, 48), 21, Ink.MUTED)
	kind_picker = OptionButton.new()
	kind_picker.add_item(tr("P5_EXAMPLE"))
	kind_picker.add_item(tr("P5_FIERCE_LOCKED"))
	kind_picker.set_item_disabled(1, true)
	kind_picker.position = Vector2(685, 380)
	kind_picker.size = Vector2(643, 48)
	_page.add_child(kind_picker)
	Ink.label(_page, tr("P5_SEED_ENTRY"), Rect2(478, 446, 196, 48), 21, Ink.MUTED)
	seed_input = LineEdit.new()
	seed_input.position = Vector2(685, 446)
	seed_input.size = Vector2(643, 48)
	seed_input.placeholder_text = tr("P5_SEED_PLACEHOLDER")
	seed_input.max_length = 80
	_page.add_child(seed_input)
	_focus = _button("start_shouxiang", tr("P5_START_SHOUXIANG"), Rect2(478, 530, 850, 64), _start.bind("shouxiang"), true, true)
	_button("start_duoming", tr("P5_START_DUOMING"), Rect2(478, 606, 850, 64), _start.bind("duoming"))
	_button("continue", tr("P5_CONTINUE"), Rect2(478, 682, 850, 64), host.continue_run, FileAccess.file_exists(host.save_path))
	_button("observer", tr("P6_OBSERVATORY"), Rect2(478, 758, 850, 64), host.open_observer)
	if FileAccess.file_exists(host.save_path):
		Ink.label(_page, tr("P5_CONFIRM_RESTART"), Rect2(478, 844, 850, 54), 19, Ink.MUTED)
	Ink.box(_page, Rect2(1390, 218, 466, 738), Color("161f20ed"), Ink.RULE)
	Ink.label(_page, tr("P7_GROWTH_NIGHT"), Rect2(1420, 248, 406, 58), 34, Ink.PAPER, true)
	_button("growth_shouxiang", tr("P7_GROWTH_SHOUXIANG"), Rect2(1420, 352, 406, 62), _growth_start.bind("shouxiang"))
	_button("growth_duoming", tr("P7_GROWTH_DUOMING"), Rect2(1420, 426, 406, 62), _growth_start.bind("duoming"))
	_button("build_lab", tr("P7_LAB_TITLE"), Rect2(1420, 532, 406, 62), host.open_growth_lab)
	Ink.label(_page, tr("P7_NIGHT_INVENTORY_HELP"), Rect2(1420, 632, 406, 146), 20, Ink.MUTED)

func _start(mode: String) -> void:
	var kind := "example" if kind_picker.selected == 0 else "fierce"
	var seed := seed_input.text
	show_intro = false
	host.start_run(mode, kind, seed)

func _growth_start(mode: String) -> void:
	show_intro = false
	host.start_growth_run(mode, seed_input.text)

func _wallet(state: Dictionary, rect: Rect2) -> void:
	var left := Ink.label(_page, tr("P9_NIGHT_INCENSE_VALUE") % state.incense, Rect2(rect.position, Vector2(234, rect.size.y)), 23, Ink.COPPER)
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Ink.box(_page, Rect2(rect.position + Vector2(262, 12), Vector2(1, 20)), Ink.RULE)
	var right := Ink.label(_page, tr("P9_NIGHT_NAMES_VALUE") % state.names, Rect2(rect.position + Vector2(276, 0), Vector2(220, rect.size.y)), 23)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _map(history: bool) -> void:
	heading.text = tr("P9_NIGHT_PAST_ROUTE" if history else "P9_NIGHT_MAP")
	var layer := Ink.folio(_page, MAP_AREA, Color("161217ad"))
	_route_layer = Control.new()
	_route_layer.size = SHEET.size
	_route_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_route_layer.draw.connect(_draw_paths)
	_page.add_child(_route_layer)
	var nodes: Array = host.run.config.nodes
	var points: Dictionary = {}
	var routes: Dictionary = {}
	var depth_rows: Dictionary = {}
	for node in nodes:
		var depth: int = node.depth
		var index: int = depth_rows.get(depth, 0)
		depth_rows[depth] = index + 1
		points[node.id] = _route_point(depth, index)
		routes[node.id] = ROUTE_COLORS[_route_key(str(node.route))]
	for node in nodes:
		for next in node.next:
			_paths.append({
				"from":points[node.id], "to":points[next],
				"traveled":node.id in host.run.state.visited and next in host.run.state.visited,
				"color":routes[next]})
	_route_layer.queue_redraw()
	if host.run.state.has("growth") and not history:
		var economy: Dictionary = host.run.config.growth_night
		var curve := tr("P7_NIGHT_RESOURCE_CURVE") % [economy.incense_regen, economy.victory_incense, host.run.config.incense_cap]
		Ink.label(layer, curve, Rect2(474, 10, 776, 45), 19, Ink.PAPER)
	var legend_keys := ["safe", "risk", "special"]
	for index in legend_keys.size():
		var key: String = legend_keys[index]
		var legend := Ink.label(layer, tr("P9_ROUTE_" + key.to_upper()), Rect2(26 + index * 148, 13, 128, 40), 19, ROUTE_COLORS[key])
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Ink.box(layer, Rect2(56 + index * 148, 53, 68, 1), ROUTE_COLORS[key])
	var ready: Dictionary = {}
	for node in host.run.available_nodes():
		ready[str(node.id)] = true
	Ink.folio(_page, Rect2(64, 864, 1276, 108))
	_boss_portrait = Ink.texture(_page,null,Rect2(80,870,80,94))
	_boss_portrait.hide()
	_node_title = Ink.label(_page, "", Rect2(86, 874, 300, 42), 25, Ink.COPPER, true)
	_node_note = Ink.label(_page, "", Rect2(370, 878, 948, 76), 21, Ink.PAPER)
	var current: Dictionary = host.run.current_node()
	if current.is_empty():
		current = nodes[0]
	_show_route_node(current)
	var available_controls: Array[Button] = []
	for node in nodes:
		var id: String = node.id
		var is_current := id == str(host.run.state.current_node_id)
		var can_enter: bool = ready.has(id) and not history
		var visited: bool = id in host.run.state.visited
		var position: Vector2 = points[id]
		var node_button := _route_button(node, Rect2(position - Vector2(80, 40), Vector2(160, 142)), can_enter, is_current, visited)
		if can_enter:
			available_controls.append(node_button)
			if _focus == null:
				_focus = node_button
	_link_horizontal(available_controls)
	var roster_top := _story_card(available_controls)
	if history:
		_focus = _button("summary_back", tr("P9_NIGHT_BACK_REPORT"), Rect2(1612, 899, 244, 64), _switch_report.bind(false), true, true)
	var roster_bottom := 888.0 if history else 972.0
	if not history and host.run.state.has("opening_faction") and not host.run.state.roster.is_empty():
		roster_bottom -= 68.0
		_post_picker()
	_roster(Rect2(1358, roster_top, 498, roster_bottom - roster_top))

func _post_picker() -> void:
	var picker := OptionButton.new()
	picker.name = "ReservePost"
	picker.fit_to_longest_item = false
	picker.position = Vector2(1358,915)
	picker.size = Vector2(498,56)
	picker.add_theme_font_size_override("font_size",21)
	picker.add_item("下场布防 · 免费换岗")
	picker.set_item_disabled(0,true)
	var members := {}
	for member in host.run.state.roster:
		members[member.uid] = member
	for option in host.run.reserve_post_options():
		var allies: Array = host.run.state.roster.filter(func(unit): return unit.post == option.to)
		var coverage := "独守" if allies.is_empty() else "与%s合守" % "、".join(_unit_names(allies))
		var member: Dictionary = members[option.uid]
		picker.add_icon_item(preload("res://src/units/UnitAppearance.gd").bust_texture(option.id), "%s %.0f/%.0f · %s → %s（%s）" % [_unit_name(option.id),member.hp,member.max_hp,tr(str(option.from).to_upper()),tr(str(option.to).to_upper()),coverage])
		picker.get_popup().set_item_icon_max_width(picker.item_count-1,48)
		picker.set_item_metadata(picker.item_count-1,option)
		var left: Array = host.run.state.roster.filter(func(unit): return unit.uid != option.uid and unit.post == option.from)
		var origin := "原岗将无人驻守。" if left.is_empty() else "原岗仍有%s驻守。" % "、".join(_unit_names(left))
		var hint := ""
		match option.to:
			"post_stair_head": hint = "从楼梯口开战，退守方向是名册房。同层且视线通畅才能点册。"
			"post_table_hall": hint = "从门厅香案开战，退守方向是楼梯口。点册须同层、在射程内且视线通畅。"
			"post_rear": hint = "从后厢开战，角色仍会按自己的规则支援。"
		picker.set_item_tooltip(picker.item_count-1,"到岗后 %d/%d 人。%s%s" % [allies.size()+1,Data.battle_rules.post_cap,origin,hint])
	picker.select(0)
	picker.disabled = picker.item_count == 1
	if picker.disabled: picker.set_item_text(0,"下场布防 · 暂无可调岗位")
	_page.add_child(picker)
	picker.item_selected.connect(func(index: int):
		if index <= 0: return
		var option: Dictionary = picker.get_item_metadata(index)
		host.reserve_post(option.uid,option.to))

func _story_card(route_buttons: Array[Button]) -> float:
	var act: Dictionary = host.run.story_act()
	if act.is_empty():
		return 208.0
	var choice: Dictionary = host.run.self_listing_choice()
	var height := 172.0 if choice.is_empty() else 292.0
	var card := Ink.folio(_page, Rect2(1358, 208, 498, height), Color("1a1517f5"))
	Ink.label(card, tr(act.title_key), Rect2(28, 20, 442, 48), 28, Ink.COPPER, true)
	var body := Ink.label(card, "", Rect2(30, 75, 436, 82), 21)
	body.text = tr(act[str(host.run.state.mode) + "_key"])
	if not choice.is_empty():
		Ink.box(card, Rect2(28, 164, 442, 1), Ink.RULE)
		var payment: Dictionary = choice.get("payment", {})
		if choice.paid:
			Ink.label(card, tr("P11_SELF_WOUNDED") % payment.names_paid, Rect2(30, 186, 436, 76), 21, Ink.RUST)
		else:
			var preview := tr(choice.reason)
			if choice.allowed:
				preview = tr("P11_SELF_PREVIEW") % [payment.names_paid, payment.max_hp_before, payment.max_hp_after]
			Ink.label(card, preview, Rect2(30, 174, 436, 55), 19, Ink.MUTED)
			var list_name := _button("self_listing", tr("P11_SELF_CHOICE"), Rect2(1388, 445, 438, 45),
				host.choose_self_listing, choice.allowed)
			if choice.allowed and not route_buttons.is_empty():
				var terminal := route_buttons[-1]
				terminal.focus_neighbor_right = terminal.get_path_to(list_name)
				list_name.focus_neighbor_left = list_name.get_path_to(terminal)
	return 224.0 + height

func _route_point(depth: int, branch: int) -> Vector2:
	if depth < ROUTE_ASCENT.size():
		return Vector2(ROUTE_ASCENT[depth], 365 + (depth % 2) * 18)
	if depth == 5:
		return Vector2(1198 if branch == 0 else 918, 554)
	return Vector2(ROUTE_RETURN[clampi(depth - 6, 0, ROUTE_RETURN.size() - 1)], 732 - (depth % 2) * 20)

func _route_key(value: String) -> String:
	for key in ROUTE_COLORS:
		if value == tr("P9_ROUTE_" + key.to_upper()):
			return key
	return "main"

func _route_button(node: Dictionary, rect: Rect2, can_enter: bool, current: bool, visited: bool) -> Button:
	var id: String = node.id
	var route_color: Color = ROUTE_COLORS[_route_key(str(node.route))]
	var button := _button("node_" + id, "", rect, host.choose_node.bind(id), can_enter, can_enter)
	button.flat = true
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var seal := Control.new()
	seal.size = Vector2(160, 82)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(seal)
	seal.draw.connect(_draw_route_seal.bind(seal, str(node.type), route_color, current, can_enter, visited))
	button.focus_entered.connect(seal.queue_redraw)
	button.focus_exited.connect(seal.queue_redraw)
	button.mouse_entered.connect(seal.queue_redraw)
	button.mouse_exited.connect(seal.queue_redraw)
	button.tooltip_text = str(node.description)
	button.mouse_entered.connect(_show_route_node.bind(node))
	button.focus_entered.connect(_show_route_node.bind(node))
	var mark_key := "P5_CURRENT" if current else ("P5_AVAILABLE" if can_enter else ("P5_VISITED" if visited else "P5_UNOPENED"))
	var title := Ink.label(button, str(node.title), Rect2(7, 84, 146, 34), 23, Ink.PAPER if (can_enter or visited) else Ink.MUTED, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var kind := Ink.label(button, tr("P9_ROUTE_STATE") % [node.route, tr(mark_key)], Rect2(5, 116, 150, 24), 16, route_color if can_enter or current else Ink.ASH)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return button

func _draw_route_seal(seal: Control, type: String, tone: Color, current: bool, ready: bool, visited: bool) -> void:
	var center := Vector2(80, 40)
	var button := seal.get_parent() as Button
	var focus := button.has_focus() or button.is_hovered()
	var stamp := Ink.SEAL if current else (Color("3d2b21") if ready else Color("171417"))
	var border := Ink.PAPER if focus else (tone if current or ready or visited else tone.darkened(0.53))
	seal.draw_circle(center, 38, stamp)
	seal.draw_arc(center, 38, 0, TAU, 44, border, 2.0, true)
	seal.draw_arc(center, 32, 0, TAU, 40, Color(border, 0.60), 1.0, true)
	for degrees in [0, 90, 180, 270]:
		var mark := Vector2.RIGHT.rotated(deg_to_rad(degrees))
		seal.draw_line(center + mark * 29, center + mark * 34, border, 1.5, true)
	var glyph := tr("P9_ROUTE_GLYPH_" + type.to_upper())
	var font := Ink.serif_font()
	var width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	seal.draw_string(font, center + Vector2(-width / 2, 11), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, border)

func _show_route_node(node: Dictionary) -> void:
	var show_boss: bool = node.get("boss_id","") == "B01" and host.run.state.mode == "shouxiang"
	_boss_portrait.visible = show_boss
	_node_title.position.x = 174 if show_boss else 86
	_node_title.text = str(node.title)
	_node_note.text = str(node.description)
	if host.run.state.has("nameless_modifiers") and node.has("chunk_ids"):
		var titles := PackedStringArray()
		for id in node.chunk_ids: titles.append(preload("res://src/data/ChunkCatalog.gd").read_chunk(id).get("title",id))
		_node_note.text = tr("P10_ROUTE_NODE") % [str(node.description),"、".join(titles)]

	_node_note.tooltip_text = _node_note.text if show_boss else ""
	_node_note.mouse_filter = Control.MOUSE_FILTER_PASS if show_boss else Control.MOUSE_FILTER_IGNORE
	if show_boss:
		var spec: Dictionary = preload("res://src/data/StageOptions.gd").bosses().B01
		var lead: Dictionary = spec.formations[0]
		var rams: Array = spec.formations.filter(func(f): return f.role == "ram")
		_boss_portrait.texture = Appearance.portrait_texture(lead.unit)
		_node_note.text = "主殿门开战时剩 %d%% 耐久。一名%s已在门内。" % [roundi(spec.initial_doors.door_hall*100),_unit_name(lead.unit)]
		if not rams.is_empty():
			_node_note.text += "\n第 %s 秒，第二名%s从门外赶来。" % [String.num(rams[0].at).trim_suffix(".0"),_unit_name(rams[0].unit)]

func _draw_paths() -> void:
	for path in _paths:
		var origin: Vector2 = path.from
		var destination: Vector2 = path.to
		var tone: Color = path.color
		var direction := (destination - origin).normalized()
		var start := origin + direction * 40
		var finish := destination - direction * 40
		var bend := direction.orthogonal() * (17.0 if absf(direction.x) > 0.80 else -21.0)
		var route := Curve2D.new()
		route.add_point(start, Vector2.ZERO, (finish - start) * 0.34 + bend)
		route.add_point(finish, (start - finish) * 0.28 + bend, Vector2.ZERO)
		var points := route.get_baked_points()
		if path.traveled:
			_route_layer.draw_polyline(points, Color("221617"), 8, true)
			_route_layer.draw_polyline(points, tone, 3, true)
		else:
			for index in range(0, points.size() - 1, 3):
				var end := mini(index + 1, points.size() - 1)
				_route_layer.draw_line(points[index], points[end], tone.darkened(0.32), 2, true)

func _roster(rect: Rect2) -> void:
	Ink.folio(_page, rect, Color("181518eb"))
	var state: Dictionary = host.run.state
	Ink.label(_page, tr("P5_ROSTER"), Rect2(rect.position + Vector2(28, 18), Vector2(420, 56)), 32, Ink.PAPER, true)
	Ink.label(_page, tr("P9_NIGHT_ROSTER_COUNTS") % [state.roster.size(), state.fallen.size()], Rect2(rect.position + Vector2(30, 81), Vector2(425, 37)), 20, Ink.MUTED)
	Ink.box(_page, Rect2(rect.position + Vector2(30, 133), Vector2(rect.size.x - 60, 1)), Ink.RULE)
	var rows := Ink.scroll_rows(_page, Rect2(rect.position + Vector2(29, 151), Vector2(rect.size.x - 58, rect.size.y - 258)), 5)
	for unit in state.roster:
		var field := Label.new()
		field.text = tr("P9_NIGHT_ROSTER_ROW") % [_unit_name(str(unit.id)), unit.hp, unit.max_hp]
		if state.has("opening_faction") and str(unit.id).begins_with("H"): field.text += " · " + tr(str(unit.post).to_upper())
		field.add_theme_font_size_override("font_size", 20)
		field.add_theme_color_override("font_color", Ink.PAPER)
		var portrait: Texture2D = preload("res://src/units/UnitAppearance.gd").bust_texture(unit.id) if state.has("opening_faction") else null
		if portrait:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation",10)
			rows.add_child(row)
			var face := TextureRect.new()
			face.texture = portrait
			face.custom_minimum_size = Vector2(72,48)
			face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(face)
			field.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(field)
		else:
			rows.add_child(field)
	if state.roster.is_empty():
		var empty := Label.new()
		empty.text = tr("P5_NONE")
		empty.add_theme_color_override("font_color", Ink.MUTED)
		rows.add_child(empty)
	var bottom := rect.position.y + rect.size.y - 91
	Ink.box(_page, Rect2(rect.position.x + 30, bottom, rect.size.x - 60, 1), Ink.RULE)
	var modifiers: Array[String] = []
	for key in state.build:
		var value: float = state.build[key]
		if not is_zero_approx(value):
			modifiers.append(tr("P5_MOD_" + str(key).to_upper()) % value)
	var build_text := "  /  ".join(modifiers)
	if state.has("growth"):
		var inventory: Dictionary = state.growth.get("inventory", {})
		var amount := 0
		for value in inventory.values():
			amount += int(value)
		build_text = (tr("P9_NIGHT_INVENTORY_TOTAL") % amount) + ("  /  " + build_text if not build_text.is_empty() else "")
	elif modifiers.is_empty():
		build_text = tr("P5_NO_BUILD")
	var build := Ink.label(_page, build_text, Rect2(rect.position.x + 30, bottom + 10, rect.size.x - 60, 52), 19, Ink.MUTED)
	Ink.one_line(build)
	build.tooltip_text = build_text
	build.mouse_filter = Control.MOUSE_FILTER_PASS

func _offers(market: bool) -> void:
	heading.text = tr("P9_NIGHT_MARKET" if market else "P5_REWARD_TITLE")
	var offers: Array = host.run.market_options() if market else host.run.reward_options()
	var count := offers.size()
	var width := 397.0 if market else 466.0
	var gap := 34.0 if market else 43.0
	var total := count * width + maxi(0, count - 1) * gap
	var action_keys: Array[Button] = []
	for index in count:
		var rect := Rect2((1920.0 - total) / 2 + index * (width + gap), 214, width, 644 if market else 692)
		var action := _offer_card(offers[index], rect, market)
		if not action.disabled:
			action_keys.append(action)
			if _focus == null:
				_focus = action
	_link_horizontal(action_keys)
	if market:
		var market_help := "P9_MARKET_DUOMING_HELP" if host.run.state.mode == "duoming" else "P9_MARKET_SHOUXIANG_HELP"
		Ink.label(_page, tr(market_help), Rect2(99, 908, 1280, 56), 21, Ink.MUTED, true)
		var leave := _button("leave", tr("P5_LEAVE"), Rect2(1536, 886, 320, 62), host.leave_node, true, true)
		for action in action_keys:
			action.focus_neighbor_bottom = action.get_path_to(leave)
		if _focus == null:
			_focus = leave
	else:
		var help := Ink.label(_page, tr("P5_REWARD_HELP"), Rect2(100, 924, 1720, 51), 22, Ink.MUTED)
		help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _offer_card(offer: Dictionary, rect: Rect2, market: bool) -> Button:
	var effect: Dictionary = offer.effect
	var outer := Ink.folio(_page, rect, Color("181317f4"), Color("87694d"))
	var card_w := rect.size.x
	var art_h := 253.0 if market else 295.0
	var category := _offer_type(offer)
	var type := Ink.label(outer, category, Rect2(24, 19, card_w - 48, 33), 17, Ink.RUST if offer.category == "survival" else Ink.COPPER)
	type.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := Ink.label(outer, str(offer.title), Rect2(24, 51, card_w - 48, 62), 35, Ink.PAPER, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Ink.one_line(title)
	title.tooltip_text = title.text
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	var artwork_size := Vector2(card_w - 50, art_h - 2)
	var texture := _offer_art(effect, artwork_size.x / artwork_size.y)
	Ink.box(outer, Rect2(24, 124, card_w - 48, art_h), Color("141214"), Ink.RULE)
	var artwork_rect := Rect2(Vector2(25, 125), artwork_size)
	if texture != null:
		Ink.texture(outer, texture, artwork_rect)
	else:
		var genre := Ink.label(outer, tr("P9_OFFER_CENSER_MARK"), artwork_rect, 68, Color("778d81"), true)
		genre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Ink.ruling(outer, Rect2(31, 128 + art_h, card_w - 62, 18))
	var text := _offer_description(offer)
	var desc := Ink.label(outer, text, Rect2(32, 155 + art_h, card_w - 64, 108), 21, Ink.PAPER, true)
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.max_lines_visible = 4
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.tooltip_text = text
	desc.mouse_filter = Control.MOUSE_FILTER_PASS
	var picker: OptionButton
	var ids: Array[String] = []
	var offer_id := str(offer.id)
	if offer.get("requires_target", false):
		var pick_label := tr("P5_MUTATION_TARGET" if effect.kind == "mutate" else "P9_NIGHT_EFFECT_TARGET")
		Ink.label(outer, pick_label, Rect2(26, rect.size.y - 159, card_w - 52, 30), 17, Ink.MUTED)
		picker = OptionButton.new()
		picker.name = ("target_" + offer_id).validate_node_name()
		picker.position = Vector2(24, rect.size.y - 126)
		picker.size = Vector2(card_w - 48, 41)
		picker.fit_to_longest_item = false
		picker.add_theme_font_size_override("font_size", 18)
		outer.add_child(picker)
		for unit in host.run.target_options(offer_id):
			ids.append(str(unit.uid))
			picker.add_item(tr("P5_TARGET_OPTION") % [_unit_name(str(unit.id)), ids.size(), unit.hp, unit.max_hp])
		if ids.is_empty():
			picker.add_item(tr("P5_NO_TARGET"))
			picker.disabled = true
		target_picker = picker
		target_pickers[offer_id] = picker
	var allowed := bool(offer.get("allowed", true))
	var cost := tr("P11R_MARKET_PRICE") % offer.cost if market else tr("P5_TAKE")
	var action_text := cost if allowed else tr(str(offer.get("reason", "P5_NOT_ENOUGH")))
	if market and not allowed and picker == null:
		var price := Ink.label(outer, tr("P5_COST") % offer.cost, Rect2(27, rect.size.y - 113, card_w - 54, 31), 18, Ink.COPPER)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var suffix := "buy_" if market else "reward_"
	var action := Ink.button(outer, suffix + offer_id, action_text, Rect2(24, rect.size.y - 72, card_w - 48, 52), _choose_offer.bind(offer_id, market, picker, ids), allowed, true)
	buttons[suffix + offer_id] = action
	if picker != null and not picker.disabled:
		action.focus_neighbor_top = action.get_path_to(picker)
		picker.focus_neighbor_bottom = picker.get_path_to(action)
	return action

func _offer_type(offer: Dictionary) -> String:
	var effect: Dictionary = offer.effect
	match str(effect.kind):
		"recruit":
			var source := Data.get_unit(str(effect.unit_id))
			var faction := str(source.get("谱系", source.get("所属", "")))
			if not faction.is_empty():
				return faction
			return tr("P9_OFFER_GHOST" if str(effect.unit_id).begins_with("G") else "P9_OFFER_HUMAN")
		"equipment":
			return tr("P9_OFFER_CENSER")
		"mutate":
			return tr("P9_OFFER_MUTATION")
		"growth_item":
			var item: Dictionary = Data.growth_rules.items.get(str(effect.id), {})
			return tr("P9_OFFER_" + str(item.get("slot", "job")).to_upper())
		"growth_material":
			return tr("P9_OFFER_MATERIAL")
	return tr("P5_CATEGORY_" + str(offer.category).to_upper())

func _offer_art(effect: Dictionary, aspect: float) -> Texture2D:
	var unit_id := str(effect.get("unit_id", effect.get("form_id", "")))
	if not unit_id.is_empty():
		var portrait := Appearance.portrait_texture(unit_id)
		if portrait != null:
			var size := portrait.get_size()
			var view := AtlasTexture.new()
			view.atlas = portrait
			view.region = Rect2(0, 0, size.x, minf(size.x / aspect, size.y))
			view.filter_clip = true
			return view
	match str(effect.kind):
		"equipment":
			return Ink.object_art(0)
		"recruit":
			return Ink.ritual_art(4)
		"mutate":
			return Ink.object_art(3)
		"growth_material":
			return Ink.object_art(1)
		"recover":
			return Ink.ritual_art(5)
		"stats":
			return Ink.ritual_art(2)
		"growth_item":
			var item: Dictionary = Data.growth_rules.items.get(str(effect.id), {})
			match str(item.get("slot", "")):
				"censer": return Ink.censer_art(str(effect.id))
				"nameplate": return Ink.ritual_art(2)
				"art": return Ink.ritual_art(1)
	return Ink.object_art(1)

func _offer_description(offer: Dictionary) -> String:
	var effect: Dictionary = offer.effect
	match str(effect.kind):
		"recruit":
			var source := Data.get_unit(str(effect.unit_id))
			var post := tr(str(effect.post).to_upper()) if str(effect.post) != "ghost_main_path" else tr("P9_OFFER_TIDE")
			return tr("P9_OFFER_NEW_UNIT") % [effect.count, post, source.get("生命", "0"), source.get("攻击", "0"), source.get("防御", "0"), source.get("速度", "0")]
		"growth_item":
			var item: Dictionary = Data.growth_rules.items.get(str(effect.id), {})
			if item.is_empty():
				return str(offer.description)
			var detail := str(item.get("description", offer.description))
			if item.get("status", "") != "active":
				return detail + "\n" + tr("P9_OFFER_ITEM_PENDING")
			return detail + "\n" + (tr("P7_ITEM_FEES") % [item.get("equip_cost", 0), item.get("remove_cost", 0)])
		"growth_material":
			return tr("P9_OFFER_MATERIAL_EFFECT")
		"mutate":
			var source := Data.get_unit(str(effect.form_id))
			return tr("P9_OFFER_MUTATION_EFFECT") % [_unit_name(str(effect.form_id)), source.get("生命", "0"), source.get("攻击", "0"), source.get("防御", "0"), source.get("速度", "0")]
		"recover":
			var state: Dictionary = host.run.state
			var incense_gain := minf(float(effect.incense), float(host.run.config.incense_cap) - float(state.incense))
			var names_gain := minf(float(effect.names), float(host.run.config.names_cap) - float(state.names))
			return tr("P9_OFFER_RECOVERY_EFFECT") % [incense_gain, names_gain, effect.heal]
	return str(offer.description)

func _choose_offer(id: String, market: bool, picker: OptionButton, ids: Array[String]) -> void:
	var target := ""
	if picker != null and picker.selected >= 0 and picker.selected < ids.size():
		target = ids[picker.selected]
	if market:
		host.buy_offer(id, target)
	else:
		host.select_reward(id, target)

func _event() -> void:
	var node: Dictionary = host.run.current_node()
	heading.text = str(node.title)
	Ink.box(_page, Rect2(352, 256, 1216, 638), Color("121b1cf5"), Ink.RULE)
	Ink.label(_page, str(node.description), Rect2(424, 282, 1072, 98), 28, Ink.PAPER, true)
	var choices: Array = host.run.event_options()
	for index in choices.size():
		var choice: Dictionary = choices[index]
		var detail := str(choice.get("description", ""))
		if not choice.get("allowed", true):
			detail = tr(str(choice.get("reason", "P5_INVALID_CHOICE")))
		var action := _button("event_" + str(choice.id), str(choice.title) + "\n" + detail, Rect2(424, 414 + index * 145, 1072, 113), host.resolve_event.bind(str(choice.id)), bool(choice.get("allowed", true)))
		if _focus == null and not action.disabled:
			_focus = action

func _rest() -> void:
	heading.text = tr("P9_NIGHT_REST")
	Ink.box(_page, Rect2(400, 278, 1120, 566), Color("121b1cf5"), Ink.RULE)
	var reserves: Array = host.run.rest_reserve_options()
	_focus = _button("rest", tr("P5_REST"), Rect2(702, 698, 516, 64), host.finish_rest, true, true)
	if not reserves.is_empty() and host.run.state.roster.size() == 1:
		var guard: Dictionary = host.run.state.roster[0]
		_focus.text = tr("NIGHT_REST_HEAL_SOLO") % [_unit_name(guard.id),guard.hp,host.run.rest_health_after(guard)]
	if reserves.is_empty() or host.run.state.roster.size() >= 2:
		Ink.label(_page, str(host.run.current_node().description), Rect2(477, 324, 966, 86), 31, Ink.PAPER, true)
		if host.run.state.has("opening_faction") and host.run.state.mode=="shouxiang" and host.run.state.roster.size()>=2:
			var help := "集中疗伤只治疗一人，本次放弃补给。"
			if not reserves.is_empty(): help += " 请援占用本次休整，全队不回血、不领补给。"
			Ink.label(_page,help,Rect2(477,418,966,46),22,Ink.MUTED)
			var rows := Ink.scroll_rows(_page,Rect2(477,470,966,154 if not reserves.is_empty() else 190),4)
			rows.name = "RestHealthForecast"
			for unit in host.run.state.roster:
				var line := HBoxContainer.new()
				rows.add_child(line)
				var face := TextureRect.new()
				face.texture = Appearance.bust_texture(unit.id)
				face.custom_minimum_size = Vector2(58,40)
				face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				line.add_child(face)
				var hp := Label.new()
				var after: float = host.run.rest_health_after(unit)
				hp.text = "%s　休整 %.2f → %.2f / %.0f" % [_unit_name(unit.id),unit.hp,after,unit.max_hp]
				hp.add_theme_font_size_override("font_size",22)
				line.add_child(hp)
				if host.run.treatment_health_after(unit)>after:
					var care := Button.new()
					care.text = "集中疗伤至 %.2f · %d香火" % [host.run.treatment_health_after(unit),host.run.config.rest.treatment_cost]
					care.add_theme_font_size_override("font_size",22)
					care.disabled = not host.run.can_treat(unit)
					care.pressed.connect(host.treat_at_rest.bind(unit.uid))
					line.add_child(care)
			if not reserves.is_empty():
				for i in reserves.size():
					var option: Dictionary = reserves[i]
					var unit: Dictionary = Data.get_unit(option.id)
					var caption := "%s · %s · %d香火" % [_unit_name(option.id),unit["定位"],option.cost]
					var button := _button("reserve_"+str(option.id),caption,Rect2(477+i*486,635,474,52),host.finish_rest.bind(option.id),option.allowed)
					button.icon = Appearance.bust_texture(option.id)
					button.add_theme_constant_override("icon_max_width",48)
					button.tooltip_text = "%s · %s" % [tr(str(option.post).to_upper()),unit["专属技能"]]
			_focus.tooltip_text = tr("P5_REST_HELP")
		else:
			Ink.label(_page, tr("P5_REST_HELP"), Rect2(477, 490, 966, 116), 22, Ink.MUTED)
		return
	Ink.label(_page, tr("NIGHT_REST_RESERVE_TITLE" if host.run.state.roster.is_empty() else "NIGHT_REST_LAST_GUARD") % host.run.state.opening_faction, Rect2(466,305,980,62),34,Ink.PAPER,true)
	Ink.label(_page, tr("NIGHT_REST_RESERVE_HELP") % int(host.run.state.incense),Rect2(466,373,990,50),22,Ink.MUTED)
	var recruit_buttons: Array[Button] = []
	var regroup_buttons: Array[Button] = []
	for i in reserves.size():
		var option: Dictionary = reserves[i]
		var unit: Dictionary = Data.get_unit(option.id)
		var x := 461 + i * 510
		Ink.box(_page, Rect2(x,444,487,204), Color("1d2020"), Ink.RULE)
		Ink.texture(_page, _offer_art(option.effect,0.84), Rect2(x+8,452,124,147))
		Ink.label(_page,"生命 %s" % unit["生命"],Rect2(x+12,601,123,36),18,Ink.PAPER)
		Ink.label(_page,"%s · %s" % [unit["姓名"],unit["定位"]],Rect2(x+145,454,330,48),26,Ink.PAPER,true)
		var skill := Ink.label(_page,str(unit["专属技能"]),Rect2(x+145,507,326,85),20,Ink.MUTED)
		skill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var caption := tr("NIGHT_REST_RESERVE_BUY" if option.allowed else "NIGHT_REST_RESERVE_SHORT") % option.cost
		var hire := _button("reserve_"+str(option.id),caption,Rect2(x+145,593,323,45),host.finish_rest.bind(option.id),option.allowed)
		if option.allowed:
			hire.focus_neighbor_bottom = hire.get_path_to(_focus)
			recruit_buttons.append(hire)
		if option.can_regroup:
			var label := "请援并调%s至%s · %d香火" % [_unit_name(host.run.state.roster[0].id),tr(str(option.post).to_upper()),option.cost]
			var paired := _button("regroup_"+str(option.id),label,Rect2(x,647,487,44),host.finish_rest.bind(option.id,true),option.allowed)
			if option.allowed:
				hire.focus_neighbor_bottom = hire.get_path_to(paired)
				paired.focus_neighbor_top = paired.get_path_to(hire)
				paired.focus_neighbor_bottom = paired.get_path_to(_focus)
				regroup_buttons.append(paired)
	_link_horizontal(recruit_buttons)
	_link_horizontal(regroup_buttons)
	if not regroup_buttons.is_empty():
		_focus.focus_neighbor_top = _focus.get_path_to(regroup_buttons[0])
	elif not recruit_buttons.is_empty():
		_focus.focus_neighbor_top = _focus.get_path_to(recruit_buttons[0])

func _mercy() -> void:
	heading.text = tr("P5_MERCY_TITLE")
	Ink.box(_page, Rect2(400, 266, 1120, 582), Color("121b1cf5"), Ink.RULE)
	var summary: Dictionary = host.run.summary()
	var reason_text := tr(summary.reason)
	if host.run.state.mode=="duoming" and summary.reason=="P4_END_DAYBREAK":
		reason_text = "天亮前未能夺下名册。"
	Ink.label(_page, reason_text, Rect2(478, 330, 964, 74), 28, Ink.RUST)
	Ink.label(_page, tr("P5_MERCY_HELP"), Rect2(478, 418, 964, 120), 23, Ink.MUTED)
	var interruption: Dictionary = host.run.state.last_battle.get("register_break",{})
	if not interruption.is_empty():
		var cause := "占领中天亮"
		if not interruption.get("at_dawn",false):
			cause = "房内已无攻方" if interruption.attackers==0 else "守方入房："+"、".join(interruption.guards)
		var line := "最佳夺册 %.2f / %.0f 秒　·　第 %.1f 秒　·　%s" % [interruption.peak,interruption.required,interruption.seconds,cause]
		Ink.label(_page,line,Rect2(478,478,964,52),22,Ink.PAPER)
	var detail := _recent_loss()
	if not detail.is_empty():
		Ink.label(_page,detail,Rect2(478,530,964,86),22,Ink.PAPER)
	_focus = _button("mercy", tr("P5_MERCY"), Rect2(556, 626, 390, 64), host.use_mercy, true, true)
	_button("decline", tr("P5_DECLINE"), Rect2(970, 626, 390, 64), host.leave_node)

func _recent_loss() -> String:
	var latest: Dictionary = {}
	var victim := ""
	for member in host.run.state.last_battle.get("fallen",[]):
		var hit = member.get("fatal_hit")
		if hit is Dictionary and hit.has_all(["seconds","source","damage","hp_before","kind","room"]) and hit.seconds >= latest.get("seconds",0):
			latest = hit
			victim = _unit_name(member.id)
	if latest.is_empty(): return ""
	var who := _unit_name(latest.source) if not str(latest.source).is_empty() else "无来源记录"
	var location := "名册房 · " if latest.room == "register" else ""
	var kind := str({"melee":"近战","charge":"冲撞","physical":"攻击","projectile":"远击"}.get(latest.kind,"攻击"))
	return "%.2f秒　%s%s阵亡 · %s%s %.2f，受击前生命 %.2f" % [latest.seconds,location,victim,who,kind,latest.damage,latest.hp_before]

func _summary() -> void:
	var summary: Dictionary = host.run.summary()
	var victory: bool = summary.outcome == "victory"
	var story: Dictionary = summary.get("story", {})
	var ending_id := str(story.get("ending", ""))
	var ending: Dictionary = Story.rules().get("endings", {}).get(ending_id, {})
	heading.text = tr("P5_END_TITLE")
	var accent := Ink.COPPER if victory else Ink.RUST
	Ink.folio(_page, Rect2(397, 190, 1126, 715), Color("171317e6"), Color("88674e"))
	var art := Ink.object_art(2) if not victory else (Ink.object_art(1) if ending_id in ["E01", "E03"] else Ink.ritual_art(3))
	if art != null:
		var artwork := Rect2(843, 210, 234, 173)
		Ink.box(_page, artwork, Color("121013"))
		Ink.texture(_page, art, artwork, false)
		if ending_id == "E03":
			var name_ink := Ink.label(Ink.folio(_page, Rect2(1020, 303, 72, 71), Color("6c3428")), tr("P11_UNIT_H01_NAME"), Rect2(1, 1, 70, 69), 45, Ink.PAPER, true)
			name_ink.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_metric(tr("P9_NIGHT_INCENSE"), float(summary.incense), Rect2(462, 231, 260, 131))
	_summary_metric(tr("P9_NIGHT_NAMES"), float(summary.names), Rect2(1196, 231, 260, 131))
	Ink.ruling(_page, Rect2(479, 372, 962, 18), accent)

	var title := tr(ending.title_key) if not ending.is_empty() else tr("P5_VICTORY" if victory else "P5_DEFEAT")
	var ending_title := Ink.label(_page, title, Rect2(483, 387, 954, 60), 46, accent, true)
	ending_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var outcome_reason: String = summary.reason
	if victory and not summary.battles.is_empty():
		outcome_reason = str(summary.battles[-1].reason)
	var outcome := tr(outcome_reason)
	var details_text := ""
	var cause := ""
	if not ending.is_empty():
		details_text = tr(ending.text_key)
		match ending_id:
			"E01": cause = tr("P11R_RESTORE_CAUSE")
			"E02": cause = tr("P11R_RELEASE_CAUSE") % summary.names
			"E03": cause = tr("P11R_SELF_CAUSE") % [story.self_listing.names_paid, story.self_listing.max_hp_after]
	elif not victory:
		cause = _erase_line(summary)
		if story.get("seize_finished_here", false):
			details_text = tr("P11_STORY_SEIZE_COMPLETE")
	elif story.get("seize_finished_here", false):
		details_text = tr("P11_STORY_SEIZE_COMPLETE")
	elif not story.is_empty() and summary.mode == "shouxiang":
		details_text = tr("P11_STORY_OPEN_END")
	if not details_text.is_empty():
		var passage := Ink.label(_page, details_text, Rect2(502, 448, 916, 71), 24, Ink.PAPER, true)
		passage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not cause.is_empty():
		var context := Ink.label(_page, cause, Rect2(503, 526, 914, 62), 21, accent)
		context.name = "EndingCause"
		context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var reason := Ink.label(_page, outcome, Rect2(497, 592, 926, 38), 19, Ink.MUTED)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Ink.ruling(_page, Rect2(479, 637, 962, 16), Ink.RULE)
	_summary_roster(tr("P9_NIGHT_STILL_LISTED"), summary.roster, Rect2(492, 660, 398, 166), Ink.COPPER)
	_summary_roster(tr("P5_DEAD"), summary.fallen, Rect2(1029, 660, 398, 166), Ink.RUST)
	Ink.box(_page, Rect2(960, 669, 1, 151), Ink.RULE)
	var departed: Array = summary.get("departed", [])
	if not departed.is_empty():
		var text := tr("P7_DEPARTED") % "  /  ".join(_unit_names(departed))
		var field := Ink.label(_page, text, Rect2(471, 829, 978, 24), 17, Ink.MUTED)
		field.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Ink.one_line(field)
		field.mouse_filter = Control.MOUSE_FILTER_PASS
		field.tooltip_text = text
	var ticks := roundi(float(summary.elapsed) * 10.0)
	var duration := tr("P11R_DURATION") % [floori(float(ticks) / 600.0), float(ticks % 600) / 10.0]
	var time := Ink.label(_page, duration, Rect2(523, 866, 874, 26), 18, Ink.MUTED)
	time.name = "BattleDuration"
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var seed := Ink.label(_page, tr("P5_SEED") % summary.seed, Rect2(66, 927, 587, 48), 18, Ink.MUTED)
	Ink.one_line(seed)
	seed.mouse_filter = Control.MOUSE_FILTER_PASS
	seed.tooltip_text = str(summary.seed)
	_button("copy_seed", tr("P5_COPY_SEED"), Rect2(662, 924, 226, 55), host.copy_seed)
	_button("replay_seed", tr("P6_REPLAY_THIS_SEED"), Rect2(902, 924, 270, 55), host.open_observer.bind(str(summary.seed)))
	_button("map_history", tr("P9_NIGHT_BACK_ROUTE"), Rect2(1186, 924, 251, 55), _switch_report.bind(true))
	_focus = _button("menu", tr("P9_NIGHT_BACK_TITLE"), Rect2(1451, 924, 262, 55), host.show_intro, true, true)

func _erase_line(summary: Dictionary) -> String:
	var id := str(summary.get("killer_id", ""))
	if str(summary.reason) == "P4_END_DAYBREAK":
		return tr("P9_NIGHT_ERASED_BY_TIME")
	return tr("P9_NIGHT_ERASED_UNKNOWN") if id.is_empty() else tr("P8_ERASED_BY") % [_unit_name(id), id]

func _summary_metric(caption: String, value: float, rect: Rect2) -> void:
	var plate := Ink.folio(_page, rect, Color("261c1cf0"))
	var name := Ink.label(plate, caption, Rect2(0, 12, rect.size.x, 43), 27, Ink.COPPER, true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var metric := Ink.label(plate, "%.1f" % value, Rect2(0, 59, rect.size.x, 59), 45, Ink.PAPER, true)
	metric.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _summary_roster(caption: String, records: Array, rect: Rect2, color: Color) -> void:
	var header := Ink.label(_page, caption, Rect2(rect.position, Vector2(rect.size.x, 36)), 27, color, true)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rows := Ink.scroll_rows(_page, Rect2(rect.position + Vector2(0, 43), Vector2(rect.size.x, rect.size.y - 43)), 4)
	var line := Label.new()
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.text = "　/　".join(_unit_names(records))
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 21)
	line.add_theme_color_override("font_color", Ink.PAPER)
	rows.add_child(line)

func _unit_name(id: String) -> String:
	var data := Data.get_unit(id)
	return Codex.unit_text(id, "NAME", str(data.get("姓名", data.get("名称", id))))

func _unit_names(records: Array) -> Array[String]:
	var counts: Dictionary = {}
	for unit in records:
		var title := _unit_name(str(unit.id))
		counts[title] = int(counts.get(title, 0)) + 1
	var results: Array[String] = []
	for title in counts:
		results.append(tr("P9_NIGHT_ROSTER_MULTIPLE") % [title, counts[title]] if counts[title] > 1 else title)
	if results.is_empty():
		results.append(tr("P5_NONE"))
	return results

func _switch_report(history: bool) -> void:
	_history = history
	render()

func _button(id: String, text: String, rect: Rect2, action: Callable, allowed := true, accent := false) -> Button:
	var control := Ink.button(_page, id, text, rect, action, allowed, accent)
	buttons[id] = control
	return control

func _link_horizontal(controls: Array[Button]) -> void:
	controls.sort_custom(func(a: Button, b: Button) -> bool: return a.global_position.x < b.global_position.x)
	for index in controls.size():
		if index > 0:
			controls[index].focus_neighbor_left = controls[index].get_path_to(controls[index - 1])
		if index + 1 < controls.size():
			controls[index].focus_neighbor_right = controls[index].get_path_to(controls[index + 1])

func _focus_default(key: String) -> void:
	var candidate: Button = buttons.get(key, _focus)
	if is_instance_valid(candidate) and candidate.is_visible_in_tree() and not candidate.disabled:
		candidate.grab_focus()
		return
	if is_instance_valid(_focus) and _focus.is_visible_in_tree():
		_focus.grab_focus()
