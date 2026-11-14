extends Node
## Opt-in reproducible in-game capture/benchmark, also available in the export.
var game: Node3D
var destination := ""

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func capture(label_text: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(destination.path_join(label_text + ".png"))

func equip(id: String) -> void:
	game.start_round()
	game.confirm_purchase(id)
	game.begin_training()
	game.ui.toast.visible = false

func run(controller: Node3D) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = controller
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			destination = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(destination)
	if "--benchmark" in OS.get_cmdline_user_args():
		await benchmark()
	else:
		await showcase()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().quit()

func showcase() -> void:
	for id: String in ["deagle", "ak47", "m4a1"]:
		equip(id)
		game.ui.notify("%s · 双手续弹演示" % game.weapon.get_data().name, 8.0)
		await frames(60)
		await capture(id + "-game")
		game.weapon.mag -= 1
		game.weapon.start_reload()
		if id == "ak47":
			Input.action_press("move_right")
			await frames(25)
			Input.action_release("move_right")
		if id == "m4a1":
			await frames(80)
			game.pause_game()
			await frames(45)
			game.resume_game()
		while game.weapon.is_reloading():
			await frames(1)
		await frames(40)
	# A close in-game target view and its actual headshot/fall/respawn.
	game.player.reset_position(Vector3(0, 0.02, -3.5))
	game.player.weapon_root.visible = false
	var target = game.arena.targets[1]
	game.player.camera.look_at(target.global_position + Vector3(0,1.05,0))
	game.ui.notify("训练服识别色 · 非头部命中无伤害", 3.0)
	await frames(35)
	await capture("trainee-standing")
	game.player.camera.look_at(target.get_node("Head").global_position)
	game.pending_shots = 1
	await frames(35)
	game.player.camera.look_at(target.global_position + Vector3(0,0.7,0))
	await capture("trainee-fall")
	await frames(70)

func benchmark() -> void:
	var reports: Array = []
	for resolution in [Vector2i(1280,720),Vector2i(960,540)]:
		DisplayServer.window_set_size(resolution)
		equip("ak47")
		await frames(240)
		game.resume_game()
		var samples: Array[float] = []
		var start := Time.get_ticks_usec()
		var previous := start
		var last_reload := 0.0
		while Time.get_ticks_usec() - start < 20000000:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0)
			previous = now
			var elapsed := float(now-start)/1000000.0
			game.player.camera.rotation.y = sin(elapsed*0.25)*0.25
			if get_tree().paused:game.resume_game()
			if elapsed-last_reload>3.5:
				game.weapon.mag -= 1
				game.weapon.start_reload()
				last_reload = elapsed
		var total_ms := 0.0
		for value in samples:total_ms += value
		samples.sort()
		var report := {"resolution":str(resolution),"frames":samples.size(),"seconds":total_ms/1000.0,
			"mean_fps":1000.0*samples.size()/total_ms,"p95_ms":samples[int(samples.size()*0.95)],
			"p99_ms":samples[int(samples.size()*0.99)],"worst_ms":samples[-1],
			"gpu":RenderingServer.get_video_adapter_name(),"renderer":"Forward+ / D3D12"}
		reports.append(report)
		print("BENCHMARK ",JSON.stringify(report))
		await capture("benchmark-%dx%d" % [resolution.x,resolution.y])
	var file := FileAccess.open(destination.path_join("performance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"))
