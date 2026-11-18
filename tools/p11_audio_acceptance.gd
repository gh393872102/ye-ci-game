extends SceneTree
## Run against an isolated project copy with the real Godot mixer enabled.
const STEP := 1.0 / 60.0
const CORE := ["C01", "C03", "C04"]

var output: String
var data: Node
var rules: Node
var clock: Node
var preferences: Node
var combat: Node2D
var sim: Node2D
var session: Node
var audio: Node
var capture := AudioEffectCapture.new()
var checks: Array[Dictionary] = []
var cues: Array[Dictionary] = []
var captures := {}
var level_comparison := {}
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else ""
	data = root.get_node("Data")
	rules = root.get_node("Rules")
	clock = root.get_node("Clock")
	preferences = root.get_node("Settings")
	if not (output.begins_with("/private/tmp/ye-ci-p11-audio-") or output.begins_with("/tmp/ye-ci-p11-audio-")) \
			or preferences.PATH != output.path_join("state/settings.cfg") \
			or data.codex_store.path != output.path_join("state/codex.json"):
		push_error("Audio acceptance needs temporary settings and codex paths.")
		quit(2)
		return
	Engine.max_fps = 120
	capture.buffer_length = 8.0
	AudioServer.add_bus_effect(0, capture)
	for bus in preferences.AUDIO_BUSES:
		_check(AudioServer.get_bus_index(bus) >= 0, "Actual bus exists: " + bus)
	if failures > 0 or not data.errors.is_empty():
		quit(2)
		return
	await _ambience()
	await _structures()
	await _water()
	await _register()
	await _quiet_skills()
	await _settings()
	_discard()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	var report := {
		"engine": Engine.get_version_info().string, "platform": OS.get_name(),
		"display_driver": DisplayServer.get_name(), "audio_driver": AudioServer.get_driver_name(),
		"mix_rate_hz": AudioServer.get_mix_rate(),
		"scope": "Controlled positions with the live Combat scene, battle steps, paid actions, and Godot output. The Master capture is before its fader. Godot peak meters observe the Master fader.",
		"checks": checks, "passed": checks.size() - failures, "failed": failures,
		"cue_playbacks": cues, "native_mix_captures": captures, "r07_comparison": level_comparison,
	}
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", false) + "\n")
	file.close()
	quit(0 if failures == 0 else 1)

func _check(ok: bool, label: String, observed: Variant = null) -> bool:
	checks.append({"ok": ok, "check": label, "observed": observed})
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)
	return ok

func _discard() -> void:
	if is_instance_valid(combat):
		combat.free()

func _scene(extra: Array = [], wave := false) -> void:
	_discard()
	combat = load("res://scenes/combat/Combat.tscn").instantiate()
	_check(combat.configure_chunks(CORE + extra), "Real chunks compose: " + str(CORE + extra))
	root.add_child(combat)
	sim = combat.get_node("Simulation")
	sim.set_physics_process(false)
	session = combat.get_node("Session")
	audio = combat.get_node("BattleAudio")
	audio.cue_played.connect(_played)
	if not wave:
		sim.tide.config.waves = []
	clock.set_paused(false)

func _boot(ritual := "R01") -> void:
	_check(session.start_battle("shouxiang").ok, "Real battle starts: " + ritual)
	var reserve := float(session.rules.incense_cap)
	_check(session.configure_dual({"shouxiang": reserve, "duoming": reserve}, "shouxiang").ok,
		"Both seats use the real command path")
	session.configure_growth("p11-audio")
	session.configure_roster("p11-audio")
	_check(session.configure_ritual(ritual, "p11-audio"), "Ritual configured: " + ritual)

func _clean_field() -> void:
	for actor in sim.humans + sim.targets:
		actor.free()
	sim.humans.clear()
	sim.targets.clear()
	sim._update_units()

func _played(id: String, trigger: String, voice: AudioStreamPlayer) -> void:
	cues.append({
		"id": id, "trigger": trigger, "ritual": session.ritual.id, "bus": str(voice.bus),
		"stream": voice.stream.resource_path.get_file() if id != "SFX06" else "tide_steps.wav",
		"gain_db": voice.volume_db, "pitch": voice.pitch_scale, "playing": voice.playing,
		"stream_seconds": voice.stream.get_length(), "battle_seconds": sim.simulation_time,
	})

