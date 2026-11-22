extends CanvasLayer
## Inventory is supplied by the current night or an explicitly authored trial.
const Ink = preload("res://src/ui/LedgerInk.gd")

const Appearance = preload("res://src/units/UnitAppearance.gd")

var decisions: CanvasLayer
var unit: Node2D
var surface: PanelContainer
var content: VBoxContainer
var scroll: ScrollContainer
var buttons: Dictionary = {}
var slots_label: Label
var slot_picker: OptionButton
var item_picker: OptionButton
var description: Label
var recipe_picker: OptionButton
var partner_picker: OptionButton
var material_picker: OptionButton
var current_tab := "equipment"
var item_ids: Array[String] = []
var recipe_ids: Array[String] = []
var partner_ids: Array[String] = []
var material_ids: Array[String] = []
var selected_pose := 0
var selected_slot := 0
var selected_item := ""
var selected_recipe := ""
var selected_partner := ""
var selected_material := ""

func _ready() -> void:
	layer = 9
	surface = PanelContainer.new()
	surface.position = decisions.ACTION_RECT.position
	surface.size = decisions.ACTION_RECT.size
	surface.theme = preload("res://resources/p9_theme.tres")
	var skin := Ink.skin(Color("181419f9"), Color("866448"), 2)
	skin.set_content_margin_all(16)
	surface.add_theme_stylebox_override("panel", skin)
	add_child(surface)
	surface.draw.connect(func(): Ink.draw_binding(surface, surface.size, Color("836247")))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	surface.add_child(scroll)
	decisions.scroll_style(scroll.get_v_scroll_bar())
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 7)
	scroll.add_child(content)
	surface.hide()

func open_for(target: Node2D, tab := "equipment") -> void:
	if not is_instance_valid(target) or target.dead or not decisions.growth_enabled(): return
	unit = target
	current_tab = tab
	decisions.panel.hide()
	decisions.current_panel = "growth"
	Clock.set_paused(true)
	render()

func close() -> void:
	surface.hide()
	if decisions.current_panel == "growth": decisions.current_panel = "unit"

func render() -> void:
	if not is_instance_valid(unit) or unit.dead:
		close()
		return
	var focused := surface.get_viewport().gui_get_focus_owner()
	var previous := str(focused.name) if is_instance_valid(focused) and surface.is_ancestor_of(focused) else ""
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	buttons.clear()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	var heading := _label(tabs, tr("P7_GROWTH_TITLE") % unit.display_name, 28)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_override("font", Ink.serif_font())
	heading.add_theme_color_override("font_color", Ink.COPPER)
	_button(tabs,"equipment",tr("P7_EQUIPMENT"),_tab.bind("equipment"))
	if unit.side == "yegui":
		_button(tabs,"forms",tr("P7_MUTATIONS"),_tab.bind("forms"))
		_button(tabs,"fusions",tr("P7_FUSIONS"),_tab.bind("fusions"))
	elif unit.unit_id.begins_with("G"):
		_button(tabs,"fusions",tr("P7_GRAY_CONTRACT"),_tab.bind("fusions"))
	else:
		_button(tabs,"vocation",tr("P7_VOCATION"),_tab.bind("vocation"))
	_button(tabs,"close",tr("P9_BATTLE_CLOSE"),close)
	slots_label = _label(content, decisions.growth_slots_summary(unit), 18)
	var options: Dictionary
	if decisions.read_only():
		var owned: Array[Dictionary] = []
		for id in decisions.session.growth.state.get("inventory",{}):
			var qty: int = decisions.session.growth.state.inventory[id]
			if qty > 0 and Data.growth_rules.items.has(id):
				var item: Dictionary = Data.growth_rules.items[id].duplicate(true)
				item.qty = qty
				owned.append(item)
		options = {"inventory":owned,"eligible":false,"reason":"P6_READ_ONLY"}
	else:
		options = decisions.session.growth.options(unit)
	match current_tab:
		"equipment": _equipment(options)
		"forms": _forms(options)
		"fusions": _fusions(options)
		"vocation": _vocation(options)
	surface.show()
	var next := content.find_child(previous, true, false) as Control if not previous.is_empty() else null
	if next is BaseButton and not next.disabled:
		next.grab_focus()
	else:
		buttons.get(current_tab, buttons.equipment).grab_focus()

func _tab(tab: String) -> void:
	current_tab = tab
	render()

