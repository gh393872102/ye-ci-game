## Reproduce: ./tools/godot.sh --script res://tests/P5UIExtra.gd
## Native rendering required. Uses synthetic UI input and isolated /tmp saves.
extends SceneTree
var host: Node
var failures := 0
var results: Array[Dictionary] = []
var shots: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()
func click(button: Button) -> void:
	var pos := button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = pos
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await process_frame
func shot(id: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var badge := Label.new()
	badge.text = '界面规则夹具 / 非完整夜程'
	badge.position = Vector2(64,965)
	badge.add_theme_font_size_override('font_size',18)
	layer.add_child(badge)
	await process_frame
	await process_frame
	RenderingServer.force_draw(true)
	var path := 'res://docs/phase-reports/p5-shots/extra-fixture-' + id + '.png'
	root.get_texture().get_image().save_png(path)
	shots.append(path)
	root.remove_child(layer)
	layer.queue_free()
func check(value: bool, text: String) -> void:
	print(('PASS ' if value else 'FAIL ') + text)
	results.append({'check':text,'passed':value})
	if not value: failures += 1
func _run() -> void:
	root.size = Vector2i(1280,720)
	host = load('res://scenes/night/Night.tscn').instantiate()
	host.save_path = '/tmp/ye-ci-p5-extra-ui-fixture.json'
	root.add_child(host)
	await process_frame
	host.start_run('shouxiang','example','P5-target-UI')
	host.run.state.phase = 'reward'
	host.run.state.current_node_id = 'n01'
	host.run.state.offers = [host.run.config.rewards.r_incense_gear.duplicate(true),host.run.config.rewards.r_thick_name.duplicate(true),host.run.config.rewards.r_rekindle.duplicate(true)]
	host.refresh()
	await shot('target-reward-layout-fixture-720')
	host.panel.target_pickers.r_thick_name.select(1)
	var before: float = host.run.state.roster[1].max_hp
	await click(host.panel.buttons.reward_r_thick_name)
	check(host.run.state.phase == 'map' and host.run.state.roster[1].max_hp == before + 15 and host.run.state.roster[0].max_hp == 70, 'Reward target selector applies only selected Iron Shoulder')
	host.run.state.phase = 'market'
	host.run.state.offers = [host.run.config.rewards.r_incense_gear.duplicate(true),host.run.config.rewards.r_thick_name.duplicate(true),host.run.config.rewards.r_sharp_name.duplicate(true),host.run.config.rewards.r_slow_incense.duplicate(true)]
	host.refresh()
	await shot('target-market-layout-fixture-720')
	host.panel.target_pickers.r_incense_gear.select(2)
	var incense: float = host.run.state.incense
	await click(host.panel.buttons.buy_r_incense_gear)
	check(host.run.state.roster[2].equipment_id == 'ritual_incense' and host.run.state.incense == incense - 6, 'Market target selector equips selected Vermilion and debits visible price')
	host.run.state.phase = 'battle'
	host.run.state.current_node_id = 'n10'
	host._enter_battle(false)
	root.get_node('Clock').set_paused(true)
	host.combat.get_node('Simulation').simulation_time = 220.0
	await shot('boss-phase-layout-fixture-720')
	check(host.battle_heading.text.contains('三鼓') and host.battle_heading.text.contains('同时'), 'Boss phase panel reads current actual profile phase by simulation time')
	check(host.combat.get_node('Decisions').managed_by_night and not host.combat.get_node('Decisions').ending.visible, 'Managed battle hides standalone rematch ending')
	host.save_and_exit()
	check(host.panel.show_intro and host.panel.visible and host.combat == null, 'Real save-and-exit presents intro after successful save')
	await click(host.panel.buttons.start_duoming)
	check(host.run.state.mode == 'duoming' and host.run.state.phase == 'map' and not host.panel.show_intro, 'Real new-night button can replace saved active night with attacker seat')
	# Isolated invalid-save and cross-night discovery fixtures; no player save is touched.
	host.run.state.unlocks['G12'] = 'recruited'
	host.run.state.unlocks['H01'] = 'recruited'
	host.run.state.incense = 41.0
	host.run.state.names = 11.0
	host.run.state.build.incense_regen_delta = 0.18
	host.run.state.roster[0].attack += 2
	host.run.state.phase = 'ended'
	host.run.state.outcome = 'defeat'
	host.run.state.reason = 'P4_END_TIDE_EXHAUSTED'
	host.save_run()
	host.show_intro()
	await click(host.panel.buttons.start_shouxiang)
	check(host.run.state.unlocks.get('G12') == 'recruited' and host.run.state.unlocks.get('H01') == 'recruited', 'New-night button preserves discoveries from a valid failed-night save')
	check(host.run.state.incense == 20 and host.run.state.names == 8 and host.run.state.build.incense_regen_delta == 0 and host.run.state.roster[0].attack == 8 and host.run.state.stats.battles.is_empty(), 'Discovery merge carries no resources, build modifiers, combat stats or battle history')
	await click(host.panel.buttons.node_n01)
	root.get_node('Clock').set_paused(true)
	host.combat.get_node('Simulation').set_physics_process(false)
	for step in 120: host.combat.get_node('Simulation').advance(1.0/60)
	host.save_run()
	var original: String = FileAccess.get_file_as_string(host.save_path)
	var live_id: int = host.combat.get_instance_id()
	var old_seed: String = host.run.state.seed
	var old_time: float = host.combat.get_node('Simulation').simulation_time
	var old_clock: float = root.get_node('Clock').combat_time
	FileAccess.open(host.save_path,FileAccess.WRITE).store_string('{}')
	host.continue_run()
	check(host.combat.get_instance_id() == live_id and host.run.state.seed == old_seed and host.combat.get_node('Simulation').simulation_time == old_time, 'Corrupt save cannot dispose or replace an existing live night and battle')
	check(FileAccess.get_file_as_string(host.save_path) == '{}', 'Failed corrupt-load never overwrites the source save')
	var malformed: Dictionary = host.run.state.duplicate(true)
	malformed.battle_snapshot.session.remaining = 'invalid-timer-fixture'
	load('res://src/night/NightSave.gd').save(host.save_path,malformed)
	var bad_bytes: String = FileAccess.get_file_as_string(host.save_path)
	host.continue_run()
	check(host.combat.get_instance_id() == live_id and host.run.state.seed == old_seed and host.combat.get_node('Simulation').simulation_time == old_time and root.get_node('Clock').paused and root.get_node('Clock').combat_time == old_clock, 'Rejected snapshot restore leaves the old live battle, night and clock intact')
	check(host.feedback.text == root.get_node('Data').tr('P5_SAVE_BATTLE_INVALID') and FileAccess.get_file_as_string(host.save_path) == bad_bytes, 'Snapshot failure is explicit and does not overwrite the saved file')
	FileAccess.open(host.save_path,FileAccess.WRITE).store_string(original)
	host.continue_run()
	check(host.combat.get_instance_id() != live_id and host.run.state.seed == old_seed and is_equal_approx(host.combat.get_node('Simulation').simulation_time,old_time), 'Validated snapshot replaces the prior battle only after successful restore')
	host.save_and_exit()
	await click(host.panel.buttons.start_duoming)
	host.run.state.phase = 'reward'
	host.run.state.current_node_id = 'n01'
	host.run.state.roster[1].hp *= 0.5
	host.run.state.offers = [host.run.config.rewards.r_climb_formula.duplicate(true),host.run.config.rewards.r_break_formula.duplicate(true),host.run.config.rewards.r_rekindle.duplicate(true)]
	host.refresh()
	await shot('mutation-reward-720')
	var target_uid: String = host.run.target_options('r_climb_formula')[1].uid
	host.panel.target_pickers.r_climb_formula.select(1)
	var free_incense: float = host.run.state.incense
	await click(host.panel.buttons.reward_r_climb_formula)
	var changed: Dictionary = {}
	for unit in host.run.state.roster:
		if unit.uid == target_uid: changed = unit
	check(changed.get('id') == 'G09' and changed.get('mutation_count') == 1 and is_equal_approx(changed.hp / changed.max_hp,0.5) and host.run.state.incense == free_incense, 'Real mutation reward transforms the selected white once, preserving uid and injury ratio without a hidden incense charge')
	host.run.state.phase = 'market'
	host.run.state.offers = [host.run.config.rewards.r_climb_formula.duplicate(true),host.run.config.rewards.r_break_formula.duplicate(true),host.run.config.rewards.r_tide_gap.duplicate(true),host.run.config.rewards.r_change.duplicate(true)]
	host.refresh()
	await shot('mutation-market-720')
	var m_targets: Array = host.run.target_options('r_break_formula')
	var legal := true
	for unit in m_targets:
		legal = legal and unit.id == 'G01' and unit.mutation_count == 0 and unit.uid != target_uid
	check(legal and m_targets.size() == host.run.state.roster.size() - 1, 'Mutation pickers list only legal unmutated white ghosts and exclude the previous elite')
	var breaker_uid: String = m_targets[0].uid
	var before_price: float = host.run.state.incense
	await click(host.panel.buttons.buy_r_break_formula)
	var breaker: Dictionary = {}
	for unit in host.run.state.roster:
		if unit.uid == breaker_uid: breaker = unit
	check(breaker.get('id') == 'G12' and host.run.state.incense == before_price - 15 and host.panel.buttons.buy_r_break_formula.disabled, 'Real market mutation purchase charges its visible 15 incense price and disables the purchased card')
	var report := {'phase':'P5','scope':'UI extra integration fixtures','checks':results.size(),'failures':failures,'results':results,'screenshots':shots,'fixture_policy':'Screenshots are UI/rule fixtures, not complete-night victories. Only /tmp save paths are used. Visible buttons use synthetic mouse input; setup may inject rewards, phase, injury ratios or invalid saves. Complete-night proof is in the main P5 suite.','engine':Engine.get_version_info().string,'date':Time.get_datetime_string_from_system()}
	FileAccess.open('res://docs/phase-reports/p5-ui-extra-results.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t') + '\n')
	quit(failures)
