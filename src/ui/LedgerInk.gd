extends RefCounted
## Shared visual treatment for the night ledger and its four reference books.
const PAPER := Color("ece0cb")
const MUTED := Color("bab09d")
const ASH := Color("989284")
const COPPER := Color("cca875")
const RUST := Color("e2a389")
const RULE := Color("5e4e3b")
const DARK := Color("101013")
const PLATE := Color("211d1c")
const SEAL := Color("72382f")
const ASSETS := "res://assets/ui/night/"
const PAPER_SHADER = preload("res://assets/ui/night/ink_paper.gdshader")
static var _serif: SystemFont
static var _paper_material: ShaderMaterial

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

static func folio(parent: Node, rect: Rect2, tone := Color("151315f9"), border := RULE) -> ColorRect:
	var surface := box(parent, rect, tone)
	if _paper_material == null:
		_paper_material = ShaderMaterial.new()
		_paper_material.shader = PAPER_SHADER
	surface.material = _paper_material
	binding(surface, Rect2(Vector2.ZERO, rect.size), border)
	return surface

static func binding(parent: Node, rect: Rect2, color := RULE) -> Control:
	var line := Control.new()
	line.position = rect.position
	line.size = rect.size
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	line.draw.connect(func(): draw_binding(line, line.size, color))
	return line

static func draw_binding(canvas: CanvasItem, bounds: Vector2, color := RULE) -> void:
	var inner := Rect2(Vector2(1, 1), bounds - Vector2(2, 2))
	canvas.draw_rect(inner, color, false, 1)
	canvas.draw_rect(inner.grow(-5), Color(color, 0.42), false, 1)
	for corner in [Vector2(8, 8), Vector2(bounds.x - 8, 8), Vector2(8, bounds.y - 8), bounds - Vector2(8, 8)]:
		var direction := Vector2(1 if corner.x < bounds.x / 2 else -1, 1 if corner.y < bounds.y / 2 else -1)
		var key := PackedVector2Array([corner + direction * Vector2(0, 17), corner, corner + direction * Vector2(17, 0)])
		var inner_key := PackedVector2Array([corner + direction * Vector2(5, 11), corner + direction * Vector2(5, 5), corner + direction * Vector2(11, 5)])
		canvas.draw_polyline(key, color, 1.3)
		canvas.draw_polyline(inner_key, color, 1.0)

static func ruling(parent: Node, rect: Rect2, color := RULE) -> void:
	var line := Control.new()
	line.position = rect.position
	line.size = rect.size
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	line.draw.connect(func():
		var center := line.size / 2
		line.draw_line(Vector2(0, center.y), center - Vector2(16, 0), color, 1)
		line.draw_line(center + Vector2(16, 0), Vector2(line.size.x, center.y), color, 1)
		for offset in [-8.0, 0.0, 8.0]:
			var at := center + Vector2(offset, 0)
			line.draw_polyline(PackedVector2Array([at - Vector2(4, 0), at - Vector2(0, 4), at + Vector2(4, 0), at + Vector2(0, 4), at - Vector2(4, 0)]), color, 1)
	)

static func serif_font() -> Font:
	if _serif == null:
		_serif = SystemFont.new()
		_serif.font_names = PackedStringArray(["Songti SC", "Noto Serif CJK SC", "SimSun", "PingFang SC"])
		var shared := ThemeDB.get_project_theme()
		if shared != null and shared.default_font != null:
			_serif.fallbacks = [shared.default_font]
	return _serif

static func label(parent: Node, value: String, rect: Rect2, points: int, ink := PAPER, serif := false) -> Label:
	var field := Label.new()
	field.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	field.position = rect.position
	field.size = rect.size
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_theme_font_size_override("font_size", points)
	field.add_theme_color_override("font_color", ink)
	if serif:
		field.add_theme_font_override("font", serif_font())
	field.text = value
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
	control.add_theme_stylebox_override("normal", skin(Color("493025") if accent else PLATE, COPPER if accent else RULE))
	control.add_theme_stylebox_override("hover", skin(Color("483127"), COPPER))
	control.add_theme_stylebox_override("pressed", skin(Color("5e3328"), COPPER, 2))
	control.add_theme_stylebox_override("disabled", skin(Color("161417"), Color("3b332c")))
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
	var bar := scroll.get_v_scroll_bar()
	var track := skin(Color("221b1b"), Color("4d3c2e"))
	var grip := skin(Color("8c704d"), Color("a68a60"))
	track.set_content_margin_all(4)
	grip.set_content_margin_all(4)
	for key in ["scroll", "scroll_focus"]:
		bar.add_theme_stylebox_override(key, track)
	for key in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(key, grip)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", gap)
	scroll.add_child(rows)
	return rows
