extends Node
## Explicit export-compatible presentation harness. Recording is not a benchmark.
var game: Node3D
var folder := ""
var demo_weapon := "ak47"
var demo_kind := "empty"
var slowdown := 1.0

func frames(count: int) -> void:
	for _i in count: await get_tree().process_frame

func capture(name_text: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(folder.path_join(name_text+".png"))
	assert(result == OK)

func equip(map_id: String, weapon_id: String) -> void:
	game.show_setup()
	game.ui._select(map_id, weapon_id)
	game.start_round()
	game.begin_training()
	game.player.camera.rotation = Vector3.ZERO

func click(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = get_viewport().get_visible_rect().size/2
	game._unhandled_input(event)

func run(controller: Node3D) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = controller
	# Apply the requested capture size after the window has entered the scene.
	var engine_args := OS.get_cmdline_args()
	var resolution_index := engine_args.find("--resolution")
	if resolution_index >= 0 and resolution_index+1 < engine_args.size():
		var dimensions := engine_args[resolution_index+1].split("x")
		if dimensions.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(dimensions[0]),int(dimensions[1])))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): folder = arg.trim_prefix("--capture-dir=")
		elif arg.begins_with("--demo-weapon="): demo_weapon = arg.trim_prefix("--demo-weapon=")
		elif arg.begins_with("--demo-kind="): demo_kind = arg.trim_prefix("--demo-kind=")
		elif arg.begins_with("--demo-slow="): slowdown = float(arg.trim_prefix("--demo-slow="))
	if folder.is_empty(): folder = "user://viewmodel-evidence"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(3)
	if "--viewmodel-benchmark" in OS.get_cmdline_user_args(): await benchmark()
	elif "--capture-only" in OS.get_cmdline_user_args(): await captures()
	elif "--hold-fire-demo" in OS.get_cmdline_user_args(): await hold_demo()
	else: await reload_demo()
	Engine.time_scale = 1.0
	Input.action_release("move_left")
	Input.action_release("move_right")
	click(false)
	game._stop_play()
	print("VIEWMODEL PRESENTATION COMPLETE")
	get_tree().quit()

func captures() -> void:
	for map_id: String in ["training_hall", "old_town"]:
		for id: String in ["deagle", "ak47", "m4a1"]:
			equip(map_id,id)
			await frames(20)
			game.set_physics_process(false)
			game.weapon.set_physics_process(false)
			game.player.active = false
			var view = game.player.view
			await capture(map_id+"-"+id+"-idle")
			for kind: String in ["empty","tactical"]:
				var duration: float = game.weapon.get_data().reload_ms
				for p: float in [0.18,0.35,0.62,0.85]:
					view.set_reload(duration*(1.0-p),duration,kind,1 if kind=="empty" else 2)
					await frames(2)
					await capture("%s-%s-%s-%03d" % [map_id,id,kind,int(p*100)])
			view.reset_pose()
			game.set_physics_process(true)
			game.weapon.set_physics_process(true)

func reload_demo() -> void:
	equip("old_town",demo_weapon)
	await frames(45)
	await capture(demo_weapon+"-idle")
	game.weapon.mag = 0 if demo_kind=="empty" else maxi(1,int(game.weapon.get_data().mag_size)/2)
	Engine.time_scale = 1.0/slowdown
	# Release exports remove assert expressions, including their side effects.
	if not game.weapon.start_reload():
		push_error("Reload demonstration could not start")
		get_tree().quit(1)
		return
	var start_game_ms: float = game.weapon.time_ms
	var start_frame: int = Engine.get_process_frames()
	var start := Time.get_ticks_usec()
	while game.weapon.is_reloading(): await frames(1)
	var reload_wall_seconds := (Time.get_ticks_usec()-start)/1000000.0
	var reload_game_ms: float = game.weapon.time_ms-start_game_ms
	var reload_frames: int = Engine.get_process_frames()-start_frame
	Engine.time_scale = 1.0
	await frames(45)
	var report := {"weapon":demo_weapon,"kind":demo_kind,"slowdown":slowdown,
		"reload_ms":game.weapon.get_data().reload_ms,"reload_wall_seconds":reload_wall_seconds,
		"reload_game_ms":reload_game_ms,"reload_frames":reload_frames,
		"mag_after":game.weapon.mag,"reserve_after":game.weapon.reserve,
		"note":"Fixed-step recording duration is not a performance measurement."}
	var file := FileAccess.open(folder.path_join("demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))

func hold_demo() -> void:
	var report: Array = []
	for id: String in ["deagle","ak47","m4a1"]:
		equip("training_hall",id)
		await frames(30)
		click(true)
		await get_tree().create_timer(1.2).timeout
		click(false)
		var fired: int = game.shots
		await frames(25)
		await capture(id+"-hold")
		game.weapon.start_reload()
		click(true)
		while game.weapon.is_reloading(): await frames(1)
		await frames(30)
		var blocked: bool = game.shots==fired
		click(false)
		click(true)
		await get_tree().create_timer(0.45).timeout
		click(false)
		report.append({"weapon":id,"held_1_2s_shots":fired,"press_during_reload_blocked":blocked,
			"fresh_press_shots":game.shots-fired})
		await frames(30)
	var file := FileAccess.open(folder.path_join("hold-demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))

func benchmark() -> void:
	var reports: Array = []
	for map_id: String in ["training_hall","old_town"]:
		equip(map_id,"m4a1")
		await frames(240)
		var samples: Array[float] = []
		var start := Time.get_ticks_usec()
		var previous := start
		var last_cycle := -1
		var last_pulse := -1
		while Time.get_ticks_usec()-start < 30000000:
			await frames(1)
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0)
			previous = now
			var elapsed := float(now-start)/1000000.0
			var right := int(elapsed/0.7)%2==0
			Input.action_release("move_left" if right else "move_right")
			Input.action_press("move_right" if right else "move_left")
			# One eight-second cycle: ~7 real rounds, release, reload, fresh press.
			# Uses the normal ammo pool; no replenishment or modified game clock.
			var cycle := int(elapsed/8.0)
			if cycle != last_cycle:
				click(false)
				click(true)
				last_cycle = cycle
			if fmod(elapsed,8.0)>0.65 and last_pulse!=cycle:
				click(false)
				game.weapon.start_reload()
				last_pulse = cycle
		Input.action_release("move_left")
		Input.action_release("move_right")
		click(false)
		var total := 0.0
		for v: float in samples: total+=v
		samples.sort()
		var report := {"map":map_id,"seconds":total/1000.0,"frames":samples.size(),
			"mean_fps":1000.0*samples.size()/total,"p95_ms":samples[int(samples.size()*0.95)],
			"p99_ms":samples[int(samples.size()*0.99)],"worst_ms":samples[-1],
			"shots":game.shots,"reloads":game.weapon.reload_serial,
			"gpu":RenderingServer.get_video_adapter_name(),
			"resolution":[get_viewport().get_texture().get_width(),get_viewport().get_texture().get_height()]}
		reports.append(report)
		print("VIEWMODEL PERFORMANCE ",JSON.stringify(report))
		await capture(map_id+"-benchmark")
	var file := FileAccess.open(folder.path_join("performance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"))
