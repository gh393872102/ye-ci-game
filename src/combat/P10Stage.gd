extends Node2D
## Authored incursions and optional register pressures use the shared actors and fixed combat steps.
const FEEDBACK_SECONDS := 3.0
const UPPER_ROOMS := ["gallery", "stair_landing", "incense", "rear", "beam", "bell", "attic"]
const EFFECT_KEYS := {
	"guard": "P10_GATE_GUARD", "break": "P10_GATE_BREAK", "flood": "P10_TIDE_FLOOD",
	"upper": "P10_UPPER_ENTRY", "upper_lost": "P10_UPPER_LOST",
	"rekindle": "P10_PURIFIED", "purify": "P10_PURIFIED_NO_REKINDLE",
	"window": "P10_NAMING_WINDOW", "listed": "P10_NAMING_RESOLVED", "watched": "P10_WATCHED_READER"
}

var session: Node
var simulation: Node2D
var spec: Dictionary
var modifiers: Dictionary
var state: Dictionary

func setup(owner: Node, boss: Dictionary, active_modifiers: Dictionary, seed_text: String) -> void:
	session = owner
	simulation = owner.simulation
	spec = boss
	modifiers = active_modifiers
	state = {
		"boss_id": str(spec.get("id", "")), "modifier_ids": modifiers.keys(), "seed": seed_text,
		"formation": 0, "boss_actor": "", "gate_entrants": [], "gate_broken": false, "gate_flooded": false,
		"upper_exposed": 0.0, "upper_engaged": false, "upper_lost": false,
		"watch_queued": false, "watch_rolls": 0, "boss_listed": false,
		"feedback": "", "feedback_detail": "", "feedback_left": 0.0, "effects": []
	}
	z_index = 40
	session.set_meta("p10_rekindle_multiplier", float(modifiers.get("N01", {}).get("recovery_multiplier", 1.0)))
	simulation.step_completed.connect(_advance)
	simulation.tide.effect_emitted.connect(_tide_effect)
	session.command_applied.connect(_watch_ritual)

func detach() -> void:
	simulation.step_completed.disconnect(_advance)
	simulation.tide.effect_emitted.disconnect(_tide_effect)
	session.command_applied.disconnect(_watch_ritual)

func open() -> void:
	for id in spec.get("initial_doors", {}):
		_crack_door(str(id), float(spec.initial_doors[id]))
	if modifiers.has("N02"):
		_crack_door("door_side", float(modifiers.N02.side_durability_ratio))
	_spawn_formations()
	session._update_warnings()
	queue_redraw()

func _crack_door(id: String, ratio: float) -> void:
	var door: Node2D = simulation.world.get_node(id)
	door.set_durability(door.max_durability * ratio)

func snapshot() -> Dictionary:
	return state.duplicate(true)

func resume(saved: Dictionary) -> void:
	state = saved.duplicate(true)
	queue_redraw()

static func valid_snapshot(saved: Dictionary, boss: Dictionary) -> bool:
	for key in ["gate_broken", "gate_flooded", "upper_engaged", "upper_lost", "watch_queued", "boss_listed"]:
		if not saved.get(key) is bool:
			return false
	for key in ["boss_actor", "feedback", "feedback_detail"]:
		if not saved.get(key) is String:
			return false
	for key in ["formation", "watch_rolls", "upper_exposed", "feedback_left"]:
		if not _nonnegative_number(saved.get(key)):
			return false
	if int(saved.formation) != float(saved.formation) or int(saved.formation) > boss.get("formations", []).size() or int(saved.watch_rolls) != float(saved.watch_rolls):
		return false
	if not saved.get("gate_entrants") is Array or saved.gate_entrants.size() > 64:
		return false
	if not saved.gate_entrants.all(func(id): return id is String):
		return false
	if not saved.get("effects") is Array or saved.effects.size() > 16:
		return false
	for effect in saved.effects:
		if not effect is Dictionary or not EFFECT_KEYS.has(effect.get("kind")):
			return false
		if not _nonnegative_number(effect.get("x")) or not _nonnegative_number(effect.get("y")) or not _nonnegative_number(effect.get("left")):
			return false
	return true

static func _nonnegative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)) and float(value) >= 0.0

