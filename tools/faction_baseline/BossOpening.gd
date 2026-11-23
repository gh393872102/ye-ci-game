extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Reload the same paid ordinary roster for each isolated B01 configuration.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[2] if args.size()==3 else "opening"
	if (args.size() not in [2,3] or mode not in ["opening","read","train","reserve","cover"]) or args[0] not in ["渡口","灯市","秋社"]:
		quit(2)
		return
	var stages: Dictionary = load("res://src/data/StageOptions.gd").bosses()
	var original: Dictionary = stages.B01
	var trials := []
	probe_boss_gate = true
	var orders := []
	if mode == "cover":
		orders.append({"ratio":original.initial_doors.door_hall,"setback":0.0,"read":true,"train":"H02"})
		for post in ["post_hall_door","post_register"]:
			orders.append({"ratio":original.initial_doors.door_hall,"setback":0.0,"read":true,"train":"","aid_post":post})
		orders.append({"ratio":original.initial_doors.door_hall,"setback":0.0,"read":true,"train":"","aid_post":"post_register","timing":-1})
	elif mode == "reserve":
		for timing in [-1,0,25,27,29]:
			orders.append({"ratio":original.initial_doors.door_hall,"setback":0.0,"read":true,"train":"H01","timing":timing})
	elif mode == "train":
		for read_now in [false,true]:
			orders.append({"ratio":original.initial_doors.door_hall,"setback":0.0,"read":read_now,"train":"H01"})
		orders.append({"ratio":original.initial_doors.door_hall,"setback":0.0,"read":false,"train":"H01","again":["H01"]})
	else:
		for ratio in ([0.06] if mode=="read" else [0.06,0.30,1.0]):
			for setback in [0.0,20.0]:
				orders.append({"ratio":ratio,"setback":setback,"read":mode=="read","train":""})
	for order in orders:
		var night: RefCounted = load("res://src/night/NightRun.gd").new()
		if not night.load_save(args[1]).ok or night.state.seed!=args[0] or night.state.opening_faction!="守香司" or not night.choose_node("n10").ok or night.current_node().boss_id!="B01":
			quit(2)
			return
		reading_limit = 1 if order.get("timing",0) == -1 else 2
		second_read_after = order.get("timing",0)
		var spec := original.duplicate(true)
		spec.initial_doors.door_hall = order.ratio
		spec.formations[0].x = float(original.formations[0].x)-order.setback
		stages.B01 = spec
		var b := await fight(night,"守香司",args[0],false,order.get("aid_post",""),false,"H03" if order.has("aid_post") else "",true,false,1,[],false,-1.0,order.train,"",order.read,"破门",0.0,false,false,order.get("again",[]))
		stages.B01 = original
		if not b.get("settled",false) or not is_equal_approx(b.gate.initial_hp,b.gate.maximum*order.ratio):
			quit(2)
			return
		trials.append({"ratio":order.ratio,"second_after":second_read_after,"training":order.train,"opening_x":spec.formations[0].x,"battle":b})
	var file := FileAccess.open("res://tools/faction_baseline/boss-opening-%s%s.json"%[args[0],"" if mode=="opening" else "-"+mode],FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed":args[0],"checkpoint_sha256":FileAccess.get_sha256(args[1]),"trials":trials},"\t")+"\n")
	quit(0)
