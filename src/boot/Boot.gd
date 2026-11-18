extends Node

func _ready() -> void:
	get_window().min_size = Settings.fit_resolution(Settings.RESOLUTIONS[0])
	if not Data.errors.is_empty():
		# Boot never enters Combat on malformed data, including exported builds.
		var label := Label.new()
		label.text = tr("P9_BOOT_DATA_FAILED")
		label.position = Vector2(40, 80)
		add_child(label)
		if DisplayServer.get_name() == "headless":
			get_tree().quit(1)
		return
	get_tree().set_meta("p9_title_shell", true)
	get_tree().change_scene_to_file.call_deferred("res://scenes/night/Night.tscn")
