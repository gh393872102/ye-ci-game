extends RefCounted
## Rebuilds a seed's route, encounter maps and offer pool from the same authored inputs.
const Chunks = preload("res://src/data/ChunkCatalog.gd")
const Rituals = preload("res://src/data/RitualCatalog.gd")
const Stages = preload("res://src/data/StageOptions.gd")

static func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	for id in Chunks.CORE + Chunks.OPTIONAL:
		if Chunks.read_chunk(id).is_empty(): errors.append("Invalid P10 chunk: "+id)
	for id in Stages.BOSS_IDS:
		var boss: Dictionary = Stages.bosses().get(id,{})
		if not boss.get("unit_id") in Data.combat_profiles or not boss.get("chunks") is Array or Chunks.compose(boss.chunks).is_empty() or float(boss.get("duration",0)) <= 0:
			errors.append("Invalid P10 boss: "+id)
	for id in Stages.MODIFIER_IDS:
		if not Stages.modifiers().has(id): errors.append("Missing P10 modifier: "+id)
	return errors

static func selected_ritual(seed_text: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("ritual/" + seed_text).hash()
	return "R%02d" % rng.randi_range(1,12)

static func configure(config: Dictionary, kind: String, seed_text: String, ritual: String, modifiers: Array) -> bool:
	var row := Rituals.row(ritual)
	if row.is_empty() or not Stages.valid("",modifiers):
		return false
	var fierce := kind == "fierce"
	if not fierce and (kind != "example" or ritual != "R01" or not modifiers.is_empty()):
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = ("route/" + seed_text).hash()
	if fierce:
		_shuffle_stops(config.nodes,rng,ritual)
		config.title = TranslationServer.translate("P10_FIERCE") + " · " + str(row.title)
		Rituals.add_ritual_rewards(config.rewards,ritual)
	for node: Dictionary in config.nodes:
		if node.type not in ["battle","boss"]: continue
		var boss := ""
		if node.type == "boss":
			boss = str(row.boss_id)
			if boss.is_empty():
				boss = ("B%02d" % rng.randi_range(1,3)) if fierce else "B01"
			config.battle_profiles[node.profile_id].duration = float(Stages.bosses()[boss].duration)
		node.boss_id = boss
		if fierce:
			var plan := generate_map(seed_text + "/" + str(node.id),ritual,boss,modifiers)
			if plan.is_empty(): return false
			node.chunk_ids = plan.chunk_ids
		elif not node.has("chunk_ids") or Chunks.compose(node.chunk_ids).is_empty():
			return false
	return true

static func generate_map(seed_text: String, ritual: String, boss: String, modifiers: Array, extra_chunks: Array = []) -> Dictionary:
	var row := Rituals.row(ritual)
	if row.is_empty() or not Stages.valid(boss,modifiers): return {}
	var weights: Dictionary = row.chunk_weights.duplicate()
	var extra_weights: Dictionary = Stages.chunk_weights(modifiers)
	for id in extra_weights:
		weights[id] = float(weights.get(id,1.0)) * float(extra_weights[id])
	var required: Array = row.required_chunks.duplicate()
	for id in Stages.required_chunks(boss,modifiers) + extra_chunks:
		if id not in required: required.append(id)
	return Chunks.generate(seed_text,weights,required)

static func _shuffle_stops(nodes: Array, rng: RandomNumberGenerator, ritual: String) -> void:
	# Keep the branch and boss reachable. Shuffle the supply stops within the route.
	var stops: Array[Dictionary] = []
	var positions: Array[int] = []
	var events: Array[Dictionary] = []
	for i in nodes.size():
		if nodes[i].type not in ["market","event","rest"] or nodes[i].id == "n06": continue
		positions.append(i)
		stops.append(nodes[i].duplicate(true))
		if nodes[i].type == "event": events.append(nodes[i])
	for i in range(stops.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var hold: Dictionary = stops[i]
		stops[i] = stops[j]
		stops[j] = hold
	for i in positions.size():
		var old: Dictionary = nodes[positions[i]]
		var next: Dictionary = stops[i]
		for key in ["id","depth","next"]:
			next[key] = old[key]
		if next.type == "event" and ritual == "R11":
			var total := 0.0
			for source in events: total += Rituals.event_weight(ritual,source.event_id)
			var roll := rng.randf()*total
			for source in events:
				roll -= Rituals.event_weight(ritual,source.event_id)
				if roll <= 0:
					for key in ["event_id","title","description"]: next[key] = source[key]
					break
		nodes[positions[i]] = next
