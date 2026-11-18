extends Node2D
## The same authored fixture can be inspected on its own or installed in a live map.
const Catalog = preload("res://src/data/ChunkCatalog.gd")
const Ink := Color("81928c")
const Wood := Color("4e443e")
const Paper := Color("c9b28a")

@export var chunk_id := ""
var spec := {}
var world: Node2D

func _ready() -> void:
	if spec.is_empty():
		spec = Catalog.read_chunk(chunk_id)
	if world == null and not spec.is_empty():
		var camera := Camera2D.new()
		camera.position = Vector2(Rules.body_to_px((spec.visual.start + spec.visual.end) / 2.0), Rules.HORIZON_Y - 180)
		add_child(camera)
	queue_redraw()

func _draw() -> void:
	# Installed pieces use the common stained timber and stone atlas. Keep the individual
	# chunk scene callable for geometry inspection, including its original guide marks.
	if spec.is_empty() or is_instance_valid(world):
		return
	var art: Dictionary = spec.visual
	var y := float(Rules.HORIZON_Y)
	var left := Vector2(Rules.body_to_px(art.start), y)
	var width := Rules.body_to_px(art.end - art.start)
	match art.motif:
		"gate_court":
			for x in range(32, int(width), 176):
				var foot := left + Vector2(x, -52)
				draw_line(foot, foot - Vector2(0, 66), Wood, 6)
				draw_colored_polygon(PackedVector2Array([foot - Vector2(10,66), foot - Vector2(0,83), foot + Vector2(10,-66)]), Ink)
				draw_circle(foot - Vector2(0,55), 5, Paper)
		"alley":
			_planks(left, width, Color("354044"))
			for x in range(0, int(width), 155):
				draw_line(left + Vector2(x,-18), left + Vector2(x,-114), Color("36444a"), 8)
			draw_line(left - Vector2(0,108), left + Vector2(width,-108), Ink, 3)
		"beam":
			for x in range(12, int(width), 250):
				var foot := left + Vector2(x, -54)
				draw_line(foot, foot + Vector2(58,-146), Wood, 8)
			if _intact("beam_span"):
				draw_line(left - Vector2(0,185), left + Vector2(width,-185), Color("776350"), 9)
		"register":
			for x in range(35, int(width) - 40, 144):
				var panel := left + Vector2(x,-158)
				draw_rect(Rect2(panel, Vector2(76,62)), Color("303129"))
				for row in 5:
					draw_line(panel + Vector2(8,row * 9 + 12), panel + Vector2(67,row * 9 + 12), Color("676044"), 2)
		"water":
			draw_rect(Rect2(left - Vector2(0,52), Vector2(width,56)), Color("263f49"))
			for x in range(12, int(width) - 90, 110):
				var ripple := left + Vector2(x, -11 - (x % 31))
				draw_line(ripple, ripple + Vector2(69,0), Color("537885"), 2)
		"well":
			var lip := left + Vector2(width * 0.69,-2)
			draw_rect(Rect2(lip - Vector2(37,18),Vector2(74,34)), Color("1e272b"))
			draw_arc(lip - Vector2(0,3), 39, PI, TAU, 20, Ink, 4)
			if _intact("outer_a"):
				draw_line(lip - Vector2(33,23), lip + Vector2(33,-23), Wood, 5)
		"bridge":
			if _intact("stone_bridge"):
				_planks(left, width, Color("5a645e"))
				for x in range(105, int(width), 280):
					draw_arc(left + Vector2(x,118), 97, PI, TAU, 22, Color("4b5554"), 12)
			else:
				draw_line(left, left + Vector2(width * 0.39,18), Ink, 7)
				draw_line(left + Vector2(width * 0.61,27), left + Vector2(width,0), Ink, 7)
		"stage":
			draw_rect(Rect2(left - Vector2(0,61), Vector2(width,65)), Color("3a3333"))
			draw_line(left - Vector2(0,174), left + Vector2(width,-174), Wood, 10)
			if _intact("inner_a"):
				for x in range(15, int(width), 75):
					draw_colored_polygon(PackedVector2Array([left + Vector2(x,-167), left + Vector2(x + 60,-167), left + Vector2(x + 43,-82)]), Color("563c3d"))
		"side_hall":
			_planks(left, width, Color("484b44"))
			for x in range(22, int(width), 102):
				draw_line(left + Vector2(x,-14), left + Vector2(x + 41,-118), Color("5e6859"), 8)
		"fissure":
			var foot := left + Vector2(width * 0.49,-24)
			draw_colored_polygon(PackedVector2Array([foot - Vector2(30,0), foot + Vector2(-11,-102), foot + Vector2(28,-65), foot + Vector2(42,0)]), Color("15191d"))
			draw_line(foot + Vector2(-12,-102), foot + Vector2(27,-66), Color("736582"), 4)
		"hearth":
			var hearth := left + Vector2(width * 0.63,-53)
			draw_rect(Rect2(hearth - Vector2(70,12), Vector2(140,54)), Color("414443"))
			draw_arc(hearth, 28, PI, TAU, 18, Color("a77753"), 5)
			if _intact("stove_hearth"):
				draw_colored_polygon(PackedVector2Array([hearth - Vector2(11,-3), hearth + Vector2(-5,-30), hearth + Vector2(2,-13), hearth + Vector2(11,-34), hearth + Vector2(14,4)]), Color("c99261"))
		"silence":
			for x in range(50, int(width) - 35, 145):
				var peg := left + Vector2(x,-120)
				draw_line(peg, peg + Vector2(0,12), Ink, 2)
				draw_rect(Rect2(peg + Vector2(-15,15),Vector2(30,44)), Color("394049"))
				draw_line(peg + Vector2(-8,29), peg + Vector2(8,29), Paper, 2)
	var font: Font = preload("res://resources/p9_theme.tres").default_font
	draw_string(font, left + Vector2(14,-77), str(spec.title), HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Paper)

func _intact(object_id: String) -> bool:
	if not is_instance_valid(world):
		return true
	var object := world.get_node_or_null(object_id)
	return object != null and object.durability > 0

func _planks(left: Vector2, width: float, color: Color) -> void:
	draw_rect(Rect2(left - Vector2(0,18), Vector2(width,21)), color)
	for x in range(13, int(width), 71):
		draw_line(left + Vector2(x,-16), left + Vector2(x,1), Ink.darkened(0.34), 1)
