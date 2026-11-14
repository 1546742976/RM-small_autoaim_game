extends Node
const Layout=preload("res://scripts/yard_layout.gd")
const Direction=preload("res://scripts/shot_direction.gd")
var game: Node3D
var checks:=0
var failures:=0
var folder:=""
var impacts: Array=[]

func check(value: bool,label_text: String) -> void:
	checks+=1
	if not value:
		failures+=1
		printerr("PROJECTILE FAIL: "+label_text)

func frames(count:=2) -> void:
	for i in count: await get_tree().physics_frame
	await get_tree().process_frame

func capture(label_text: String) -> void:
	if DisplayServer.get_name()=="headless": return
	if game.ui.transition and game.ui.transition.is_running(): await game.ui.transition.finished
	await RenderingServer.frame_post_draw
	get_window().get_texture().get_image().save_png(folder.path_join(label_text+".png"))

func prepare(map_id:="training_hall",weapon_id:="ak47") -> void:
	game.show_setup()
	game.ui._select(map_id,weapon_id)
	game.start_round()
	if map_id=="assessment_yard":
		var guard:=0
		while not game.arena.map_root.navigation_ready and guard<1200:
			await frames(1)
			guard+=1
		check(game.arena.map_root.navigation_ready,"navigation completed")
	game.begin_training()
	game.player.set_physics_process(true)
	await frames(12)
	game.player.set_physics_process(false)
	for target in game.arena.targets: target.set_physics_process(false)
	impacts.clear()

func fly(seconds:=4.1) -> void:
	for i in ceili(seconds*120):
		if game.phase!="training": break
		game.projectiles.advance(1.0/120)
		if is_instance_valid(game.duel): game.duel.resolve()
		elif game.settling and game.projectiles.live_count()==0: game.finish_round(game.settlement_reason)

func run(controller: Node3D) -> void:
	if "--fast-checks" in OS.get_cmdline_user_args():
		Engine.physics_ticks_per_second=960
		Engine.time_scale=8
	process_mode=Node.PROCESS_MODE_ALWAYS
	game=controller
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.set_physics_process(false)
	game.weapon.set_physics_process(false)
	game.projectiles.impacted.connect(func(_origin,_direction,hit,owner_id): impacts.append({"hit":hit,"owner":owner_id}))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): folder=arg.trim_prefix("--capture-dir=")
	if folder.is_empty(): folder="user://projectile-checks"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(3)
	if "--projectile-demo" in OS.get_cmdline_user_args() or "--assessment-demo" in OS.get_cmdline_user_args(): await demo()
	elif "--projectile-benchmark" in OS.get_cmdline_user_args() or "--assessment-benchmark" in OS.get_cmdline_user_args(): await benchmark()
	else:
		await projectiles_test()
		await movement_test()
		await yard_test()
	game.show_menu()
	var report:=FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("PROJECTILE PASS: %d checks (%d failures)"%[checks,failures])
	get_tree().quit(1 if failures else 0)

