extends Node
var game: Node3D
var bridge: Node
var checks := 0
var failures := 0
var ray := Vector3.ZERO
var port := 0
var capture_dir := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("CONTROL FAIL: "+message)

func frames(count := 2) -> void:
	for i in count: await get_tree().process_frame

func new_client() -> Dictionary:
	var socket := StreamPeerTCP.new()
	socket.connect_to_host("127.0.0.1",port)
	var deadline := Time.get_ticks_msec()+1500
	while Time.get_ticks_msec()<deadline:
		socket.poll()
		if socket.get_status()==StreamPeerTCP.STATUS_CONNECTED: break
		await frames(1)
	check(socket.get_status()==StreamPeerTCP.STATUS_CONNECTED,"TCP connection")
	if socket.get_status()==StreamPeerTCP.STATUS_CONNECTED: socket.set_no_delay(true)
	return {"socket":socket,"id":0,"rx":PackedByteArray()}

func packet(request: Dictionary) -> PackedByteArray:
	var body := JSON.stringify(request).to_utf8_buffer()
	var n := body.size()
	var bytes := PackedByteArray([(n>>24)&255,(n>>16)&255,(n>>8)&255,n&255])
	bytes.append_array(body)
	return bytes

func send_request(c: Dictionary, body: Dictionary) -> void:
	c.id += 1
	body.v = 1
	body.id = c.id
	body.payload_bytes = 0
	c.socket.put_data(packet(body))

func receive(c: Dictionary) -> Dictionary:
	var deadline := Time.get_ticks_msec()+1800
	while Time.get_ticks_msec()<deadline:
		c.socket.poll()
		var available: int = c.socket.get_available_bytes()
		if available>0:
			var received: Array = c.socket.get_partial_data(available)
			c.rx.append_array(received[1])
		if c.rx.size()>=4:
			var n: int = (int(c.rx[0])<<24)|(int(c.rx[1])<<16)|(int(c.rx[2])<<8)|int(c.rx[3])
			if c.rx.size()>=n+4:
				var result: Dictionary = JSON.parse_string(c.rx.slice(4,4+n).get_string_from_utf8())
				var length: int = result.payload_bytes
				if c.rx.size()>=4+n+length:
					result.image = c.rx.slice(4+n,4+n+length)
					c.rx = c.rx.slice(4+n+length)
					return result
		await frames(1)
	check(false,"response received before deadline")
	return {"ok":false,"error":"timeout","image":PackedByteArray()}

func request(c: Dictionary, body: Dictionary) -> Dictionary:
	send_request(c,body)
	return await receive(c)

func observe(c: Dictionary) -> Dictionary:
	var result := await request(c,{"type":"observe"})
	check(result.ok,"observation returned")
	return result

func action(frame: Dictionary, yaw := 0.0, pitch := 0.0, fire := true) -> Dictionary:
	return {"type":"act","frame_id":frame.frame_id,"round_id":frame.round_id,"yaw_deg":yaw,"pitch_deg":pitch,"fire":fire}

func target_action(frame: Dictionary, point: Vector3) -> Dictionary:
	var direction: Vector3 = (point-game.player.camera.global_position).normalized()
	var yaw := atan2(-direction.x,-direction.z)
	var pitch := asin(direction.y)
	return action(frame,-rad_to_deg(wrapf(yaw-game.player.rotation.y,-PI,PI)),rad_to_deg(pitch-game.player._pitch))