func _advance(delta: float) -> void:
	if not session.running:
		return
	state.feedback_left = maxf(0.0, float(state.feedback_left) - delta)
	for index in range(state.effects.size() - 1, -1, -1):
		state.effects[index].left = float(state.effects[index].left) - delta
		if state.effects[index].left <= 0.0:
			state.effects.remove_at(index)
	var boss_ink := float(spec.get("ink_drain", 0.0)) if not state.boss_listed else 0.0
	var drain := boss_ink + float(modifiers.get("N01", {}).get("drain_per_second", 0.0))
	if drain > 0:
		_drain_register(drain * delta)
	if modifiers.has("N03") and not state.watch_queued and simulation.simulation_time >= float(modifiers.N03.watch_spawn_at):
		var tide: RefCounted = simulation.tide
		if simulation.targets.size() + tide.pending.size() < int(tide.config.capacity):
			tide.pending.append("G26")
			state.watch_queued = true
	_spawn_formations()
	match state.boss_id:
		"B01": _watch_gate()
		"B02": _watch_upper(delta)
		"B03": _watch_naming_window()
	queue_redraw()

func _drain_register(amount: float) -> void:
	var ward: float = float(session.roster.state.get("register_ward_multiplier", 1.0)) if float(session.roster.state.get("register_ward", 0.0)) > 0 else 1.0
	session.names = maxf(0.0, session.names - amount * ward)

func _spawn_formations() -> void:
	var formations: Array = spec.get("formations", [])
	while int(state.formation) < formations.size():
		var formation: Dictionary = formations[int(state.formation)]
		if float(formation.at) > simulation.simulation_time + 0.00001:
			return
		var floor_id := int(formation.floor)
		var x := Rules.body_to_px(float(formation.x))
		var unit: Node2D = simulation.tide.spawn(str(formation.unit), int(formation.lane), x)
		if unit == null:
			return
		unit.floor_id = floor_id
		unit.position.y = simulation.world.floor_y(floor_id) + float(simulation.tide.config.lane_offsets[int(formation.lane)])
		unit.current_post = "upper_entry" if floor_id > 0 else "ghost_main_path"
		unit.brain.stage = "upper" if floor_id > 0 else ("rear" if state.boss_id == "B03" else "main")
		if formation.get("climb", false):
			unit.brain.stage = "climb"
			unit.set_state("Climb")
			simulation.tide.effect("climb_start", unit.position, unit.instance_id)
		unit.sync_meta()
		if formation.role == "boss":
			state.boss_actor = unit.instance_id
		elif formation.role in ["ram", "tide"]:
			state.gate_entrants.append(unit.instance_id)
		simulation.record_event("p10_stage_entrant", unit, str(formation.role))
		state.formation = int(state.formation) + 1
		simulation._update_units()

func _watch_gate() -> void:
	var gate: Node2D = simulation.world.get_node("door_hall")
	for index in range(simulation.events.size() - 1, -1, -1):
		var event: Dictionary = simulation.events[index]
		if float(event.time) < simulation.simulation_time - 0.000001:
			break
		if event.kind == "roster_gate_transferred" and event.detail == "door_hall":
			_show_effect("guard", gate.position + Vector2(63, 0))
			break
	if not state.gate_broken or state.gate_flooded:
		return
	var inside := 0
	for actor in simulation.targets:
		if not actor.dead and actor.floor_id == gate.floor_id and actor.instance_id in state.gate_entrants and actor.position.x > gate.position.x + Rules.FOOT_RADIUS_PX:
			inside += 1
		if inside >= 2:
			state.gate_flooded = true
			simulation.record_event("p10_tide_flood", actor, "door_hall")
			_show_effect("flood", gate.position + Vector2(24, 0))
			break

func _watch_upper(delta: float) -> void:
	var attackers: Array[Node2D] = []
	var defenders: Array[Node2D] = []
	for actor in simulation.targets:
		if _on_upper_line(actor):
			attackers.append(actor)
	for actor in simulation.humans:
		if _on_upper_line(actor):
			defenders.append(actor)
	state.upper_engaged = not attackers.is_empty() and not defenders.is_empty()
	if attackers.is_empty() or not defenders.is_empty():
		state.upper_exposed = maxf(0.0, float(state.upper_exposed) - 2.0 * delta)
		state.upper_lost = false
		return
	state.upper_exposed = minf(float(spec.upper_grace), float(state.upper_exposed) + delta)
	if float(state.upper_exposed) < float(spec.upper_grace):
		return
	if not state.upper_lost:
		state.upper_lost = true
		simulation.record_event("p10_upper_lost", attackers[0], "gallery")
		_show_effect("upper_lost", attackers[0].position)
	_drain_register(float(spec.upper_drain) * delta)

