extends Node
## Clearly authored trials; the normal night never receives this trial inventory.
const Builds = ["chaodu","shoumen","pomen","dengmian","shangliang","wuce"]
var scenario: RefCounted
var combat: Node2D
var menu: Control
var toolbar: Control
var heading: Label
var notes: Label
var notes_scroll: ScrollContainer
var feedback: Label
var menu_feedback: Label
var buttons: Dictionary = {}
var recording_saved := false

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 22
	add_child(layer)
	var font: Font = preload("res://resources/p9_theme.tres").default_font
	var skin := Theme.new()
	skin.default_font = font
	skin.default_font_size = 22
	menu = Control.new()
	menu.theme = skin
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.size = Vector2(1920,1080)
	layer.add_child(menu)
	var background := ColorRect.new()
	background.color = Color("0b171c")
	background.size = Vector2(1920,1080)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(background)
	_label(menu,tr("P7_LAB_TITLE"),Rect2(64,40,1450,60),36)
	_label(menu,tr("P7_LAB_HELP"),Rect2(64,120,1700,80),22)
	_button(menu,"night",tr("P6_BACK_NIGHT"),Rect2(1590,40,260,50),func(): get_tree().change_scene_to_file("res://scenes/night/Night.tscn"))
	for index in Builds.size():
		var id: String = Builds[index]
		var rect := Rect2(64+(index%3)*604,250+(index/3)*310,560,240)
		_button(menu,"build_"+id,tr("P7_BUILD_"+id.to_upper()) + "\n\n" + tr("P7_BUILD_HELP_"+id.to_upper()),rect,start_build.bind(id))
	var factions := OptionButton.new()
	factions.name = "faction_trial"
	factions.position = Vector2(64, 890)
	factions.size = Vector2(420, 62)
	menu.add_child(factions)
	var ids: Array = preload("res://src/growth/BuildScenario.gd").FACTIONS
	for id in ids:
		factions.add_item(tr("P7_BUILD_" + str(id).to_upper()))
	_button(menu, "start_faction", "进入单阵营试炼", Rect2(510, 890, 270, 62), func(): start_build(ids[factions.selected]))
	menu_feedback = _label(menu,"",Rect2(64,1000,1600,45),20)
	toolbar = Control.new()
	toolbar.theme = skin
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toolbar)
	heading = _label(toolbar,"",Rect2(600,66,425,90),21)
	notes_scroll = ScrollContainer.new()
	notes_scroll.position = Vector2(600,730)
	notes_scroll.size = Vector2(1250,160)
	notes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toolbar.add_child(notes_scroll)
	notes = _label(notes_scroll,"",Rect2(0,0,1200,160),19)
	notes.custom_minimum_size.x = 1200
	_button(toolbar,"inspect_next",tr("P6_INSPECT_NEXT"),Rect2(600,912,300,48),func(): combat.get_node("Decisions")._cycle_unit(1))
	_button(toolbar,"growth",tr("P7_GROWTH_OPEN"),Rect2(920,912,300,48),_open_growth)
	_button(toolbar,"return",tr("P7_RETURN_LAB"),Rect2(1560,1028,320,44),show_menu)
	feedback = _label(toolbar,"",Rect2(600,1038,920,38),18)
	toolbar.hide()
	Clock.set_paused(true)

func start_build(id: String, seed := "") -> void:
	var next_scenario: RefCounted = load("res://src/growth/BuildScenario.gd").new()
	var candidate: Node2D = preload("res://scenes/combat/Combat.tscn").instantiate()
	candidate.name = "PreparedCombat"
	add_child(candidate)
	var result: Dictionary = next_scenario.start(candidate,id,seed)
	if not result.ok:
		remove_child(candidate)
		candidate.queue_free()
		feedback.text = tr(str(result.reason))
		menu_feedback.text = feedback.text
		return
	_dispose()
	scenario = next_scenario
	combat = candidate
	combat.name = "Combat"
	combat.get_node("BattleCamera").make_current()
	combat.get_node("Decisions").managed_by_night = true
	menu.hide()
	toolbar.show()
	heading.text = tr("P7_BUILD_"+id.to_upper()) + " · " + tr("P7_AUTHORED_TRIAL")
	var config: Dictionary = scenario.scenario
	notes.text = "\n".join(config.get("notes",[]) + config.get("steps",[]))
	feedback.text = tr("P7_TRIAL_PAUSED")
	recording_saved = false
	Clock.set_paused(true)

func _physics_process(_delta: float) -> void:
	if scenario != null and is_instance_valid(combat): scenario.advance(Clock.delta)

func _process(_delta: float) -> void:
	if scenario == null or not is_instance_valid(combat): return
	var decision: CanvasLayer = combat.get_node("Decisions")
	var growth_open: bool = decision.growth_panel.surface.visible
	notes_scroll.visible = not growth_open and not decision.panel.visible and decision.activity.text.is_empty()
	buttons.inspect_next.visible = not growth_open
	buttons.growth.visible = not growth_open
	feedback.visible = decision.feedback.text.is_empty()
	if not combat.get_node("Session").result.is_empty() and not recording_saved:
		var result: Dictionary = scenario.finish_recording()
		recording_saved = bool(result.get("ok",false))
		feedback.text = tr(str(combat.get_node("Session").result.reason))

func _open_growth() -> void:
	if not is_instance_valid(combat): return
	var decision: CanvasLayer = combat.get_node("Decisions")
	if not is_instance_valid(decision.selected):
		var session: Node = combat.get_node("Session")
		var collection: Array = combat.get_node("Simulation").humans if session.mode == "shouxiang" else combat.get_node("Simulation").targets
		if collection.is_empty(): return
		decision.select_unit(collection[0])
	decision.open_growth()

func show_menu() -> void:
	if scenario != null and is_instance_valid(combat) and not recording_saved: scenario.finish_recording()
	_dispose()
	toolbar.hide()
	menu.show()
	Clock.set_paused(true)

func _dispose() -> void:
	if is_instance_valid(combat):
		remove_child(combat)
		combat.queue_free()
	combat = null
	scenario = null

func _label(parent: Node,text: String,rect: Rect2,font_size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.position = rect.position
	result.size = rect.size
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",Color("cdd1bc"))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func _button(parent: Node,id: String,text: String,rect: Rect2,callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.position = rect.position
	result.size = rect.size
	result.pressed.connect(callback)
	parent.add_child(result)
	buttons[id] = result
	return result
