extends Panel
## A non-modal decision guide. Progress belongs to this night and travels with its normal save.
const Ink = preload("res://src/ui/LedgerInk.gd")
const TOPICS := ["PAUSE","BUY","DEPLOY","READ","LINES"]
var night: RefCounted
var title: Label
var body: Label
var next: Button
var skip: Button

func setup(run: RefCounted) -> void:
	night = run
	name = "ExampleTutorial"
	position = Vector2(36,178)
	size = Vector2(514,223)
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("131e20f2")
	skin.border_color = Ink.RULE
	skin.set_border_width_all(1)
	skin.border_width_left = 3
	add_theme_stylebox_override("panel",skin)
	title = Ink.label(self,"",Rect2(23,12,464,44),29,Ink.COPPER,true)
	body = Ink.label(self,"",Rect2(24,64,464,83),22,Ink.PAPER)
	skip = Ink.button(self,"skip",tr("P11_GUIDE_SKIP"),Rect2(25,159,174,44),_skip)
	next = Ink.button(self,"next","",Rect2(301,159,188,44),_next,true,true)
	_refresh()

func _next() -> void:
	night.state.guide_step = int(night.state.get("guide_step",0))+1
	_refresh()

func _skip() -> void:
	night.state.guide_step = TOPICS.size()
	_refresh()

func _refresh() -> void:
	var step := clampi(int(night.state.get("guide_step",0)),0,TOPICS.size())
	visible = step < TOPICS.size()
	if not visible: return
	var key := "P11_GUIDE_" + str(TOPICS[step])
	title.text = tr("P11_GUIDE_HEADING") % [step+1,TOPICS.size(),tr(key)]
	var tide: bool = night.state.mode == "duoming" and step in [1,2,3]
	body.text = tr(key + ("_TIDE" if tide else "_BODY"))
	next.text = tr("P11_GUIDE_DONE" if step == TOPICS.size()-1 else "P11_GUIDE_NEXT")