func _on_upper_line(actor: Node2D) -> bool:
	return not actor.dead and actor.floor_id >= 2 and simulation.world.room_at(actor.position, actor.floor_id) in UPPER_ROOMS

func _watch_naming_window() -> void:
	for index in range(simulation.events.size() - 1, -1, -1):
		var event: Dictionary = simulation.events[index]
		if float(event.time) < simulation.simulation_time - 0.000001:
			break
		if event.kind == "roster_naming_window" and event.unit == state.boss_actor:
			var boss: Node2D = session._actor(state.boss_actor)
			if boss != null:
				_show_effect("window", boss.position)
			break

func _tide_effect(kind: String, point: Vector2, detail: String) -> void:
	if not session.running:
		return
	if kind == "door_break" and detail == "door_hall" and state.boss_id == "B01":
		state.gate_broken = true
		_show_effect("break", point)
	elif kind == "upper_entry" and state.boss_id == "B02":
		var ghost: Node2D = session._actor(detail)
		if ghost != null and ghost.unit_id == "G09":
			_show_effect("upper", point)
	elif kind == "purified":
		var last: Dictionary = session.ledger.back() if not session.ledger.is_empty() else {}
		var boss: Node2D = session._actor(detail) if detail == state.boss_actor else null
		if state.boss_id == "B03" and boss != null and float(boss.roster.get("ghost", {}).get("naming_left", 0.0)) > 0.0:
			state.boss_listed = true
			_show_effect("listed", point)
		elif not detail.begins_with("G01_"):
			_show_effect("rekindle" if float(last.get("names_delta", 0.0)) > 0.0 else "purify", point)

func _watch_ritual(_seat: String, action: String, args: Dictionary, _origin: String) -> void:
	if action != "start_ritual" or not modifiers.has("N03"):
		return
	var caster: Node2D = session._actor(str(args.get("caster_id", "")))
	if caster == null or not caster.brain.channel.active:
		return
	state.watch_rolls = int(state.watch_rolls) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = str(state.seed).hash() + int(state.watch_rolls) * 2654435761
	if rng.randf() >= float(modifiers.N03.watch_probability):
		return
	for watcher in simulation.targets:
		if watcher.dead or watcher.unit_id not in ["G25", "G26"] or not session.roster.ready(watcher) or not simulation.growth_engine().can_act(watcher):
			continue
		if not session.roster.ghosts.valid_target(watcher, caster):
			continue
		var answer: Dictionary = session.roster.cast(watcher, {"target_id": caster.instance_id})
		if answer.ok:
			simulation.record_event("p10_reader_watched", watcher, caster.instance_id)
			_show_effect("watched", caster.position, watcher.display_name)
			return

func _show_effect(kind: String, point: Vector2, detail := "") -> void:
	state.effects.append({"kind": kind, "x": point.x, "y": point.y, "left": FEEDBACK_SECONDS})
	if state.effects.size() > 16:
		state.effects.pop_front()
	state.feedback = EFFECT_KEYS[kind]
	state.feedback_detail = detail
	state.feedback_left = FEEDBACK_SECONDS
	queue_redraw()

func stage_text() -> String:
	var text := ""
	match state.boss_id:
		"B01":
			text = tr("P10_B01_FLOODED" if state.gate_flooded else ("P10_B01_OPEN" if state.gate_broken else spec.description_key))
		"B02":
			if state.upper_lost:
				text = tr("P10_B02_LOST")
			elif state.upper_engaged:
				text = tr("P10_B02_CONTESTED")
			elif float(state.upper_exposed) > 0.0:
				text = tr("P10_B02_THREAT") % [state.upper_exposed, spec.upper_grace]
		"B03":
			var ghost: Node2D = session._actor(state.boss_actor)
			if state.boss_listed:
				text = tr("P10_B03_RESOLVED")
			elif ghost != null:
				var left: float = float(ghost.roster.get("ghost", {}).get("naming_left", 0.0))
				if left > 0.0:
					text = tr("P10_B03_WINDOW") % left
	return tr(spec.description_key) if text.is_empty() and not spec.is_empty() else text