func run(controller: Node3D) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = controller
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir=arg.trim_prefix("--capture-dir=")
	bridge = load("res://scripts/control_bridge.gd").new()
	game.add_child(bridge)
	game.control_bridge = bridge
	check(bridge.start(game,"127.0.0.1",0,"control-test"),"listener started")
	port = bridge.server.get_local_port()
	game.shot_fired.connect(func(_origin: Vector3,direction: Vector3): ray=direction)
	var bad := await new_client()
	check((await request(bad,{"type":"hello","token":"wrong"})).error=="unauthorized","wrong token rejected")
	var c := await new_client()
	# Split both the binary prefix and JSON body across network writes.
	c.id = 1
	var hello := packet({"v":1,"id":1,"type":"hello","token":"control-test","payload_bytes":0})
	c.socket.put_data(hello.slice(0,2))
	await frames(2)
	c.socket.put_data(hello.slice(2,8))
	await frames(2)
	c.socket.put_data(hello.slice(8))
	check((await receive(c)).ok and game.player.remote_controlled,"fragmented handshake takes control")
	bad = await new_client()
	check((await request(bad,{"type":"hello","token":"control-test"})).error=="busy","second controller rejected")
	# Two requests arriving in one TCP packet must retain their separate replies.
	var pings := packet({"v":1,"id":2,"type":"ping"})
	pings.append_array(packet({"v":1,"id":3,"type":"ping"}))
	c.socket.put_data(pings)
	check((await receive(c)).id==2 and (await receive(c)).id==3,"coalesced messages")
	c.id = 3
	# Render-only color patches validate JPEG orientation/channel order. They are
	# local fixtures, never part of normal game play or a target-data endpoint.
	var patches: Array[ColorRect] = []
	for i in 3:
		var patch := ColorRect.new()
		patch.position = Vector2(16+i*48,16)
		patch.size = Vector2(32,32)
		patch.color = [Color.RED,Color.GREEN,Color.BLUE][i]
		game.ui.root.add_child(patch)
		patches.append(patch)
	var calibration := await observe(c)
	var colors := Image.new()
	colors.load_jpg_from_buffer(calibration.image)
	for i in 3:
		var pixel := colors.get_pixel(int((32+i*48)*calibration.width/game.ui.root.size.x),int(32*calibration.height/game.ui.root.size.y))
		var channels := [pixel.r,pixel.g,pixel.b]
		check(channels[i]>0.7 and channels[(i+1)%3]<0.2 and channels[(i+2)%3]<0.2,"JPEG RGB channel and top-left orientation "+str(i))
	for patch in patches: patch.queue_free()
	var next_frame := await observe(c)
	check(next_frame.timestamp_us-calibration.timestamp_us>=33334,"frame capture capped at 30 Hz")
	var previous_frame := {}
	for map_id in ["training_hall","old_town"]:
		for weapon_id in ["deagle","ak47","m4a1"]:
			game.show_setup()
			game.ui._select(map_id,weapon_id)
			game.start_round()
			game.begin_training()
			await frames(12)
			game.player.set_physics_process(false)
			var image := await observe(c)
			if not previous_frame.is_empty():
				check((await request(c,action(previous_frame))).error=="stale_observation","old round cannot control new round")
			previous_frame = image
			check(image.image.size()>5000 and image.encoding=="jpeg","real JPEG payload")
			var decoded := Image.new()
			check(decoded.load_jpg_from_buffer(image.image)==OK and decoded.get_width()==int(image.width) and decoded.get_height()==int(image.height),"JPEG dimensions decode")
			check(is_equal_approx(image.camera.cx,image.width/2.0) and is_equal_approx(image.camera.cy,image.height/2.0) and image.camera.fx>0 and image.camera.fy>0,"camera intrinsics match image")
			var local_point := Vector3(1,0.5,-10)
			var projected: Vector2 = game.player.camera.unproject_position(game.player.camera.global_transform*local_point)
			var viewport_size: Vector2 = game.get_viewport().get_visible_rect().size
			projected *= Vector2(image.width/viewport_size.x,image.height/viewport_size.y)
			check(projected.distance_to(Vector2(image.camera.cx+image.camera.fx*0.1,image.camera.cy-image.camera.fy*0.05))<0.01,"intrinsics agree with rendered camera projection")
			var header := image.duplicate()
			header.erase("image")
			var text := JSON.stringify(header).to_lower()
			check(not "target" in text and not "head" in text and not "position" in text and not "visible" in text,"no target ground truth in observation")
			if not capture_dir.is_empty() and map_id=="training_hall" and weapon_id=="deagle":
				DirAccess.make_dir_recursive_absolute(capture_dir)
				decoded.save_png(capture_dir.path_join("control-camera.png"))
			for speed in [0.339,0.34,0.341,1.0]:
				game.player._horizontal_speed = speed*game.player.MAX_SPEED
				game.weapon.advance_ms(300)
				var before: int = game.shots
				var mag: int = game.weapon.mag
				var rng_before: int=game.shot_rng.state
				var result := await request(c,action(image))
				check(result.ok and result.fired and game.shots==before+1 and game.weapon.mag==mag-1,map_id+weapon_id+" remote single shot at "+str(speed))
				check((game.shot_rng.state==rng_before)==(speed<0.34),"remote shot obeys precision boundary")
				game.projectiles.clear()
			game.player._horizontal_speed = 0
			game.weapon.reset(weapon_id)
			game.weapon.active = true
			var target: Node3D = game.arena.targets[0]
			game.player.reset_position(game.arena.map_root.test_views[0])
			game.player.set_physics_process(true)
			await frames(12)
			game.player.set_physics_process(false)
			image = await observe(c)
			var before_hits: int = game.hits
			var result := await request(c,target_action(image,target.get_node("Body").global_position))
			while game.projectiles.live_count()>0:
				await request(c,{"type":"ping"})
				await frames(2)
			check(result.fired and game.hits==before_hits+1 and target.hp==100,"remote body hit has zero damage")
			game.weapon.advance_ms(300)
			game.weapon.mag = 1
			game.weapon.reserve = 0
			var before_kills: int = game.kills
			result = await request(c,target_action(image,target.get_node("Head").global_position))
			check(result.fired and game.settling,"remote last projectile enters settling")
			while game.projectiles.live_count()>0:
				await request(c,{"type":"ping"})
				await frames(2)
			check(result.fired and game.phase=="results" and game.kills==before_kills+1,"remote aim then last headshot counts before results")
			game.player.set_physics_process(true)
	await radar_and_settlement(c)
	game.show_setup()
	game._select_loadout("training_hall","ak47")
	# Guard behavior in an active round.
	game.start_round()
	game.begin_training()
	await frames(4)
	var image := await observe(c)
	var result := await request(c,action(image,5,3,false))
	check(result.ok and result.look_applied and not result.fired and is_equal_approx(game.player._pitch,deg_to_rad(3)),"right/up angle convention")
	result = await request(c,action(image,0,180,false))
	check(is_equal_approx(game.player._pitch,1.42),"pitch upper clamp")
	result = await request(c,action(image,0,-180,false))
	check(is_equal_approx(game.player._pitch,-1.42),"pitch lower clamp")
	game.player.reset_position(game.arena.get_spawn().origin)
	game.weapon.last_fire_ms = game.weapon.time_ms+1000
	var before: int = game.shots
	var rng_before: int = game.shot_rng.state
	result = await request(c,action(image,2,0))
	check(result.look_applied and not result.fired and result.fire_error=="cooldown","cooldown rejects fire but applies look")
	game.weapon.advance_ms(2000)
	await frames(10)
	check(game.shots==before and game.shot_rng.state==rng_before,"failed shot does not queue or consume RNG")
	game.weapon.mag -= 1
	result = await request(c,{"type":"reload","frame_id":image.frame_id,"round_id":image.round_id})
	check(result.reloaded and game.weapon.is_reloading(),"remote reload")
	result = await request(c,action(image))
	check(not result.fired and result.fire_error=="reloading","reload blocks shot")
	game.weapon.advance_ms(4000)
	game.weapon.mag = 0
	result = await request(c,action(image))
	check(not result.fired and result.fire_error=="mag_empty","empty weapon blocks shot")
	game.weapon.reset("ak47")
	game.weapon.active = true
	game.weapon.mag -= 1
	var rotation_before: Vector3 = game.player.rotation
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(200,200)
	game.player._unhandled_input(mouse)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._unhandled_input(click)
	var reload_event := InputEventAction.new()
	reload_event.action = "reload"
	reload_event.pressed = true
	game._unhandled_input(reload_event)
	check(game.player.rotation==rotation_before and game.pending_shots==0 and not game.weapon.is_reloading(),"manual look/fire/reload disabled during takeover")
	var position_before: Vector3 = game.player.position
	Input.action_press("move_right")
	await frames(20)
	Input.action_release("move_right")
	check(game.player.position.distance_to(position_before)>0.1,"manual WASD still works")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not get_tree().paused,"controller survives game focus loss")
	send_request(c,action(image))
	game.pause_game()
	result = await receive(c)
	check(not result.ok and result.error=="paused","pause wins over pending input")
	var paused_image := await observe(c)
	check(paused_image.state.paused and not paused_image.state.can_fire,"paused observation allowed")
	game.resume_game()
	check((await request(c,action(image))).error=="stale_observation","pre-pause frame invalid after resume")
	# Reading a paused frame must not permit firing after resume either.
	check((await request(c,action(paused_image))).error=="stale_observation","paused frame invalid after resume")
	image = await observe(c)
	result = await request(c,action(image,0,0,false))
	check(result.ok,"fresh frame restores control")
	before = game.shots
	# Duplicate sequence IDs close the controller without replaying its action.
	var duplicate := action(image)
	duplicate.v = 1
	duplicate.id = c.id
	c.socket.put_data(packet(duplicate))
	check((await receive(c)).error=="invalid_request","duplicate request id rejected")
	await frames(4)
	check(game.shots==before and get_tree().paused and not game.player.remote_controlled,"duplicate action never fires and connection released")
	game.resume_game()
	c = await new_client()
	check((await request(c,{"type":"hello","token":"control-test"})).ok,"reconnect works")
	check((await request(c,action(image))).error=="stale_observation","old session frame rejected")
	# Slow consumer: one requested image only; timeout releases control.
	send_request(c,{"type":"observe"})
	var initial_frame: int = bridge.frame_id
	var until := Time.get_ticks_msec()+2300
	while Time.get_ticks_msec()<until: await frames(1)
	check(bridge.frame_id==initial_frame+1,"slow client does not accumulate frames")
	check(not game.player.remote_controlled and get_tree().paused,"idle timeout pauses and releases control")
	game.resume_game()
	bad = await new_client()
	bad.socket.put_data(PackedByteArray([127,255,255,255]))
	await frames(6)
	bad.socket.poll()
	check(bad.socket.get_status()!=StreamPeerTCP.STATUS_CONNECTED,"oversized frame closes connection")
	game.show_menu()
	game.shot_sound.stop()
	game.hit_sound.stop()
	await frames(4)
	print("CONTROL PASS: %d checks (%d failures)" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)

