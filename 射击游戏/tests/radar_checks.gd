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
	if "--audio-demo" in OS.get_cmdline_user_args():
		await audio_demo()
		print("RADAR PASS: %d checks (%d failures)"%[checks,failures])
		get_tree().quit(1 if failures else 0)
		return
	check(not radar.visible,"menu hides radar")
	var state:=Snapshot.new()
	for i in 8:
		var angle:=i*PI/4
		state.advance(0,Vector3.ZERO,Vector3(sin(angle),0,-cos(angle))*10,true,true,0,true)
		check(state.sector==i,"eight directional sectors")
	state.advance(0,Vector3.ZERO,Vector3.FORWARD*10,true,true,PI/2,true)
	check(state.sector==2,"turning updates relative direction")
	state.advance(0,Vector3.ZERO,Vector3.FORWARD*10,true,true,0,true)
	state.advance(0.1,Vector3.ZERO,Vector3.RIGHT*10,true,true,0)
	check(state.sector==0,"bearing waits for sampling interval")
	state.advance(0.4,Vector3.ZERO,Vector3.RIGHT*10,true,true,0)
	check(state.sector==2,"bearing updates after half second")
	state.advance(0,Vector3.ZERO,Vector3(0,8,0),true,true,0,true)
	check(state.overlap,"height ignored at overlapping horizontal position")
	game.show_setup()
	game.ui._select("assessment_yard","ak47")
	game.start_round()
	await frames()
	check(not radar.visible,"countdown hides radar")
	while not game.arena.map_root.navigation_ready: await frames(1)
	game.begin_training()
	game.player.set_physics_process(false)
	await frames()
	check(radar.visible and radar.snapshot.present,"wall-obscured opponents visible during training")
	check(radar.snapshot.round_id==game.round_id,"new round supplies direction only")
	await capture("radar-training")
	await paired_capture()
	var original: float=radar.snapshot.bearing
	game.pause_game()
	await frames(2)
	game.player.position.x+=8
	await get_tree().create_timer(0.6,true).timeout
	check(not radar.visible and radar.snapshot.bearing==original,"pause hides and freezes radar sample")
	await capture("radar-paused")
	game.ui.show_help()
	await capture("radar-help")
	game.ui.close_help()
	game.resume_game()
	await frames(2)
	check(radar.visible and radar.snapshot.bearing!=original,"resume immediately refreshes")
	var top: Vector3=game.arena.map_root.layout.platform_center(game.arena.map_root.layout.platforms[1])
	game.player.position=top
	game.duel.bot.position=top+Vector3(0,-2,0)
	radar.was_visible=false
	await frames(2)
	check(radar.snapshot.overlap,"high platform retains coarse overlap")
	await capture("radar-overlap")
	game.begin_settlement("测试结算")
	await frames(2)
	check(radar.visible,"settling keeps radar")
	game.duel.player_alive=false
	await frames(2)
	check(not radar.snapshot.present,"dead player immediately disappears")
	game.finish_round("测试结束")
	await frames(2)
	check(not radar.visible,"results hides radar")
	var previous_round: int=game.round_id
	game.start_round()
	while not game.arena.map_root.navigation_ready: await frames(1)
	game.begin_training()
	await frames(2)
	check(radar.visible and radar.snapshot.round_id>previous_round and radar.snapshot.present,"replay restores new round contacts")
	for map_id in ["old_town","training_hall"]:
		await prepare(map_id)
		await frames(2)
		check(not radar.visible and not radar.snapshot.present,"other map clears radar "+map_id)
	await audio_checks()
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