func _equipment(options: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	content.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 7)
	row.add_child(left)
	var pickers := HBoxContainer.new()
	pickers.add_theme_constant_override("separation", 8)
	left.add_child(pickers)
	slot_picker = OptionButton.new()
	slot_picker.name = "slot_picker"
	for key in ["P7_SLOT_CENSER", "P7_SLOT_ART_ONE", "P7_SLOT_ART_TWO", "P7_SLOT_NAMEPLATE"]:
		slot_picker.add_item(tr(key))
	slot_picker.custom_minimum_size = Vector2(217, 42)
	slot_picker.select(selected_slot)
	slot_picker.item_selected.connect(func(index: int):
		selected_slot = index
		selected_item = ""
		render()
	)
	pickers.add_child(slot_picker)
	item_picker = OptionButton.new()
	item_picker.name = "item_picker"
	item_picker.custom_minimum_size = Vector2(378, 42)
	item_ids.clear()
	var slot: String = ["censer", "art", "art", "nameplate"][selected_slot]
	for item in options.get("inventory", []):
		if item.slot != slot or int(item.get("qty", 0)) <= 0:
			continue
		item_ids.append(str(item.id))
		item_picker.add_item(tr("P7_INVENTORY_ITEM") % [item.id, item.name, item.qty])
	pickers.add_child(item_picker)
	if item_ids.is_empty():
		item_picker.add_item(tr("P7_INVENTORY_EMPTY"))
		item_picker.disabled = true
		selected_item = ""
	else:
		item_picker.select(maxi(0, item_ids.find(selected_item)))
		selected_item = item_ids[item_picker.selected]
		item_picker.item_selected.connect(func(index: int):
			selected_item = item_ids[index]
			_refresh_description()
		)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	left.add_child(actions)
	description = _label(row, "", 18)
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var editable := _editable()
	_button(actions, "equip_item", tr("P7_EQUIP_CONFIRM"), _equip, editable and bool(options.get("eligible", true)) and not selected_item.is_empty() and not _item_unavailable(selected_item))
	_button(actions, "unequip_item", tr("P7_UNEQUIP_CONFIRM"), _unequip, editable)
	_refresh_description()
	if not options.get("eligible", true):
		_label(left, tr(str(options.get("reason", "P7_EQUIP_INELIGIBLE"))), 16)
	if decisions.read_only() and options.get("reason", "") != "P6_READ_ONLY":
		_label(left, tr("P6_READ_ONLY"), 16)

func _refresh_description() -> void:
	var slots: Dictionary = unit.growth.get("slots", {})
	var arts: Array = slots.get("arts", ["", ""])
	var slot: String = ["censer", "art", "art", "nameplate"][selected_slot]
	var old_id: String = arts[selected_slot - 1] if slot == "art" else slots.get(slot, "")
	var items: Dictionary = Data.growth_rules.items
	var old: Dictionary = items.get(old_id, {})
	description.text = tr("P7_CURRENT_EMPTY") if old.is_empty() else tr("P7_CURRENT_ITEM") % [old.name, old.description]
	if selected_item.is_empty():
		description.text += "\n" + tr("P7_INVENTORY_NOTE")
		return
	var item: Dictionary = items[selected_item]
	var price: float = decisions.session.growth.equip_price(old_id, selected_item)
	description.text += "\n" + tr("P7_CANDIDATE_ITEM") % [item.name, item.description]
	description.text += "\n" + tr("P7_SWAP_PRICE") % [str(price).trim_suffix(".0"), str(item.remove_cost).trim_suffix(".0")]
	if selected_item == "I20": description.text += "\n" + tr("P7_ITEM_INTERFACE")
	elif item.get("status","") in ["interface","locked"]: description.text += "\n" + tr("P7_NOT_OPEN")
	if selected_item == "I19" and decisions.session.growth.state.get("locked_paths",[]).is_empty(): description.text += "\n" + tr("P7_NO_LOCK")
	if buttons.has("equip_item") and is_instance_valid(buttons.equip_item):
		var duplicate := old_id == selected_item or (slot == "art" and selected_item in arts)
		var affordable: bool = decisions.available_incense() >= price
		if duplicate:
			description.text += "\n" + tr("P7_ALREADY_EQUIPPED")
		elif not affordable:
			description.text += "\n" + tr("P7_NO_INCENSE")
		buttons.equip_item.disabled = not _editable() or _item_unavailable(selected_item) or not decisions.session.growth.eligible(unit) or duplicate or not affordable

