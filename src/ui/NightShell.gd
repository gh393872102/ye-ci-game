extends CanvasLayer
## The title and pause surfaces leave the shared NightRun and battle clocks in charge.
const Backdrop = preload("res://assets/ui/p9/shrine-night.webp")
const PreferencesMenu = preload("res://src/ui/SettingsMenu.gd")

var host: Node
var title: Control
var title_home: Control
var title_start: Control
var pause: Panel
var preferences: Control
var title_buttons: Dictionary = {}
var pause_buttons: Dictionary = {}
var family_portrait: TextureRect
var family_note: Label
var family_picker: OptionButton
var faction_picker: OptionButton
var faction_detail: Label
var faction_portraits: Array[TextureRect] = []
var seed_input: LineEdit
var night_kind: OptionButton
var fierce_options: Control
var ritual_choice: OptionButton
var modifier_boxes: Dictionary = {}
var title_note: Label
var restart_note: Label
var pause_note: Label
var _pause_focus: WeakRef
var _settings_focus: WeakRef

func _ready() -> void:
	layer = 35
	_build_title()
	_build_pause()
	var settings_layer := CanvasLayer.new()
	settings_layer.layer = 60
	add_child(settings_layer)
	preferences = PreferencesMenu.new()
	settings_layer.add_child(preferences)
	preferences.closed.connect(_settings_closed)

func _build_title() -> void:
	title = Control.new()
	title.size = Vector2(1920, 1080)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(title)
	var image := TextureRect.new()
	image.texture = Backdrop
	image.size = title.size
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(image)
	title_home = _page(title)
	title_start = _page(title)
	var nameplate := _label(title_home, "P9_TITLE", Rect2(102, 110, 520, 197), 146, Color("e6d9b5"))
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["Songti SC", "SimSun", "Noto Serif CJK SC", "PingFang SC"])
	title_font.font_weight = 700
	title_font.fallbacks = [nameplate.get_theme_default_font()]
	nameplate.add_theme_font_override("font", title_font)
	_rule(title_home, Rect2(111, 324, 430, 1), Color("726e54"))
	_rule(title_home, Rect2(111, 323, 84, 3), Color("b89f69"))
	title_buttons.start = _button(title_home, "P9_TITLE_ACTION", Rect2(111, 360, 430, 65), _show_start)
	title_buttons.start.add_theme_color_override("font_color", Color("f0d7a1"))
	title_buttons.continue_run = _button(title_home, "P9_TITLE_CONTINUE", Rect2(111, 439, 430, 65), host.continue_run)
	title_buttons.codex = _button(title_home, "P9_TITLE_CODEX", Rect2(111, 518, 430, 65), host.open_codex)
	title_buttons.settings = _button(title_home, "P9_TITLE_SETTINGS", Rect2(111, 597, 430, 65), host.open_settings)
	title_buttons.quit = _button(title_home, "P9_TITLE_QUIT", Rect2(111, 676, 430, 65), func(): get_tree().quit())
	_rule(title_home, Rect2(111, 797, 430, 1), Color("716e57"))
	title_buttons.observer = _button(title_home, "P9_TITLE_OBSERVER", Rect2(111, 818, 205, 60), host.open_observer, 24)
	title_buttons.build_lab = _button(title_home, "P7_LAB_TITLE", Rect2(336, 818, 205, 60), host.open_growth_lab, 24)
	_build_start()
	title_note = _label(title, "", Rect2(111, 941, 682, 62), 22, Color("d8bb80"))
	title_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.hide()

