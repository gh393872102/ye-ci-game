extends SceneTree
## Ordinary openings and a controlled market-to-battle regression. No victory samples.
const SEEDS := ["渡口", "灯市", "秋社", "霜降"]
const CASES := [["R03", "H20"], ["R03", "H26"], ["R04", "H14"], ["R07", "H29"]]
var rows := []
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in SEEDS.size():
		for recruit_id in ["H03", "H11", "H21", "H27"]:
			measure(SEEDS[i], "R01", "", recruit_id)
		measure(SEEDS[i], CASES[i][0], CASES[i][1])
	var portraits := check_card_portraits()
	var path := args[0] if args.size() else "/tmp/ye-night-recruit-posts.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write recruitment results to " + path)
		quit(2)
		return
	file.store_string(JSON.stringify({"rules_hash":load("res://src/replay/BattleRecord.gd").rules_hash(),
			"rows":rows, "portrait_checks":portraits, "failed_checks":failures}, "\t") + "\n")
	file.close()
	await create_timer(0.6).timeout
	quit(1 if failures else 0)

func measure(seed_text: String, ritual: String, id: String, recruit_id := "") -> void:
	var data := root.get_node("Data")
	var night: RefCounted = load("res://src/night/NightRun.gd").new()
	var bridge: RefCounted = load("res://src/night/NightBattleBridge.gd").new()
	var normal := id.is_empty()
	var ok: bool = night.new_p10_run("shouxiang", "example" if normal else "fierce", seed_text, ritual, []).ok
	var row := {"seed":seed_text, "ritual":ritual, "tested_unit":id, "opening_incense":night.state.incense}
	if not normal:
		# Place a real ritual card in a controlled market before n01. Keep stock, caps, currency and price.
		var card: Dictionary = night.config.rewards["p10_recruit_" + id]
		night.state.phase = "market"
		night.state.offers = [card]
		# Fill the four troop slots without occupying this named recruit's post.
		var original: Array = night.state.roster.duplicate(true)
		var troops := original.filter(func(unit): return str(unit.id).begins_with("T")).size()
		for index in range(troops, int(data.battle_rules.troop_cap)):
			night.state.roster.append(night._unit("T01", "post_gate_inner" if card.effect.post != "post_gate_inner" else "post_barricade_outer_court"))
		row.named_with_full_troops = night._effect_reason(card.effect, "")
		row.extra_troop = night._effect_reason({"kind":"recruit", "unit_id":"T01", "post":"post_gate_inner", "count":1}, "")
		ok = ok and row.named_with_full_troops == "" and row.extra_troop == "P5_ROSTER_CAP"
		night.state.roster = original
		var purchase: Dictionary = night.buy_offer(card.id)
		row.price = card.cost
		row.market_result = purchase.reason
		row.balance = night.state.incense
		ok = ok and purchase.ok and is_equal_approx(row.balance, row.opening_incense - row.price)
		night.state.phase = "map"
	var entered: Dictionary = night.choose_node("n01")
	ok = ok and entered.ok
	var combat: Node = load("res://scenes/combat/Combat.tscn").instantiate()
	var built: bool = combat.configure_chunks(night.current_node().chunk_ids)
	ok = ok and built
	root.add_child(combat)
	var sim := combat.get_node("Simulation")
	sim.set_physics_process(false)
	var session := combat.get_node("Session")
	var result: Dictionary = bridge.start(combat, night)
	row.start = result.reason
	row.layout = night.current_node().chunk_ids
	ok = ok and result.ok
	if normal:
		if OS.has_environment("YE_WRITE_PRIOR") and seed_text == SEEDS[0] and recruit_id == "H03":
			var prior_file := FileAccess.open("/tmp/ye-prior-recruit.snap", FileAccess.WRITE)
			prior_file.store_var(bridge.snapshot(combat))
		if OS.has_environment("YE_READ_PRIOR") and seed_text == SEEDS[0] and recruit_id == "H03":
			var prior_file := FileAccess.open("/tmp/ye-prior-recruit.snap", FileAccess.READ)
			var resumed: Dictionary = bridge.restore(combat, night, prior_file.get_var())
			row.prior_save = resumed.ok and bridge.recording.metadata.source == "night_resume_fragment"
			ok = ok and row.prior_save
		row.affordable_at_eight = {}
		for offer in session.purchase_options():
			if offer.allowed and offer.cost <= 8 and str(offer.id).begins_with("H"):
				var posts: Array = session.legal_posts(offer.id)
				if not posts.is_empty():
					row.affordable_at_eight[offer.id] = {"cost":offer.cost,"faction":data.get_unit(offer.id)["所属"],"posts":posts}
		row.opening_roster = []
		for unit in sim.humans:
			row.opening_roster.append(unit.unit_id)
		var receipt: Dictionary = session.purchase(recruit_id)
		var posts: Array = session.legal_posts(recruit_id)
		var deployed := false
		if receipt.ok and not posts.is_empty():
			deployed = session.deploy_at(posts[0]).ok
		row.opening_purchase = {"id":recruit_id, "paid":row.opening_incense - session.incense, "deployed":deployed}
		ok = ok and deployed and row.affordable_at_eight.has(recruit_id)
		if deployed:
			ok = ok and is_equal_approx(row.opening_purchase.paid, row.affordable_at_eight[recruit_id].cost)
		var night_panel: Node = load("res://src/ui/NightPanel.gd").new()
		var expected: String = data.get_unit(recruit_id)["所属"]
		var label: String = night_panel._offer_type({"effect":{"kind":"recruit", "unit_id":recruit_id}})
		var ghost_label: String = night_panel._offer_type({"effect":{"kind":"recruit", "unit_id":"G01"}})
		row.card_labels = [label, ghost_label]
		ok = ok and label == expected and ghost_label == data.get_unit("G01")["谱系"]
		night_panel.free()
	else:
		var actual := []
		for unit in sim.humans:
			if unit.unit_id == id:
				actual.append(unit.current_post)
		row.posts = actual
		row.in_battle_shop = session.rules.purchases.has(id)
		ok = ok and actual.size() == 1 and not row.in_battle_shop and session.purchase(id).reason == "P4_UNKNOWN_PURCHASE"
	row.passed = ok
	rows.append(row)
	if not ok: failures += 1
	if bridge.recording != null: bridge.recording.stop()
	combat.free()

func check_card_portraits() -> Dictionary:
	var panel: Node = load("res://src/ui/NightPanel.gd").new()
	var data := root.get_node("Data")
	var result := {}
	for size in [Vector2(347, 251), Vector2(416, 293)]:
		var checked := 0
		var missing := []
		for id in data.appearance_rules.units:
			if not (str(id).begins_with("H") or str(id).begins_with("G")): continue
			var art: Texture2D = panel._offer_art({"kind":"recruit", "unit_id":id}, size.aspect())
			var face: Array = data.appearance_rules.units[id].get("face_region", [])
			checked += 1
			if not art is AtlasTexture or face.size() != 4:
				missing.append(id)
				continue
			var pixels: Vector2 = art.atlas.get_size()
			var box := Rect2(Vector2(face[0], face[1]) * pixels, Vector2(face[2], face[3]) * pixels)
			if not art.region.encloses(box): missing.append(id)
		result[str(size)] = {"checked":checked, "missing_or_clipped":missing}
		if checked != 64 or not missing.is_empty(): failures += 1
	panel.free()
	return result