func _human(id: String, x_body: float, floor_id := 0, post := "post_register") -> Node2D:
	var actor: Node2D = sim.spawn_human(id, post)
	_put_actor(actor, x_body, floor_id)
	actor.brain.settled_position = actor.position
	return actor

func _ghost(id: String, x_body: float, lane := 3, floor_id := 0) -> Node2D:
	var actor: Node2D = sim.tide.spawn(id, lane, rules.body_to_px(x_body))
	_put_actor(actor, x_body, floor_id)
	return actor

func _put_actor(actor: Node2D, x_body: float, floor_id: int) -> void:
	actor.position = Vector2(rules.body_to_px(x_body), sim.world.floor_y(floor_id))
	actor.floor_id = floor_id
	actor.attacks_enabled = false
	actor.sync_meta()
	sim._update_units()

func _cast(actor: Node2D, args := {}) -> Dictionary:
	var payload := args.duplicate()
	payload.unit_id = actor.instance_id
	var friendly: bool = actor.side == "xianghuo"
	return session.execute_for("shouxiang" if friendly else "duoming", "unit_skill", payload, "player" if friendly else "ai")

func _advance(seconds: float) -> void:
	for _index in ceili(seconds / STEP):
		sim.advance(STEP)

func _capture(label: String, seconds: float, trigger: Callable, live_steps := false) -> Dictionary:
	capture.clear_buffer()
	var previous := cues.size()
	trigger.call()
	var end := Time.get_ticks_usec() + roundi(seconds * 1000000)
	var next_step := Time.get_ticks_usec()
	var meter := -200.0
	while Time.get_ticks_usec() < end:
		await process_frame
		while live_steps and Time.get_ticks_usec() >= next_step:
			sim.advance(STEP)
			next_step += roundi(STEP * 1000000)
		meter = maxf(meter, AudioServer.get_bus_peak_volume_left_db(0, 0))
		meter = maxf(meter, AudioServer.get_bus_peak_volume_right_db(0, 0))
	var frames := capture.get_buffer(capture.get_frames_available())
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * 4)
	var peak := 0.0
	var sum_squares := 0.0
	for index in frames.size():
		var frame := frames[index]
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		sum_squares += frame.length_squared()
		bytes.encode_s16(index * 4, roundi(clampf(frame.x, -1, 1) * 32767))
		bytes.encode_s16(index * 4 + 2, roundi(clampf(frame.y, -1, 1) * 32767))
	var sample := AudioStreamWAV.new()
	sample.data = bytes
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = int(AudioServer.get_mix_rate())
	sample.stereo = true
	var path := output.path_join(label + ".wav")
	_check(sample.save_to_wav(path) == OK, "Captured PCM WAV: " + label)
	var row := {
		"file": path.get_file(), "sha256": FileAccess.get_sha256(path), "frames": frames.size(),
		"peak_dbfs": linear_to_db(maxf(peak, 0.0000000001)),
		"rms_dbfs": linear_to_db(maxf(sqrt(sum_squares / maxi(1, frames.size() * 2)), 0.0000000001)),
		"master_meter_dbfs": meter, "cues": cues.slice(previous),
	}
	captures[label] = row
	return row

func _hear(row: Dictionary, id: String, trigger: String) -> void:
	var found: bool = row.cues.any(func(cue): return cue.id == id and cue.trigger == trigger and cue.playing)
	_check(found and row.frames > 0 and row.peak_dbfs > -65.0, id + " mixer signal after " + trigger,
		{"cue_seen": found, "peak_dbfs": row.peak_dbfs})

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _nothing() -> void:
	pass

