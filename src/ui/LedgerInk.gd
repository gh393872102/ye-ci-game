extends RefCounted
## Shared visual treatment for the night ledger and its four reference books.
const PAPER := Color("dfddd0")
const MUTED := Color("a7b3a4")
const ASH := Color("828f86")
const COPPER := Color("acccba")
const RUST := Color("d69d82")
const RULE := Color("44574f")
const DARK := Color("101718")
const PLATE := Color("1b2524")
const ASSETS := "res://assets/ui/night/"
static var _serif: SystemFont

static func box(parent: Node, rect: Rect2, fill: Color, border := Color.TRANSPARENT) -> ColorRect:
	var panel := ColorRect.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.color = fill
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	if border.a > 0:
		var edge := Panel.new()
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.add_theme_stylebox_override("panel", skin(Color.TRANSPARENT, border))
		panel.add_child(edge)
		edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return panel

static func skin(fill: Color, border: Color, line := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(line)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

static func label(parent: Node, value: String, rect: Rect2, points: int, ink := PAPER, serif := false) -> Label:
	var field := Label.new()
	field.text = value
	field.position = rect.position
	field.size = rect.size
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	field.add_theme_font_size_override("font_size", points)
	field.add_theme_color_override("font_color", ink)
	if serif:
		if _serif == null:
			_serif = SystemFont.new()
			_serif.font_names = PackedStringArray(["Songti SC", "Noto Serif CJK SC", "SimSun", "PingFang SC"])
			var shared := ThemeDB.get_project_theme()
			if shared != null and shared.default_font != null:
				_serif.fallbacks = [shared.default_font]
		field.add_theme_font_override("font", _serif)
	parent.add_child(field)
	return field

static func one_line(field: Label) -> void:
	field.autowrap_mode = TextServer.AUTOWRAP_OFF
	field.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

static func button(parent: Node, id: String, value: String, rect: Rect2, action: Callable, allowed := true, accent := false) -> Button:
	var control := Button.new()
	control.name = id.validate_node_name()
	control.text = value
	control.position = rect.position
	control.size = rect.size
	control.disabled = not allowed
	control.pressed.connect(action)
	control.add_theme_font_size_override("font_size", 21)
	button_ink(control, accent)
	parent.add_child(control)
	return control

static func button_ink(control: Button, accent: bool) -> void:
	control.add_theme_color_override("font_color", PAPER)
	control.add_theme_color_override("font_hover_color", PAPER)
	control.add_theme_color_override("font_focus_color", PAPER)
	control.add_theme_color_override("font_pressed_color", PAPER)
	control.add_theme_color_override("font_disabled_color", MUTED)
	control.add_theme_stylebox_override("normal", skin(Color("354b43") if accent else PLATE, COPPER if accent else RULE))
	control.add_theme_stylebox_override("hover", skin(Color("3b5349"), COPPER))
	control.add_theme_stylebox_override("pressed", skin(Color("2a3d36"), COPPER, 2))
	control.add_theme_stylebox_override("disabled", skin(Color("181e1e"), Color("354540")))
	control.add_theme_stylebox_override("focus", skin(Color.TRANSPARENT, Color("e3ce9e"), 3))

static func texture(parent: Node, source: Texture2D, rect: Rect2, crop := true) -> TextureRect:
	var frame := TextureRect.new()
	frame.position = rect.position
	frame.size = rect.size
	frame.texture = source
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if crop else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	return frame

static func art(name: String) -> Texture2D:
	var path := ASSETS + name + ".webp"
	return load(path) if ResourceLoader.exists(path, "Texture2D") else null

static func object_art(quarter: int) -> Texture2D:
	var sheet := art("night-objects")
	if sheet == null:
		return null
	return _tile(sheet, 2, 2, quarter)

static func ritual_art(index: int) -> Texture2D:
	var path := "res://assets/ui/p9/ritual-objects.webp"
	if not ResourceLoader.exists(path, "Texture2D"):
		return null
	return _tile(load(path), 3, 2, index)

static func censer_art(id: String) -> Texture2D:
	match id:
		"I01", "I12": return object_art(3)
		"I02", "I09", "I14": return object_art(2)
		"I03", "I08", "I20": return ritual_art(1)
		"I04", "I11": return ritual_art(3)
	return null

static func _tile(sheet: Texture2D, columns: int, rows: int, index: int) -> Texture2D:
	var size := sheet.get_size() / Vector2(columns, rows)
	var view := AtlasTexture.new()
	view.atlas = sheet
	view.region = Rect2(Vector2(index % columns, floori(float(index) / columns)) * size, size)
	view.filter_clip = true
	return view

static func scroll_rows(parent: Node, rect: Rect2, gap := 8) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.position = rect.position
	scroll.size = rect.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", gap)
	scroll.add_child(rows)
	return rows
