extends Node
const Layout=preload("res://scripts/yard_layout.gd")
const Duel=preload("res://scripts/assessment_duel.gd")
var game: Node3D
var checks:=0
var failures:=0
var folder:=""

func check(value: bool,label_text: String) -> void:
	checks+=1
	if not value:
		failures+=1
		printerr("ASSESSMENT FAIL: "+label_text)

func frames(count:=2) -> void:
	for i in count: await get_tree().physics_frame
	await get_tree().process_frame

func equip(id:="ak47") -> void:
	game.show_setup()
	game.ui._select("assessment_yard",id)
	game.start_round()

func capture(label_text: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(label_text+".png"))

func run(controller: Node3D) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	game=controller
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): folder=arg.trim_prefix("--capture-dir=")
	if folder.is_empty(): folder="user://assessment"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(3)
	if "--assessment-demo" in OS.get_cmdline_user_args():
		# Avoid unrelated desktop input changing a scripted recording.
		game.set_process_input(false)
		game.set_process_unhandled_input(false)
		await demo()
	elif "--assessment-benchmark" in OS.get_cmdline_user_args(): await benchmark()
	else: await tests()
	game.show_menu()
	var file:=FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("ASSESSMENT PASS: %d checks (%d failures)" %[checks,failures])
	get_tree().quit(1 if failures else 0)

func tests() -> void:
	var previous:=""
	for seed_number in 1000:
		var layout=Layout.new()
		layout.generate(seed_number)
		check(layout.valid(),"connected seed %d"%seed_number)
		check(layout.road_signature!=previous,"different corners seed %d"%seed_number)
		previous=layout.road_signature
		var other=Layout.new()
		other.generate(seed_number)
		check(layout.cells==other.cells and layout.road_signature==other.road_signature,"reproducible seed %d"%seed_number)
		for lane in layout.lanes:
			for p in lane:
				for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]: check(layout.height_at(p+offset)==0,"4m reserved lane")
	check(Duel.outcome(true,false,0,0).begins_with("获胜"),"final bullet win precedes empty/timeout")
	check(Duel.outcome(false,false,0,0).begins_with("平局"),"simultaneous death")
	check(Duel.outcome(false,true,10,10).begins_with("失败"),"player death")
	check(Duel.outcome(true,true,0,10).contains("弹药耗尽"),"ammo ending")
	check(Duel.outcome(true,true,1,0).begins_with("未分胜负"),"timeout")
	for i in 10:
		equip()
		game.set_physics_process(false)
		await frames()
		var layout=game.arena.map_root.layout
		var capsule:=CharacterBody3D.new()
		capsule.collision_layer=4
		capsule.collision_mask=1
		var shape:=CollisionShape3D.new()
		var geometry:=CapsuleShape3D.new()
		geometry.radius=0.3
		geometry.height=1.8
		shape.shape=geometry
		shape.position.y=0.9
		capsule.add_child(shape)
		game.add_child(capsule)
		await frames()
		var paths: Array=layout.lanes.duplicate()
		paths.append_array(layout.links)
		for points in paths:
			for j in range(1,points.size()):
				var params:=PhysicsTestMotionParameters3D.new()
				params.from=Transform3D(Basis.IDENTITY,layout.world(points[j-1])+Vector3(0,0.02,0))
				params.motion=layout.world(points[j])-layout.world(points[j-1])
				var result:=PhysicsTestMotionResult3D.new()
				check(not PhysicsServer3D.body_test_motion(capsule.get_rid(),params,result),"capsule route sweep %d"%i)
		capsule.free()
		await overview("layout-%02d"%i)
	for weapon_id in ["deagle","ak47","m4a1"]:
		equip(weapon_id)
		game.set_physics_process(false)
		await frames()
		var spawn: Vector3=game.duel.bot.position
		check(game.duel.bot.shot_count==0 and game.duel.bot.position==spawn,"countdown holds bot")
		game.begin_training()
		game.duel.bot.position=Vector3(0,0.02,31)
		game.player.reset_position(Vector3(0,0.02,35))
		game.duel.bot.pose(0)
		game.duel.bot.target.active=true
		game.duel.bot.active=true
		await frames()
		var body_hit: Dictionary=game.duel.bot.target.apply_hit(false)
		check(body_hit.hit and not body_hit.killed,"body causes no damage")
		check(game.duel.bot.can_see(game.player.global_position+Vector3(0,1.65,0)),"visible player")
		var obstruction:=StaticBody3D.new()
		obstruction.collision_layer=1
		var block:=CollisionShape3D.new()
		var box:=BoxShape3D.new()
		box.size=Vector3(4,3,0.4)
		block.shape=box
		obstruction.add_child(block)
		obstruction.position=Vector3(0,1.5,33)
		game.add_child(obstruction)
		await frames()
		check(not game.duel.bot.can_see(game.player.global_position+Vector3(0,1.65,0)),"wall blocks bot vision")
		game.duel.bot.aim_direction=Vector3.BACK
		game.duel.bot.aim_offset=Vector2.ZERO
		game.duel.bot._fire()
		game.duel.resolve()
		check(game.duel.player_alive,"wall blocks bot bullet")
		obstruction.free()
		await frames()
		game.duel.bot.aim_direction=Vector3.BACK
		var before_reaction: int=game.duel.bot.shot_count
		for k in 40: game.duel.bot.step(1.0/120)
		check(game.duel.bot.shot_count==before_reaction,"reaction delay")
		for k in 140: game.duel.bot.step(1.0/120)
		check(game.duel.bot.shot_count>0,"bot really fires")
		var before: float=game.duel.bot.clock
		game.pause_game()
		await frames(8)
		check(game.duel.bot.clock==before,"pause freezes bot")
		game.resume_game()
		game.duel.bot.shot_pending=false
		game.player.camera.look_at(game.duel.bot.target._regions[0].area.global_position)
		await capture(weapon_id+"-opponent")
		game.weapon.mag=1
		game.weapon.reserve=0
		check(game.weapon.try_fire().is_empty(),"final shot accepted")
		game.duel.resolve()
		check(game.phase=="results" and game.kills==1 and game.shots==1,"real final headshot victory "+weapon_id)
		await capture(weapon_id+"-result")
	# Actual enemy ray into the player body and head; only the head ends play.
	equip()
	game.set_physics_process(false)
	game.begin_training()
	game.duel.bot.position=Vector3(0,0.02,31)
	game.player.reset_position(Vector3(0,0.02,35))
	game.duel.bot.pose(0)
	await frames()
	var origin: Vector3=game.duel.bot.gun.global_transform*Vector3(0,0.1975,-0.8215)
	game.duel.bot.aim_offset=Vector2.ZERO
	game.duel.bot.aim_direction=(game.player.position+Vector3(0,1.0,0)-origin).normalized()
	game.duel.bot._fire()
	game.duel.resolve()
	check(game.duel.player_alive and game.shots==0,"enemy body hit no damage or player stats")
	game.duel.bot.aim_direction=(game.player.position+Vector3(0,1.65,0)-origin).normalized()
	game.duel.bot._fire()
	game.duel.resolve()
	check(not game.duel.player_alive and game.phase=="results","real enemy headshot defeat")
	await capture("defeat")
	game.set_physics_process(true)
	game.show_setup()
	game.ui._select("old_town","ak47")
	game.start_round()
	check(not is_instance_valid(game.duel) and game.arena.targets.size()==6,"old map restored")
	check(game.player.collision_mask==1,"player collision restored")
	game.show_setup()
	await capture("setup")