func _ambience() -> void:
	_scene([], true)
	var row := await _capture("01-start", 1.10, func(): _boot())
	_hear(row, "SFX01", "battle_start")
	row = await _capture("06-footsteps", 4.68, _nothing, true)
	_hear(row, "SFX06", "tide_approaching")
	var loop: AudioStreamPlayer = audio.get_node("TideFootsteps")
	_check(loop.playing and loop.get_playback_position() > 0.05 and loop.get_playback_position() < 2.0,
		"Approach stays audible after a complete 3.72-second loop", {"playback_seconds": loop.get_playback_position()})
	clock.set_paused(true)
	await _wait(0.22)
	row = await _capture("06-paused", 0.35, _nothing)
	_check(loop.stream_paused and row.peak_dbfs < -100, "Pause stops the continuous footstep signal", row.peak_dbfs)
	clock.set_paused(false)
	row = await _capture("01-minute", 1.12, func():
		sim.simulation_time = 59.99
		sim.advance(STEP)
	)
	_hear(row, "SFX01", "minute_pressure")
	_scene()
	_boot()
	_clean_field()
	var drummer := _human("H07", 113.0)
	_ghost("G01", 114.0)
	await _wait(1.08)
	row = await _capture("01-watch", 1.02, func(): _check(_cast(drummer).ok, "Watch drum command succeeds"))
	_hear(row, "SFX01", "roster_watch_drum")

func _structures() -> void:
	_scene()
	_boot()
	_clean_field()
	_human("H01", 113.0)
	var guard := _human("H09", 89.4, 0, "post_hall_door")
	var ram := _ghost("G12", 87.6)
	var hall: Node2D = sim.world.get_node("door_hall")
	hall.set_durability(hall.max_durability * (float(session.rules.door_warning_ratio) + 0.01))
	await _wait(1.02)
	var row := await _capture("02-door-critical", 0.72, func(): sim.deal_damage(ram, hall, "structure", 38.0))
	_hear(row, "SFX02", "door_critical")
	_check(not hall.destroyed and hall.durability / hall.max_durability <= float(session.rules.door_warning_ratio),
		"Gate damage crosses the configured warning threshold", hall.durability)
	hall.set_durability(7.0)
	var hp: float = guard.hp
	row = await _capture("12-iron-shoulder", 0.94, func():
		_check(_cast(guard).ok, "Iron Shoulder activates gate guard")
		sim.deal_damage(ram, hall, "structure", 38.0)
	)
	_hear(row, "SFX12", "roster_gate_transferred")
	_check(guard.hp < hp and hall.durability == 7.0, "Would-be lethal gate hit is transferred",
		{"guard_hp_before": hp, "guard_hp_after": guard.hp, "gate_remaining": hall.durability})
	guard.roster.statuses.erase("gate_guard")
	row = await _capture("08-gate-break", 1.45, func(): sim.deal_damage(ram, hall, "structure", 38.0))
	_hear(row, "SFX02", "door_break")
	_hear(row, "SFX08", "hall_gate_break")
	_check(hall.destroyed and hall.is_open, "The shattered hall gate is traversable")
	sim.world.set_all_doors_open(true)
	for object in sim.world.obstacles:
		object.set_occupied(false)
	var first := _ghost("G01", 87.94, 1)
	var second := _ghost("G01", 87.94, 2)
	sim.advance(STEP)
	row = await _capture("08-tide-flood", 1.40, func(): _advance(0.45))
	_hear(row, "SFX08", "tide_through_gate")
	_check(first.position.x > hall.position.x + rules.FOOT_RADIUS_PX and second.position.x > hall.position.x + rules.FOOT_RADIUS_PX,
		"Two actual GhostBrain paths move through the gate")

	_scene()
	_boot()
	_clean_field()
	_human("H01", 113.0)
	sim.world.set_all_doors_open(true)
	for object in sim.world.obstacles:
		object.set_occupied(false)
	var climber := _ghost("G09", float(sim.tide.config.climb.from_x) - 0.02)
	await _wait(1.02)
	row = await _capture("03-beam-climb", 0.91, func(): _advance(0.10))
	_hear(row, "SFX03", "climb_start")
	var landing := Vector2(rules.body_to_px(float(sim.tide.config.climb.to_x)), sim.world.floor_y(2))
	climber.position = landing + Vector2(-4, 4)
	row = await _capture("09-upper-pounce", 1.0, func(): _advance(0.18))
	_hear(row, "SFX09", "upper_entry")
	_check(climber.floor_id == 2 and climber.brain.stage == "upper", "Rope climber reaches the upper room on its real route")
	var stair: Dictionary = sim.world.stair_link("stair_beam")
	var smasher := _ghost("G17", float(stair.from_x), 3, int(stair.from_floor))
	row = await _capture("03-beam-smash", 1.0, func():
		_check(_cast(smasher, {"path_id": "stair_beam"}).ok, "Mountain ghost command breaks the beam")
	)
	_hear(row, "SFX03", "roster_beam_smashed")
	_check(not sim.world.path_is_open("stair_beam"), "Beam crossing becomes unusable")