func projectiles_test() -> void:
	await prepare()
	for axis in [Vector3(0,0,-1),Vector3(0,0.5,-1),Vector3(0,-0.5,-1)]:
		var direction: Vector3=axis.normalized()
		var straight: Dictionary=game.projectiles.spawn(Vector3(0,50,0),direction,"player")
		game.projectiles.advance(0.4)
		check(straight.area.global_position.distance_to(Vector3(0,50,0)+direction*10)<0.001,"no drop at horizontal/up/down elevation")
		game.projectiles.clear()
	var camera: Camera3D=game.player.camera
	var tracer: Dictionary=game.projectiles.spawn(camera.global_position+Vector3(0,0,0.5),Vector3.BACK,"bot")
	tracer.distance=0.75
	game.projectiles._update_trail(tracer)
	check(not tracer.trail.visible,"trail crossing eye is hidden even when tip is farther than 40cm")
	tracer.area.position.x+=1
	game.projectiles._update_trail(tracer)
	check(tracer.trail.visible,"distant short trail remains visible")
	game.projectiles.clear()
	var bullet: Dictionary=game.projectiles.spawn(Vector3(0,3,8),Vector3.UP,"player")
	fly(0.4)
	check(bullet.area.position.is_equal_approx(Vector3(0,13,8)),"10m flight takes 0.4s without gravity")
	check(game.hits==0 and bullet.live,"no instantaneous damage")
	game.pause_game()
	var frozen: Vector3=bullet.area.position
	await frames(8)
	game._physics_process(0.1)
	check(bullet.area.position==frozen,"paused projectile frozen")
	game.resume_game()
	fly()
	check(game.projectiles.live_count()==0,"100m lifetime ends")
	for map_id in ["training_hall","old_town"]:
		for weapon_id in ["deagle","ak47","m4a1"]:
			await prepare(map_id,weapon_id)
			var target=game.arena.targets[0]
			game.player.reset_position(game.arena.map_root.test_views[0])
			game.player.set_physics_process(true)
			await frames(12)
			game.player.set_physics_process(false)
			game.player.camera.look_at(target.get_node("Body").global_position)
			check(game.weapon.try_fire().is_empty(),"body launch "+weapon_id)
			check(game.shots==1 and game.hits==0,"spawn increments shots only")
			fly()
			check(game.hits==1 and target.hp==100 and target.alive,"body stops projectile without damage "+map_id+weapon_id)
			game.weapon.advance_ms(4000)
			game.weapon.mag=1
			game.weapon.reserve=0
			game.player.camera.look_at(target.get_node("Head").global_position)
			check(game.weapon.try_fire().is_empty(),"last shot launch")
			check(game.phase=="training" and game.settling and game.kills==0,"last shot waits in flight")
			fly()
			check(game.phase=="results" and game.kills==1 and game.hits==2,"last projectile credited before results "+map_id+weapon_id)
	await prepare()
	var head: Vector3=game.arena.targets[0].get_node("Head").global_position
	game.projectiles.spawn(head+Vector3(0.11,0,2),Vector3.FORWARD,"player")
	fly(0.2)
	check(game.kills==1,"sphere grazing head contact")
	game.arena.targets[0].reset_target()
	await frames()
	var wall:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(2,2,0.002)
	shape.shape=box
	wall.add_child(shape)
	game.add_child(wall)
	wall.position=head+Vector3(0,0,1)
	await frames()
	game.projectiles.spawn(head+Vector3(0,0,2),Vector3.FORWARD,"player")
	game.projectiles.advance(0.16)
	check(game.arena.targets[0].alive and impacts[-1].hit.get("collider")==wall,"sweep stops at 2mm wall before head")
	wall.free()
	game.arena.targets[0].reset_target()
	await frames()
	game.projectiles.spawn(head,Vector3.FORWARD,"player")
	fly(0.02)
	check(not game.arena.targets[0].alive,"initial overlap resolves once")
	await prepare()
	var moving_target=game.arena.targets[3]
	moving_target.set_physics_process(true)
	await frames(6)
	var initial_head: Vector3=moving_target.get_node("Head").global_position
	game.projectiles.spawn(initial_head+Vector3(0,0,0.5),Vector3.FORWARD,"player")
	for i in 6:
		await get_tree().physics_frame
		game.projectiles.advance(1.0/120)
	check(not moving_target.alive,"projectile contacts moving bone-following head")
	moving_target.set_physics_process(false)
	await prepare()
	game.player.camera.look_at(game.arena.targets[0].get_node("Head").global_position)
	game.weapon.try_fire()
	game.remaining=0.01
	game._physics_process(0.02)
	check(game.settling and game.phase=="training" and game.weapon.fire_error()=="not_training","timed map waits for emitted projectile")
	fly()
	check(game.phase=="results" and game.kills==1,"timed map credits post-deadline impact")
	await prepare()
	# Actual precision policy: horizontal threshold plus airborne state.
	for speed in [0.339,0.34,0.341,1.0]:
		for grounded in [true,false]:
			var rng:=RandomNumberGenerator.new()
			rng.seed=106
			var before:=rng.state
			var direction:=Direction.sample(Basis.IDENTITY,speed,rng,grounded)
			var precise: bool=speed<0.34 and grounded
			check(direction.is_equal_approx(Vector3.FORWARD)==precise,"ground/air precision boundary")
			check((rng.state==before)==precise,"only scattered successful shots consume randomness")
	game.projectiles.spawn(Vector3.ZERO,Vector3.UP,"player")
	game.show_menu()
	check(game.projectiles.bullets.is_empty(),"menu clears previous projectiles")