func audio_checks() -> void:
	await prepare("training_hall")
	game.player.set_physics_process(true)
	await frames(12)
	var sound=game.player.footsteps
	var before: int=sound.count
	Input.action_press("move_forward")
	await frames(80)
	Input.action_release("move_forward")
	check(sound.count>before,"actual grounded travel produces footsteps")
	await frames(90)
	before=sound.count
	await frames(30)
	check(sound.count==before,"stationary player has no repeated steps")
	Input.action_press("jump")
	await frames(18)
	Input.action_release("jump")
	before=sound.count
	await frames(18)
	check(sound.count==before,"airborne movement is silent")
	await frames(100)
	check(sound.count==before+1,"landing produces one impact")
	sound.emit_step("hard")
	game.pause_game()
	await frames(2)
	check(sound.voice.stream_paused,"pause suspends footstep playback")
	game.resume_game()
	await frames(2)
	check(not sound.voice.stream_paused,"resume releases playback pause")
	check(game.combat_sound("head").data != game.combat_sound("body").data,"head and body use distinct impact Foley")
	var shot_state: int=game.shot_rng.state
	var fingerprints: Array=[]
	for id in ["deagle","ak47","m4a1"]:
		var clip: AudioStreamWAV=game.combat_sound(id)
		fingerprints.append(hash(clip.data))
	check(fingerprints[0]!=fingerprints[1] and fingerprints[1]!=fingerprints[2],"three independent gun timbres")
	check(game.shot_rng.state==shot_state,"audio randomness never consumes spread RNG")
	await prepare("assessment_yard")
	var opponent=game.duel.bot
	var top: Vector3=game.arena.map_root.layout.platform_center(game.arena.map_root.layout.platforms[0])
	opponent.position=top
	await frames(3)
	check(opponent.footsteps.surface()=="wood","platform collider selects wood Foley")
	opponent.position=Vector3(0,0.02,33)
	game.player.position=Vector3(0,0.02,35)
	await frames(3)
	opponent.footsteps.advance(0.1,true)
	check(not opponent.footsteps.blocked,"open path keeps footsteps clear")
	var wall:=StaticBody3D.new()
	var collider:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(5,5,0.2)
	collider.shape=shape
	wall.add_child(collider)
	game.add_child(wall)
	wall.position=Vector3(0,2,34)
	await frames(3)
	opponent.footsteps.advance(0.2,true)
	check(opponent.footsteps.blocked and opponent.footsteps.voice.volume_db<=-15.9 and opponent.footsteps.filter.cutoff_hz<2200,"wall attenuates and low-passes opponent steps")
	wall.free()
	game.show_menu()
	check(not opponent.footsteps.voice.playing,"menu stops opponent Foley")


func audio_demo() -> void:
	for id in ["deagle","ak47","m4a1"]:
		await prepare("training_hall",id)
		game.player.camera.rotation.x=0.5
		for shot in 3:
			game.weapon.advance_ms(500)
			game.weapon.try_fire()
			for tick in 60:
				game.projectiles.advance(1.0/120)
				await get_tree().physics_frame
		await capture("gun-"+id)
		for empty in [false,true]:
			game.weapon.mag=0 if empty else 2
			game.weapon.reserve=90
			check(game.weapon.start_reload(),"demo reload starts")
			while game.weapon.is_reloading():
				game.weapon.advance_ms(1000.0/60)
				game.player.update_reload(game.weapon.reload_left_ms,game.weapon.get_data().reload_ms,game.weapon.reload_kind,game.weapon.reload_serial)
				await get_tree().physics_frame

		await get_tree().create_timer(0.6).timeout
	await prepare("assessment_yard")
	game.player.reset_position(Vector3(8,0.02,34))
	game.player.set_physics_process(true)
	Input.action_press("move_left")
	await frames(100)
	Input.action_release("move_left")
	await frames(70)
	await capture("own-footsteps")
	game.player.set_physics_process(false)
	var bot=game.duel.bot
	bot.position=Vector3(0,0.02,33)
	bot.rotation.y=PI
	bot.reaction=-100
	bot.active=true
	game.player.camera.look_at(bot.position+Vector3.UP)
	await walk_bot(Vector3(0,0.02,35),"opponent footsteps demo")
	check(bot.footsteps.count>0,"demo opponent emits actual movement Foley")
	await capture("opponent-footsteps")
	await get_tree().create_timer(0.7).timeout
