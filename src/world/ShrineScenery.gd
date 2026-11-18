extends Node2D
## The static rear layers keep their canvas batches when an occupied slot or door changes.
var painter: RefCounted
var is_sky := false
var is_cover := false

func _ready() -> void:
	set_process(is_sky)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		position.x = roundf((camera.get_screen_center_position().x - Rules.CAMERA_WIDTH_PX * .5) * .86)

func _draw() -> void:
	if is_sky:
		painter.draw_sky(self)
	elif is_cover:
		painter.draw_cover(self)
	else:
		painter.draw_architecture(self)