func _build_start() -> void:
	_label(title_start, "P9_TITLE_ACTION", Rect2(111, 130, 530, 86), 64, Color("e6d9b5"))
	_rule(title_start, Rect2(111, 247, 466, 1), Color("807458"))
	_label(title_start, "P9_TITLE_NIGHT_KIND", Rect2(111, 281, 226, 58), 24)
	night_kind = OptionButton.new()
	night_kind.position = Vector2(335, 281)
	night_kind.size = Vector2(242, 58)
	night_kind.add_item(tr("P9_TITLE_NIGHT_ROSTER"))
	night_kind.add_item(tr("P9_TITLE_NIGHT_CLASSIC"))
	night_kind.add_item(tr("P10_FIERCE"))
	title_start.add_child(night_kind)
	_build_fierce_options()
	faction_picker = OptionButton.new()
	faction_picker.position = Vector2(780, 281)
	faction_picker.size = Vector2(640, 64)
	faction_picker.add_item("守方开局 · 原有混编")
	faction_picker.set_item_metadata(0, "")
	for faction in preload("res://src/night/FactionOpening.gd").PAIRS:
		var names := PackedStringArray()
		for id in preload("res://src/night/FactionOpening.gd").PAIRS[faction]:
			names.append(str(Data.get_unit(id)["姓名"]))
		faction_picker.add_item("%s守册 · %s" % [faction, "、".join(names)])
		faction_picker.set_item_metadata(faction_picker.item_count - 1, faction)
	faction_picker.tooltip_text = "单司双人守册，开局保留20香火；存活的具名守军可维持防线。"
	title_start.add_child(faction_picker)
	family_picker = OptionButton.new()
	family_picker.position = Vector2(780,207)
	family_picker.size = Vector2(640,58)
	family_picker.add_item("攻方开局 · 原有鬼潮")
	family_picker.set_item_metadata(0,"")
	for family in preload("res://src/night/FactionOpening.gd").FAMILIES:
		var entry: Dictionary = preload("res://src/night/FactionOpening.gd").FAMILIES[family]
		var ghost := Data.get_unit(entry.id)
		family_picker.add_item("%s夺名 · %s × %d · %s" % [family,ghost["名称"],floori(16.0 / entry.slots),ghost["定位"]])
		family_picker.set_item_metadata(family_picker.item_count-1,family)
	family_picker.tooltip_text = "初始、定时鬼潮与付费补潮沿用所选谱系。开局16香火，主动变异可能跨谱。"
	title_start.add_child(family_picker)
	family_portrait = preload("res://src/ui/LedgerInk.gd").texture(title_start,null,Rect2(1450,305,280,346),false)
	family_note = _label(title_start,"",Rect2(1450,660,360,180),23)
	family_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	family_note.add_theme_constant_override("outline_size",5)
	family_note.add_theme_color_override("font_outline_color",Color("17140f"))
	family_picker.item_selected.connect(_describe_family)
	_describe_family(0)
	faction_detail = Label.new()
	faction_detail.position = Vector2(787, 361)
	faction_detail.size = Vector2(635, 160)
	faction_detail.add_theme_font_size_override("font_size", 23)
	title_start.add_child(faction_detail)
	for i in 2:
		var portrait := preload("res://src/ui/LedgerInk.gd").texture(faction_detail,null,Rect2(i * 260,160,246,303),false)
		faction_portraits.append(portrait)
	faction_picker.item_selected.connect(_describe_faction)
	_describe_faction(0)
	night_kind.item_selected.connect(func(index: int):
		fierce_options.visible = index == 2
		family_picker.visible = index == 0
		_describe_family(family_picker.selected)
		faction_picker.visible = index == 0
		faction_detail.visible = index == 0 and faction_picker.selected > 0)
	_label(title_start, "P9_TITLE_NIGHT_SEED", Rect2(111, 369, 465, 44), 24)
	seed_input = LineEdit.new()
	seed_input.position = Vector2(111, 425)
	seed_input.size = Vector2(466, 58)
	seed_input.max_length = 80
	seed_input.placeholder_text = tr("P5_SEED_PLACEHOLDER")
	title_start.add_child(seed_input)
	title_buttons.shouxiang = _button(title_start, "P9_TITLE_SHOUXIANG", Rect2(111, 538, 466, 99), _start_night.bind("shouxiang"), 27)
	title_buttons.shouxiang.text += "\n" + tr("P9_TITLE_SHOUXIANG_HELP")
	title_buttons.duoming = _button(title_start, "P9_TITLE_DUOMING", Rect2(111, 652, 466, 99), _start_night.bind("duoming"), 27)
	title_buttons.duoming.text += "\n" + tr("P9_TITLE_DUOMING_HELP")
	restart_note = _label(title_start, "P9_TITLE_START_OVER", Rect2(111, 767, 560, 42), 21, Color("d8bb80"))
	title_buttons.back = _button(title_start, "P9_TITLE_RETURN", Rect2(111, 831, 228, 60), _show_home, 24)

