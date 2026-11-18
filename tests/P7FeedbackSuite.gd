extends "res://tests/P7Suite.gd"
## Supplemental native event-frame evidence; does not replace the full rule or whole-night suites.
func _run()->void:
	capture=true;feedback_only=true;get_window().size=Vector2i(1920,1080)
	await _scenarios()
	if is_instance_valid(scene):scene.free()
	FileAccess.open("res://docs/phase-reports/p7-feedback-results.json",FileAccess.WRITE).store_string(JSON.stringify({"phase":"P7Feedback","checks":checks,"failures":failures,"results":rows,"builds":builds,"screenshots":shots,"scope":"Actual authored-scenario event frames, fixed simulation time during render, shared core and exact disk replay. Separate from ordinary whole-night G1 timing."},"\t")+"\n")
	print("P7Feedback RESULT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