func _item_unavailable(id: String) -> bool:
	return id != "I20" and Data.growth_rules.items.get(id,{}).get("status","") in ["interface","locked"]

func _equip() -> void:
	if selected_item.is_empty(): return
	_send("equip_item",{"unit_id":unit.instance_id,"item_id":selected_item,"slot_index":maxi(0,selected_slot - 1) if selected_slot in [1,2] else 0})

func _unequip() -> void:
	_send("unequip_item",{"unit_id":unit.instance_id,"slot":["censer","art","art","nameplate"][selected_slot],"index":selected_slot - 1 if selected_slot in [1,2] else 0})

func _forms(_options: Dictionary) -> void:
	var header := HBoxContainer.new()
	content.add_child(header)
	var help := _label(header, tr("P7_FORM_HELP"), 17)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var poses := OptionButton.new()
	poses.name = "pose_picker"
	for key in ["P7_POSE_IDLE", "P7_POSE_WALK", "P7_POSE_ACT"]:
		poses.add_item(tr(key))
	poses.select(selected_pose)
	header.add_child(poses)
	poses.item_selected.connect(func(index: int): selected_pose = index)
	var row := GridContainer.new()
	row.columns = 3
	row.add_theme_constant_override("h_separation", 12)
	content.add_child(row)
	for id in Data.growth_rules.mutations:
		var form: Dictionary = Data.growth_rules.mutations[id]
		if not decisions.session.growth.mutation_available(id):
			continue
		var reason: String = decisions.session.growth.mutation_reason(unit, id, decisions.available_incense())
		var result: Dictionary = Data.get_unit(form.result_id)
		var card := HBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var texture := Appearance.pose_texture(form.result_id, selected_pose)
		if texture != null:
			var preview := TextureRect.new()
			preview.name = "preview_" + str(id)
			preview.texture = texture
			preview.custom_minimum_size = Appearance.FRAME_SIZE
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(preview)
			poses.item_selected.connect(func(index: int): preview.texture = Appearance.pose_texture(form.result_id, index))
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(column)
		var text: String = tr("P9_MUTATE_PREVIEW") % [form.name, result.get("名称", form.result_id), form.cost]
		_button(column, "mutate_" + id, text, _send.bind("mutate_form", {"unit_id":unit.instance_id, "form_id":id}), _editable() and reason.is_empty())
		_label(column, tr("P7_FORM_ROLE") % [result.get("定位", ""), result["速度"]], 17)
		_label(column, tr("P9_MUTATE_BASE") % [result["生命"], result["攻击"], result["防御"]], 17)
		if not reason.is_empty():
			_label(column, tr(reason), 16)

func _fusions(_options: Dictionary) -> void:
	_label(content,tr("P7_FUSION_HELP"),18)
	recipe_picker = OptionButton.new()
	recipe_picker.name = "recipe_picker"
	recipe_picker.custom_minimum_size.y = 42
	recipe_ids.clear()
	for id in Data.growth_rules.fusions:
		var recipe: Dictionary = Data.growth_rules.fusions[id]
		recipe_ids.append(str(id))
		recipe_picker.add_item(str(recipe.get("name",id)) + " · " + str(recipe.get("result_name","")) + " · " + tr("P7_COST") % recipe.get("cost",20))
	content.add_child(recipe_picker)
	recipe_picker.select(maxi(0,recipe_ids.find(selected_recipe)))
	if not recipe_ids.is_empty(): selected_recipe = recipe_ids[recipe_picker.selected]
	recipe_picker.item_selected.connect(func(index): selected_recipe = recipe_ids[index]; _fusion_description())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	content.add_child(row)
	partner_picker = OptionButton.new()
	partner_picker.name = "partner_picker"
	partner_picker.custom_minimum_size = Vector2(570,42)
	partner_ids.clear()
	for other in decisions.simulation.humans + decisions.simulation.targets:
		if other == unit or other.dead or other.side != unit.side: continue
		partner_ids.append(str(other.instance_id))
		partner_picker.add_item(tr("P7_FUSION_PARTNER") % [other.display_name,other.hp])
	row.add_child(partner_picker)
	if partner_ids.is_empty(): partner_picker.add_item(tr("P7_NO_PARTNER"))
	partner_picker.select(maxi(0,partner_ids.find(selected_partner)))
	partner_picker.item_selected.connect(func(index): selected_partner = partner_ids[index])
	material_picker = OptionButton.new()
	material_picker.name = "material_picker"
	material_picker.custom_minimum_size = Vector2(350,42)
	material_ids.assign(decisions.session.growth.state.get("materials",[]))
	material_picker.add_item(tr("P7_NO_MATERIAL"))
	for id in material_ids:
		var data: Dictionary = Data.get_unit(id)
		material_picker.add_item(str(data.get("姓名",id)) + tr("P7_REMAINING_NAME"))
	row.add_child(material_picker)
	material_picker.item_selected.connect(func(index): selected_material = "" if index == 0 else material_ids[index - 1])
	description = _label(content,"",18)
	description.custom_minimum_size = Vector2(940,70)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fusion_description()
	_button(content,"fuse",tr("P7_FUSE_CONFIRM"),_fuse,_editable() and Data.growth_rules.fusions.get(selected_recipe,{}).get("status","") == "active")

