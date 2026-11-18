extends SceneTree
var checks:=0
var failures:=0
var records:Array=[]
var host
var state_dir := ""
func _initialize():call_deferred('run')
func check(ok,label):
 checks+=1;records.append({'ok':ok,'label':label});print(('PASS ' if ok else 'FAIL ')+label)
 if not ok:failures+=1
func click(button):
 await process_frame
 for pressed in [true,false]:
  var e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=button.get_global_rect().get_center();e.pressed=pressed;root.push_input(e,true);await process_frame
func shot(id):
 await process_frame;await process_frame;RenderingServer.force_draw(true)
 root.get_texture().get_image().save_png(state_dir+'/'+id+'.png')
func run():
 await process_frame
 root.size=Vector2i(1920,1080)
 var args=OS.get_cmdline_user_args()
 state_dir=str(args[0]) if args.size()>0 else ''
 var isolated=state_dir.begins_with('/tmp/') and root.get_node('Data').codex_store.path==state_dir+'/codex.json'
 check(isolated,'Codex IO uses explicit isolated /tmp path')
 if not isolated:
  quit(1)
  return
 change_scene_to_file(ProjectSettings.get_setting('application/run/main_scene'))
 for i in 8:await process_frame
 host=current_scene
 check(host.scene_file_path=='res://scenes/night/Night.tscn','Default Boot main scene reaches real Night host')
 check(host.panel.buttons.has('codex') and host.panel.buttons.codex.is_visible_in_tree(),'Default Night page has reachable codex button')
 await shot('01-default-night-1080')
 root.size=Vector2i(1280,720);await click(host.panel.buttons.codex)
 check(host.codex_panel.surface.visible,'Actual Night codex button opens codex')
 for book in ['humans','ghosts','items','customs']:
  await click(host.codex_panel.buttons['book_'+book])
  check(host.codex_panel.current_book==book and host.codex_panel.rows.get_child_count()>0,'Real tab button opens '+book)
  await shot('02-'+book+'-720')
 await click(host.codex_panel.buttons.close)
 check(not host.codex_panel.surface.visible,'Actual close returns to Night menu')
 host.panel.seed_input.text='P8-HOST-SMOKE-ISOLATED'
 await click(host.panel.buttons.growth_shouxiang)
 check(host.run.state.get('roster_enabled',false) and host.run.state.mode=='shouxiang' and host.run.state.phase=='map','Growth Night button starts actual new_roster_run')
 check(host.run.codex.entry('ritual_example_incense').stage==1,'Initial example-incense ritual is stage 1 in actual night codex')
 check(FileAccess.file_exists(state_dir+'/night.json') and FileAccess.file_exists(state_dir+'/codex.json'),'Actual host writes only isolated Night and Codex files')
 await shot('03-growth-map-720')
 var first=host.run.available_nodes()[0].id
 await click(host.panel.buttons['node_'+first])
 check(is_instance_valid(host.combat) and host.combat.get_node('Session').roster.enabled,'Actual first node enters managed P8 combat')
 var sim=host.combat.get_node('Simulation');sim.set_physics_process(false);root.get_node('Clock').set_paused(true)
 var decisions=host.combat.get_node('Decisions');var chosen
 for unit in sim.humans:
  if unit.unit_id=='H17':chosen=unit
 check(chosen!=null,'Actual carried first-battle roster contains H17')
 if chosen!=null:
  decisions.select_unit(chosen)
  check(decisions.portrait.texture!=null and decisions.details.text.contains(chosen.skill_text),'Carried unit complete card displays real portrait and source skill')
  await shot('04-managed-card-720')
  await click(decisions.buttons.card_skill)
  check(decisions.current_panel=='unit_skill' and decisions.buttons.has('skill_cast'),'Real carried-card skill button opens formal dedicated command menu')
  await shot('05-managed-skill-720')
 print('P8HostSmoke RESULT %d/%d'%[checks,failures])
 var f=FileAccess.open(state_dir+'/results.json',FileAccess.WRITE);f.store_string(JSON.stringify({'scope':'Actual default Boot/Night host UI smoke; first-node only, not a complete night. Temporary source copy changes only IO paths to /tmp.','checks':checks,'failures':failures,'records':records},'\t'));f.close()
 host._dispose_battle();quit(failures)