func _water() -> void:
	_scene(["C05"])
	_boot("R02")
	_clean_field()
	_human("H01", 113.0)
	sim.world.set_all_doors_open(true)
	var ghost := _ghost("G10", 51.0, 2)
	await _wait(1.04)
	var row := await _capture("04-water-entry", 0.95, func(): _advance(3.8))
	_hear(row, "SFX04", "water_entry")
	_check(ghost.floor_id == 5 and sim.world.chunk_at(ghost.position, 5) == "C05", "Water ghost follows authored sluice route")
	_put_actor(ghost, 70.0, 5)
	var ally := _human("H09", 68.0, 5, "post_water_sluice")
	var before := ally.position.x
	row = await _capture("04-water-drag", 1.02, func():
		_check(_cast(ghost, {"target_id": ally.instance_id}).ok, "Water ghost uses its real drag skill")
	)
	_hear(row, "SFX04", "roster_water_drag")
	_check(ally.position.x > before, "Drag actually displaces the defender", ally.position.x - before)

func _register() -> void:
	_scene()
	_boot()
	_clean_field()
	var caster := _human("H01", 113.0)
	var ward := _human("H08", 113.3)
	var ghost := _ghost("G01", 114.0)
	ghost.motion_enabled = false
	await _wait(1.10)
	var row := await _capture("05-guard-ledger", 0.85, func(): _check(_cast(ward).ok, "Register protection succeeds"))
	_hear(row, "SFX05", "roster_register_guard")
	row = await _capture("05-register-open", 0.90, func():
		_check(session.start_ritual(caster, ghost).ok, "Paid reading starts against a valid target")
		sim.advance(STEP)
	)
	_hear(row, "SFX05", "ritual_start")
	_hear(row, "SFX07", "reading")
	row = await _capture("07-register-brush", 0.62, func(): _advance(1.0))
	_hear(row, "SFX07", "reading")
	var names: float = session.names
	row = await _capture("07-11-register-finish", 1.70, func():
		caster.brain.channel.advance(sim, caster, caster.brain.channel.duration)
	)
	_hear(row, "SFX07", "channel_complete")
	_hear(row, "SFX11", "purified")
	_check(ghost.dead and session.names > names, "Paid completion sends the ghost off and credits the ledger")
	var face_maker := _human("H32", 113.5)
	row = await _capture("11-new-face", 1.46, func():
		_check(_cast(face_maker, {"target_id": caster.instance_id}).ok, "Face-maker applies a face")
	)
	_hear(row, "SFX11", "roster_temporary_face")
	var boss := _ghost("G32", 114.0)
	boss.motion_enabled = false
	session.roster.cooldown(caster, 0.0)
	session.names = 12.0
	_check(session.start_ritual(caster, boss).ok, "Paid reading starts against Unregistered")
	await _wait(0.9)
	row = await _capture("05-naming-window", 0.92, func():
		caster.brain.channel.advance(sim, caster, caster.brain.channel.duration)
	)
	_hear(row, "SFX05", "roster_naming_window")
	_check(float(boss.roster.ghost.get("naming_left", 0.0)) > 0, "The actual Unregistered naming window opens")
	row = await _capture("10-extinguish", 1.35, func():
		session.names = 0.0
		sim.advance(STEP)
	)
	_hear(row, "SFX10", "register_extinguishing")
	_check(session.running and session.extinguish_left < float(session.rules.extinguish_seconds),
		"The real recoverable extinguish window opens", session.extinguish_left)