func _fusion_description() -> void:
	var recipe: Dictionary = Data.growth_rules.fusions.get(selected_recipe,{})
	var names: Array[String] = []
	for id in recipe.get("sources",[]):
		var data: Dictionary = Data.get_unit(id)
		names.append(tr("P7_BORROWED_GHOST") if id == "borrowed_ghost" else str(data.get("姓名",data.get("名称",id))))
	description.text = tr("P7_RECIPE_SOURCES") % " + ".join(names)
	var material: String = recipe.get("material_id","")
	partner_picker.disabled = not material.is_empty()
	if not material.is_empty() and material in material_ids:
		selected_material = material
		material_picker.select(material_ids.find(material) + 1)
	if recipe.get("status","") in ["interface","locked"]: description.text += "\n" + tr("P7_NOT_OPEN")
	if buttons.has("fuse") and is_instance_valid(buttons.fuse): buttons.fuse.disabled = not _editable() or recipe.get("status","") != "active"

func _fuse() -> void:
	var second := partner_ids[partner_picker.selected] if partner_picker.selected >= 0 and partner_picker.selected < partner_ids.size() else ""
	if not str(Data.growth_rules.fusions.get(selected_recipe,{}).get("material_id","")).is_empty(): second = ""
	_send("fuse",{"first_id":unit.instance_id,"second_id":second,"recipe_id":selected_recipe,"material_id":selected_material})

func _vocation(_options: Dictionary) -> void:
	_label(content,tr("P7_VOCATION_HELP"),19)
	for id in Data.growth_rules.jobs:
		var job: Dictionary = Data.growth_rules.jobs[id]
		var quantity: int = decisions.session.growth.state.inventory.get(id,0)
		_button(content,"stamp_" + str(id),str(job.get("name",id)) + " ×%d" % quantity,_send.bind("stamp_job",{"unit_id":unit.instance_id,"job_id":id}),_editable() and quantity > 0)
	var borrow: Dictionary = Data.growth_rules.borrow
	_label(content,tr("P7_BORROW_HELP") + "\n" + tr("P7_BORROW_RISK") % [borrow.duration,borrow.failure_rate*100,borrow.risky_failure_rate*100],18)
	_button(content,"borrow_god",tr("P7_BORROW_PRICE") % [borrow.cost,borrow.names_cost],_send.bind("borrow_god",{"unit_id":unit.instance_id}),_editable())

func _editable() -> bool:
	return decisions._can_command() and is_instance_valid(unit) and unit.side == ("xianghuo" if decisions.view_seat() == "shouxiang" else "yegui")

func _send(action: String, args: Dictionary) -> void:
	if not _editable(): return
	Clock.set_paused(true)
	var result: Dictionary = decisions._issue(action,args)
	decisions._feedback(result)
	if result.ok and is_instance_valid(decisions.selected): decisions._refresh_card()
	if is_instance_valid(unit) and not unit.dead: render()
	else: close()

func _label(parent: Node,text: String,size := 20) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size",size)
	result.add_theme_color_override("font_color", Ink.PAPER)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func _button(parent: Node,id: String,text: String,callback: Callable,allowed := true) -> Button:
	var result := Button.new()
	result.name = id.validate_node_name()
	result.text = text
	result.custom_minimum_size.y = 42
	result.disabled = not allowed
	result.pressed.connect(callback)
	Ink.button_ink(result, false)
	parent.add_child(result)
	buttons[id] = result
	return result