func title_text() -> String:
	return tr(spec.name_key) if not spec.is_empty() else ""

func modifiers_text() -> String:
	var captions := PackedStringArray()
	for id in modifiers:
		captions.append(tr(modifiers[id].name_key))
	return tr("P10_ACTIVE_MODIFIERS") % "、".join(captions) if not captions.is_empty() else ""

func feedback_text() -> String:
	if float(state.feedback_left) <= 0.0 or str(state.feedback).is_empty():
		return ""
	var caption := tr(str(state.feedback))
	return caption % state.feedback_detail if state.feedback == "P10_WATCHED_READER" else caption

func _draw() -> void:
	if simulation == null:
		return
	var register: Node2D = simulation.world.get_node("register_desk")
	match state.boss_id:
		"B01": _draw_hall(simulation.world.get_node("door_hall").position)
		"B02": _draw_gallery()
	if (state.boss_id == "B03" and not state.boss_listed) or modifiers.has("N01"):
		_draw_ink(register.position)
	if modifiers.has("N02"):
		var side_door: Node2D = simulation.world.get_node("door_side")
		if not side_door.destroyed:
			var p := side_door.position - Vector2(0, 112)
			draw_polyline(PackedVector2Array([p + Vector2(-19, -25), p + Vector2(4, -8), p + Vector2(-8, 15), p + Vector2(14, 34)]), Color("d38464"), 5)
	for effect in state.effects:
		_draw_effect(effect)

func _draw_hall(point: Vector2) -> void:
	if not state.gate_broken:
		draw_polyline(PackedVector2Array([point + Vector2(4, -153), point + Vector2(-3, -127), point + Vector2(8, -106), point + Vector2(-4, -89)]), Color("ecc18c"), 4)

func _draw_gallery() -> void:
	var timber_y: float = simulation.world.floor_y(2)
	var color := Color(0.51, 0.74, 0.71, 0.44) if not state.upper_lost else Color(0.97, 0.42, 0.28, 0.63)
	for index in 6:
		var p := Vector2(Rules.body_to_px(89.0 + index * 1.8), timber_y - 140)
		draw_line(p, p + Vector2(-9 + index % 3 * 7, 103), color, 3)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 96), p + Vector2(9, 98), p + Vector2(0, 117)]), color)
	draw_line(Vector2(Rules.body_to_px(88.5), timber_y - 6), Vector2(Rules.body_to_px(100), timber_y - 6), color, 4)

func _draw_ink(point: Vector2) -> void:
	var t: float = simulation.simulation_time
	var ink := Color(0.32, 0.24, 0.44, 0.31)
	draw_set_transform(point, 0.0, Vector2(1.0, 0.20))
	draw_circle(Vector2(0, -28), 146, ink)
	draw_arc(Vector2(0, -28), 154, 0, TAU, 30, Color(0.68, 0.52, 0.79, 0.50), 5)
	draw_set_transform(Vector2.ZERO)
	for index in 8:
		var offset := Vector2((index - 3.5) * 28, -22 - fposmod(t * 31.0 + index * 19.0, 125.0))
		draw_colored_polygon(PackedVector2Array([point + offset, point + offset + Vector2(11, -14), point + offset + Vector2(10, 7), point + offset + Vector2(-4, 12)]), ink.lightened(0.38))

func _draw_effect(effect: Dictionary) -> void:
	var p := Vector2(float(effect.x), float(effect.y))
	var phase := 1.0 - float(effect.left) / FEEDBACK_SECONDS
	var warm := Color(0.98, 0.73, 0.43, (1.0 - phase) * 0.98)
	match str(effect.kind):
		"guard":
			for offset in [0, 13, 26]:
				draw_arc(p - Vector2(0, 51), 55 + offset + 35 * phase, PI * 0.56, PI * 1.44, 18, warm, 5)
		"window":
			draw_rect(Rect2(p - Vector2(76, 217), Vector2(152, 198)), warm, false, 4)
		"watched":
			draw_arc(p - Vector2(0, 91), 31 + 12 * phase, 0, TAU, 24, warm, 3)
			draw_line(p - Vector2(0, 126), p - Vector2(0, 55), warm, 3)
