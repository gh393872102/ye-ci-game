extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var host: Node = load("res://scenes/night/Night.tscn").instantiate()
	host.save_path = "user://erase-pair.json"
	root.add_child(host)
	host.start_p10_night("duoming","example","渡口","R01",[],"无册谱")
	host.choose_node("n01")
	var sim: Node = host.combat.get_node("Simulation")
	var session: Node = sim.session
	var reader: Node = sim.humans[0]
	var first: Node = sim.targets[0]
	var second: Node = sim.targets[1]
	for clerk in [first,second]:
		clerk.floor_id = reader.floor_id
		clerk.position = reader.position
	var target := {"target_id":reader.instance_id}
	var before: float = session.names
	var one: Dictionary = session.roster.cast(first,target)
	var after: float = session.names
	var two: Dictionary = session.roster.cast(second,target)
	var duplicate: float = session.names
	var other: Node = sim.spawn_human("H17","post_register")
	second.position = other.position
	second.floor_id = other.floor_id
	var next: Dictionary = session.roster.cast(second,{"target_id":other.instance_id})
	print("two clerks ",reader.unit_id," ",[before,after,duplicate,session.names]," casts ",[one.ok,two.ok,next.ok])
	var ok: bool = one.ok and not two.ok and next.ok and before-after==1 and after==duplicate and duplicate-session.names==1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host.save_path))
	host.free()
	await create_timer(.3).timeout
	quit(0 if ok else 1)
