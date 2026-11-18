extends Node
## Scene-local foley. Presentation consumes battle state without advancing it.
signal cue_played(cue: String, trigger: String, player: AudioStreamPlayer)

const DRUM = preload("res://assets/audio/p11/watch_drum.wav")
const CLOSE_REGISTER = preload("res://assets/audio/p11/register_close.wav")
const FOOTSTEPS = preload("res://assets/audio/p11/tide_steps.wav")
const CUES := {
	"SFX01": [DRUM, &"SFX", -13.0],
	"SFX02": [preload("res://assets/audio/p11/door_split.wav"), &"SFX", -13.0],
	"SFX03": [preload("res://assets/audio/p11/beam_creak.wav"), &"SFX", -17.0],
	"SFX04": [preload("res://assets/audio/p11/water_alley.wav"), &"SFX", -18.0],
	"SFX05": [preload("res://assets/audio/p11/ledger_page.wav"), &"Ritual", -15.0],
	"SFX07": [preload("res://assets/audio/p11/register_brush.wav"), &"Ritual", -14.0],
	"SFX08": [preload("res://assets/audio/p11/gate_rush.wav"), &"SFX", -11.0],
	"SFX09": [preload("res://assets/audio/p11/rope_pounce.wav"), &"SFX", -12.0],
	"SFX10": [preload("res://assets/audio/p11/dying_ember.wav"), &"Ritual", -12.0],
	"SFX11": [preload("res://assets/audio/p11/send_off.wav"), &"Ritual", -12.0],
	"SFX12": [preload("res://assets/audio/p11/iron_shoulder.wav"), &"SFX", -12.0],
}
const LOUD_SKILLS := {
	"gong": [preload("res://assets/audio/p11/gong.wav"), preload("res://assets/audio/p11/gong_damped.wav")],
	"bell": [preload("res://assets/audio/p11/bell.wav"), preload("res://assets/audio/p11/bell_damped.wav")],
	"cry": [preload("res://assets/audio/p11/cry.wav"), preload("res://assets/audio/p11/cry_damped.wav")],
}
const QUIET_TRIM_DB := -24.0
const SILENT_DB := -58.0
const READ_BEAT_SECONDS := 0.9
const PRESSURE_INTERVAL := 60.0
const VOICE_COUNT := 8

var simulation: Node2D
var _session: Node
var _voices: Array[AudioStreamPlayer] = []
var _steps: AudioStreamPlayer
var _last_cues: Dictionary = {}
var _in_water: Dictionary = {}
var _on_beam: Dictionary = {}
var _reading: Dictionary = {}
var _behind_gate: Dictionary = {}
var _gate_crossings := 0
var _approaching := 0

func _ready() -> void:
	_session = simulation.session
	for index in VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.name = "Foley%d" % (index + 1)
		add_child(voice)
		_voices.append(voice)
	_steps = AudioStreamPlayer.new()
	_steps.name = "TideFootsteps"
	_steps.bus = &"SFX"
	var stream: AudioStreamWAV = FOOTSTEPS.duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	_steps.stream = stream
	_steps.volume_db = SILENT_DB
	add_child(_steps)
	_session.ledger_recorded.connect(_on_ledger)
	simulation.event_recorded.connect(_on_event)
	simulation.door_damaged.connect(_on_door_damage)
	simulation.tide.effect_emitted.connect(_on_tide_effect)
	simulation.step_completed.connect(_on_step)

func _process(delta: float) -> void:
	if not _session.active or not _session.running:
		if _steps.playing:
			_steps.stop()
			_steps.volume_db = SILENT_DB
		return
	_steps.stream_paused = Clock.paused
	if Clock.paused:
		return
	var target_db := SILENT_DB
	if _approaching > 0:
		target_db = -29.0 + float(mini(_approaching, 30)) * 0.27
		if not _steps.playing:
			_steps.play()
			cue_played.emit("SFX06", "tide_approaching", _steps)
	_steps.volume_db = move_toward(_steps.volume_db, target_db, delta * 74.0)
	if _approaching == 0 and _steps.playing and _steps.volume_db <= SILENT_DB:
		_steps.stop()

func _on_ledger(action: String, detail: String) -> void:
	if not _session.active or not _session.running:
		return
	match action:
		"start":
			for voice in _voices:
				voice.stop()
			_steps.stop()
			_steps.volume_db = SILENT_DB
			_last_cues.clear()
			_in_water.clear()
			_on_beam.clear()
			_reading.clear()
			_behind_gate.clear()
			_gate_crossings = 0
			_approaching = 0
			_cue("SFX01", "battle_start")
		"growth_drum":
			_watch_drum("growth_drum")
		"ritual_start":
			_cue("SFX05", "ritual_start")
		"growth_last_gate_hit":
			_cue("SFX12", "growth_last_gate_hit")
		"growth_status_drag":
			if detail.begins_with("G10_"):
				_cue("SFX04", "growth_water_drag", null, 3.0, 0.91)

func _on_event(kind: String, unit: Node2D, _detail: String) -> void:
	if not _session.active or not _session.running:
		return
	match kind:
		"roster_watch_drum":
			_watch_drum(kind)
		"roster_beam_smashed":
			_cue("SFX03", kind, null, 4.0, 0.76)
		"roster_water_drag":
			_cue("SFX04", kind, null, 3.0, 0.91)
		"roster_register_guard", "roster_naming_window":
			_cue("SFX05", kind)
		"channel_complete":
			if is_instance_valid(unit) and unit.brain.channel.paid:
				_cue("SFX07", kind, CLOSE_REGISTER, 2.0)
		"roster_temporary_face":
			_cue("SFX11", kind, null, -3.0, 1.12)
		"roster_gate_transferred":
			_cue("SFX12", kind)
		"roster_gong", "roster_silent_taunt":
			_loud("gong", kind, kind == "roster_silent_taunt")
		"roster_bell_shock", "roster_bell_backlash":
			_loud("bell", kind, kind == "roster_bell_backlash")
		"roster_mourning_cry", "roster_cry_backlash":
			_loud("cry", kind, kind == "roster_cry_backlash")

