extends CanvasLayer
## Explicit opt-in developer UI. Never added to the player's command bar.
var world: Node2D
var overlay: Node2D
var enabled := false
var panel: PanelContainer
var status: Label
var picker: OptionButton
var human: Node2D

func _ready() -> void:
	layer = 5
	human = world.placeholders[0]
	panel = PanelContainer.new()
	panel.position = Vector2(24, 80)
	panel.custom_minimum_size = Vector2(680, 0)
	var theme := Theme.new()
	theme.default_font = world.font
	theme.default_font_size = 20
	panel.theme = theme
	var background := StyleBoxFlat.new()
	background.bg_color = Color("14282b")
	background.content_margin_left = 16
	background.content_margin_right = 16
	background.content_margin_top = 12
	background.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", background)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	for key in ["WALK_PANEL", "WALK_HELP"]:
		var label := Label.new()
		label.text = tr(key)
		box.add_child(label)
	var row := HBoxContainer.new()
	box.add_child(row)
	_button(row, "WALK_SELECT", select_human)
	_button(row, "WALK_OPEN", func(): world.set_all_doors_open(true); status.text = tr("WALK_DOORS_OPEN"))
	_button(row, "WALK_CLOSE", func(): world.set_all_doors_open(false); status.text = tr("WALK_DOORS_CLOSED"))
	var destinations := HBoxContainer.new()
	box.add_child(destinations)
	picker = OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	for post in world.posts:
		picker.add_item(post.name)
	destinations.add_child(picker)
	_button(destinations, "WALK_GO", func(): _go(world.posts[picker.selected].name))
	_button(box, "WALK_RETREAT", func():
		select_human()
		status.text = tr("WALK_ACCEPTED" if human.request_retreat() else human.last_rejection))
	status = Label.new()
	status.text = tr("WALK_IDLE")
	box.add_child(status)
	panel.hide()

func _button(parent: Control, key: String, action: Callable) -> void:
	var button := Button.new()
	button.text = tr(key)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)

func set_enabled(value: bool) -> void:
	enabled = value
	panel.visible = value
	if value:
		overlay.flags[3] = true
	else:
		human.selected = false
		human.queue_redraw()

func select_human() -> void:
	human.selected = true
	human.queue_redraw()
	status.text = tr("WALK_SELECTED")

func _go(post_id: String) -> void:
	select_human()
	status.text = tr("WALK_ACCEPTED" if human.request_post(post_id) else human.last_rejection)

func request_world_point(point: Vector2) -> bool:
	if not enabled or not human.selected:
		return false
	if world.is_outside_gate(point.x):
		status.text = tr("WALK_REJECT_OUTSIDE")
		return false
	for post in world.posts:
		if post.position.distance_to(point) <= 24:
			_go(post.name)
			return human.last_rejection.is_empty()
	status.text = tr("WALK_REJECT_COURT" if world.is_open_court(point) else "WALK_REJECT_TARGET")
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_walk"):
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()
	elif enabled and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point: Vector2 = world.get_global_mouse_position()
		if Rect2(human.position - Vector2(30, Rules.UNIT_HEIGHT_PX), Vector2(60, Rules.UNIT_HEIGHT_PX)).has_point(point):
			select_human()
		else:
			request_world_point(point)
		get_viewport().set_input_as_handled()
