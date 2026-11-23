extends "res://tools/faction_baseline/OrdinaryOpening.gd"
## Replay a naturally reached n05 map. Every debit uses the ordinary shop and upgrade.
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := OS.get_environment("YE_CI_PIN_MAP")
	if args.size()!=1 or not FileAccess.file_exists(path):
		quit(2)
		return
	var seed_text := args[0]
	var report := {"map_sha256":FileAccess.get_sha256(path),"seed":seed_text,"trials":[]}
	var ok := true
	for wearer in [false,true]:
		for train in ["月讳","骨针","两人"]:
			var night: RefCounted = load("res://src/night/NightRun.gd").new()
			if not night.load_save(path).ok or night.state.seed!=seed_text or night.state.get("opening_faction","")!="符法司" or not night.choose_node("n05").ok:
				quit(2)
				return
			var b := await fight_pin(night,seed_text,wearer,train in ["月讳","两人"],train in ["骨针","两人"])
			var trained := []
			trained.append_array(b.get("upgrades",[]))
			if b.has("aid_upgrade"): trained.append(b.aid_upgrade)
			var spent: float = b.aid.paid
			for order in trained:
				spent += order.paid
				ok = ok and order.ok and order.paid==8
			ok = ok and b.settled and b.hold and b.aid.placed and b.aid.paid==8 and b.foreign_units.is_empty() and spent==(24 if train=="两人" else 16)
			if wearer:
				ok = ok and b.recruit_gear.ok and b.recruit_gear.before-b.recruit_gear.after==1 and b.recruit_gear.paid==0
			report.trials.append({"train":train,"equipped":wearer,"spent":spent,"battle":b})
	report.passed = ok
	FileAccess.open("res://tools/faction_baseline/pin-training-"+seed_text+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	quit(0 if ok else 1)