func _on_door_damage(door: Node2D, previous_durability: float) -> void:
	if not _session.active or not _session.running:
		return
	if door.destroyed:
		_cue("SFX02", "door_break")
		if door.name == &"door_hall":
			_gate_crossings = 0
			_cue("SFX08", "hall_gate_break", null, -3.0, 0.88)
	elif door.max_durability > 0.0:
		var danger: float = door.max_durability * float(_session.rules.door_warning_ratio)
		if door.durability <= danger and previous_durability > danger:
			_cue("SFX02", "door_critical", null, -1.0, 1.13)

func _on_tide_effect(kind: String, _point: Vector2, detail: String) -> void:
	if not _session.active or not _session.running:
		return
	match kind:
		"climb_start":
			var ghost: Node2D = _session._actor(detail)
			if ghost != null and ghost.unit_id == "G09" and ghost.brain.stage == "climb":
				_cue("SFX03", kind)
		"upper_entry":
			if detail.begins_with("G09_"):
				_cue("SFX09", kind)
		"purified":
			_cue("SFX11", kind)

func _on_step(delta: float) -> void:
	if not _session.active or not _session.running:
		return
	var now: float = simulation.simulation_time
	if floori((now + 0.000001) / PRESSURE_INTERVAL) > floori((now - delta + 0.000001) / PRESSURE_INTERVAL):
		_cue("SFX01", "minute_pressure", null, -3.0, 0.91)
	if _session.names <= 0.0 and (_session.mode == "shouxiang" or _session.dual_enabled):
		if _session.extinguish_left > float(_session.rules.extinguish_seconds) - delta * 1.5:
			_cue("SFX10", "register_extinguishing")
	_watch_actors()

func _watch_actors() -> void:
	var world: Node2D = simulation.world
	var hall: Node2D = world.get_node_or_null("door_hall")
	var outer: Node2D = world.get_node_or_null("door_outer")
	var approach_end: float = outer.position.x if outer != null else Rules.BASE_START_X
	var water_route: bool = "C05" in world.layout.get("chunk_ids", [])
	var wet := {}
	var beams := {}
	var readings := {}
	var past := {}
	var approach := 0
	for unit: Node2D in simulation.humans + simulation.targets:
		var id := unit.get_instance_id()
		if unit.side == "yegui":
			if unit.floor_id == 0 and unit.position.x < approach_end and unit.current_speed > 0.5:
				approach += 1
			if hall != null and unit.floor_id == hall.floor_id and unit.position.x > hall.position.x + Rules.FOOT_RADIUS_PX:
				past[id] = true
				if hall.destroyed and not _behind_gate.has(id) and unit.velocity.x > 0.5:
					_gate_crossings += 1
					if _gate_crossings == 2:
						_cue("SFX08", "tide_through_gate")
		elif unit.brain.channel.active:
			var beat := floori(unit.brain.channel.elapsed / READ_BEAT_SECONDS)
			readings[id] = beat
			if beat != int(_reading.get(id, -1)):
				_cue("SFX07", "reading", null, -3.5, 1.0 + 0.025 * float(beat % 3))
		if water_route and world.chunk_at(unit.position, unit.floor_id) == "C05":
			wet[id] = true
			if not _in_water.has(id) and unit.current_speed > 0.5:
				_cue("SFX04", "water_entry")
		if unit.floor_id == 3 and world.room_at(unit.position, unit.floor_id) == "beam":
			beams[id] = true
			if not _on_beam.has(id) and unit.current_speed > 0.5:
				_cue("SFX03", "beam_entry")
	_approaching = approach
	_behind_gate = past
	_in_water = wet
	_on_beam = beams
	_reading = readings
	if hall != null and not hall.destroyed:
		_gate_crossings = 0

func _watch_drum(trigger: String) -> void:
	var damped: bool = _session.ritual.id == "R07"
	_cue("SFX01", trigger, null, QUIET_TRIM_DB if damped else 0.0, 0.70 if damped else 1.04)

func _loud(skill: String, trigger: String, damped: bool) -> void:
	damped = damped or _session.ritual.id == "R07"
	var samples: Array = LOUD_SKILLS[skill]
	_play(skill, trigger, samples[1 if damped else 0], &"Ritual", -11.0 + (QUIET_TRIM_DB if damped else 0.0), 1.0)

func _cue(id: String, trigger: String, override: AudioStreamWAV = null, trim := 0.0, pitch := 1.0) -> void:
	var sound: Array = CUES[id]
	_play(id, trigger, sound[0] if override == null else override, sound[1], sound[2] + trim, pitch)

func _play(id: String, trigger: String, sound: AudioStreamWAV, bus: StringName, volume: float, pitch: float) -> void:
	var now := Time.get_ticks_msec()
	var key := id + ":" + trigger
	if now - int(_last_cues.get(key, -1000)) < 300:
		return
	_last_cues[key] = now
	var voice := _voices.back() as AudioStreamPlayer
	for candidate in _voices:
		if not candidate.playing:
			voice = candidate
			break
	# Keep the active voice count bounded when several doors or skills resolve together.
	_voices.erase(voice)
	_voices.push_front(voice)
	voice.stop()
	voice.stream = sound
	voice.bus = bus
	voice.volume_db = volume
	voice.pitch_scale = pitch
	voice.play()
	cue_played.emit(id, trigger, voice)
