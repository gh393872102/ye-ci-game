extends CanvasLayer
## Player decisions are input only. BattleSession owns validation, payment and settlement.
const Card = preload("res://src/ui/UnitCardContent.gd")
const Ink = preload("res://src/ui/LedgerInk.gd")
const Appearance = preload("res://src/units/UnitAppearance.gd")
const PAPER := Color("e6dfcc")
const MUTED := Color("aab5ac")
const COPPER := Color("c7b78e")
const ALERT := Color("f1ad91")
const PURCHASE_PAGE_SIZE := 3
const DRAG_THRESHOLD := 12.0
const ACTION_RECT := Rect2(558, 712, 1338, 273)
const PURCHASE_RECT := Rect2(1225, 510, 668, 476)
const DEPLOY_RECT := Rect2(1179, 720, 714, 268)
const UPGRADE_RECT := Rect2(83, 152, 594, 487)
const PORTRAIT_RECT := Rect2(83, 141, 1036, 784)
const RITUAL_INTERRUPTS := ["P4_RITUAL_INTERRUPTED_DAMAGE", "P4_RITUAL_INTERRUPTED_MOVEMENT",
	"CHANNEL_RETREAT", "CHANNEL_CANCELLED", "CHANNEL_BROKEN"]
const SHOU_COMMANDS := [
	["BUY", "P9_BUY_COMMAND"], ["DEPLOY", "P9_DEPLOY_COMMAND"], ["UPGRADE", "P9_UPGRADE_COMMAND"],
	["REGISTER_ACTION", "P9_RITUAL_COMMAND"], ["REPAIR", "P9_REPAIR_COMMAND"], ["EQUIPMENT", "P9_EQUIPMENT_COMMAND"]
]
const DUO_COMMANDS := [
	["UPGRADE", "P9_MUTATE_COMMAND"], ["REGISTER_ACTION", "P9_FUSION_COMMAND"], ["BUY", "P9_REINFORCE_COMMAND"]
]
var managed_by_night := false
var preferred_faction := ""
var observation_mode := false
var replay_read_only := false
var simulation: Node2D
var world: Node2D
var camera: Camera2D
var session: Node
var selected: Node2D
var panel: PanelContainer
var content: VBoxContainer
var details: RichTextLabel
var panel_scroll: ScrollContainer
var host: Control
var selection_layer: Control
var drag_origin := Vector2.INF
var drag_tip := Vector2.INF
var selected_group: Array[Node2D] = []
var valid_post_hover := ""
var legal_ritual_targets: Array[Node2D] = []
var purchase_page := 0
var recruitable_faction_only := false
var paused_before_purchase := true
var offer_status: Dictionary = {}
var target_hint: Label
var warning_plate: PanelContainer
var register_warning_plate: PanelContainer
var register_warning: Label
var activity_plate: PanelContainer
var channel_progress: ProgressBar
var active_channels: Array[RefCounted] = []
var interruption := ""
var interruption_left := 0.0
var portrait: TextureRect
var feedback: Label
var activity: Label
var warnings: Label
var prebattle: PanelContainer
var ending: PanelContainer
var buttons: Dictionary = {}
var highlights: Node2D
var current_panel := ""
var caster: Node2D
var last_result := ""
var legal_post_ids: Array[String] = []
var unit_panel: PanelContainer
var refresh_left := 0.0
var growth_panel: CanvasLayer
var portrait_note: Label
var skill_target_ids: Array[String] = []
var skill_target_picker: OptionButton
var skill_mode_picker: OptionButton

class PurchaseFigure extends Node2D:
	var unit_id := ""
	var side := "xianghuo"
	var height_px := 80.0
	var hit_flash := 0.0
	var current_speed := 0.0
	var attack_left := 0.0
	var ai_state := "Idle"
	var dead := false
	var simulation: Node2D
	var roster := {}
	func _draw() -> void:
		Appearance.draw(self)

func _ready() -> void:
	layer = 8
	host = Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.theme = preload("res://resources/p9_theme.tres")
	add_child(host)
	panel = _panel(host, ACTION_RECT)
	panel_scroll = ScrollContainer.new()
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_scroll.follow_focus = true
	panel.add_child(panel_scroll)
	scroll_style(panel_scroll.get_v_scroll_bar())
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	panel_scroll.add_child(content)
	panel.hide()
	unit_panel = _panel(host, PORTRAIT_RECT)
	unit_panel.hide()
	feedback = _label(host, "", 17)
	feedback.position = Vector2(558, 1050)
	feedback.size = Vector2(1338, 24)
	feedback.clip_text = true
	feedback.add_theme_color_override("font_color", COPPER)

	warning_plate = _notice_plate(Rect2(24, 75, 376, 40), Color("a57b51"), Color("dbc8aa"))
	warnings = _label(warning_plate, "", 23)
	warnings.add_theme_font_override("font", Ink.serif_font())
	warnings.add_theme_color_override("font_color", Color("281c19"))
	warning_plate.hide()

	register_warning_plate = _notice_plate(Rect2(1502, 75, 392, 40), Color("a76a4d"), Color("642820"))
	register_warning = _label(register_warning_plate, "", 24)
	register_warning.add_theme_font_override("font", Ink.serif_font())
	register_warning.add_theme_color_override("font_color", Ink.PAPER)
	register_warning_plate.hide()

	activity_plate = _notice_plate(Rect2(1516, 72, 380, 30), Color("897750"))
	var activity_column := VBoxContainer.new()
	activity_column.add_theme_constant_override("separation", 6)
	activity_plate.add_child(activity_column)
	activity = _label(activity_column, "", 21)
	activity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	channel_progress = ProgressBar.new()
	channel_progress.max_value = 1.0
	channel_progress.show_percentage = false
	channel_progress.custom_minimum_size.y = 10
	channel_progress.add_theme_stylebox_override("background", Ink.skin(Color("1c1418"), Ink.RULE))
	channel_progress.add_theme_stylebox_override("fill", Ink.skin(Color("c67c51"), Ink.COPPER))
	channel_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	activity_column.add_child(channel_progress)
	activity_plate.hide()

	selection_layer = Control.new()
	selection_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_layer.draw.connect(_draw_selection_box)
	host.add_child(selection_layer)
	prebattle = _panel(host, Rect2(632, 224, 656, 360))
	var intro := VBoxContainer.new()
	intro.add_theme_constant_override("separation", 18)
	prebattle.add_child(intro)
	_label(intro, tr("P4_PRETITLE"), 32)
	_label(intro, tr("P4_PREHELP"), 20)
	_button(intro, "shouxiang", tr("P4_START_SHOUXIANG"), func(): start_battle("shouxiang"))
	_button(intro, "duoming", tr("P4_START_DUOMING"), func(): start_battle("duoming"))
	_label(intro, tr("P4_SHOU_OBJECTIVE") + "\n" + tr("P4_DUO_OBJECTIVE"), 18)
	_focus_first(intro)
	ending = _panel(host, Rect2(632, 220, 656, 440))
	ending.hide()
	highlights = Node2D.new()
	highlights.name = "DeploymentHighlights"
	highlights.z_index = 30
	highlights.draw.connect(_draw_highlights)
	world.add_child(highlights)
	Clock.set_paused(true)
	growth_panel = preload("res://src/ui/GrowthPanel.gd").new()
	growth_panel.name = "GrowthPanel"
	growth_panel.decisions = self
	add_child(growth_panel)

func _panel(parent: Node, rect: Rect2) -> PanelContainer:
	var result := PanelContainer.new()
	result.position = rect.position
	result.size = rect.size
	var skin := Ink.skin(Color("161216f9"), Color("846449"), 2)
	skin.set_content_margin_all(16)
	result.add_theme_stylebox_override("panel", skin)
	parent.add_child(result)
	if rect.size.x >= 520 and rect.size.y >= 200:
		result.draw.connect(func(): Ink.draw_binding(result, result.size, Color("836247")))
	return result