func _describe_family(index: int) -> void:
	var active := index > 0 and night_kind.selected == 0
	family_portrait.visible = active
	family_note.visible = active
	if not active: return
	var family: Dictionary = preload("res://src/night/FactionOpening.gd").FAMILIES[family_picker.get_item_metadata(index)]
	var ghost := Data.get_unit(family.id)
	family_portrait.texture = preload("res://src/units/UnitAppearance.gd").portrait_texture(family.id)
	family_note.text = "%s · %s\n%s\n补潮10香火，每次%d只。" % [ghost["名称"],ghost["定位"],ghost["专属技能"],floori(float(Data.battle_rules.reinforce.count)/family.slots)]

func _describe_faction(index: int) -> void:
	faction_detail.visible = index > 0 and night_kind.selected == 0
	if index == 0: return
	var faction: String = faction_picker.get_item_metadata(index)
	var lines := PackedStringArray()
	for id in preload("res://src/night/FactionOpening.gd").PAIRS[faction]:
		var unit := Data.get_unit(id)
		var portrait := faction_portraits[lines.size()]
		portrait.texture = preload("res://src/units/UnitAppearance.gd").portrait_texture(id)
		portrait.tooltip_text = str(unit["姓名"])
		lines.append("%s · %s" % [unit["姓名"], unit["定位"]])
	lines.append("两人合计身价17，起手20香火。具名守军存活即可维持守册。")
	faction_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	faction_detail.text = "\n".join(lines)

func _build_fierce_options() -> void:
	fierce_options = Panel.new()
	fierce_options.position = Vector2(780,253)
	fierce_options.size = Vector2(655,567)
	title_start.add_child(fierce_options)
	var ink := preload("res://src/ui/LedgerInk.gd")
	ink.label(fierce_options,tr("P10_FIERCE"),Rect2(35,25,570,71),52,ink.PAPER,true)
	ink.label(fierce_options,tr("P10_KIND_HINT"),Rect2(38,108,580,85),24,ink.MUTED)
	ink.label(fierce_options,tr("P10_RITUAL"),Rect2(38,203,180,48),24)
	ritual_choice = OptionButton.new()
	ritual_choice.position = Vector2(237,195)
	ritual_choice.size = Vector2(365,58)
	ritual_choice.add_item(tr("P10_RANDOM_RITUAL"))
	ritual_choice.set_item_metadata(0,"")
	for id in Data.ritual_rules:
		ritual_choice.add_item(str(Data.ritual_rules[id].title))
		ritual_choice.set_item_metadata(ritual_choice.item_count-1,id)
	fierce_options.add_child(ritual_choice)
	ink.label(fierce_options,tr("P10_MODIFIERS"),Rect2(38,284,450,42),24)
	var definitions := preload("res://src/data/StageOptions.gd").modifiers()
	var y := 332
	for id in definitions:
		var toggle := CheckButton.new()
		toggle.text = tr(definitions[id].name_key)
		toggle.tooltip_text = tr(definitions[id].description_key)
		toggle.position = Vector2(38,y)
		toggle.size = Vector2(558,53)
		fierce_options.add_child(toggle)
		modifier_boxes[id] = toggle
		y += 62
	fierce_options.hide()

func _build_pause() -> void:
	pause = Panel.new()
	pause.position = Vector2(1416, 156)
	pause.size = Vector2(454, 486)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("121c1ef7")
	frame.border_color = Color("78765e")
	frame.set_border_width_all(1)
	frame.border_width_top = 2
	pause.add_theme_stylebox_override("panel", frame)
	add_child(pause)
	_label(pause, "P9_PAUSE_TITLE", Rect2(30, 22, 394, 60), 37, Color("e5d6ad"))
	_rule(pause, Rect2(30, 103, 394, 1), Color("726e54"))
	pause_buttons.resume = _button(pause, "P9_PAUSE_RETURN", Rect2(30, 129, 394, 55), resume_battle, 25)
	pause_buttons.settings = _button(pause, "P9_TITLE_SETTINGS", Rect2(30, 197, 394, 55), host.open_settings, 25)
	pause_buttons.save = _button(pause, "P9_PAUSE_SAVE", Rect2(30, 265, 394, 55), host.save_run, 25)
	pause_buttons.exit = _button(pause, "P9_PAUSE_TITLE_RETURN", Rect2(30, 333, 394, 55), host.save_and_exit, 25)
	pause_note = _label(pause, "P9_PAUSE_NOTE", Rect2(30, 410, 394, 45), 19, Color("d1c39e"))
	pause_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause.hide()