func radar_and_settlement(c: Dictionary) -> void:
	for weapon_id in ["deagle","ak47","m4a1"]:
		game.show_setup()
		game._select_loadout("assessment_yard",weapon_id)
		game.start_round()
		while not game.arena.map_root.navigation_ready:
			await request(c,{"type":"ping"})
			await frames(1)
		game.begin_training()
		await frames(12)
		var image:=await observe(c)
		check(image.state.remaining_s==-1 and image.state.game_time_s>=0 and not image.state.settling,"unlimited yard state "+weapon_id)
		var header:=image.duplicate()
		header.erase("image")
		var text:=JSON.stringify(header).to_lower()
		for forbidden in ["target","radar","position","layout","seed","head","visible","opponent"]:
			check(not forbidden in text,"no local radar data in protocol: "+forbidden)
		game.player.apply_look_delta(0,60)
		var result:=await request(c,action(image))
		check(result.fired and game.shots==1 and game.projectiles.live_count()>0,"yard remote launch is one moving projectile "+weapon_id)
		game.begin_settlement("测试在途结算")
		result=await request(c,action(image,1,0,true))
		check(result.look_applied and not result.fired and result.fire_error=="round_finishing","settlement permits live player look but no new shot")
		result=await request(c,{"type":"reload","frame_id":image.frame_id,"round_id":image.round_id})
		check(not result.reloaded and result.reload_error=="round_finishing","settlement cannot reload")
		if weapon_id!="ak47": continue
		# Freeze the fixture while both the socket JPEG and local window are read.
		game.set_physics_process(false)
		game.player.set_physics_process(false)
		game.weapon.set_physics_process(false)
		await frames(12)
		image=await observe(c)
		var decoded:=Image.new()
		decoded.load_jpg_from_buffer(image.image)
		await RenderingServer.frame_post_draw
		var window:=get_window().get_texture().get_image()
		var clean:=get_viewport().get_texture().get_image()
		var radar: Control=get_tree().current_scene.radar
		check(radar.visible,"local radar remains visible while requesting JPEG")
		var error:=0.0
		var local_difference:=0.0
		var samples:=0
		var rect:=radar.get_global_rect().grow(-8)
		for y in range(int(rect.position.y),int(rect.end.y),4):
			for x in range(int(rect.position.x),int(rect.end.x),4):
				var a:=decoded.get_pixel(x,y)
				var b:=clean.get_pixel(x,y)
				var d:=window.get_pixel(x,y)
				error+=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
				local_difference+=absf(a.r-d.r)+absf(a.g-d.g)+absf(a.b-d.b)
				samples+=1
		check(error/samples<0.09 and local_difference/samples>0.12,"actual TCP JPEG preserves original pixels beneath local radar")
		if not capture_dir.is_empty():
			window.save_png(capture_dir.path_join("radar-local.png"))
			clean.save_png(capture_dir.path_join("radar-clean.png"))
			var file:=FileAccess.open(capture_dir.path_join("radar-program.jpg"),FileAccess.WRITE)
			file.store_buffer(image.image)
		game.set_physics_process(true)
		game.player.set_physics_process(true)
		game.weapon.set_physics_process(true)
