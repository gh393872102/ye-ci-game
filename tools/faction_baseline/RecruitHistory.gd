extends SceneTree
## One previous-node casualty in an otherwise normal opening. No balance estimate.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path = "user://history-%d.json" % OS.get_process_id()
	root.add_child(host)
	var ok: bool = host.run.new_p10_run("shouxiang","example","渡口","R01",[],"","符法司").ok
	# Use an actual unit record with a unique uid to exercise Night's casualty handoff.
	var record: Dictionary = host.run.state.roster[0].duplicate(true)
	record.id = "H17"
	record.uid = "fixture_fallen_h17"
	record.hp = 0.0
	host.run.state.fallen.append(record)
	host.choose_node("n01")
	var ui: Node = host.combat.get_node("Decisions")
	ui.open_purchase()
	ok = ok and ui.previous_casualties.has("H17") and ui.offer_status.H17.text == "可再招 · 前战阵亡"
	ui.buttons.purchase_scope.pressed.emit()
	ok = ok and not ui.offer_status.has("H17") and ui.offer_status.has("H19")
	ui.buttons.buy_H19.pressed.emit()
	ok = ok and ui.buttons.has("defend_hall")
	ui.buttons.defend_hall.pressed.emit()
	ok = ok and ui.current_panel.is_empty() and "主殿门厅" in ui.feedback.text
	print("Recruit history filter and direct hall deployment: ",ok)
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://history-%d.json" % OS.get_process_id()))
	await create_timer(0.4).timeout
	quit(0 if ok else 1)
