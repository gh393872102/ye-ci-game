extends CanvasLayer
## Read-only record. The store advances after real encounters and outcomes.
signal closed
const Ink = preload("res://src/ui/LedgerInk.gd")
const Appearance = preload("res://src/units/UnitAppearance.gd")
const CardContent = preload("res://src/ui/UnitCardContent.gd")
const Codex = preload("res://src/progression/CodexStore.gd")
const FaceShader = preload("res://assets/portraits/p8/face_state.gdshader")
const ShadowShader = preload("res://assets/portraits/p8/codex_silhouette.gdshader")
const ObjectShader = preload("res://assets/ui/night/object_record.gdshader")
const BOOKS := ["humans", "ghosts", "items", "customs"]

var store: RefCounted
var surface: Control
var buttons: Dictionary = {}
var rows: VBoxContainer
var heading: Label
var details: Label
var note: Label
var portrait: TextureRect
var failure_text: Label
var silhouette: Node2D
var current_book := "humans"
var current_id := ""

var _prior_focus: Control
var _stages: Array[Button] = []
var _stat_plate: ColorRect
var _stage_note: Label
var _affiliation: Label
var _stats: Label
var _history: Control
var _details_scroll: ScrollContainer

class HiddenFigure extends Node2D:
	var unit_id := ""
	var side := "xianghuo"
	var height_px := 80.0
	var hit_flash := 0.0
	var current_speed := 0.0
	var attack_left := 0.0
	var ai_state := "Idle"
	var dead := false
	var simulation: Node2D
	var roster := {"face_state":"faceless"}
	func _draw() -> void:
		preload("res://src/units/UnitAppearance.gd").draw(self)

func setup(value: RefCounted) -> void:
	store = value
	if is_node_ready() and surface.visible:
		show_book(current_book)

