extends Node
## Opt-in reproducible captures and independent real-time benchmarks.
var game: Node3D
var destination := ""
var waypoint := 1

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func capture(label_text: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(destination.path_join(label_text+".png"))

func equip(map_id: String, id: String) -> void:
	game.show_setup()
	game.ui._select(map_id,id)
	game.start_round()
	game.begin_training()
	waypoint = 1

func run(controller: Node3D) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = controller
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): destination = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(destination)
	if "--previews" in OS.get_cmdline_user_args(): await previews()
	elif "--benchmark" in OS.get_cmdline_user_args(): await benchmark()
	else: await showcase()
	Input.action_release("move_forward")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.shot_sound.stop()
	game.hit_sound.stop()
	await frames(8)
	get_tree().quit()

func previews() -> void:
	for map_id: String in ["old_town","training_hall"]:
		equip(map_id,"deagle")
		game.arena.set_active(false)
		game.player.active = false
		game.ui.root.hide()
		game.player.weapon_root.hide()
		if map_id == "old_town":
			game.player.reset_position(Vector3(-14,0.6,16))
			game.player.camera.look_at(Vector3(-13,2,-4))
		await frames(30)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.resize(768,432,Image.INTERPOLATE_LANCZOS)
		image.save_png(destination.path_join(map_id+".png"))
	for id: String in ["deagle","ak47","m4a1"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(768,300)
		viewport.own_world_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var model: Node3D = load("res://assets/models/%s.glb" % id).instantiate()
		viewport.add_child(model)
		var meshes := model.find_children("*","MeshInstance3D",true,false)
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in meshes:
			if "Arm" in str(mesh.name):
				mesh.hide()
				continue
			var transformed: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = transformed if first else bounds.merge(transformed)
			first = false
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(bounds.size.z*0.40,0.23)
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.position = bounds.get_center()+Vector3(2,0.65,0.9)
		camera.look_at(bounds.get_center())
		camera.current = true
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.75
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color("f0ede4")
		sky_material.sky_horizon_color = Color("c4c9d2")
		sky_material.ground_bottom_color = Color("777e87")
		sky_material.ground_horizon_color = Color("c4c9d2")
		sky.sky_material = sky_material
		environment.environment.sky = sky
		environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		viewport.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-40,-40,0)
		light.light_energy = 1.4
		viewport.add_child(light)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(15,130,0)
		fill.light_energy = 0.6
		viewport.add_child(fill)
		await frames(12)
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(destination.path_join(id+".png"))
		remove_child(viewport)
		viewport.queue_free()
	print("PREVIEWS COMPLETE")

func walk_step() -> void:
	var route: Array = game.arena.map_root.route
	var destination_point: Vector3 = route[waypoint]
	var delta: Vector3 = destination_point-game.player.position
	delta.y = 0
	if delta.length()<0.8:
		waypoint = (waypoint+1)%route.size()
		return
	game.player.rotation.y = atan2(-delta.x,-delta.z)
	Input.action_press("move_forward")

func showcase() -> void:
	game.show_menu()
	await frames(40)
	await capture("01-menu")
	game.ui.show_help()
	await frames(20)
	await capture("02-help")
	game.ui.close_help()
	game.show_setup()
	game.ui._select("old_town","ak47")
	await frames(35)
	await capture("03-setup")
	game.start_round()
	await frames(30)
	await capture("04-countdown")
	while game.phase == "countdown": await frames(1)
	await frames(30)
	await capture("05-old-town")
	var route: Array = game.arena.map_root.route
	for i in range(1,route.size()):
		while waypoint == i and game.phase == "training":
			walk_step()
			await frames(1)
		Input.action_release("move_forward")
		await frames(20)
		await capture("town-route-"+str(i))
	Input.action_release("move_forward")
	for id: String in ["deagle","ak47","m4a1"]:
		equip("old_town",id)
		await frames(30)
		await capture("town-"+id)
		var target: Node3D = game.arena.targets[0]
		game.player.camera.look_at(target.get_node("Head").global_position)
		game.pending_shots = 1
		await frames(35)
		game.weapon.start_reload()
		while game.weapon.is_reloading(): await frames(1)
	game.pause_game()
	await frames(25)
	await capture("06-pause")
	game.ui.show_help()
	await frames(25)
	await capture("07-pause-help")
	game.ui.close_help()
	game.resume_game()
	game.finish_round("时间到")
	await frames(30)
	await capture("08-results")
	equip("training_hall","m4a1")
	await frames(45)
	await capture("09-training-hall")

func benchmark() -> void:
	var reports: Array = []
	for map_id: String in ["old_town","training_hall"]:
		for resolution in [Vector2i(1280,720),Vector2i(960,540)]:
			DisplayServer.window_set_size(resolution)
			equip(map_id,"ak47")
			await frames(240)
			var samples: Array[float] = []
			var start := Time.get_ticks_usec()
			var previous := start
			var last_reload := 0.0
			while Time.get_ticks_usec()-start<30000000:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				samples.append(float(now-previous)/1000.0)
				previous = now
				var elapsed := float(now-start)/1000000.0
				walk_step()
				if elapsed-last_reload>3.5:
					game.weapon.mag -= 1
					game.weapon.start_reload()
					last_reload = elapsed
			Input.action_release("move_forward")
			var total_ms := 0.0
			for value in samples: total_ms += value
			samples.sort()
			var report := {"map":map_id,"resolution":str(resolution),"frames":samples.size(),"seconds":total_ms/1000.0,
				"mean_fps":1000.0*samples.size()/total_ms,"p95_ms":samples[int(samples.size()*0.95)],
				"p99_ms":samples[int(samples.size()*0.99)],"worst_ms":samples[-1],
				"gpu":RenderingServer.get_video_adapter_name(),"renderer":"Forward+ / D3D12"}
			reports.append(report)
			print("BENCHMARK ",JSON.stringify(report))
			await capture("benchmark-%s-%dx%d" % [map_id,resolution.x,resolution.y])
	var file := FileAccess.open(destination.path_join("performance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"))
