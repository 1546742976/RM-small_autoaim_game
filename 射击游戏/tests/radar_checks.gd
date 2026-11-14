extends "res://tests/projectile_checks.gd"
const Snapshot = preload("res://scripts/radar_snapshot.gd")
var radar: Control

func frames(count:=2) -> void:
	for i in count: await get_tree().physics_frame
	for i in 3: await get_tree().process_frame

func run(controller: Node3D) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	game=controller
	game.set_physics_process(false)
	game.weapon.set_physics_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): folder=arg.trim_prefix("--capture-dir=")
	if folder.is_empty(): folder="user://radar-checks"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(3)
	radar=get_tree().current_scene.radar
	check(not radar.visible,"menu hides radar")
	for x in [-21.0,-20.0,-17.001,-17.0,20.0,21.0,100.0]:
		for z in [-36.0,-35.0,-32.001,-32.0,35.0,36.0]:
			var point:=Snapshot.region_center(Vector3(x,0,z))
			check(Snapshot.BOUNDS.has_point(point),"quantized point stays inside map")
			check(point==Snapshot.region_center(Vector3(x,10,z)),"height never changes contact")
	check(Snapshot.region_center(Vector3(-21,0,-36))==Vector2(-19,-34),"negative corner cell center")
	check(Snapshot.region_center(Vector3(21,0,36))==Vector2(20,34),"partial edge cell center")
	var state:=Snapshot.new()
	state.sample(Vector3.ZERO,Vector3(1,0,1),true,true)
	var initial:=state.contacts.duplicate()
	check(not state.advance(0.499,Vector3(10,0,10),Vector3(-10,0,-10),true,true) and state.contacts==initial,"half-second sample holds coarse region")
	check(state.advance(0.001,Vector3(10,0,10),Vector3(-10,0,-10),true,true) and state.contacts!=initial,"half-second sample refreshes both sides")
	state.sample(Vector3.ZERO,Vector3(0,6,0),true,true)
	check(state.contacts.player==state.contacts.opponent,"same area / different height has identical center")
	state.advance(0,Vector3.ZERO,Vector3.ZERO,false,true)
	check(not state.contacts.has("player") and state.contacts.has("opponent"),"death removes only dead contact immediately")
	game.show_setup()
	game.ui._select("assessment_yard","ak47")
	game.start_round()
	await frames()
	check(not radar.visible,"countdown hides radar")
	while not game.arena.map_root.navigation_ready: await frames(1)
	game.begin_training()
	game.player.set_physics_process(false)
	await frames()
	check(radar.visible and radar.snapshot.contacts.size()==2,"wall-obscured opponents visible during training")
	check(radar.snapshot.round_id==game.round_id and not radar.snapshot.regions.is_empty(),"current random map supplies coarse passages")
	await capture("radar-training")
	await paired_capture()
	var original: Dictionary=radar.snapshot.contacts.duplicate()
	game.pause_game()
	await frames(2)
	game.player.position.x+=8
	await get_tree().create_timer(0.6,true).timeout
	check(not radar.visible and radar.snapshot.contacts==original,"pause hides and freezes radar sample")
	await capture("radar-paused")
	game.ui.show_help()
	await capture("radar-help")
	game.ui.close_help()
	game.resume_game()
	await frames(2)
	check(radar.visible and radar.snapshot.contacts.player!=original.player,"resume immediately refreshes")
	var top: Vector3=game.arena.map_root.layout.platform_center(game.arena.map_root.layout.platforms[1])
	game.player.position=top
	game.duel.bot.position=top+Vector3(0,-2,0)
	radar.was_visible=false
	await frames(2)
	check(radar.snapshot.contacts.player==radar.snapshot.contacts.opponent,"high platform retains coarse overlap")
	await capture("radar-overlap")
	game.begin_settlement("测试结算")
	await frames(2)
	check(radar.visible,"settling keeps radar")
	game.duel.player_alive=false
	await frames(2)
	check(not radar.snapshot.contacts.has("player"),"dead player immediately disappears")
	game.finish_round("测试结束")
	await frames(2)
	check(not radar.visible,"results hides radar")
	var previous_round: int=game.round_id
	game.start_round()
	while not game.arena.map_root.navigation_ready: await frames(1)
	game.begin_training()
	await frames(2)
	check(radar.visible and radar.snapshot.round_id>previous_round and radar.snapshot.contacts.size()==2,"replay restores new round contacts")
	for map_id in ["old_town","training_hall"]:
		await prepare(map_id)
		await frames(2)
		check(not radar.visible and radar.snapshot.contacts.is_empty(),"other map clears radar "+map_id)
	if DisplayServer.get_name()!="headless": await physical_input()
	game.show_menu()
	var report:=FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("RADAR PASS: %d checks (%d failures)"%[checks,failures])
	get_tree().quit(1 if failures else 0)

func paired_capture() -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var local: Image=get_window().get_texture().get_image()
	var clean: Image=game.get_viewport().get_texture().get_image()
	local.save_png(folder.path_join("local-window.png"))
	clean.save_png(folder.path_join("program-view.png"))
	check(local.get_size()==clean.get_size() and local.get_size()==DisplayServer.window_get_size(),"one-to-one inner and outer render dimensions")
	var outside:=0.0
	var inside:=0.0
	var samples:=0
	for y in range(0,local.get_height(),8):
		for x in range(0,local.get_width(),8):
			var a:=local.get_pixel(x,y)
			var b:=clean.get_pixel(x,y)
			var difference:=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
			if radar.get_global_rect().has_point(Vector2(x,y)): inside+=difference
			else: outside+=difference; samples+=1
	check(outside/maxi(1,samples)<0.012 and inside>5,"only radar region differs; underlying game remains intact")

func physical_input() -> void:
	game.show_menu()
	await frames(24)
	var button: Button=game.ui.action_buttons.start
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.position=button.get_global_rect().get_center()*Vector2(game.get_viewport().size)/game.ui.root.size
	event.pressed=true
	Input.parse_input_event(event)
	event=event.duplicate()
	event.pressed=false
	Input.parse_input_event(event)
	await frames(3)
	check(game.phase=="setup","outer window forwards actual menu click")
	await prepare("assessment_yard")
	game.set_physics_process(true)
	game.weapon.set_physics_process(true)
	game.player.set_physics_process(true)
	await frames(12)
	var before: Vector3=game.player.position
	Input.action_press("move_right")
	await frames(20)
	Input.action_release("move_right")
	check(game.player.position.x>before.x,"WASD still moves under local overlay")
	Input.action_press("jump")
	await frames(18)
	Input.action_release("jump")
	check(game.player.position.y>0.5,"Space jump survives viewport routing")
	var key:=InputEventKey.new()
	key.keycode=KEY_ESCAPE
	key.pressed=true
	Input.parse_input_event(key)
	key=key.duplicate()
	key.pressed=false
	Input.parse_input_event(key)
	await frames(2)
	check(get_tree().paused and not radar.visible,"Esc pauses through container exactly once")
	game.resume_game()
	game.set_physics_process(false)
	game.weapon.set_physics_process(false)