func movement_test() -> void:
	await prepare()
	game.player.set_physics_process(true)
	Input.action_press("jump")
	var highest:=0.0
	for i in 150:
		await get_tree().physics_frame
		highest=maxf(highest,game.player.position.y)
		if i==20:
			var rng_state: int=game.shot_rng.state
			check(not game.player.is_on_floor() and game.weapon.try_fire().is_empty(),"airborne launch permitted")
			game._update_hud()
			check(game.shot_rng.state!=rng_state and not game.ui.crosshair.accurate,"actual airborne launch uses spread")
	Input.action_release("jump")
	check(highest>0.90 and highest<1.04,"jump peaks near one metre")
	check(game.player.is_on_floor(),"held jump does not bounce after landing")
	var ceiling:=StaticBody3D.new()
	var ceiling_shape:=CollisionShape3D.new()
	var ceiling_box:=BoxShape3D.new()
	ceiling_box.size=Vector3(3,0.2,3)
	ceiling_shape.shape=ceiling_box
	ceiling.add_child(ceiling_shape)
	game.add_child(ceiling)
	ceiling.position=game.player.position+Vector3(0,2.1,0)
	await frames(3)
	Input.action_press("jump")
	highest=0
	for i in 100:
		await get_tree().physics_frame
		highest=maxf(highest,game.player.position.y)
	Input.action_release("jump")
	check(highest<0.23 and game.player.is_on_floor(),"head ceiling stops upward motion")
	ceiling.free()
	var target=game.arena.targets[1]
	game.player.reset_position(target.position+Vector3(0,0.02,2))
	Input.action_press("move_forward")
	await frames(100)
	Input.action_release("move_forward")
	check(game.player.position.z>target.position.z+0.55,"solid training character blocks walking")
	await capture("solid-character")
	game.player.set_physics_process(false)

