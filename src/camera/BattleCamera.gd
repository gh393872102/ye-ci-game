extends Camera2D
var edge_scroll := false
var dragging := false

func _ready() -> void:
	add_to_group("camera")
	zoom = Vector2.ONE
	position_smoothing_enabled = false
	_sync_preferences()
	Settings.changed.connect(_sync_preferences)
	set_left(Rules.DEFAULT_CAMERA_LEFT)

func _sync_preferences() -> void:
	edge_scroll = Settings.values.edge_scroll

func set_left(value: float) -> void:
	position = Vector2(clampf(value, 0, Rules.REFERENCE_MAP_WIDTH_PX - Rules.CAMERA_WIDTH_PX) + Rules.CAMERA_WIDTH_PX / 2.0, Rules.DESIGN_HEIGHT / 2.0)
	force_update_scroll()

func left() -> float:
	return position.x - Rules.CAMERA_WIDTH_PX / 2.0

func world_rect() -> Rect2:
	return Rect2(left(), 0, Rules.CAMERA_WIDTH_PX, Rules.HORIZON_Y)

func _process(real_delta: float) -> void:
	if Settings.gameplay_modal_open():
		dragging = false
		return
	var axis := Input.get_axis("camera_left", "camera_right")
	if edge_scroll and Settings.mouse_pan_active and not dragging and DisplayServer.window_is_focused():
		var mouse := get_viewport().get_mouse_position()
		if mouse.y >= Rules.TOP_BAR_HEIGHT and mouse.y < Rules.HORIZON_Y:
			if mouse.x < 18:
				axis -= 1
			elif mouse.x > Rules.DESIGN_WIDTH - 18:
				axis += 1
	if axis != 0.0:
		set_left(left() + axis * Rules.CAMERA_PAN_SPEED * real_delta)

func _input(event: InputEvent) -> void:
	if Settings.gameplay_modal_open():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		dragging = event.pressed
	if event is InputEventMouseMotion and dragging:
		set_left(left() - event.relative.x)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging = false