func _ready() -> void:
	layer = 40
	surface = Control.new()
	surface.size = Vector2(1920, 1080)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(surface)
	Ink.box(surface, Rect2(0, 0, 1920, 1080), Ink.DARK)
	var backdrop := Ink.art("night-court")
	if backdrop != null:
		Ink.texture(surface, backdrop, Rect2(0, 0, 1920, 1080))
		Ink.box(surface, Rect2(0, 0, 1920, 1080), Color("100c13a8"))
	var cover := Ink.label(surface, tr("P9_CODEX_TITLE"), Rect2(635, 26, 650, 99), 71, Ink.COPPER, true)
	cover.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Ink.ruling(surface, Rect2(643, 119, 634, 19), Ink.COPPER)
	_button(surface, "close", tr("P9_CODEX_RETURN"), Rect2(1668, 53, 188, 47), close)
	Ink.folio(surface, Rect2(69, 158, 1783, 821), Color("141114f8"), Color("8e6e51"))
	Ink.box(surface, Rect2(521, 174, 1, 786), Ink.RULE)
	Ink.box(surface, Rect2(1163, 174, 1, 786), Ink.RULE)
	for index in BOOKS.size():
		var book: String = BOOKS[index]
		var tab := _button(surface, "book_" + book, tr("P8_CODEX_" + book.to_upper()), Rect2(90 + index * 101, 182, 96, 50), show_book.bind(book))
		tab.add_theme_font_override("font", Ink.serif_font())
	var final_tab: Button = buttons.book_customs
	final_tab.focus_neighbor_right = final_tab.get_path_to(buttons.close)
	buttons.close.focus_neighbor_left = buttons.close.get_path_to(final_tab)
	rows = Ink.scroll_rows(surface, Rect2(90, 254, 406, 695), 5)

	heading = Ink.label(surface, "", Rect2(550, 184, 583, 85), 57, Ink.PAPER, true)
	Ink.one_line(heading)
	_affiliation = Ink.label(surface, "", Rect2(552, 272, 582, 36), 21, Ink.MUTED)
	for index in 4:
		var rect := Rect2(549 + 147 * index, 325, 142, 47)
		var tab := _button(surface, "stage_%d" % index, tr("P9_CODEX_STAGE_%d" % index), rect, show_stage.bind(index))
		tab.add_theme_font_size_override("font_size", 18)
		_stages.append(tab)
	_stat_plate = Ink.folio(surface, Rect2(549, 391, 586, 61), Color("2a201df8"))
	_stats = Ink.label(_stat_plate, "", Rect2(16, 12, 554, 38), 19, Ink.COPPER)
	var detail_rows := Ink.scroll_rows(surface, Rect2(550, 478, 582, 440))
	_details_scroll = detail_rows.get_parent() as ScrollContainer
	_details_scroll.focus_mode = Control.FOCUS_ALL
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size", 22)
	details.add_theme_constant_override("line_spacing", 7)
	details.add_theme_color_override("font_color", Ink.PAPER)
	detail_rows.add_child(details)
	for tab in _stages:
		tab.focus_neighbor_bottom = tab.get_path_to(_details_scroll)

	Ink.box(surface, Rect2(1184, 179, 646, 723), Color("100e12"))
	portrait = Ink.texture(surface, null, Rect2(1186, 181, 642, 719), false)
	Ink.binding(surface, Rect2(1184, 179, 646, 723), Color("72563e"))
	silhouette = HiddenFigure.new()
	silhouette.position = Vector2(1508, 846)
	var shadow := ShaderMaterial.new()
	shadow.shader = ShadowShader
	silhouette.material = shadow
	surface.add_child(silhouette)
	note = Ink.label(surface, "", Rect2(1184, 912, 646, 47), 18, Ink.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Ink.box(surface, Rect2(69, 994, 1783, 1), Ink.RULE)
	_stage_note = Ink.label(surface, "", Rect2(70, 1011, 1315, 42), 19, Ink.MUTED)
	var failure_log := _button(surface, "failure_log", tr("P11_CODEX_FAILURE_TITLE"), Rect2(1547, 1007, 305, 46), _show_failures)
	buttons.close.focus_neighbor_bottom = buttons.close.get_path_to(failure_log)
	failure_log.focus_neighbor_top = failure_log.get_path_to(buttons.close)
	_build_failures()
	surface.hide()

func open() -> void:
	if store == null:
		store = Data.get("codex_store")
	if store == null or surface.visible:
		return
	_prior_focus = get_viewport().gui_get_focus_owner()
	Clock.set_paused(true)
	show_book(current_book)
	surface.show()
	_focus_book()

func close() -> void:
	if not is_instance_valid(surface) or not surface.visible:
		return
	_history.hide()
	surface.hide()
	if is_instance_valid(_prior_focus) and _prior_focus.is_visible_in_tree():
		_prior_focus.grab_focus()
	closed.emit()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(surface) or not surface.is_visible_in_tree() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("codex"):
		if _history.visible:
			_hide_failures()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif not _history.visible and _details_scroll.has_focus():
		if event.is_action_pressed("ui_down"):
			_details_scroll.scroll_vertical += 68
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_up"):
			_details_scroll.scroll_vertical -= 68
			get_viewport().set_input_as_handled()

func show_book(book: String) -> void:
	if book not in BOOKS:
		return
	var last_entry := current_id if book == current_book else ""
	current_book = book
	if not is_node_ready() or store == null:
		return
	for key in buttons.keys():
		if str(key).begins_with("entry_"):
			buttons.erase(key)
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for candidate in BOOKS:
		Ink.button_ink(buttons["book_" + candidate], candidate == book)
	var entries: Array = store.entries(book)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var id := str(entry.id)
		var title := tr("P11R_CODEX_ENTRY") % [entry.name, tr("P9_CODEX_STAGE_%d" % int(entry.stage))]
		var button := _button(rows, "entry_" + id, title, Rect2(0, 0, 404, 58), select_entry.bind(id))
		button.custom_minimum_size.y = 58
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_override("font", Ink.serif_font())
		button.add_theme_font_size_override("font_size", 21)
		button.focus_neighbor_left = button.get_path_to(buttons["book_" + book])
		button.focus_neighbor_right = button.get_path_to(_details_scroll)
		if index == 0:
			var tab: Button = buttons["book_" + book]
			tab.focus_neighbor_bottom = tab.get_path_to(button)
			button.focus_neighbor_top = button.get_path_to(tab)
	if not entries.is_empty():
		select_entry(last_entry if buttons.has("entry_" + last_entry) else str(entries[0].id))
	_refresh_failures()

func select_entry(id: String) -> void:
	var entry: Dictionary = store.entry(id)
	if entry.is_empty():
		return
	if buttons.has("entry_" + current_id):
		Ink.button_ink(buttons["entry_" + current_id], false)
	current_id = id
	if buttons.has("entry_" + id):
		Ink.button_ink(buttons["entry_" + id], true)
		_details_scroll.focus_neighbor_left = _details_scroll.get_path_to(buttons["entry_" + id])
	show_stage(int(entry.stage))

func show_stage(stage: int) -> void:
	var entry: Dictionary = store.entry(current_id)
	if entry.is_empty() or stage < 0 or stage > int(entry.stage):
		return
	var known := stage >= 2
	var folio := stage == 3
	var source: Dictionary = entry.source
	heading.text = tr("P9_CODEX_UNKNOWN") if stage == 0 else str(entry.name)
	portrait.hide()
	silhouette.hide()
	portrait.material = null
	portrait.texture = null
	_stat_plate.visible = not folio
	_details_scroll.position.y = 403 if folio else 478
	_details_scroll.size.y = 515 if folio else 440
	_details_scroll.scroll_vertical = 0
	_update_stages(stage, int(entry.stage))
	if folio:
		details.add_theme_font_override("font", Ink.serif_font())
		details.add_theme_font_size_override("font_size", 29)
	else:
		details.remove_theme_font_override("font")
		details.add_theme_font_size_override("font_size", 22)
	if entry.book in ["humans", "ghosts"]:
		_show_figure(entry, stage)
		var card := CardContent.format(current_id)
		_affiliation.text = str(card.affiliation) if known else tr("P9_CODEX_CLASS_PENDING")
		_stats.text = str(card.stats) if known else tr("P9_CODEX_UNKNOWN_STATS")
		if known:
			details.text = "\n\n".join([str(card.skill), str(card.trait), str(card.slots), str(card.tags), tr("P9_CODEX_EQUIPMENT_SCOPE")])
		else:
			details.text = tr("P9_CODEX_CONTENT_PENDING")
	else:
		var is_item: bool = entry.book == "items"
		_affiliation.text = tr("P8_CODEX_ITEMS") if is_item else tr("P8_CODEX_CUSTOMS")
		_stats.text = tr("P9_CODEX_CENSER_SLOT") if is_item else tr("P9_CODEX_CUSTOM_" + str(source.get("kind", "ritual")).to_upper())
		_show_object(is_item, stage, current_id)
		if not known:
			details.text = tr("P9_CODEX_CONTENT_PENDING")
		elif source.get("implemented", true):
			details.text = str(entry.skill_text)
			if is_item:
				details.text += "\n\n" + (tr("P7_ITEM_FEES") % [source.get("equip_cost", 0), source.get("remove_cost", 0)])
		else:
			details.text = tr("P9_CODEX_CUSTOM_PENDING")
	if folio:
		details.text = tr("P9_CODEX_NAMED") + "\n\n" + str(entry.get("epilogue", tr("P9_CODEX_NAMED_RECORD")))

func _show_figure(entry: Dictionary, stage: int) -> void:
	var id := str(entry.id)
	if stage == 0:
		silhouette.unit_id = id
		silhouette.side = "yegui" if id.begins_with("G") else "xianghuo"
		silhouette.height_px = float(Data.roster_rules.get("profiles", {}).get(id, {}).get("height_px", 80))
		silhouette.scale = Vector2.ONE * (415.0 / silhouette.height_px)
		silhouette.queue_redraw()
		silhouette.show()
		note.text = tr("P9_CODEX_SILHOUETTE_CAPTION")
		return
	var art := Appearance.portrait_texture(id)
	if art != null:
		var material := ShaderMaterial.new()
		material.shader = FaceShader
		material.set_shader_parameter("portrait_mode", 2 if stage == 1 else 0)
		portrait.material = material
		portrait.texture = art
		portrait.show()
	note.text = ""

func _show_object(is_item: bool, stage: int, id: String) -> void:
	portrait.texture = Ink.censer_art(id) if is_item else Ink.object_art(1)
	if portrait.texture == null:
		portrait.texture = Ink.object_art(0)
	if portrait.texture != null:
		if stage < 2:
			var shader := ShaderMaterial.new()
			shader.shader = ObjectShader
			shader.set_shader_parameter("outline", stage == 1)
			portrait.material = shader
		portrait.show()
	note.text = tr("P9_CODEX_OBJECT_ART" if is_item else "P9_CODEX_CUSTOM_ART")

func _update_stages(stage: int, unlocked: int) -> void:
	for index in _stages.size():
		var tab := _stages[index]
		tab.disabled = index > unlocked
		Ink.button_ink(tab, index == stage)
		var status := "P9_CODEX_STAGE_HERE" if index == stage else ("P9_CODEX_STAGE_DONE" if index <= unlocked else "P9_CODEX_STAGE_LATER")
		tab.tooltip_text = tr(status) % tr("P9_CODEX_STAGE_%d" % index)
	_details_scroll.focus_neighbor_top = _details_scroll.get_path_to(_stages[stage])
	_stage_note.text = tr("P11_CODEX_NAMING_HINT" if stage == 2 else "P9_CODEX_NEXT_%d" % stage)

func _build_failures() -> void:
	_history = Control.new()
	_history.size = Vector2(1920, 1080)
	_history.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.add_child(_history)
	Ink.box(_history, Rect2(0, 0, 1920, 1080), Color("100a10e7"))
	Ink.folio(_history, Rect2(388, 208, 1144, 660), Color("1a1417fa"), Ink.COPPER)
	Ink.label(_history, tr("P11_CODEX_FAILURE_TITLE"), Rect2(422, 232, 700, 80), 45, Ink.PAPER, true)
	_button(_history, "failure_back", tr("P4_CLOSE"), Rect2(1320, 250, 176, 48), _hide_failures)
	Ink.ruling(_history, Rect2(420, 326, 1076, 17), Ink.COPPER)
	var listing := Ink.scroll_rows(_history, Rect2(421, 363, 1080, 469))
	failure_text = Label.new()
	failure_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	failure_text.add_theme_font_override("font", Ink.serif_font())
	failure_text.add_theme_font_size_override("font_size", 27)
	failure_text.add_theme_color_override("font_color", Ink.PAPER)
	listing.add_child(failure_text)
	_history.hide()

func _refresh_failures() -> void:
	var lines: Array[String] = []
	for index in range(store.failures.size() - 1, -1, -1):
		var record: Dictionary = store.failures[index]
		var id := str(record.killer_id)
		var source := Data.get_unit(id)
		var killer := Codex.unit_text(id, "NAME", str(source.get("姓名", source.get("名称", tr("P11_CODEX_FAILURE_UNKNOWN")))))
		if str(record.reason) == "P4_END_DAYBREAK":
			killer = tr("P11_CODEX_FAILURE_TIME")
		var reason := tr(str(record.reason))
		if reason == str(record.reason):
			reason = tr("P11R_FAILURE_UNRECORDED")
		lines.append(tr("P11R_FAILURE_ROW") % [killer, reason])
	failure_text.text = "\n\n".join(lines) if not lines.is_empty() else tr("P11_CODEX_FAILURE_NONE")

func _show_failures() -> void:
	_refresh_failures()
	_history.show()
	_details_scroll.focus_mode = Control.FOCUS_NONE
	for id in buttons:
		if id != "failure_back":
			buttons[id].focus_mode = Control.FOCUS_NONE
	buttons.failure_back.grab_focus()

func _hide_failures() -> void:
	_history.hide()
	_details_scroll.focus_mode = Control.FOCUS_ALL
	for id in buttons:
		buttons[id].focus_mode = Control.FOCUS_ALL
	buttons.failure_log.grab_focus()

func _focus_book() -> void:
	_details_scroll.focus_mode = Control.FOCUS_ALL
	for id in buttons:
		buttons[id].focus_mode = Control.FOCUS_ALL
	buttons["book_" + current_book].grab_focus()

func _button(parent: Node, id: String, caption: String, rect: Rect2, callback: Callable) -> Button:
	var button := Ink.button(parent, id, caption, rect, callback)
	buttons[id] = button
	return button