func yard_test() -> void:
	for weapon_id in ["deagle","ak47","m4a1"]:
		await prepare("assessment_yard",weapon_id)
		var bot=game.duel.bot
		bot.target.active=true
		bot.position=Vector3(0,0.02,31)
		bot.pose(0)
		game.player.reset_position(Vector3(0,0.02,35))
		game.player.set_physics_process(true)
		await frames(12)
		game.player.set_physics_process(false)
		game.player.camera.look_at(bot.target.get_node("Body").global_position)
		check(game.weapon.try_fire().is_empty(),"yard body launch "+weapon_id)
		fly(0.3)
		check(game.hits==1 and bot.target.alive,"yard body blocks with zero damage "+weapon_id)
		game.weapon.advance_ms(4000)
		game.weapon.mag=1
		game.weapon.reserve=0
		game.player.camera.look_at(bot.target.get_node("Head").global_position)
		check(game.weapon.try_fire().is_empty() and game.settling,"yard final shot enters settlement "+weapon_id)
		fly(0.5)
		check(game.phase=="results" and game.kills==1,"yard last headshot wins before ammo loss "+weapon_id)
	var previous:=""
	for seed_value in 1000:
		var layout=Layout.new()
		layout.generate(seed_value)
		check(layout.valid(),"connected layout %d"%seed_value)
		check(layout.road_signature!=previous,"varied corners and platforms")
		previous=layout.road_signature
		for lane in layout.lanes:
			for i in range(1,lane.size()):
				var a: Vector2i=lane[i-1]
				var b: Vector2i=lane[i]
				for z in range(mini(a.y,b.y),maxi(a.y,b.y)+2):
					for x in range(mini(a.x,b.x),maxi(a.x,b.x)+2): check(layout.height_at(Vector2i(x,z))==0,"four-metre road retained")
	for i in 10:
		game.arena.layout_rng.seed=72042+i
		await prepare("assessment_yard")
		var map=game.arena.map_root
		for platform in map.layout.platforms:
			var top: Vector3=map.layout.platform_center(platform)
			for end in [-1,1]:
				var foot: Vector3=top+Vector3(0,-2,end*7.5)
				var path: PackedVector3Array=map.navigation_path(foot,top)
				check(path.size()>1 and path[-1].distance_to(top)<0.5,"both stair entrances reach top")
		# Both actual character controllers traverse a generated platform.
		var top: Vector3=map.layout.platform_center(map.layout.platforms[i%3])
		var entry:=top+Vector3(0,-2,-7.5)
		var exit_point:=top+Vector3(0,-2,7.5)
		game.duel.bot.position=Vector3(0,-20,0)
		game.player.reset_position(entry)
		game.player.set_physics_process(true)
		await frames(8)
		await walk_player(map.navigation_path(entry,top),"player up %d"%i)
		check(absf(game.player.position.y-2.0)<0.15,"player stands on high platform")
		await walk_player(map.navigation_path(top,exit_point),"player down %d"%i)
		check(absf(game.player.position.y)<0.15,"player returns to ground")
		game.player.set_physics_process(false)
		game.player.position=Vector3(0,-20,0)
		var opponent=game.duel.bot
		opponent.position=entry
		opponent.velocity=Vector3.ZERO
		opponent.active=true
		await walk_bot(top,"bot up %d"%i)
		check(absf(opponent.position.y-2.0)<0.15,"bot stands on high platform")
		await walk_bot(exit_point,"bot down %d"%i)
		check(absf(opponent.position.y)<0.15,"bot returns to ground")
		print("VERTICAL ROUTE ",i," complete")
		await overview("layout-%02d"%i)
	await prepare("assessment_yard")
	game._physics_process(181)
	check(game.phase=="training" and game.remaining==-1 and game.elapsed>=181,"assessment has no deadline")
	check(not game.ui.clock_label.visible,"assessment timer hidden")
	await prepare("assessment_yard")
	var bot=game.duel.bot
	bot.position=Vector3(-8,0.02,33.5)
	bot.rotation.y=-PI/2
	game.player.reset_position(Vector3(8,0.02,33.5))
	bot.pose(0)
	await frames()
	bot.active=true
	bot.aim_direction=Vector3.RIGHT
	for k in 2:
		await get_tree().physics_frame
		bot.step(1.0/120)
	check(bot.shot_count==0,"bot retains reaction delay")
	for k in 80:
		await get_tree().physics_frame
		bot.step(1.0/120)
	check(bot.shot_count>0 and game.projectiles.live_count()>0,"bot creates physical projectiles")
	game.projectiles.clear()
	game.projectiles.spawn(game.player.position+Vector3(-2,1.0,0),Vector3.RIGHT,"bot")
	fly(0.15)
	check(game.duel.player_alive and impacts[-1].hit.collider.get_meta("headshot")==false,"player body blocks without damage")
	var player_head: Vector3=game.player.position+Vector3(0,1.65,0)
	var bot_head: Vector3=bot.target.get_node("Head").global_position
	game.projectiles.spawn(bot_head+Vector3(0,0,2),Vector3.FORWARD,"player")
	game.projectiles.spawn(player_head+Vector3(3,0,0),Vector3.LEFT,"bot")
	fly(0.09)
	check(game.settling and game.phase=="training","first death waits for opposing projectile")
	fly(0.1)
	check(game.phase=="results" and not game.duel.player_alive and not bot.target.alive,"in-flight trade settles as draw")
	await capture("trade-result")
	await prepare("assessment_yard")
	game.pause_game()
	game.ui.show_help()
	await capture("assessment-help")
	game.ui.close_help()
	game.resume_game()
	game.weapon.mag=0
	game.weapon.reserve=0
	game.begin_settlement("弹药耗尽")
	game.duel.resolve()
	check(game.phase=="results","empty ammo ends unlimited duel")
	game.show_setup()
	await capture("setup")

