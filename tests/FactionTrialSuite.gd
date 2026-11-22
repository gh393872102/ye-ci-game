extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var lab: Node = load("res://scenes/modes/GrowthLab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	var picker: OptionButton = lab.menu.get_node("faction_trial")
	var failures := 0
	for index in picker.item_count:
		picker.select(index)
		lab.buttons.start_faction.pressed.emit()
		if not is_instance_valid(lab.combat):
			print("FAIL ", picker.get_item_text(index), " ", lab.menu_feedback.text)
			failures += 1
			continue
		var sim: Node = lab.combat.get_node("Simulation")
		var session: Node = lab.combat.get_node("Session")
		var members: Array = sim.humans if index < 4 else sim.targets
		var field := "所属" if index < 4 else "谱系"
		var pure := not members.is_empty()
		for unit in members:
			pure = pure and root.get_node("Data").get_unit(unit.unit_id).get(field) == picker.get_item_text(index)
		var ok: bool = pure and session.roster.enabled and not session._ritual_line_broken()
		print("PASS " if ok else "FAIL ", picker.get_item_text(index), " members=", members.size())
		if index == 4:
			var actor: Node2D = members[0]
			var growth: RefCounted = session.growth
			ok = ok and growth.mutation_reason(actor, "V05", 22) == "P7_NEEDS_WATER"
			actor.position.x = root.get_node("Rules").body_to_px(10.0)
			ok = ok and growth.mutation_reason(actor, "V05", 9) == "P7_NO_INCENSE"
			var before: float = session.incense
			var result: Dictionary = session.execute_for("duoming", "mutate_form", {"unit_id":actor.instance_id, "form_id":"V05"}, "player")
			ok = ok and result.ok and actor.unit_id == "G10" and is_equal_approx(session.incense, before - 10)
			print("PASS water mutation" if ok else "FAIL water mutation")
		else:
			ok = ok and not session.growth.mutation_available("V05")
		if not ok:
			failures += 1
		lab.show_menu()
		await process_frame
	lab.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(failures)
