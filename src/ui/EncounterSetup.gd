extends Panel
## Local editor for the existing observer config. The simulator validates the final combination.
signal chunks_changed

const Ink = preload("res://src/ui/LedgerInk.gd")
const Chunks = preload("res://src/data/ChunkCatalog.gd")
const Stages = preload("res://src/data/StageOptions.gd")
var ritual_picker: OptionButton
var boss_picker := OptionButton.new()
var chunk_boxes := {}
var modifier_boxes := {}
var manual_ids := {}
var info: Label
var previous_boss_index := 0
var locked_boss := false
var opener: Control


func build(ritual: OptionButton, open_button: Control) -> void:
	ritual_picker = ritual
	opener = open_button
	focus_behavior_recursive = FOCUS_BEHAVIOR_ENABLED
	position = Vector2(168,120)
	size = Vector2(1584,832)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.position = -position
	backdrop.size = Vector2(1920,1080)
	backdrop.color = Color("050a0bd9")
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.show_behind_parent = true
	add_child(backdrop)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("141e20")
	style.border_color = Ink.RULE
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel",style)
	Ink.label(self,tr("P10_STAGE_SETUP"),Rect2(58,38,730,70),55,Ink.PAPER,true)
	Ink.label(self,tr("P10_CHUNK_HINT"),Rect2(60,119,1320,60),23,Ink.MUTED)
	Ink.box(self,Rect2(60,195,1460,1),Ink.RULE)
	Ink.label(self,tr("P10_CHUNKS"),Rect2(60,229,720,54),32,Ink.PAPER,true)
	for index in 12:
		var id := "C%02d" % (index+1)
		var row := Chunks.read_chunk(id)
		var check := CheckButton.new()
		check.text = id + "   " + str(row.get("title",id))
		check.tooltip_text = str(row.get("failure_line",""))
		check.position = Vector2(60+(index%2)*370,308+floori(index/2.0)*60)
		check.size = Vector2(347,51)
		add_child(check)
		chunk_boxes[id] = check
		check.toggled.connect(func(active: bool):
			manual_ids[id]=active
			chunks_changed.emit())
	Ink.box(self,Rect2(839,224,1,470),Ink.RULE)
	Ink.label(self,tr("P10_BOSS"),Rect2(900,229,600,50),32,Ink.PAPER,true)
	boss_picker.add_item(tr("P10_NO_BOSS"))
	boss_picker.set_item_metadata(0,"")
	for id in Stages.bosses():
		boss_picker.add_item(tr(Stages.bosses()[id].name_key))
		boss_picker.set_item_metadata(boss_picker.item_count-1,id)
	boss_picker.position = Vector2(900,305)
	boss_picker.size = Vector2(585,55)
	add_child(boss_picker)
	Ink.label(self,tr("P10_MODIFIERS"),Rect2(900,414,585,56),32,Ink.PAPER,true)
	for id in Stages.modifiers():
		var row: Dictionary = Stages.modifiers()[id]
		var box := CheckButton.new()
		box.text = tr(row.name_key)
		box.tooltip_text = tr(row.description_key)
		box.position = Vector2(900,489+modifier_boxes.size()*58)
		box.size = Vector2(585,54)
		add_child(box)
		modifier_boxes[id] = box
		box.toggled.connect(func(_active: bool): sync_required())
	info = Ink.label(self,"",Rect2(60,700,1020,98),22,Ink.MUTED)
	Ink.button(self,"apply",tr("P10_BACK_SETUP"),Rect2(1160,715,325,64),hide,true,true)
	boss_picker.item_selected.connect(func(_index: int): sync_required())
	ritual.item_selected.connect(func(_index: int): sync_required())
	sync_required()
	hide()
	visibility_changed.connect(_focus_page)

func _focus_page() -> void:
	var setup := get_parent_control()
	if not is_instance_valid(setup): return
	if visible:
		setup.focus_behavior_recursive = FOCUS_BEHAVIOR_DISABLED
		if not boss_picker.disabled: boss_picker.grab_focus()
		else: modifier_boxes.N01.grab_focus()
	else:
		setup.focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED
		if opener.is_visible_in_tree(): opener.grab_focus()

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()

func selected_modifiers() -> Array:
	var ids := []
	for id in modifier_boxes:
		if modifier_boxes[id].button_pressed: ids.append(id)
	return ids

func selected_chunks() -> Array:
	var ids := []
	for id in chunk_boxes:
		if chunk_boxes[id].button_pressed: ids.append(id)
	return ids

func sync_required() -> void:
	var row: Dictionary = Data.ritual_rules.get(ritual_picker.get_selected_metadata(),{})
	var lock_boss := not str(row.get("boss_id","")).is_empty()
	if lock_boss and not locked_boss: previous_boss_index = boss_picker.selected
	if not lock_boss and locked_boss: boss_picker.select(previous_boss_index)
	locked_boss = lock_boss
	boss_picker.disabled = lock_boss
	if lock_boss:
		for index in boss_picker.item_count:
			if boss_picker.get_item_metadata(index) == row.boss_id: boss_picker.select(index)
	var forced: Array = Chunks.CORE.duplicate()
	forced.append_array(row.get("required_chunks",[]))
	forced.append_array(Stages.required_chunks(boss_picker.get_selected_metadata(),selected_modifiers()))
	for id in chunk_boxes:
		chunk_boxes[id].disabled = id in forced
		chunk_boxes[id].set_pressed_no_signal(id in forced or manual_ids.get(id,false))
	if is_instance_valid(info): info.text = str(row.get("description",""))
	chunks_changed.emit()
