extends Control
var host: Node
var buttons: Dictionary = {}
var human_counts: Dictionary = {}
var human_posts: Dictionary = {}
var human_post_ids: Dictionary = {}
var ghost_counts: Dictionary = {}
var duration: SpinBox
var incense_shouxiang: SpinBox
var incense_duoming: SpinBox
var names: SpinBox
var profile: OptionButton
var ferocity: OptionButton
var encounter_setup: Panel
var ritual: OptionButton
var director_enabled: CheckButton
var growth_enabled: CheckButton
var growth_template: OptionButton
var seed_input: LineEdit
var replay_seed: LineEdit
var setup_root: Control
var battle_root: Control
var battle_body: Control
var records_box: VBoxContainer
var message: Label
var battle_status: Label
var director_status: Label
var door_picker: OptionButton
var door_ids: Array[String] = []
var font: Font = preload("res://resources/p9_theme.tres").default_font

func _ready() -> void:
	custom_minimum_size = Vector2(1920,1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin := Theme.new()
	skin.default_font = font
	skin.default_font_size = 21
	theme = skin
	setup_root = Control.new()
	setup_root.size = Vector2(1920,1080)
	setup_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(setup_root)
	battle_root = Control.new()
	battle_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(battle_root)
	_build_setup()
	_build_battle()
	message = _label(self, "", Rect2(600,1038,930,38),18)
	show_setup()

func _build_setup() -> void:
	_label(setup_root,tr("P6_OBSERVATORY"),Rect2(64,32,1500,60),36)
	_label(setup_root,tr("P6_CONFIG_HELP") + "\n" + tr("P7_OBSERVER_PRESET_HELP"),Rect2(64,102,1750,52),20)
	_button(setup_root,"night",tr("P6_BACK_NIGHT"),Rect2(1610,36,240,50),host.back_to_night)
	var defaults: Dictionary = Data.mode_rules.defaults
	var limits: Dictionary = Data.mode_rules.limits
	_label(setup_root,tr("P6_RULES"),Rect2(64,164,600,42),25)
	seed_input = LineEdit.new()
	seed_input.text = str(defaults.seed)
	_place(seed_input,Rect2(260,220,402,48),setup_root)
	_label(setup_root,tr("P6_SEED"),Rect2(64,226,185,36),20)
	profile = _option(setup_root,Rect2(260,284,402,46),["P6_PROFILE_ENTRY","P6_PROFILE_UPPER"])
	_label(setup_root,tr("P6_PROFILE"),Rect2(64,290,190,36),20)
	ritual = _option(setup_root,Rect2(260,346,402,46),[])
	for id in Data.ritual_rules:
		ritual.add_item(str(Data.ritual_rules[id].title))
		ritual.set_item_metadata(ritual.item_count-1,id)
	_label(setup_root,tr("P6_RITUAL"),Rect2(64,352,190,36),20)
	ferocity = _option(setup_root,Rect2(260,408,402,46),["P6_AI_CALM","P6_AI_NORMAL","P6_AI_FIERCE"])
	ferocity.select(1)
	_label(setup_root,tr("P6_AI"),Rect2(64,414,190,36),20)
	duration = _spin(setup_root,Rect2(410,474,252,46),limits.duration_min,limits.duration_max,defaults.duration)
	_label(setup_root,tr("P6_DURATION"),Rect2(64,480,350,36),20)
	names = _spin(setup_root,Rect2(410,536,252,46),limits.names_min,limits.names_max,defaults.names)
	_label(setup_root,tr("P6_NAMES"),Rect2(64,542,350,36),20)
	incense_shouxiang = _spin(setup_root,Rect2(410,598,252,46),limits.incense_min,limits.incense_max,defaults.incense.shouxiang)
	_label(setup_root,tr("P6_INCENSE_SHOUXIANG"),Rect2(64,604,350,36),20)
	incense_duoming = _spin(setup_root,Rect2(410,660,252,46),limits.incense_min,limits.incense_max,defaults.incense.duoming)
	_label(setup_root,tr("P6_INCENSE_DUOMING"),Rect2(64,666,350,36),20)
	director_enabled = CheckButton.new()
	director_enabled.text = tr("P6_DIRECTOR_ENABLE")
	_place(director_enabled,Rect2(64,730,598,46),setup_root)
	_label(setup_root,tr("P6_HUMANS"),Rect2(720,164,660,42),25)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/reference_gate_court.json"))
	var human_list := _scroll_list(setup_root,Rect2(720,220,660,430),Vector2(640,Data.mode_rules.allowed_humans.size()*72))
	for index in Data.mode_rules.allowed_humans.size():
		var id: String = Data.mode_rules.allowed_humans[index]
		var row: Dictionary = Data.get_unit(id)
		_label(human_list,str(row.get("姓名",id)),Rect2(0,6+index*72,130,40),21)
		var count := 0
		var default_post := "post_hall_door"
		for item in defaults.humans:
			if item.id == id:
				count = int(item.count)
				default_post = item.post
		human_counts[id] = _spin(human_list,Rect2(136,index*72,94,46),0,1 if id.begins_with("H") else 4,count)
		var picker := OptionButton.new()
		_place(picker,Rect2(250,index*72,380,46),human_list)
		human_posts[id] = picker
		_list_posts(id,layout.posts,default_post)
	_label(setup_root,tr("P6_COVER_HELP"),Rect2(720,672,660,76),19)
	_label(setup_root,tr("P6_GHOSTS"),Rect2(1430,164,420,42),25)
	var ghost_list := _scroll_list(setup_root,Rect2(1430,220,420,215),Vector2(400,Data.mode_rules.allowed_ghosts.size()*72))
	for index in Data.mode_rules.allowed_ghosts.size():
		var id: String = Data.mode_rules.allowed_ghosts[index]
		var row: Dictionary = Data.get_unit(id)
		_label(ghost_list,str(row.get("名称",id)),Rect2(0,6+index*72,230,40),21)
		var count := 0
		for item in defaults.ghosts:
			if item.id == id: count = int(item.count)
		ghost_counts[id] = _spin(ghost_list,Rect2(240,index*72,160,46),0,limits.ghost_max,count)
	_label(setup_root,tr("P6_REPLAY_TITLE"),Rect2(720,782,1080,42),26)
	replay_seed = LineEdit.new()
	replay_seed.placeholder_text = tr("P6_REPLAY_SEED_HELP")
	_place(replay_seed,Rect2(720,838,840,46),setup_root)
	_button(setup_root,"find_replays",tr("P6_FIND_REPLAYS"),Rect2(1580,838,270,46),func(): host.find_replays(replay_seed.text))
	var scroll := ScrollContainer.new()
	_place(scroll,Rect2(720,898,1130,110),setup_root)
	records_box = VBoxContainer.new()
	records_box.custom_minimum_size.x = 1080
	scroll.add_child(records_box)
	encounter_setup = preload("res://src/ui/EncounterSetup.gd").new()
	_button(setup_root,"encounter_setup",tr("P10_STAGE_SETUP"),Rect2(1430,470,420,61),encounter_setup.show)
	_label(setup_root,tr("P6_REPLAY_LOCAL_HELP").replace("\n\n","\n"),Rect2(1430,549,420,130),18)
	growth_enabled = CheckButton.new()
	growth_enabled.text = tr("P7_OBSERVER_GROWTH_ENABLE")
	growth_enabled.button_pressed = false
	_place(growth_enabled,Rect2(1430,686,420,42),setup_root)
	growth_template = _option(setup_root,Rect2(1430,734,420,42),["P7_OBSERVER_RITUAL_BREAK","P7_OBSERVER_GATE_BEAM"])
	growth_template.disabled = true
	growth_enabled.toggled.connect(func(enabled: bool): growth_template.disabled = not enabled)
	_button(setup_root,"start_watch",tr("P6_START_WATCH"),Rect2(64,822,598,54),_start.bind("watch",""))
	_button(setup_root,"start_duel_shouxiang",tr("P6_START_DUEL_SHOUXIANG"),Rect2(64,890,598,54),_start.bind("duel","shouxiang"))
	_button(setup_root,"start_duel_duoming",tr("P6_START_DUEL_DUOMING"),Rect2(64,958,598,54),_start.bind("duel","duoming"))

	setup_root.add_child(encounter_setup)
	encounter_setup.chunks_changed.connect(_update_observer_posts)
	encounter_setup.build(ritual,buttons.encounter_setup)

func _update_observer_posts() -> void:
	var layout := preload("res://src/data/ChunkCatalog.gd").compose(encounter_setup.selected_chunks())
	if layout.is_empty(): return
	for id in human_posts:
		var selected: int = human_posts[id].selected
		var previous := str(human_post_ids[id][selected]) if selected >= 0 else ""
		_list_posts(id,layout.posts,previous)

func _list_posts(id: String, posts: Array, preferred: String) -> void:
	var picker: OptionButton = human_posts[id]
	var role: String = Data.combat_profiles[id].role
	if role == "talisman": role = "crossbow"
	var ids: Array[String] = []
	picker.clear()
	for post in posts:
		if post.default_deployment and role in post.allowed_roles:
			ids.append(str(post.id))
			picker.add_item(tr(str(post.id).to_upper()))
	if not ids.is_empty(): picker.select(maxi(0,ids.find(preferred)))
	human_post_ids[id] = ids

func make_config(kind: String, seat: String) -> Dictionary:
	var humans: Array[Dictionary] = []
	var ghosts: Array[Dictionary] = []
	for id in human_counts:
		if human_counts[id].value > 0:
			humans.append({"id":id,"count":int(human_counts[id].value),"post":human_post_ids[id][human_posts[id].selected]})
	for id in ghost_counts:
		if ghost_counts[id].value > 0: ghosts.append({"id":id,"count":int(ghost_counts[id].value)})
	return {"kind":kind,"roster_enabled":true,"player_seat":seat if not seat.is_empty() else "shouxiang","seed":seed_input.text,"profile_id":["entry","upper"][profile.selected],"ritual":ritual.get_selected_metadata(),"chunk_ids":encounter_setup.selected_chunks(),"boss_id":encounter_setup.boss_picker.get_selected_metadata(),"nameless_modifiers":encounter_setup.selected_modifiers(),"duration":duration.value,"incense":{"shouxiang":incense_shouxiang.value,"duoming":incense_duoming.value},"names":names.value,"ferocity":["calm","normal","fierce"][ferocity.selected],"director_enabled":director_enabled.button_pressed,"growth_enabled":growth_enabled.button_pressed,"growth_template":["ritual_break","gate_beam"][growth_template.selected],"humans":humans,"ghosts":ghosts}

func _start(kind: String, seat: String) -> void:
	host.start_observation(make_config(kind,seat))

func _build_battle() -> void:
	battle_status = _label(battle_root,"",Rect2(600,66,440,138),19)
	battle_body = Control.new()
	battle_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_body.position = Vector2(600,730)
	battle_root.add_child(battle_body)
	director_status = _label(battle_body,"",Rect2(0,0,1250,96),20)
	_button(battle_body,"inspect_next",tr("P6_INSPECT_NEXT"),Rect2(0,108,260,48),func(): host.combat.get_node("Decisions")._cycle_unit(1))
	_button(battle_body,"director_reinforce",tr("P6_DIRECTOR_REINFORCE"),Rect2(280,108,290,48),func(): host.director("reinforce"))
	_button(battle_body,"director_pause",tr("P6_DIRECTOR_PAUSE"),Rect2(590,108,280,48),func(): host.director("pause"))
	door_picker = OptionButton.new()
	_place(door_picker,Rect2(0,172,380,44),battle_body)
	_button(battle_body,"director_repair",tr("P6_DIRECTOR_REPAIR"),Rect2(400,172,380,44),_repair)
	_button(battle_root,"archive",tr("P6_ARCHIVE"),Rect2(1400,1028,200,44),host.save_recording)
	_button(battle_root,"setup",tr("P6_RETURN_SETUP"),Rect2(1620,1028,260,44),host.return_setup)

func _repair() -> void:
	if door_picker.selected >= 0 and door_picker.selected < door_ids.size():
		host.director("repair",{"door_id":door_ids[door_picker.selected]})

func show_battle(config: Dictionary) -> void:
	setup_root.hide()
	battle_root.show()
	door_ids.clear()
	door_picker.clear()
	for door in host.combat.get_node("ReferenceMap").doors:
		door_ids.append(str(door.name))
		door_picker.add_item(tr(str(door.name).to_upper()))
	message.position = Vector2(600,1038)
	queue_redraw()

func show_setup() -> void:
	message.show()
	setup_root.show()
	battle_root.hide()
	message.position = Vector2(64,1038)
	buttons.start_watch.grab_focus()
	queue_redraw()

func show_records(records: Array) -> void:
	for key in buttons.keys():
		if str(key).begins_with("replay_"): buttons.erase(key)
	for child in records_box.get_children():
		records_box.remove_child(child)
		child.queue_free()
	for record in records:
		var label: String = str(record.label)
		if record.get("source", "") == "observer": label = tr("P6_WATCH" if record.get("mode", "") == "watch" else "P6_DUEL")
		if record.get("source") == "night_resume_fragment": label += " · " + tr("P11_REPLAY_FROM_RESUME")
		var text := label + " · " + tr("P6_RECORD_DURATION") % record.duration + " · " + tr("P6_RECORD_COMPLETE" if record.get("complete",false) else "P6_RECORD_PARTIAL")
		var button := _button(records_box,"replay_" + str(record.id),text,Rect2(0,0,1080,42),host.start_replay.bind(str(record.id)))
		button.custom_minimum_size.y = 42

func update_status(state: Dictionary, session: Node, replay: bool) -> void:
	message.visible = host.combat.get_node("Decisions").feedback.text.is_empty()
	var seat: String = session.player_seat
	battle_status.text = tr("P6_REPLAY" if replay else ("P6_WATCH" if seat.is_empty() else "P6_DUEL"))
	if not seat.is_empty(): battle_status.text += " · " + tr("P4_SEAT_" + seat.to_upper())
	var result: Dictionary = session.result
	if not result.is_empty():
		battle_status.text += "\n" + tr(str(result.reason))
		if result.has("winner"): battle_status.text += "\n" + tr("P6_WINNER") % tr("P4_SEAT_" + str(result.winner).to_upper())
	var remaining := maxi(0,int(Data.mode_rules.director_limit) - host.controller.director_used)
	director_status.text = tr("P6_READ_ONLY") if replay or seat.is_empty() else tr("P6_DUEL_HELP")
	var counts: Dictionary = state.get("ai_decisions", {})
	if not counts.is_empty():
		director_status.text += "\n" + tr("P6_AI_DECISIONS") % [counts.get("shouxiang",0),counts.get("duoming",0)]
	if replay:
		var progress: Dictionary = state.get("replay",{})
		director_status.text += "\n" + tr("P6_REPLAY_PROGRESS") % [progress.get("steps",0),progress.get("total_steps",0),progress.get("commands",0),progress.get("total_commands",0)]
		if progress.get("done",false):
			director_status.text += "\n" + (tr("P6_REPLAY_VERIFIED") if progress.get("verified",false) else tr(str(progress.get("error","P6_REPLAY_DIVERGED"))))
	else:
		director_status.text += "\n" + (tr("P6_DIRECTOR_REMAINING") % remaining if host.controller.config.get("director_enabled",false) else tr("P6_DIRECTOR_CLOSED"))
	var enabled: bool = not replay and host.controller.config.get("director_enabled",false) and remaining > 0 and session.running and result.is_empty()
	for id in ["director_reinforce","director_pause","director_repair"]: buttons[id].disabled = not enabled
	buttons.archive.disabled = replay or host.final_archived

func _label(parent: Node, text: String, rect: Rect2, font_size := 21) -> Label:
	var result := Label.new()
	result.text = text
	result.position = rect.position
	result.size = rect.size
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",Color("c8cfb9"))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func _button(parent: Node, id: String, text: String, rect: Rect2, callback: Callable) -> Button:
	var result := Button.new()
	result.name = id.validate_node_name()
	result.text = text
	result.position = rect.position
	result.size = rect.size
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("203332")
	skin.border_color = Color("6b8172")
	skin.set_border_width_all(1)
	skin.set_content_margin_all(8)
	result.add_theme_stylebox_override("normal",skin)
	var focus := skin.duplicate()
	focus.border_color = Color("ccb88b")
	focus.set_border_width_all(2)
	result.add_theme_stylebox_override("focus",focus)
	result.pressed.connect(callback)
	parent.add_child(result)
	buttons[id] = result
	return result

func _scroll_list(parent: Node, rect: Rect2, minimum: Vector2) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_place(scroll,rect,parent)
	var list := Control.new()
	list.custom_minimum_size = minimum
	scroll.add_child(list)
	return list

func _spin(parent: Node, rect: Rect2, minimum: float, maximum: float, value: float) -> SpinBox:
	var result := SpinBox.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = 1
	result.value = value
	_place(result,rect,parent)
	return result

func _option(parent: Node, rect: Rect2, keys: Array) -> OptionButton:
	var result := OptionButton.new()
	for key in keys: result.add_item(tr(key))
	_place(result,rect,parent)
	return result

func _place(control: Control, rect: Rect2, parent: Node) -> void:
	control.position = rect.position
	control.size = rect.size
	parent.add_child(control)

func _draw() -> void:
	if setup_root != null and setup_root.visible:
		draw_rect(Rect2(0,0,1920,1080),Color("0a141b"))
		for y in [24,144,1024,1056]: draw_line(Vector2(32,y),Vector2(1888,y),Color("3d5751"),1)