func overview(label_text: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var camera:=Camera3D.new()
	game.add_child(camera)
	camera.position=Vector3(43,64,52)
	camera.look_at(Vector3.ZERO)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=95
	camera.current=true
	game.player.weapon_root.hide()
	game.ui.hud.hide()
	game.ui.overlay.hide()
	await frames()
	await capture(label_text)
	camera.free()
	game.player.camera.current=true

func demo() -> void:
	var reports: Array=[]
	for i in 3:
		game.arena.layout_rng.seed=72042+i
		equip("ak47")
		game.set_physics_process(false)
		await frames(4)
		await overview("random-%d"%i)
		game.player.weapon_root.show()
		game.ui.show_countdown(3)
		game.set_physics_process(true)
		while game.phase=="countdown": await frames(1)
		await capture("play-%d"%i)
		# Scripted recording driver uses real WASD, collision and fire rules.
		# Brake at grid corners instead of overshooting and skipping waypoints.
		# Meet the bot along its chosen lane so the three recordings do not
		# pass one another on separate roads. This helper is not game AI.
		var points:=PackedVector3Array()
		var patrol: PackedVector3Array=game.duel.bot.patrol.duplicate()
		patrol.reverse()
		var cursor: Vector3=game.player.position
		for goal in patrol:
			var section: PackedVector3Array=game.arena.map_root.layout.path(cursor,goal)
			points.append_array(section)
			cursor=goal
		var reached:=0
		var encountered:=false
		for p in points:
			if game.phase!="training" or encountered: break
			var guard:=0
			while game.phase=="training" and guard<480:
				if game.duel.bot.visible_player:
					encountered=true
					break
				var offset: Vector3=p-game.player.position
				offset.y=0
				var speed:=Vector2(game.player.velocity.x,game.player.velocity.z).length()
				if offset.length()<0.3 and speed<0.2: break
				game.player.rotation.y=atan2(-offset.x,-offset.z)
				if offset.length()>speed*speed/24.0+0.15:
					Input.action_press("move_forward")
				else: Input.action_release("move_forward")
				await frames(1)
				guard+=1
			Input.action_release("move_forward")
			if not encountered and game.phase=="training":
				check(guard<480,"demo route progress %d"%i)
				if guard>=480: break
				reached+=1
		if encountered and game.phase=="training":
			# Recording-only aiming uses the actor pose, not the vision SDK.
			game.player.camera.look_at(game.duel.bot.position+Vector3(0,1.1,0))
			game.set_primary_pressed(true)
			await capture("encounter-%d"%i)
			await get_tree().create_timer(0.7).timeout
			game.set_primary_pressed(false)
			if game.phase=="training":
				game.player.camera.look_at(game.duel.bot.target._regions[0].area.global_position)
				game.set_primary_pressed(true)
				await get_tree().create_timer(1.0).timeout
				game.set_primary_pressed(false)
			await get_tree().create_timer(1.0).timeout
		check(encountered and game.shots>0 and game.duel.bot.shot_count>0,"demo real exchange %d"%i)
		reports.append({"seed":game.arena.map_root.generation_seed,"reached_waypoints":reached,"encountered":encountered,"player_shots":game.shots,"bot_shots":game.duel.bot.shot_count,"phase":game.phase})
		await capture("result-%d"%i)
		await get_tree().create_timer(1.0).timeout
		if game.phase=="training": game.finish_round("演示结束")
	var file:=FileAccess.open(folder.path_join("demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"))

func benchmark() -> void:
	var reports: Array=[]
	for i in 3:
		game.arena.layout_rng.seed=72042+i
		equip("ak47")
		game.begin_training()
		# Dedicated performance fixture keeps the combat active after a hit.
		game.set_physics_process(false)
		game.player.active=false
		# Begin with an encounter, then continue along the real route. Damage is
		# not resolved in this performance fixture, so every sample lasts 30 s.
		game.duel.bot.position=Vector3(2,0.02,31)
		await frames(240)
		var bot=game.duel.bot
		var path: PackedVector3Array=game.arena.map_root.layout.path(game.player.position,game.arena.map_root.bot_spawn)
		var start:=Time.get_ticks_usec()
		var previous:=start
		var samples: Array[float]=[]
		var index:=0
		var bot_cpu_us:=0
		while Time.get_ticks_usec()-start<30000000:
			await get_tree().process_frame
			var now:=Time.get_ticks_usec()
			var delta: float=(now-previous)/1000000.0
			samples.append(delta*1000)
			previous=now
			var bot_start:=Time.get_ticks_usec()
			game.duel.step(delta)
			bot_cpu_us+=Time.get_ticks_usec()-bot_start
			game.duel.bot.shot_pending=false
			if path.size()>0:
				var goal:=path[index]
				var offset: Vector3=goal-game.player.position
				offset.y=0
				game.player.velocity=offset.normalized()*3
				game.player.move_and_slide()
				if offset.length()<0.4:
					index+=1
					if index>=path.size():
						path.reverse()
						index=0
			if game.weapon.fire_error().is_empty(): game.weapon.try_fire()
			game.player.update_reload(game.weapon.reload_left_ms,2500,game.weapon.reload_kind,game.weapon.reload_serial)
			game.weapon.reserve=50
			game.player.rotation.y=atan2(-(bot.position.x-game.player.position.x),-(bot.position.z-game.player.position.z))
			# Shoot above the bot to retain the same live encounter for 30 seconds.
			game.player.camera.rotation.x=0.2
		var seconds:=float(Time.get_ticks_usec()-start)/1000000.0
		samples.sort()
		reports.append({"seed":game.arena.map_root.generation_seed,"generation_ms":game.arena.map_root.generation_ms,"seconds":seconds,"mean_fps":samples.size()/seconds,"p95_ms":samples[int(samples.size()*0.95)],"p99_ms":samples[int(samples.size()*0.99)],"worst_ms":samples[-1],"bot_shots":bot.shot_count,"player_shots":game.shots,"gpu":RenderingServer.get_video_adapter_name()})
		await capture("benchmark-%d"%i)
		reports[-1]["bot_cpu_ms_per_frame"]=bot_cpu_us/1000.0/samples.size()
		game.set_physics_process(true)
	var file:=FileAccess.open(folder.path_join("performance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"))