func walk_player(path: PackedVector3Array,label_text: String) -> void:
	for point in path:
		var guard:=0
		while guard<360:
			var offset: Vector3=point-game.player.position
			offset.y=0
			var speed:=Vector2(game.player.velocity.x,game.player.velocity.z).length()
			if offset.length()<0.25 and speed<0.3: break
			game.player.rotation.y=atan2(-offset.x,-offset.z)
			if offset.length()>speed*speed/24.0+0.13: Input.action_press("move_forward")
			else: Input.action_release("move_forward")
			await frames(1)
			guard+=1
		Input.action_release("move_forward")
		check(guard<360,label_text+" waypoint %s at %s"%[point,game.player.position])
		if guard>=360: break

func walk_bot(destination: Vector3,label_text: String) -> void:
	var bot=game.duel.bot
	bot.navigation_only=true
	bot.navigation_destination=destination
	bot.repath=0
	var guard:=0
	while bot.position.distance_to(destination)>0.3 and guard<1440:
		await get_tree().physics_frame
		bot.step(1.0/120)
		guard+=1
	check(guard<1440,label_text+" position %s"%bot.position)
	bot.navigation_only=false

func overview(label_text: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var camera:=Camera3D.new()
	game.add_child(camera)
	camera.position=Vector3(43,64,52)
	camera.look_at(Vector3.ZERO)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=95
	camera.current=true
	game.ui.hud.hide()
	game.ui.overlay.hide()
	await capture(label_text)
	camera.free()
	game.player.camera.current=true

func demo() -> void:
	# Separate controlled shots, a real-input stair/jump tour, then real combat.
	await prepare("training_hall","deagle")
	game.player.reset_position(Vector3(-6,0.02,5))
	game.player.set_physics_process(true)
	await frames(12)
	game.player.camera.look_at(game.arena.targets[0].get_node("Body").global_position)
	game.set_physics_process(true)
	game.weapon.set_physics_process(true)
	await get_tree().create_timer(0.7).timeout
	game.set_primary_pressed(true)
	game.set_primary_pressed(false)
	await get_tree().create_timer(0.16).timeout
	await capture("bullet-flight")
	await get_tree().create_timer(0.7).timeout
	check(game.hits==1 and game.kills==0,"demo body projectile")
	game.player.camera.look_at(game.arena.targets[0].get_node("Head").global_position)
	game.set_primary_pressed(true)
	game.set_primary_pressed(false)
	await get_tree().create_timer(0.7).timeout
	check(game.kills==1,"demo head projectile")
	await capture("head-hit")
	# A side view makes the physical flight visible; normal gameplay stays FPS.
	game.arena.targets[0].reset_target()
	game.player.weapon_root.hide()
	var side_camera:=Camera3D.new()
	game.add_child(side_camera)
	side_camera.position=Vector3(-2,2.3,0)
	side_camera.look_at(Vector3(-6,1.3,0))
	side_camera.current=true
	Engine.time_scale=0.25
	game.set_primary_pressed(true)
	game.set_primary_pressed(false)
	await get_tree().create_timer(0.2).timeout
	await capture("projectile-side-slow")
	await get_tree().create_timer(0.6).timeout
	Engine.time_scale=1.0
	side_camera.free()
	game.player.camera.current=true
	game.player.weapon_root.show()
	game.set_physics_process(false)
	game.arena.layout_rng.seed=72042
	await prepare("assessment_yard","ak47")
	await overview("overview")
	game.ui.hide_overlay()
	game.ui.hud.show()
	game.player.weapon_root.show()
	var map=game.arena.map_root
	var top: Vector3=map.layout.platform_center(map.layout.platforms[1])
	var entry:=top+Vector3(0,-2,-7.5)
	game.duel.bot.position=Vector3(0,-20,0)
	game.player.reset_position(entry,PI)
	game.player.set_physics_process(true)
	game._update_hud()
	await frames(12)
	await capture("stairs-entry")
	await walk_player(map.navigation_path(entry,top),"demo climb")
	game.player.rotation.y=0
	game.player.camera.rotation.x=-0.25
	await capture("high-platform")
	Input.action_press("jump")
	await frames(32)
	Input.action_release("jump")
	check(not game.player.is_on_floor(),"demo real jump")
	game._update_hud()
	await capture("jump")
	await frames(100)
	check(game.player.is_on_floor(),"demo jump lands")
	# Combat fixture starts opponents at different heights, with no damage bypass.
	var bot=game.duel.bot
	bot.position=entry
	bot.velocity=Vector3.ZERO
	bot.rotation.y=PI
	bot.aim_direction=Vector3.BACK
	bot.pose(0)
	game.player.camera.look_at(bot.position+Vector3(0,1.1,0))
	game.set_physics_process(true)
	await get_tree().create_timer(0.65).timeout
	game.set_primary_pressed(true)
	await get_tree().create_timer(0.3).timeout
	game.set_primary_pressed(false)
	await capture("vertical-combat")
	if game.player.active:
		game.player.camera.look_at(bot.target.get_node("Head").global_position)
		game.set_primary_pressed(true)
		await get_tree().create_timer(0.8).timeout
		game.set_primary_pressed(false)
	var guard:=0
	while game.phase=="training" and guard<720:
		await frames(1)
		guard+=1
	check(game.shots>0 and bot.shot_count>0,"demo both sides launch real projectiles")
	check(game.phase=="results","demo combat reaches results")
	await capture("combat-result")
	await get_tree().create_timer(1.0).timeout
	var report:=FileAccess.open(folder.path_join("demo.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"seed":map.generation_seed,"player_shots":game.shots,"bot_shots":bot.shot_count,"kills":game.kills,"phase":game.phase,"fixture":"scripted shots; real WASD stair traversal and jump; combat starts at different elevations"},"\t"))

func benchmark() -> void:
	var reports: Array=[]
	for i in 3:
		game.arena.layout_rng.seed=72042+i
		await prepare("assessment_yard")
		# Measurement fixture: a body remains visible to AI, but the head cannot
		# end the 30s sample. Player shoots upward and receives reserve ammo.
		game.duel.regions[1].collision_layer=0
		game.player.reset_position(Vector3(0,0.02,34))
		game.duel.bot.position=Vector3(0,0.02,31)
		game.player.camera.rotation.x=0.65
		game.player.set_physics_process(true)
		game.weapon.set_physics_process(true)
		game.set_physics_process(true)
		await frames(240)
		var start:=Time.get_ticks_usec()
		var previous:=start
		var samples: Array[float]=[]
		while Time.get_ticks_usec()-start<30000000:
			await get_tree().process_frame
			var now:=Time.get_ticks_usec()
			samples.append((now-previous)/1000.0)
			previous=now
			game.weapon.reserve=50
			if game.weapon.fire_error().is_empty() and not game.manual_fire_held:
				game.set_primary_pressed(false)
				game.set_primary_pressed(true)
			var right:=int((now-start)/1000000)%2==0
			Input.action_release("move_left" if right else "move_right")
			Input.action_press("move_right" if right else "move_left")
		Input.action_release("move_left")
		Input.action_release("move_right")
		game.set_primary_pressed(false)
		var seconds:=float(Time.get_ticks_usec()-start)/1000000.0
		samples.sort()
		reports.append({"seed":game.arena.map_root.generation_seed,"seconds":seconds,"mean_fps":samples.size()/seconds,"p95_ms":samples[int(samples.size()*0.95)],"p99_ms":samples[int(samples.size()*0.99)],"worst_ms":samples[-1],"player_shots":game.shots,"bot_shots":game.duel.bot.shot_count,"fixture":"immortal player head, replenished reserve","gpu":RenderingServer.get_video_adapter_name()})
		await capture("benchmark-%d"%i)
		game.set_physics_process(false)
	var file:=FileAccess.open(folder.path_join("performance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(reports,"\t"))
