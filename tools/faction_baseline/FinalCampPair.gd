extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Compare offers at one natural n09 camp without granting resources or reviving units.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=2:
		quit(2)
		return
	var trials := []
	var passed := true
	for policy in ["rest","brace","hire","hire_hall"]:
		var night: RefCounted = load("res://src/night/NightRun.gd").new()
		if not night.load_save(args[0]).ok or night.state.phase!="rest" or night.state.current_node_id!="n09" or night.state.opening_faction!="符法司":
			quit(2)
			return
		var cash: float = night.state.incense
		var trial := {"policy":policy,"seed":night.state.seed,"before":cash,"offers":night.rest_reserve_options(),"before_roster":night.state.roster.duplicate(true)}
		var decision: Dictionary
		match policy:
			"rest": decision = night.finish_rest()
			"brace": decision = night.brace_hall_at_rest()
			_: decision = night.finish_rest("H18")
		trial.decision = decision
		trial.after = night.state.incense
		trials.append(trial)
		if not decision.ok:
			passed = passed and cash==night.state.incense and night.state.phase=="rest"
			continue
		if policy=="hire_hall":
			for member in night.state.roster:
				if member.id=="H18":
					trial.move = night.reserve_post(member.uid,"post_hall_door")
			if not trial.get("move",{}).get("ok",false): continue
		if not night.choose_node("n10").ok:
			passed=false
			continue
		var b := await fight(night,"符法司",trial.seed,false,"",false,"",true)
		trial.battle = b
		passed = passed and b.settled and b.hold and b.foreign_units.is_empty() and (policy=="rest" or is_equal_approx(cash-trial.after,12))
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"map_sha256":FileAccess.get_sha256(args[0]),"trials":trials}))
	quit(0 if passed else 1)