func show_title() -> void:
	if title.visible:
		_update_save_available()
		return
	title.show()
	_show_home()

func hide_title() -> void:
	title.hide()

func _show_home() -> void:
	title_home.show()
	title_start.hide()
	title_note.text = ""
	_update_save_available()
	title_buttons.start.grab_focus()

func _show_start() -> void:
	title_home.hide()
	title_start.show()
	title_note.text = ""
	restart_note.visible = FileAccess.file_exists(host.save_path)
	title_buttons.shouxiang.grab_focus()

func _update_save_available() -> void:
	title_buttons.continue_run.disabled = not FileAccess.file_exists(host.save_path)
	title_buttons.continue_run.focus_mode = Control.FOCUS_NONE if title_buttons.continue_run.disabled else Control.FOCUS_ALL

func _start_night(mode: String) -> void:
	if night_kind.selected == 2:
		var modifiers := []
		for id in modifier_boxes:
			if modifier_boxes[id].button_pressed: modifiers.append(id)
		host.start_p10_night(mode,"fierce",seed_input.text,ritual_choice.get_selected_metadata(),modifiers)
	elif night_kind.selected == 0:
		host.start_p10_night(mode,"example",seed_input.text,"R01",[], faction_picker.get_selected_metadata() if mode == "shouxiang" else family_picker.get_selected_metadata())
	else:
		host.start_run(mode, "example", seed_input.text)

func open_pause() -> void:
	if pause.visible:
		return
	_pause_focus = _current_focus()
	Clock.set_paused(true)
	pause_note.text = tr("P9_PAUSE_NOTE")
	pause.show()
	Settings.set_pause_menu(pause)
	pause_buttons.resume.grab_focus()

func close_pause() -> void:
	if pause.visible:
		_close_pause(false)

func resume_battle() -> void:
	if pause.visible:
		_close_pause(true)

func _close_pause(resume: bool) -> void:
	pause.hide()
	_restore_focus(_pause_focus)
	if resume and is_instance_valid(host.combat):
		Clock.set_paused(false)

func open_settings() -> void:
	if preferences.visible:
		return
	_settings_focus = _current_focus()
	preferences.open()
	Settings.set_gameplay_modal(preferences)

func _settings_closed() -> void:
	_restore_focus(_settings_focus)

func response(text: String) -> void:
	if title.visible:
		title_note.text = text
	if pause.visible:
		pause_note.text = text

func _current_focus() -> WeakRef:
	var owner := get_viewport().gui_get_focus_owner()
	return weakref(owner) if is_instance_valid(owner) else null

func _restore_focus(previous: WeakRef) -> void:
	if previous == null:
		return
	var control := previous.get_ref() as Control
	if is_instance_valid(control) and control.is_visible_in_tree():
		control.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	var cancel := event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu")
	var quick_pause := event.is_action_pressed("pause")
	var speed := event.is_action_pressed("speed_one") or event.is_action_pressed("speed_two")
	if preferences.visible:
		if cancel:
			preferences.close()
	elif host.codex_panel.surface.visible:
		if not quick_pause and not speed:
			return
	elif pause.visible:
		if cancel or quick_pause:
			_close_pause(quick_pause)
		elif not speed:
			return
	elif title.visible:
		if title_start.visible and cancel:
			_show_home()
		elif not quick_pause and not speed:
			return
	elif is_instance_valid(host.combat):
		if event.is_action_pressed("pause_menu"):
			open_pause()
		elif event.is_action_pressed("codex"):
			host.open_codex()
		else:
			return
	elif not quick_pause and not speed:
		return
	get_viewport().set_input_as_handled()

func _page(parent: Control) -> Control:
	var page := Control.new()
	page.size = parent.size
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(page)
	return page

func _button(parent: Control, key: String, rectangle: Rect2, action: Callable, pixels := 29) -> Button:
	var button := Button.new()
	button.text = tr(key)
	button.position = rectangle.position
	button.size = rectangle.size
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", pixels)
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

func _rule(parent: Control, rectangle: Rect2, color: Color) -> void:
	var rule := ColorRect.new()
	rule.color = color
	rule.position = rectangle.position
	rule.size = rectangle.size
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
