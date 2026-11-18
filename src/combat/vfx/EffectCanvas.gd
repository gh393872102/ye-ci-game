extends Node2D
## Draw on the world pixel grid. The effect layer updates the frame when play or camera position changes.
var simulation: Node2D
var frame := Rect2()

func refresh(world_frame: Rect2) -> void:
	frame = world_frame
	queue_redraw()

func pixel(point: Vector2, size := 2.0) -> Vector2:
	return point.snapped(Vector2(size, size))

func path(origin: Vector2, offsets: Array[Vector2], color: Color, width := 2.0) -> void:
	var points := PackedVector2Array()
	for offset in offsets:
		points.append(pixel(origin + offset))
	draw_polyline(points, color, width)

func fleck(at: Vector2, size: Vector2, color: Color) -> void:
	draw_rect(Rect2(pixel(at, 2.0), size), color)