func _quiet_skills() -> void:
	var triggers := {
		"R01": ["roster_gong", "roster_bell_shock", "roster_mourning_cry"],
		"R07": ["roster_silent_taunt", "roster_bell_backlash", "roster_cry_backlash"],
	}
	for ritual in ["R01", "R07"]:
		_scene(["C12"])
		_boot(ritual)
		_clean_field()
		var guard := _human("H14", 114.0)
		var bell := _ghost("G21", 115.3)
		var cry := _ghost("G03", 115.0)
		await _wait(1.06)
		for index in 3:
			var skill: String = ["gong", "bell", "cry"][index]
			var actor: Node2D = [guard, bell, cry][index]
			var hp: float = actor.hp
			var row := await _capture(ritual + "-" + skill, 1.70, func():
				_check(_cast(actor).ok, ritual + " actual skill succeeds: " + skill)
			)
			_hear(row, skill, triggers[ritual][index])
			if index == 0:
				_check(bell.roster.statuses.has("taunt") and bell.growth.statuses.has("stun") == (ritual == "R01"),
					ritual + " gong behavior matches the active rule")
			else:
				_check((actor.hp < hp) == (ritual == "R07"), ritual + " actual skill backlash: " + skill, hp - actor.hp)
			for unit in [guard, bell, cry]:
				unit.roster.statuses.clear()
				unit.growth.statuses.clear()
	for skill in ["gong", "bell", "cry"]:
		var ordinary: Dictionary = captures["R01-" + skill]
		var quiet: Dictionary = captures["R07-" + skill]
		var peak_drop: float = ordinary.peak_dbfs - quiet.peak_dbfs
		var rms_drop: float = ordinary.rms_dbfs - quiet.rms_dbfs
		level_comparison[skill] = {
			"r01_peak_dbfs": ordinary.peak_dbfs, "r07_peak_dbfs": quiet.peak_dbfs,
			"peak_attenuation_db": peak_drop, "rms_attenuation_db": rms_drop,
			"r01_stream_seconds": ordinary.cues[0].stream_seconds if not ordinary.cues.is_empty() else 0,
			"r07_stream_seconds": quiet.cues[0].stream_seconds if not quiet.cues.is_empty() else 0,
		}
		_check(peak_drop > 20.0 and rms_drop > 22.0, "R07 reduces actual mixer output: " + skill, level_comparison[skill])

func _settings() -> void:
	_scene()
	_boot()
	_clean_field()
	var guard := _human("H14", 114.0)
	var drummer := _human("H07", 114.0)
	var bell := _ghost("G21", 115.3)
	var modified: Dictionary = preferences.values.duplicate(true)
	await _wait(1.08)
	var row := await _capture("settings-master-full", 1.64, func(): _check(_cast(guard).ok, "Reference gong at full Master"))
	var full_db: float = row.master_meter_dbfs
	modified.volumes.Master = 50
	_check(preferences.commit(modified), "Settings commits Master at 50%")
	session.roster.cooldown(guard, 0.0)
	row = await _capture("settings-master-50", 1.64, func(): _check(_cast(guard).ok, "Reference gong at half Master"))
	_check(absf(full_db - row.master_meter_dbfs - 6.0206) < 0.8, "Master meter follows the real fader",
		{"full_dbfs": full_db, "half_dbfs": row.master_meter_dbfs})
	modified.volumes.Master = 100
	modified.volumes.Ritual = 0
	_check(preferences.commit(modified), "Settings commits Ritual mute")
	session.roster.cooldown(guard, 0.0)
	row = await _capture("settings-ritual-muted", 1.48, func(): _check(_cast(guard).ok, "Muted gong still resolves as a skill"))
	_check(row.peak_dbfs < -100.0, "Ritual mute removes the gong from the Master mix", row.peak_dbfs)
	modified.volumes.Ritual = 100
	modified.volumes.SFX = 0
	_check(preferences.commit(modified), "Settings commits SFX mute")
	bell.roster.statuses.clear()
	bell.growth.statuses.clear()
	row = await _capture("settings-sfx-muted", 1.02, func(): _check(_cast(drummer).ok, "Muted watch drum still resolves as a skill"))
	_check(row.peak_dbfs < -100.0, "SFX mute removes the watch drum from the Master mix", row.peak_dbfs)
	modified.volumes.SFX = 100
	modified.volumes.Music = 37
	modified.volumes.Master = 0
	_check(preferences.commit(modified), "Settings commits reserved Music and Master mute")
	var music := AudioServer.get_bus_index(&"Music")
	var config := ConfigFile.new()
	_check(config.load(preferences.PATH) == OK and config.get_value("audio", "Music") == 37
		and absf(AudioServer.get_bus_volume_db(music) - linear_to_db(0.37)) < 0.01
		and AudioServer.is_bus_mute(0), "Music fader and Master mute reach Godot and persist")
	_check(preferences.commit(preferences.defaults), "Isolated settings return to defaults")
