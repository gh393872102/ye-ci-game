extends Node
## Own simulation time. Never pause SceneTree or alter Engine.time_scale.
var paused := false
var time_scale := 1.0
var resume_scale := 1.0
var delta := 0.0
var cooldown_delta := 0.0
var combat_time := 0.0
var wall_time := 0.0
var started_usec := 0

func _ready() -> void:
	process_priority = -100
	started_usec = Time.get_ticks_usec()

func _process(_real_delta: float) -> void:
	wall_time = (Time.get_ticks_usec() - started_usec) / 1000000.0

func _physics_process(real_delta: float) -> void:
	advance(real_delta)

func advance(real_delta: float) -> void:
	delta = 0.0 if paused else real_delta * time_scale
	cooldown_delta = 0.0 if paused else real_delta
	combat_time += delta

func toggle_pause() -> void:
	set_paused(not paused)

func set_paused(value: bool) -> void:
	paused = value
	time_scale = 0.0 if paused else resume_scale
	delta = 0.0
	cooldown_delta = 0.0

func set_speed(value: float) -> void:
	assert(value == 1.0 or value == 2.0)
	resume_scale = value
	time_scale = 0.0 if paused else resume_scale

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
	elif event.is_action_pressed("speed_one"):
		set_speed(1.0)
	elif event.is_action_pressed("speed_two"):
		set_speed(2.0)
