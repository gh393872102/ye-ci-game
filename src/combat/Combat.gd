extends Node2D
## Spatial-only mode is used by P0/P1 regression scenes; normal Boot uses the P3 source-wave preset.
var spatial_only := false
var auto_targets := true
var tide_enabled := true
var decisions_enabled := true

func configure_chunks(ids: Array) -> bool:
	var world := $ReferenceMap
	var next := {} if ids.is_empty() else preload("res://src/data/ChunkCatalog.gd").compose(ids)
	if not ids.is_empty() and next.is_empty():
		return false
	if world.layout.get("chunk_ids", []) == next.get("chunk_ids", []):
		return true
	var session := get_node_or_null("Session")
	if session != null and session.running:
		return false
	world.configure_layout(next)
	var simulation := get_node_or_null("Simulation")
	if simulation != null:
		simulation.reload_defense_layout()
		simulation.reset_preset()
	return true

func _enter_tree() -> void:
	$ReferenceMap.spawn_placeholders = spatial_only

func _ready() -> void:
	var world := $ReferenceMap
	var camera := $BattleCamera
	var debug := $DebugOverlay
	debug.world = world
	debug.camera = camera
	var hud := preload("res://src/ui/CombatHUD.gd").new()
	hud.name = "HUD"
	hud.camera = camera
	hud.world = world
	hud.debug = debug
	$CanvasLayer.add_child(hud)
	if spatial_only:
		var walk_debugger := preload("res://src/debug/WalkDebugger.gd").new()
		walk_debugger.name = "WalkDebugger"
		walk_debugger.world = world
		walk_debugger.overlay = debug
		add_child(walk_debugger)
	else:
		var simulation := preload("res://src/combat/CombatSimulation.gd").new()
		simulation.name = "Simulation"
		simulation.world = world
		simulation.auto_targets = auto_targets
		simulation.tide_enabled = tide_enabled
		add_child(simulation)
		hud.simulation = simulation
		var inspector := preload("res://src/ui/BattleInspector.gd").new()
		inspector.name = "BattleInspector"
		inspector.world = world
		inspector.simulation = simulation
		add_child(inspector)
		if decisions_enabled:
			var session := preload("res://src/combat/BattleSession.gd").new()
			session.name = "Session"
			session.simulation = simulation
			add_child(session)
			simulation.session = session
			var decisions := preload("res://src/ui/DecisionPanel.gd").new()
			decisions.name = "Decisions"
			decisions.world = world
			decisions.camera = camera
			decisions.simulation = simulation
			decisions.session = session
			add_child(decisions)
			inspector.session = session
			inspector.decision_panel = decisions
			hud.session = session
			hud.decisions = decisions
			if tide_enabled:
				var audio := preload("res://src/audio/BattleAudio.gd").new()
				audio.name = "BattleAudio"
				audio.simulation = simulation
				add_child(audio)