func _notice_plate(rect: Rect2, rule_color: Color, paper := Color("1c1517f6")) -> PanelContainer:
	var plate := _panel(host, rect)
	plate.custom_minimum_size.x = rect.size.x
	plate.z_index = 4
	var skin := Ink.skin(paper, rule_color, 2)
	skin.set_content_margin_all(11)
	skin.content_margin_left = 17
	plate.add_theme_stylebox_override("panel", skin)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return plate

func scroll_style(bar: ScrollBar) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("28342f")
	track.content_margin_left = 3
	track.content_margin_right = 3
	var handle := track.duplicate() as StyleBoxFlat
	handle.bg_color = Color("73684e")
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for style in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(style, handle)

func _label(parent: Node, text: String, font_size := 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", PAPER)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, id: String, text: String, callback: Callable, allowed := true, reason := "") -> Button:
	var button := Button.new()
	button.name = id.validate_node_name()
	button.text = text
	button.custom_minimum_size.y = 42
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = not allowed
	button.tooltip_text = tr(reason) if not reason.is_empty() else text
	button.pressed.connect(callback)
	Ink.button_ink(button, false)
	parent.add_child(button)
	buttons[id] = button
	return button

func start_battle(mode: String) -> void:
	var answer: Dictionary = session.start_battle(mode)
	if not answer.ok:
		_feedback(answer)
		return
	_clear_selected()
	close_panel()
	prebattle.hide()
	ending.hide()
	last_result = ""
	active_channels.clear()
	interruption_left = 0.0
	feedback.text = tr("P4_SHOU_OBJECTIVE" if mode == "shouxiang" else "P4_DUO_OBJECTIVE")
	Clock.set_paused(false)

func _clear_content(title: String) -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	panel_scroll.scroll_vertical = 0
	offer_status.clear()
	target_hint = null
	var rect: Rect2 = {"purchase":PURCHASE_RECT, "deploy":DEPLOY_RECT, "upgrade":UPGRADE_RECT}.get(current_panel, ACTION_RECT)
	panel.position = rect.position
	panel.size = rect.size
	if not title.is_empty():
		var heading := _label(content, title, 32)
		heading.add_theme_color_override("font_color", Ink.COPPER)
		heading.add_theme_font_override("font", Ink.serif_font())
	panel.show()
	Clock.set_paused(true)

func _panel_header(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var heading := _label(row, title, 29)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_color_override("font_color", Ink.COPPER)
	heading.add_theme_font_override("font", Ink.serif_font())
	return row

func _clear_selected() -> void:
	if is_instance_valid(selected):
		selected.selected = false
		selected.queue_redraw()
	selected = null
	for unit in selected_group:
		if is_instance_valid(unit):
			unit.selected = false
			unit.queue_redraw()
	selected_group.clear()
	unit_panel.hide()

func close_panel() -> void:
	if growth_panel != null:
		growth_panel.close()
	if not read_only() and not session.pending_purchase.is_empty():
		_issue("cancel_purchase")
	current_panel = ""
	legal_post_ids.clear()
	legal_ritual_targets.clear()
	valid_post_hover = ""
	panel.hide()
	unit_panel.hide()
	caster = null
	highlights.queue_redraw()

func show_command(id: String) -> void:
	if not _can_command() or _blocked():
		return
	var guard := view_seat() == "shouxiang"
	match id:
		"BUY":
			open_purchase() if guard else open_reinforce()
		"DEPLOY":
			if guard:
				if session.pending_purchase.is_empty():
					open_purchase()
					feedback.text = tr("P9_NEED_PURCHASE")
				else:
					current_panel = "deploy"
					_build_deploy()
		"UPGRADE":
			open_upgrade() if guard else open_mutation()
		"REGISTER_ACTION":
			if guard:
				open_ritual()
			elif growth_enabled():
				if is_instance_valid(selected) and selected.side == "yegui":
					open_growth("fusions")
				else:
					feedback.text = tr("P4_SELECT_GHOST")
			else:
				feedback.text = tr("P4_FUSION_PENDING")
		"REPAIR":
			open_repair()
		"EQUIPMENT":
			if guard and not _owned_selected():
				feedback.text = tr("P4_SELECT_HUMAN")
			elif growth_enabled():
				open_growth()
			elif guard:
				open_upgrade()

func open_commands() -> void:
	if not _can_command():
		return
	if not session.pending_purchase.is_empty():
		show_command("DEPLOY")
		return
	close_panel()
	current_panel = "commands"
	_clear_content(tr("P9_COMMANDS"))
	_label(content, tr("P9_COMMAND_MENU_HELP"), 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	for entry in SHOU_COMMANDS if view_seat() == "shouxiang" else DUO_COMMANDS:
		var button := _button(row, "command_" + entry[0], tr(entry[1]), show_command.bind(entry[0]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "close", tr("P9_BATTLE_CLOSE"), close_panel)
	_focus_first(row)

func open_purchase() -> void:
	if not _can_command() or view_seat() != "shouxiang":
		return
	close_panel()
	paused_before_purchase = Clock.paused
	purchase_page = 0
	recruitable_faction_only = false
	current_panel = "purchase"
	_build_purchase()

func _build_purchase() -> void:
	_clear_content("")
	var offers: Array = _query("purchase_options")
	if recruitable_faction_only:
		offers = offers.filter(func(offer):
			return offer.allowed and Data.get_unit(offer.id).get("所属", "") == preferred_faction and not _query("legal_posts", {"id":offer.id}).is_empty()
		)
	offers.sort_custom(func(a, b):
		var first := str(a.id)
		var second := str(b.id)
		if not preferred_faction.is_empty():
			var first_same: bool = Data.get_unit(first).get("所属","") == preferred_faction
			var second_same: bool = Data.get_unit(second).get("所属","") == preferred_faction
			if first_same != second_same: return first_same
		if first.begins_with("T") != second.begins_with("T"):
			return first.begins_with("T")
		return first < second
	)
	var pages := maxi(1, ceili(offers.size() / float(PURCHASE_PAGE_SIZE)))
	purchase_page = clampi(purchase_page, 0, pages - 1)
	var nav := _panel_header(tr("P4_BUY_TITLE"))
	if not preferred_faction.is_empty():
		_button(nav, "purchase_scope", "看全部" if recruitable_faction_only else "可招同司", _toggle_purchase_scope)
	_button(nav, "purchase_prev", tr("P9_PAGE_PREV"), _purchase_page.bind(-1), purchase_page > 0)
	_label(nav, tr("P9_PAGE_COUNT") % [purchase_page + 1, pages], 17)
	_button(nav, "purchase_next", tr("P9_PAGE_NEXT"), _purchase_page.bind(1), purchase_page + 1 < pages)
	_button(nav, "close", tr("P9_BATTLE_CLOSE"), close_panel)
	var page_offers := offers.slice(purchase_page * PURCHASE_PAGE_SIZE, (purchase_page + 1) * PURCHASE_PAGE_SIZE)
	var hint := _label(content, tr("P9_PURCHASE_HELP"), 16)
	if not preferred_faction.is_empty():
		if recruitable_faction_only:
			hint.text = "%s · 当前可买且有空岗的援军 %d 人" % [preferred_faction, offers.size()]
			if offers.is_empty(): hint.text += "。可返回全部查看缺香、满员等原因。"
		else:
			hint.text = "%s优先 · %s" % [preferred_faction,hint.text]
		if page_offers.any(func(offer): return offer.id == "H19"):
			hint.text += "　问灯会临时收编野鬼。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Ink.MUTED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	for offer in page_offers:
		_purchase_card(row, offer)
	if not _focus_first(row):
		_focus_first(nav)

func _purchase_card(row: HBoxContainer, offer: Dictionary) -> void:
	var id: String = offer.id
	var data: Dictionary = Data.get_unit(id)
	var profile: Dictionary = Data.combat_profiles.get(id, {})
	var plate := _panel(row, Rect2())
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.custom_minimum_size.x = 195
	var skin: StyleBoxFlat = plate.get_theme_stylebox("panel").duplicate()
	skin.bg_color = Color("21191a")
	skin.set_content_margin_all(8)
	plate.add_theme_stylebox_override("panel", skin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	plate.add_child(column)
	var name := _label(column, Card.format(id).title, 25)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_override("font", Ink.serif_font())
	var illustration := ColorRect.new()
	illustration.custom_minimum_size.y = 126
	illustration.color = Color("130f13")
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(illustration)
	var figure := PurchaseFigure.new()
	figure.unit_id = id
	figure.height_px = 110.0
	illustration.add_child(figure)
	illustration.resized.connect(func(): figure.position = Vector2(illustration.size.x / 2, 119))
	if not preferred_faction.is_empty():
		var specialty := _label(illustration, str(data.get("定位","")), 16)
		specialty.set_position(Vector2(4, 0))
		specialty.add_theme_constant_override("outline_size",4)
		specialty.add_theme_color_override("font_outline_color",Color("130f13"))
	var stats := _label(column, tr("P9_PURCHASE_STATS") % [data.get("生命", "?"), data.get("攻击", "?"), data.get("防御", "?"), float(profile.get("range_body", 1))], 16)
	stats.add_theme_color_override("font_color", Ink.PAPER)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var caption := _label(column, tr("P4_AVAILABLE") if offer.allowed else tr(offer.reason), 15)
	caption.clip_text = true
	caption.add_theme_color_override("font_color", COPPER if offer.allowed else MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	offer_status[id] = caption
	var button := _button(column, "buy_" + id, tr("P9_PAY_INCENSE") % offer.cost, _purchase.bind(id), offer.allowed, offer.reason)
	button.add_theme_font_size_override("font_size", 18)
	button.custom_minimum_size.y = 36

func _toggle_purchase_scope() -> void:
	recruitable_faction_only = not recruitable_faction_only
	purchase_page = 0
	_build_purchase()
	buttons["purchase_scope"].grab_focus()

func _purchase_page(direction: int) -> void:
	purchase_page += direction
	_build_purchase()

func _purchase(id: String) -> void:
	var answer: Dictionary = _issue("purchase", {"id":id})
	_feedback(answer)
	if answer.ok:
		current_panel = "deploy"
		_build_deploy()

func _build_deploy() -> void:
	legal_post_ids.assign(_query("legal_posts", {"id":session.pending_purchase}))
	_clear_content("")
	var header := _panel_header(tr("P4_DEPLOY_TITLE") % Data.get_unit(session.pending_purchase).get("姓名", ""))
	if not preferred_faction.is_empty() and "post_register" in legal_post_ids:
		_button(header, "defend_register", "守名册房 · 余%d位" % session.post_vacancies("post_register"), select_post.bind("post_register", true))
	_button(header, "close", tr("P9_BATTLE_CLOSE"), _cancel_purchase)
	var hint := _label(content, tr("P9_DEPLOY_HELP"), 17)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", MUTED)
	target_hint = _label(content, tr("P9_DEPLOY_NO_POST") if legal_post_ids.is_empty() else "", 17)
	target_hint.add_theme_color_override("font_color", COPPER)
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	content.add_child(row)
	for post in world.posts:
		var id := str(post.name)
		if not world.can_deploy_at(id):
			continue
		var reason: String = session.deployment_reason(id, session.pending_purchase)
		var text: String = tr(id.to_upper())
		if not preferred_faction.is_empty() and reason.is_empty():
			text += " · 余%d位" % session.post_vacancies(id)
		if not reason.is_empty():
			text += " · " + tr(reason)
		var button := _button(row, "post_" + id, text, select_post.bind(id), reason.is_empty(), reason)
		button.custom_minimum_size.x = 325
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_size_override("font_size", 17)
		button.focus_entered.connect(_focus_post.bind(id))
	if not _focus_first(row):
		_focus_first(header)
	highlights.queue_redraw()

func _cancel_purchase() -> void:
	close_panel()
	feedback.text = tr("P4_CANCELLED")

func _focus_post(id: String) -> void:
	valid_post_hover = id
	_set_target_hint(tr("P9_DEPLOY_AVAILABLE") % tr(id.to_upper()), true)
	highlights.queue_redraw()

func _set_target_hint(value: String, legal := false) -> void:
	if is_instance_valid(target_hint):
		target_hint.text = value
		target_hint.add_theme_color_override("font_color", COPPER if legal else ALERT)

func select_post(post_id: String, quick := false) -> void:
	var answer: Dictionary = _issue("deploy_at", {"post_id":post_id})
	_feedback(answer)
	if answer.ok:
		close_panel()
		if quick:
			feedback.text = "%s已到名册房" % answer.unit.display_name
			Clock.set_paused(paused_before_purchase)
		elif answer.has("unit"):
			select_unit(answer.unit)
	else:
		_set_target_hint(feedback.text)

func select_unit(unit: Node2D) -> void:
	if not is_instance_valid(unit) or unit.dead or not session.active:
		return
	if not read_only() and current_panel == "ritual" and unit.side == "yegui":
		_ritual_target(unit)
		return
	close_panel()
	_clear_selected()
	selected = unit
	selected.selected = true
	selected.queue_redraw()
	Clock.set_paused(true)
	current_panel = "unit"
	_build_card()

func _build_card() -> void:
	for child in unit_panel.get_children():
		unit_panel.remove_child(child)
		child.queue_free()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	unit_panel.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	var image_column := VBoxContainer.new()
	image_column.custom_minimum_size.x = 452
	row.add_child(image_column)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(452, 655)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var path := "res://assets/portraits/%s.svg" % selected.unit_id
	var image: Texture2D = preload("res://src/units/UnitAppearance.gd").portrait_texture(selected.unit_id) if roster_enabled() else null
	if image == null and not selected.unit_id.begins_with("T") and ResourceLoader.exists(path):
		image = load(path)
	if image != null:
		portrait.texture = image
		if roster_enabled():
			var material := ShaderMaterial.new()
			material.shader = preload("res://assets/portraits/p8/face_state.gdshader")
			var appearance: Dictionary = preload("res://src/units/UnitAppearance.gd").describe(selected.unit_id)
			var region: Array = appearance.get("face_region", [.34, .055, .32, .22])
			material.set_shader_parameter("face_region", Vector4(region[0], region[1], region[2], region[3]))
			material.set_shader_parameter("native_faceless", appearance.get("default_face", "faced") == "faceless")
			portrait.material = material
	else:
		image_column.hide()
	image_column.add_child(portrait)
	Ink.binding(portrait, Rect2(1, 1, 450, 653), Color("876349"))
	portrait_note = _label(image_column, tr("P4_PORTRAIT_NOTE"), 16)
	portrait_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	portrait_note.add_theme_color_override("font_color", MUTED)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 9)
	row.add_child(right)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_font_size_override("normal_font_size", 21)
	details.add_theme_font_override("bold_font", Ink.serif_font())
	details.add_theme_color_override("default_color", PAPER)
	details.add_theme_constant_override("line_separation", 4)
	scroll_style(details.get_v_scroll_bar())
	right.add_child(details)
	_refresh_card()

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 7)
	column.add_child(actions)
	if not read_only() and view_seat() == "shouxiang" and selected.side == "xianghuo":
		_button(actions, "card_upgrade", tr("P9_UPGRADE_COMMAND"), open_upgrade)
		if selected.role == "ritual":
			_button(actions, "card_ritual", tr("P9_RITUAL_COMMAND"), open_ritual)
	elif not read_only() and view_seat() == "duoming" and selected.side == "yegui":
		_button(actions, "card_mutate", tr("P9_MUTATE_COMMAND"), open_mutation)
	if roster_enabled() and not read_only() and _owned_selected() and not selected.unit_id.begins_with("T"):
		_button(actions, "card_skill", tr("P8_SKILL_BUTTON"), open_unit_skill)
	if roster_enabled() and not read_only() and view_seat() == "shouxiang" and selected.side == "yegui":
		_button(actions, "card_mark", tr("P8_MARK_TARGET"), _mark_selected)
	if growth_enabled():
		_button(actions, "card_growth", tr("P7_GROWTH_OPEN"), open_growth)
	_button(actions, "close", tr("P9_BATTLE_CLOSE"), close_panel)
	unit_panel.show()
	_focus_first(actions)

func _refresh_card() -> void:
	if not is_instance_valid(selected) or not is_instance_valid(details):
		return
	var info := Card.format(selected.unit_id, selected)
	var body: String = "\n\n".join([
		"[font_size=53][color=#e7c496][b]%s[/b][/color][/font_size]\n[color=#c8b596]%s　·　%s[/color]" % [info.title, info.affiliation, tr("P11R_CARD_FOLIO") % selected.unit_id],
		"[font_size=21][color=#e3c39e]%s[/color][/font_size]" % info.stats,
		info.skill, info.trait, info.slots,
		"[color=#bcb29e]%s\n%s[/color]" % [info.tags, info.state]
	])
	if details.text != body:
		var offset: float = details.get_v_scroll_bar().value
		details.text = body
		details.get_v_scroll_bar().set_deferred("value", offset)
	if roster_enabled() and not selected.unit_id.begins_with("T"):
		var state: String = preload("res://src/units/UnitAppearance.gd").face_state(selected)
		if portrait.material is ShaderMaterial:
			portrait.material.set_shader_parameter("face_hidden", state == "faceless")
		portrait_note.text = tr("P8_FACE_FACELESS" if state == "faceless" else "P8_FACE_FACED")

func roster_enabled() -> bool:
	var engine = session.get("roster")
	return engine != null and bool(engine.get("enabled"))

func _owned_selected() -> bool:
	return is_instance_valid(selected) and not selected.dead and selected.side == ("xianghuo" if view_seat() == "shouxiang" else "yegui")

func _mark_selected() -> void:
	if not _can_command() or not is_instance_valid(selected): return
	_feedback(_issue("mark_target",{"target_id":selected.instance_id}))

func open_unit_skill() -> void:
	if not _can_command() or not _owned_selected() or not roster_enabled(): return
	if selected.unit_id == "H01":
		open_ritual()
		return
	current_panel = "unit_skill"
	_clear_content(tr("P8_SKILL_TITLE") % selected.display_name)
	_label(content,selected.skill_text,18)
	_label(content,tr("P8_SKILL_HELP"),17)
	if selected.unit_id == "H28":
		var market: Dictionary = Data.roster_rules.abilities.H28
		var item: Dictionary = Data.growth_rules.items.get(str(market.market_item),{})
		_label(content,tr("P8_MARKET_PRICE") % [item.get("name",market.market_item),selected.skill_cost,market.market_price,float(selected.skill_cost)+float(market.market_price)],18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	content.add_child(row)
	skill_target_picker = OptionButton.new()
	skill_target_picker.custom_minimum_size = Vector2(470,42)
	skill_target_ids.clear()
	skill_target_ids.append("")
	skill_target_picker.add_item(tr("P8_TARGET_AUTO"))
	for target in simulation.humans + simulation.targets:
		if target.dead: continue
		skill_target_ids.append(target.instance_id)
		skill_target_picker.add_item(tr("P8_TARGET_ROW") % [target.display_name,target.unit_id,target.hp])
	row.add_child(skill_target_picker)
	skill_mode_picker = OptionButton.new()
	for key in ["P8_SKILL_MODE","P8_SKILL_PULL","P8_SKILL_PUSH"]: skill_mode_picker.add_item(tr(key))
	row.add_child(skill_mode_picker)
	_button(row,"skill_auto",tr("P8_SKILL_AUTO"),_cast_selected_skill.bind(true))
	_button(row,"skill_cast",tr("P8_SKILL_CAST"),_cast_selected_skill.bind(false))
	if selected.unit_id == "H28":
		skill_target_picker.hide()
		skill_mode_picker.hide()
		buttons.skill_auto.hide()
		buttons.skill_cast.hide()
		_button(row,"skill_market",tr("P8_MARKET_CONFIRM"),_cast_selected_skill.bind(true,true))
	_button(row,"close",tr("P9_BATTLE_CLOSE"),close_panel)
	_focus_first(row)

func _cast_selected_skill(automatic: bool, confirm_market := false) -> void:
	if not _can_command() or not _owned_selected(): return
	var args := {"unit_id":selected.instance_id}
	if not automatic and skill_target_picker.selected > 0: args.target_id = skill_target_ids[skill_target_picker.selected]
	if skill_mode_picker.selected > 0: args.mode = ["auto","pull","push"][skill_mode_picker.selected]
	if confirm_market: args.confirm_market = true
	_feedback(_issue("unit_skill",args))
	_refresh_card()

func open_upgrade() -> void:
	if not _can_command() or view_seat() != "shouxiang":
		return
	if not _owned_selected():
		feedback.text = tr("P4_SELECT_HUMAN")
		return
	if not session.pending_purchase.is_empty():
		close_panel()
	unit_panel.hide()
	current_panel = "upgrade"
	var preview: Dictionary = _query("preview_upgrade", {"unit_id":selected.instance_id})
	_clear_content(selected.display_name)
	var current := _label(content, Card.format(selected.unit_id, selected).stats, 22)
	current.add_theme_color_override("font_color", Ink.COPPER)
	var plate := _panel(content, Rect2())
	var prospect := HBoxContainer.new()
	prospect.add_theme_constant_override("separation", 15)
	plate.add_child(prospect)
	var ember := TextureRect.new()
	ember.texture = Ink.ritual_art(3)
	ember.custom_minimum_size = Vector2(61, 61)
	ember.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ember.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prospect.add_child(ember)
	var forecast := _label(prospect, tr("P4_UPGRADE_PREVIEW") % [preview.cost, preview.current_hp, preview.next_hp, preview.current_defense, preview.next_defense], 21)
	forecast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forecast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	forecast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_show_upgrade_slots()
	var row := HBoxContainer.new()
	content.add_child(row)
	_button(row, "upgrade_confirm", tr("P4_CONFIRM_UPGRADE"), _upgrade, preview.allowed, preview.reason)
	if not preview.allowed:
		_label(content, tr(preview.reason), 18)
	if growth_enabled():
		_button(row, "growth", tr("P9_EQUIPMENT_COMMAND"), open_growth)
	else:
		var gear: Dictionary = session.rules.equipment
		_label(content, tr("P4_GEAR_DETAIL") % [gear.hp, gear.defense], 17)
		_button(row, "equip", tr("P4_EQUIP") % gear.cost, _equip, available_incense() >= gear.cost and str(selected.get("equipment_id")).is_empty())
	_button(row, "close", tr("P9_BATTLE_CLOSE"), close_panel)
	for button in row.get_children():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_focus_first(row)

func _show_upgrade_slots() -> void:
	var loadout: Dictionary = selected.growth.get("slots", {})
	var arts: Array = loadout.get("arts", ["", ""])
	var slots := [loadout.get("censer", ""), arts[0], arts[1], loadout.get("nameplate", "")]
	var labels := ["P7_SLOT_CENSER", "P7_SLOT_ART_ONE", "P7_SLOT_ART_TWO", "P7_SLOT_NAMEPLATE"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for index in labels.size():
		var plate := _panel(grid, Rect2())
		plate.custom_minimum_size = Vector2(260, 82)
		var slot := VBoxContainer.new()
		plate.add_child(slot)
		var heading := _label(slot, tr(labels[index]), 17)
		heading.add_theme_color_override("font_color", Ink.COPPER)
		var id := str(slots[index])
		var item: Dictionary = Data.growth_rules.items.get(id, {})
		_label(slot, tr("P4_EMPTY") if id.is_empty() else str(item.get("name", id)), 21)

func _upgrade() -> void:
	_feedback(_issue("upgrade", {"unit_id":selected.instance_id}))
	open_upgrade()
	_refresh_card()

func _equip() -> void:
	_feedback(_issue("equip", {"unit_id":selected.instance_id}))
	open_upgrade()
	_refresh_card()

func open_ritual() -> void:
	if not _can_command() or view_seat() != "shouxiang":
		return
	var chosen_caster: Node2D
	if _owned_selected() and not selected.dead and selected.role == "ritual":
		chosen_caster = selected
	else:
		for human in simulation.humans:
			if not human.dead and human.role == "ritual":
				chosen_caster = human
				break
	close_panel()
	caster = chosen_caster
	if caster == null:
		feedback.text = tr("P9_RITUAL_NO_CASTER")
		return
	current_panel = "ritual"
	_clear_content(tr("P4_RITUAL_TITLE"))
	_label(content, tr("P9_RITUAL_HELP") % caster.display_name, 18)
	target_hint = _label(content, tr("P9_RITUAL_PICK"), 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var picker := OptionButton.new()
	picker.custom_minimum_size.x = 535
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	var first_blocker := ""
	for target in simulation.targets:
		if target.dead:
			continue
		var condition := _ritual_preview(target)
		if not condition.reason.is_empty():
			if first_blocker.is_empty():
				first_blocker = tr(condition.hint)
			continue
		legal_ritual_targets.append(target)
		picker.add_item(tr("P4_RITUAL_TARGET") % [target.display_name, target.hp, target.position.distance_to(caster.position) / Rules.BODY_PX])
	var has_targets := not legal_ritual_targets.is_empty()
	picker.disabled = not has_targets
	if not has_targets:
		picker.add_item(tr("P4_NO_TARGETS"))
		_set_target_hint(first_blocker if not first_blocker.is_empty() else tr("P9_RITUAL_PICK"))
	else:
		_show_ritual_preview(legal_ritual_targets[0])
		picker.select(0)
		picker.item_selected.connect(func(index: int): _show_ritual_preview(legal_ritual_targets[index]))
	_button(row, "ritual_confirm", tr("P9_RITUAL_COMMAND"), func():
		if picker.selected >= 0 and picker.selected < legal_ritual_targets.size():
			_ritual_target(legal_ritual_targets[picker.selected])
	, has_targets)
	_button(row, "close", tr("P9_BATTLE_CLOSE"), close_panel)
	_focus_first(row)
	highlights.queue_redraw()

func _ritual_preview(target: Node2D) -> Dictionary:
	if not is_instance_valid(caster) or caster.dead or not is_instance_valid(target):
		return {"reason":"P4_INVALID_RITUAL", "hint":"P9_RITUAL_NO_CASTER"}
	return _query("preview_ritual", {"caster_id":caster.instance_id, "target_id":target.instance_id})

func _show_ritual_preview(target: Node2D) -> void:
	var preview := _ritual_preview(target)
	if preview.reason.is_empty():
		_set_target_hint(tr("P9_RITUAL_PREVIEW") % [target.display_name, preview.duration, preview.cost], true)
	else:
		_set_target_hint(tr(preview.hint))

func _ritual_target(target: Node2D) -> void:
	var preview := _ritual_preview(target)
	if not preview.reason.is_empty():
		_set_target_hint(tr(preview.hint))
		return
	var answer: Dictionary = _issue("start_ritual", {"caster_id":caster.instance_id, "target_id":target.instance_id})
	_feedback(answer)
	if answer.ok:
		if not active_channels.has(caster.brain.channel):
			active_channels.append(caster.brain.channel)
		close_panel()
		feedback.text = tr("P9_RITUAL_STARTED")
	else:
		_set_target_hint(feedback.text)

func open_repair() -> void:
	if not _can_command() or view_seat() != "shouxiang":
		return
	close_panel()
	current_panel = "repair"
	_clear_content(tr("P4_REPAIR_TITLE"))
	_label(content, tr("P4_REPAIR_HELP"), 18)
	var row := GridContainer.new()
	row.columns = 4
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 6)
	content.add_child(row)
	var repair_cost := int(session.rules.get("repair", {}).get("cost", 5))
	for door in world.doors:
		var text: String = tr("P4_REPAIR_DOOR") % [tr(str(door.name).to_upper()), door.durability, door.max_durability, repair_cost]
		var button := _button(row, "repair_" + str(door.name), text, _repair.bind(str(door.name)), door.durability < door.max_durability and available_incense() >= repair_cost)
		button.custom_minimum_size.x = 290
		button.add_theme_font_size_override("font_size", 17)
	_button(row, "close", tr("P9_BATTLE_CLOSE"), close_panel)
	_focus_first(row)

func _repair(id: String) -> void:
	_feedback(_issue("repair", {"door_id":id}))
	open_repair()

func open_mutation() -> void:
	if not _can_command() or view_seat() != "duoming":
		return
	if not selected_group.is_empty():
		_open_batch_mutation()
		return
	if not _owned_selected():
		feedback.text = tr("P4_SELECT_GHOST")
		return
	if growth_enabled():
		open_growth("forms")
		return
	current_panel = "mutation"
	_clear_content(tr("P4_MUTATE_TITLE") % selected.display_name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",24)
	content.add_child(row)
	for id in ["G09", "G12"]:
		var data: Dictionary = Data.get_unit(id)
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 480
		row.add_child(column)
		_label(column, tr("P4_MUTATION_PREVIEW") % [data.get("名称", id), data["生命"], data["攻击"], data["防御"], data["速度"]], 18)
		var preview: Dictionary = _query("preview_mutation", {"unit_id":selected.instance_id,"form_id":id})
		_button(column, "mutate_" + id, tr("P4_MUTATE_" + id) % preview.cost, _mutate.bind(id), preview.allowed, preview.reason)
		if not preview.allowed:
			_label(column, tr(preview.reason), 17)
	_label(content, tr("P4_FUSION_PENDING"), 17)
	_button(row, "close", tr("P9_BATTLE_CLOSE"), close_panel)
	_focus_first(row)

func _mutate(id: String) -> void:
	var answer: Dictionary = _issue("mutate", {"unit_id":selected.instance_id,"form_id":id})
	_feedback(answer)
	if answer.ok:
		if answer.has("unit"):
			select_unit(answer.unit)
		else:
			close_panel()

func _open_group(units: Array[Node2D]) -> void:
	close_panel()
	_clear_selected()
	selected_group.assign(units)
	for unit in selected_group:
		unit.selected = true
		unit.queue_redraw()
	_show_group()

func _show_group() -> void:
	current_panel = "group"
	_clear_content(tr("P9_GROUP_TITLE") % selected_group.size())
	var ghosts := _group_ghosts()
	var total_ghosts := 0
	for unit in selected_group:
		if is_instance_valid(unit) and unit.side == "yegui":
			total_ghosts += 1
	_label(content, tr("P9_GROUP_COUNT") % [selected_group.size(), selected_group.size() - total_ghosts, total_ghosts], 18)
	_label(content, tr("P9_GROUP_HELP"), 17).add_theme_color_override("font_color", MUTED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for unit in selected_group:
		picker.add_item(tr("P8_TARGET_ROW") % [unit.display_name, unit.unit_id, unit.hp])
	row.add_child(picker)
	_button(row, "group_card", tr("P9_GROUP_VIEW"), func():
		if picker.selected >= 0 and picker.selected < selected_group.size():
			select_unit(selected_group[picker.selected])
	, not selected_group.is_empty())
	if _can_command() and view_seat() == "duoming":
		_button(row, "group_mutate", tr("P9_GROUP_MUTATE"), _open_batch_mutation, not ghosts.is_empty(), "P9_GROUP_NO_GHOST" if ghosts.is_empty() else "")
	_button(row, "close", tr("P9_BATTLE_CLOSE"), close_panel)
	_focus_first(row)

func _group_ghosts() -> Array[Node2D]:
	var ghosts: Array[Node2D] = []
	for unit in selected_group:
		if is_instance_valid(unit) and not unit.dead and unit.side == "yegui":
			ghosts.append(unit)
	return ghosts

func _open_batch_mutation() -> void:
	var ghosts := _group_ghosts()
	if ghosts.is_empty():
		feedback.text = tr("P9_GROUP_NO_GHOST")
		return
	current_panel = "batch"
	_clear_content(tr("P9_GROUP_MUTATE"))
	_label(content, tr("P9_BATCH_HELP"), 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var forms: Dictionary = Data.growth_rules.mutations if growth_enabled() else session.rules.mutations
	for id in forms:
		var form: Dictionary = forms[id] if growth_enabled() else {"name":Data.get_unit(id).get("名称", id), "cost":forms[id]}
		if form.get("status", "active") != "active":
			continue
		var count := 0
		var funds := available_incense()
		var first_reason := ""
		for unit in ghosts:
			var reason := _mutation_reason(unit, id, funds)
			if reason.is_empty():
				count += 1
				funds -= float(form.cost)
			elif first_reason.is_empty():
				first_reason = reason
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		_button(column, "batch_" + id, tr("P9_BATCH_FORM") % [form.name, form.cost, count, ghosts.size()], _mutate_group.bind(id), count > 0, first_reason)
		if count == 0 and not first_reason.is_empty():
			_label(column, tr(first_reason), 16).add_theme_color_override("font_color", MUTED)
	_button(row, "group_back", tr("P9_BATTLE_CLOSE"), _show_group)
	_focus_first(row)

func _mutation_reason(unit: Node2D, id: String, funds: float) -> String:
	if growth_enabled():
		return session.growth.mutation_reason(unit, id, funds)
	var preview: Dictionary = _query("preview_mutation", {"unit_id":unit.instance_id, "form_id":id})
	if funds < float(preview.cost):
		return "P4_NO_INCENSE"
	return preview.reason

func _mutate_group(id: String) -> void:
	if not _can_command() or view_seat() != "duoming":
		return
	Clock.set_paused(true)
	var ghosts := _group_ghosts()
	var changed := 0
	var first_reason := ""
	for unit in ghosts:
		var action := "mutate_form" if growth_enabled() else "mutate"
		var answer := _issue(action, {"unit_id":unit.instance_id, "form_id":id})
		if answer.ok:
			changed += 1
		elif first_reason.is_empty():
			first_reason = tr(answer.reason)
	feedback.text = tr("P9_BATCH_RESULT") % [changed, ghosts.size()]
	if not first_reason.is_empty():
		feedback.text += " " + first_reason
	_open_batch_mutation()

func open_reinforce() -> void:
	if not _can_command() or view_seat() != "duoming":
		return
	close_panel()
	current_panel = "reinforce"
	_clear_content(tr("P4_COMMAND_REINFORCE"))
	var rule: Dictionary = session.rules.reinforce
	_label(content, tr("P4_REINFORCE_INFO") % [rule.count, maxi(0, int(rule.limit) - session.reinforce_count), session.reinforce_left])
	var reason := ""
	if session.reinforce_count >= int(rule.limit):
		reason = "P4_REINFORCE_LIMIT"
	elif session.reinforce_left > 0:
		reason = "P4_REINFORCE_COOLDOWN"
	elif available_incense() < float(rule.cost):
		reason = "P4_NO_INCENSE"
	var row := HBoxContainer.new()
	content.add_child(row)
	_button(row, "reinforce", tr("P4_REINFORCE") % rule.cost, reinforce, reason.is_empty(), reason)
	if not reason.is_empty():
		_label(content, tr(reason), 18)
	_button(row, "close", tr("P9_BATTLE_CLOSE"), close_panel)
	_focus_first(row)

func reinforce() -> void:
	if not _can_command() or view_seat() != "duoming":
		return
	Clock.set_paused(true)
	_feedback(_issue("reinforce"))
	open_reinforce()

func view_seat() -> String:
	return str(session.player_seat) if observation_mode else str(session.mode)

func read_only() -> bool:
	return observation_mode and (replay_read_only or view_seat().is_empty())

func available_incense() -> float:
	return float(session.incense_for(view_seat())) if observation_mode else float(session.incense)

func _find_unit(id: String) -> Node2D:
	for unit in simulation.humans + simulation.targets:
		if unit.instance_id == id: return unit
	return null

func _query(action: String, args: Dictionary = {}):
	if observation_mode:
		var answer: Dictionary = session.execute_for(view_seat(), action, args, "player")
		return answer.get("data", [] if action in ["purchase_options","legal_posts"] else {})
	match action:
		"purchase_options": return session.purchase_options()
		"legal_posts": return session.legal_posts(str(args.get("id", "")))
		"preview_upgrade": return session.preview_upgrade(_find_unit(args.unit_id))
		"preview_mutation": return session.preview_mutation(_find_unit(args.unit_id), args.form_id)
		"preview_ritual": return session.preview_ritual(_find_unit(args.caster_id), _find_unit(args.target_id))
	return {}

func _issue(action: String, args: Dictionary = {}) -> Dictionary:
	if read_only(): return {"ok":false,"reason":"P6_READ_ONLY"}
	if observation_mode or action in ["equip_item","unequip_item","mutate_form","fuse","stamp_job","borrow_god","use_key","unit_skill","mark_target"]:
		return session.execute_for(view_seat(), action, args, "player")
	match action:
		"purchase": return session.purchase(args.id)
		"deploy_at": return session.deploy_at(args.post_id)
		"cancel_purchase": return session.cancel_purchase()
		"upgrade": return session.upgrade(_find_unit(args.unit_id))
		"equip": return session.equip(_find_unit(args.unit_id))
		"start_ritual": return session.start_ritual(_find_unit(args.caster_id), _find_unit(args.target_id))
		"repair": return session.repair(args.door_id)
		"mutate": return session.mutate(_find_unit(args.unit_id), args.form_id)
		"reinforce": return session.reinforce()
	return {"ok":false,"reason":"P6_READ_ONLY"}

func _can_command() -> bool:
	return not read_only() and session.active and session.running and session.result.is_empty()

func _feedback(answer: Dictionary) -> void:
	feedback.text = tr(answer.get("reason", "P4_SUCCESS"))
	if answer.ok and feedback.text.is_empty():
		feedback.text = tr("P4_SUCCESS")

func _focus_first(parent: Node) -> bool:
	for child in parent.get_children():
		if child is Button and child.visible and not child.disabled:
			child.grab_focus()
			return true
		if child is Control and child.visible and _focus_first(child):
			return true
	return false

func _show_ending() -> void:
	close_panel()
	_clear_selected()
	for child in ending.get_children():
		ending.remove_child(child)
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	ending.add_child(box)
	_label(box, tr("P4_END_VICTORY" if session.result.outcome == "victory" else "P4_END_DEFEAT"), 34)
	_label(box, tr("P4_END_DETAILS") % [tr("P4_SEAT_" + session.mode.to_upper()), tr(session.result.reason), session.incense, session.names, session.remaining], 22)
	_button(box, "retry", tr("P4_RETRY"), func(): start_battle(session.mode))
	_button(box, "seats", tr("P4_SEAT_MENU"), func(): ending.hide(); prebattle.show(); _focus_first(prebattle.get_child(0)))
	ending.show()
	Clock.set_paused(true)
	_focus_first(box)

func _process(delta: float) -> void:
	if not session.active:
		prebattle.hide()
		ending.hide()
		panel.hide()
		unit_panel.hide()
		warning_plate.hide()
		register_warning_plate.hide()
		activity_plate.hide()
		active_channels.clear()
		activity.text = ""
		highlights.queue_redraw()
		return
	if session.running:
		prebattle.hide()
		if session.result.is_empty():
			ending.hide()
			last_result = ""
	_watch_channels(delta)
	_update_warnings()
	if managed_by_night:
		prebattle.hide()
		ending.hide()
	if not managed_by_night and not session.result.is_empty() and last_result.is_empty():
		last_result = session.result.reason
		_show_ending()
	if is_instance_valid(selected):
		if selected.dead:
			_clear_selected()
		elif unit_panel.visible:
			_refresh_card()
	if not selected_group.is_empty() and current_panel in ["group", "batch"]:
		var living: Array[Node2D] = []
		for unit in selected_group:
			if is_instance_valid(unit) and not unit.dead:
				living.append(unit)
		if living.size() != selected_group.size():
			selected_group.assign(living)
			if selected_group.is_empty():
				close_panel()
			elif current_panel == "group":
				_show_group()
			else:
				_open_batch_mutation()
	refresh_left -= delta
	if refresh_left <= 0:
		refresh_left = 0.3
		if current_panel == "purchase":
			for offer in _query("purchase_options"):
				var key: String = "buy_" + offer.id
				if offer_status.has(offer.id) and is_instance_valid(buttons.get(key)):
					buttons[key].disabled = not offer.allowed
					buttons[key].tooltip_text = buttons[key].text if offer.allowed else tr(offer.reason)
					offer_status[offer.id].text = tr("P4_AVAILABLE") if offer.allowed else tr(offer.reason)
	if current_panel in ["deploy", "ritual"] or not active_channels.is_empty():
		highlights.queue_redraw()

func _watch_channels(delta: float) -> void:
	var jobs: Array[String] = []
	var watching: Array[RefCounted] = []
	var notice_position := Vector2(1516, 146)
	for unit in simulation.humans:
		if unit.role != "ritual" or unit.dead or not unit.brain.channel.active:
			continue
		var channel: RefCounted = unit.brain.channel
		watching.append(channel)
		if watching.size() == 1:
			channel_progress.value = channel.progress()
			jobs.append(tr("P9_RITUAL_ACTIVE") % unit.display_name)
			jobs.append(tr("P9_RITUAL_PROGRESS") % [channel.elapsed, channel.duration])
			var target: Node2D = channel.target
			if is_instance_valid(target):
				var fit: Vector2 = target.get_global_transform_with_canvas().origin
				if fit.x >= 18 and fit.x <= 1901 and fit.y < 704:
					notice_position = Vector2(clampf(fit.x + 62, 20, 1516), clampf(fit.y - target.height_px - 87, 154, 572))
	for channel in active_channels:
		if not watching.has(channel) and channel.last_result in RITUAL_INTERRUPTS:
			interruption = tr(channel.last_result)
			interruption_left = 5.0
	if not active_channels.is_empty() or not watching.is_empty():
		highlights.queue_redraw()
	active_channels = watching
	interruption_left = maxf(0, interruption_left - delta)
	if not session.repair_jobs.is_empty() and watching.is_empty():
		var job: Dictionary = session.repair_jobs[0]
		jobs.append(tr("P4_REPAIR_JOB") % [tr(str(job.door.name).to_upper()), job.elapsed])
	activity.text = "\n".join(jobs)
	activity_plate.position = notice_position
	channel_progress.visible = not watching.is_empty()
	activity_plate.visible = not jobs.is_empty()
	if activity_plate.visible:
		activity_plate.reset_size()

func _update_warnings() -> void:
	var notices: Array[String] = []
	var register_notices: Array[String] = []
	if session.running:
		for key in session.warnings:
			if key.begins_with("P4_WARN_REGISTER_") or key == "P10_WARN_NAME_SEEP":
				register_notices.append(tr(key))
			elif key != "P4_WARN_UPPER_PRESSURE":
				notices.append(tr(key))
		var upstairs := 0
		for ghost in simulation.targets:
			if not ghost.dead and world.is_upper_floor(ghost.floor_id):
				upstairs += 1
		if upstairs > 0:
			notices.append(tr("P9_WARN_UPPER") % upstairs)
		if session.occupation > 0:
			register_notices.append(tr("P9_WARN_REGISTER_OCCUPIED"))
		if not simulation.humans.any(func(unit): return unit.role == "ritual" and not unit.dead):
			notices.append(tr("P9_WARN_CASTER"))
	if interruption_left > 0:
		notices.append(interruption)
	var next := "\n".join(notices)
	if warnings.text != next:
		warnings.text = next
		warning_plate.reset_size()
	warning_plate.visible = not notices.is_empty()
	var right := "\n".join(register_notices)
	if register_warning.text != right:
		register_warning.text = right
		register_warning_plate.reset_size()
	register_warning_plate.visible = not register_notices.is_empty()

func _draw_highlights() -> void:
	if not session.active:
		return
	if current_panel == "deploy" and not session.pending_purchase.is_empty():
		for id in legal_post_ids:
			if not session.deployment_reason(id, session.pending_purchase).is_empty():
				continue
			var post: Node2D = world.get_node(id)
			var color := PAPER if id == valid_post_hover else COPPER
			var center: Vector2 = post.position - Vector2(0, 11)
			highlights.draw_arc(center, 30, 0, TAU, 40, color, 2)
			highlights.draw_line(center - Vector2(0, 54), center - Vector2(0, 28), color, 2)
			_world_label(tr(id.to_upper()), center - Vector2(0, 69), color)
	elif current_panel == "ritual":
		for target in legal_ritual_targets:
			if not is_instance_valid(target) or target.dead:
				continue
			var center: Vector2 = target.position - Vector2(0, 10)
			highlights.draw_arc(center, 26, 0, TAU, 40, COPPER, 2)
			highlights.draw_line(center - Vector2(0, float(target.height_px) + 14), center - Vector2(0, float(target.height_px) + 5), PAPER, 3)
	for unit in simulation.humans:
		if unit.dead or unit.role != "ritual" or not unit.brain.channel.active:
			continue
		var channel: RefCounted = unit.brain.channel
		var point: Vector2 = unit.position - Vector2(0, float(unit.height_px) + 40)
		var bar := Rect2(point + Vector2(-75, 7), Vector2(150, 8))
		highlights.draw_rect(bar.grow(4), Color("170d11"))
		highlights.draw_rect(bar.grow(3), Color("b59066"), false, 1)
		highlights.draw_rect(bar, Color("4d3129"))
		highlights.draw_rect(Rect2(bar.position, Vector2(bar.size.x * channel.progress(), bar.size.y)), Color("d78259"))

func _world_label(text: String, baseline: Vector2, color: Color) -> void:
	var font: Font = world.font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	highlights.draw_rect(Rect2(baseline.x - width / 2 - 7, baseline.y - 18, width + 14, 22), Color("0b1112ef"))
	highlights.draw_string(font, baseline - Vector2(width / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)

func _draw_selection_box() -> void:
	if drag_origin == Vector2.INF or drag_origin.distance_to(drag_tip) < DRAG_THRESHOLD:
		return
	var rect := Rect2(drag_origin, drag_tip - drag_origin).abs()
	selection_layer.draw_rect(rect, Color(0.69, 0.70, 0.57, 0.12))
	selection_layer.draw_rect(rect, COPPER, false, 1.6)

func _cycle_unit(direction: int) -> void:
	var list: Array = simulation.targets + simulation.humans if view_seat() == "duoming" else simulation.humans + simulation.targets
	list = list.filter(func(unit): return is_instance_valid(unit) and not unit.dead)
	if list.is_empty():
		return
	var index := list.find(selected)
	if index < 0 and direction < 0:
		index = 0
	select_unit(list[posmod(index + direction, list.size())])

func _settings() -> Node:
	return get_tree().root.get_node_or_null("Settings")

func _blocked() -> bool:
	var settings := _settings()
	return settings != null and settings.gameplay_modal_open()

func _pause_menu_open() -> bool:
	var settings := _settings()
	return settings != null and settings.pause_menu_open()

func _input(event: InputEvent) -> void:
	if not session.active or _blocked():
		return
	if drag_origin != Vector2.INF and event is InputEventMouseMotion:
		drag_tip = event.position.clamp(Vector2(0, Rules.TOP_BAR_HEIGHT), Vector2(Rules.DESIGN_WIDTH, Rules.HORIZON_Y))
		selection_layer.queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if drag_origin != Vector2.INF and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_selection(event.position)
		get_viewport().set_input_as_handled()
		return
	if _pause_menu_open():
		return
	# Focused controls consume Space in the GUI pass. Pause and speed own their bindings first.
	if event.is_action_pressed("pause"):
		if session.running and session.result.is_empty():
			Clock.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_one") or event.is_action_pressed("speed_two"):
		Clock.set_speed(2.0 if event.is_action_pressed("speed_two") else 1.0)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not session.active or _blocked():
		return
	if event is InputEventMouseMotion and _on_battlefield(event.position):
		if current_panel in ["deploy", "ritual"]:
			_target_at(event.position, false)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _on_battlefield(event.position) or (not session.running and not read_only()):
			return
		if current_panel in ["deploy", "ritual"]:
			_target_at(event.position, true)
		else:
			drag_origin = event.position
			drag_tip = event.position
		get_viewport().set_input_as_handled()
		return
	if _pause_menu_open():
		return
	if event.is_action_pressed("cancel"):
		if current_panel.is_empty() and not unit_panel.visible and not growth_panel.surface.visible:
			return
		var cancelled: bool = not session.pending_purchase.is_empty()
		close_panel()
		if cancelled:
			feedback.text = tr("P4_CANCELLED")
	elif event.is_action_pressed("select_next") or event.is_action_pressed("select_previous"):
		_cycle_unit(1 if event.is_action_pressed("select_next") else -1)
	elif not _can_command():
		return
	elif event.is_action_pressed("command_wheel"):
		open_commands()
	elif not _command_event(event):
		return
	get_viewport().set_input_as_handled()

func _command_event(event: InputEvent) -> bool:
	var guard := view_seat() == "shouxiang"
	if event.is_action_pressed("buy") or (not guard and event.is_action_pressed("reinforce")):
		show_command("BUY")
	elif event.is_action_pressed("deploy"):
		show_command("DEPLOY")
	elif event.is_action_pressed("upgrade") or (not guard and event.is_action_pressed("mutate")):
		show_command("UPGRADE")
	elif event.is_action_pressed("register") or (not guard and event.is_action_pressed("fusion")):
		show_command("REGISTER_ACTION")
	elif event.is_action_pressed("repair"):
		show_command("REPAIR")
	elif InputMap.has_action("equipment") and event.is_action_pressed("equipment"):
		show_command("EQUIPMENT")
	else:
		return false
	return true

func _on_battlefield(point: Vector2) -> bool:
	return point.y > Rules.TOP_BAR_HEIGHT and point.y < Rules.HORIZON_Y

func _world_point(screen_point: Vector2) -> Vector2:
	return world.get_global_transform_with_canvas().affine_inverse() * screen_point

func _unit_at(point: Vector2, ghosts_only := false) -> Node2D:
	var unit_at: Node2D
	var nearest := INF
	for unit in world.visible_units():
		if unit.dead or (ghosts_only and unit.side != "yegui"):
			continue
		if unit.hit_rect().grow(10).has_point(point):
			var distance: float = unit.aim_point().distance_squared_to(point)
			if distance < nearest:
				unit_at = unit
				nearest = distance
	return unit_at

func _closest_post(point: Vector2) -> String:
	var result := ""
	var nearest := INF
	for post in world.posts:
		var box := Rect2(post.position - Vector2(48, 77), Vector2(96, 87))
		if box.has_point(point):
			var distance: float = post.position.distance_squared_to(point)
			if distance < nearest:
				result = str(post.name)
				nearest = distance
	return result

func _target_at(screen_point: Vector2, apply: bool) -> void:
	var point := _world_point(screen_point)
	if current_panel == "deploy":
		var id := _closest_post(point)
		valid_post_hover = ""
		if not id.is_empty() and world.can_deploy_at(id):
			var reason: String = session.deployment_reason(id, session.pending_purchase)
			if reason.is_empty():
				_focus_post(id)
				if apply:
					select_post(id)
				return
			_set_target_hint(tr(reason))
		elif world.is_outside_gate(point.x):
			_set_target_hint(tr("P9_DEPLOY_OUTSIDE"))
		elif world.is_open_court(point):
			_set_target_hint(tr("P9_DEPLOY_COURT"))
		else:
			_set_target_hint(tr("P9_DEPLOY_COVER"))
		highlights.queue_redraw()
		return
	var target := _unit_at(point, true)
	if target == null:
		_set_target_hint(tr("P9_RITUAL_WAIT_HALL" if point.x < Rules.HALL_X else "P9_RITUAL_PICK"))
	elif apply:
		_ritual_target(target)
	else:
		_show_ritual_preview(target)

func _finish_selection(screen_point: Vector2) -> void:
	var start := drag_origin
	drag_origin = Vector2.INF
	selection_layer.queue_redraw()
	var tip := screen_point.clamp(Vector2(0, Rules.TOP_BAR_HEIGHT), Vector2(Rules.DESIGN_WIDTH, Rules.HORIZON_Y))
	if start.distance_to(tip) < DRAG_THRESHOLD:
		var unit := _unit_at(_world_point(tip))
		if unit != null:
			select_unit(unit)
		return
	var origin := _world_point(start)
	var rect := Rect2(origin, _world_point(tip) - origin).abs()
	var units: Array[Node2D] = []
	for unit in world.visible_units():
		if not unit.dead and rect.intersects(unit.hit_rect()):
			units.append(unit)
	if units.size() == 1:
		select_unit(units[0])
	elif units.size() > 1:
		_open_group(units)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and selection_layer != null:
		drag_origin = Vector2.INF
		selection_layer.queue_redraw()

func growth_enabled() -> bool:
	var engine = session.get("growth")
	return engine != null and bool(engine.enabled)

func open_growth(tab := "equipment") -> void:
	if not growth_enabled() or not is_instance_valid(selected) or selected.dead:
		return
	if not session.pending_purchase.is_empty():
		close_panel()
	growth_panel.open_for(selected, tab)

func growth_slots_text(target: Node2D) -> String:
	return Card.slot_text(target.growth.get("slots", {}), target.equipment_id)

func growth_slots_summary(target: Node2D) -> String:
	var lines := growth_slots_text(target).split("\n")
	return "　".join(lines.slice(1))
