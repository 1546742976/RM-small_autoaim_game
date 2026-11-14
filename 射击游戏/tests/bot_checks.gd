extends "res://tests/projectile_checks.gd"
const Profile=preload("res://scripts/bot_profile.gd")
var comparison: Array=[]
var dt:=1.0/120.0

func run(controller: Node3D) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	game=controller
	game.set_physics_process(false)
	game.weapon.set_physics_process(false)
	game.projectiles.set_physics_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): folder=arg.trim_prefix("--capture-dir=")
	if folder.is_empty(): folder="user://bot-checks"
	DirAccess.make_dir_recursive_absolute(folder)
	Engine.physics_ticks_per_second=960
	Engine.time_scale=8
	unit_checks()
	await prepare("assessment_yard")
	await fixtures()
	if not "--bot-quick" in OS.get_cmdline_user_args():
		await routes_test()
		await compare_bots()
	Engine.time_scale=1
	Engine.physics_ticks_per_second=120
	if DisplayServer.get_name()!="headless": await demonstration()
	var report={"checks":checks,"failures":failures,"comparison":comparison}
	FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BOT PASS: %d checks (%d failures)"%[checks,failures])
	game.show_menu()
	await get_tree().create_timer(0.1,true).timeout
	get_tree().quit(1 if failures else 0)

func unit_checks() -> void:
	var point: Vector3=Profile.intercept(Vector3.ZERO,Vector3(0,0,-20),Vector3(4,0,0),false,0)
	check(point.x>3.2 and absf(point.length()/25-point.x/4)<0.001,"linear interception satisfies bullet flight time")
	check(Profile.intercept(Vector3.ZERO,Vector3(0,0,-20),Vector3(0,0,-30),false,0)==Vector3(0,0,-20),"unreachable target falls back")
	point=Profile.intercept(Vector3.ZERO,Vector3(0,2,-50),Vector3(3,-4,0),true,1.65)
	check(point.x<=3.6001 and point.y>=1.6499,"prediction cap and floor clamp")

func box(at: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new()
	var collider:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=size
	collider.shape=shape
	body.add_child(collider)
	game.add_child(body)
	body.position=at
	var mesh:=MeshInstance3D.new()
	var cube:=BoxMesh.new()
	cube.size=size
	mesh.mesh=cube
	body.add_child(mesh)
	return body

func fixtures() -> void:
	var bot=game.duel.bot
	game.player.reset_position(Vector3(-10,0.02,34))
	bot.position=Vector3(8,0.02,34)
	bot.active=true
	await frames(4)
	check(bot.tactics.safe_jump(Vector3.LEFT),"clear navigation landing permits dodge")
	var ceiling:=box(Vector3(6.5,2.1,34),Vector3(5,0.2,3))
	await frames(2)
	check(not bot.tactics.safe_jump(Vector3.LEFT),"low ceiling rejects jump")
	ceiling.free()
	var obstacle:=box(Vector3(6.5,1,34),Vector3(.3,2,3))
	await frames(2)
	check(not bot.tactics.safe_jump(Vector3.LEFT),"two metre obstacle rejects jump")
	check(not bot.tactics.clear_line(Vector3(8,1.65,34),Vector3(4,1.65,34)),"wall blocks firing line")
	var shots_before: int=bot.shot_count
	for i in 25:
		await get_tree().physics_frame
		bot.step(dt)
	check(bot.shot_count==shots_before,"occluded player cannot be fired on")
	check(bot.last_seen.distance_to(game.player.position)<.01,"omniscient pursuit knows hidden position")
	obstacle.free()
	bot.tactics.has_cover=true
	bot.tactics.cover=bot.position
	bot.tactics.cover_left=10
	bot.tactics.decision_left=0
	bot.weapon.mag=4
	bot.tactics.desired(dt,true)
	check(bot.weapon.is_reloading(),"low magazine in cover reloads")
	var old_clock: float=bot.clock
	game.pause_game()
	bot.step(.5)
	check(bot.clock==old_clock,"pause freezes bot decision and weapon clock")
	game.resume_game()
	bot.navigation_only=true
	bot.navigation_destination=Vector3(8,.02,33)
	bot.repath=0
	for i in 120:
		await get_tree().physics_frame
		bot.step(dt)
	bot.navigation_only=false
	bot.weapon.reload_left_ms=0
	bot.weapon.mag=25
	bot.position=Vector3(3,.02,34)
	bot.velocity=Vector3.ZERO
	game.player.reset_position(Vector3(-8,.02,34),-PI/2)
	bot.tactics.has_cover=false
	bot.tactics.cover_left=10
	bot.tactics.begin_move(Vector3(6,.02,34))
	var highest:=0.0
	var jumps_before: int=bot.tactics.jump_count
	for i in 100:
		await get_tree().physics_frame
		bot.step(dt)
		highest=maxf(highest,bot.position.y)
	check(bot.tactics.jump_count>jumps_before and highest>.7,"actual tactical dodge takes off")
	check(bot.is_on_floor() and bot.position.y<.1,"tactical dodge lands safely")
	var wall:=box(Vector3(0,1.2,34),Vector3(1,2.4,.2))
	var cell_index:=34*21+10
	var old_cell: int=bot.layout.cells[cell_index]
	bot.layout.cells[cell_index]=1
	bot.position=Vector3(0,.02,35)
	game.player.reset_position(Vector3(0,.02,33))
	await frames(3)
	bot.tactics.pick_cover(game.player.position)
	check(bot.tactics.has_cover,"selects reachable hidden cover with an exposed peek")
	if bot.tactics.has_cover:
		check(not bot.tactics.clear_line(game.player.position+Vector3.UP*1.65,bot.tactics.cover+Vector3.UP*1.65),"selected cover hides head")
		check(bot.tactics.clear_line(game.player.position+Vector3.UP*1.65,bot.tactics.peek+Vector3.UP*1.65),"selected peek has real line of sight")
	bot.layout.cells[cell_index]=old_cell
	wall.free()
	bot.weapon.reload_left_ms=0
	bot.weapon.mag=25
	bot.tactics.cover_left=10
	bot.tactics.has_cover=false
	bot.tactics.jump_left=10
	bot.tactics.stuck_time=0
	bot.tactics.stuck_origin=bot.position
	bot.tactics.begin_move(bot.position+Vector3.RIGHT*3)
	for i in 45: bot.tactics.desired(.05,true)
	check(bot.tactics.recovery_count>=2,"stationary blocked mover repaths and replaces target")
	bot.position=Vector3(20,.02,34)
	check(not bot.tactics.safe_jump(Vector3.RIGHT),"boundary without landing rejects jump")
	await capture("bot-fixtures")

func routes_test() -> void:
	for seed_index in 20:
		game.arena.layout_rng.seed=1000+seed_index
		await prepare("assessment_yard")
		var bot=game.duel.bot
		bot.active=true
		var start: Vector3=bot.position
		for tick in 360:
			await get_tree().physics_frame
			bot.step(dt)
			game.projectiles.advance(dt)
		check(bot.position.distance_to(start)>1,"seed %d pursues instead of standing"%seed_index)
		check(bot.position.is_finite() and bot.position.y>-.2,"seed %d stays on playable surface"%seed_index)
		var top: Vector3=game.arena.map_root.layout.platform_center(game.arena.map_root.layout.platforms[seed_index%3])
		var entry: Vector3=top+Vector3(0,-2,6)
		bot.position=entry
		bot.velocity=Vector3.ZERO
		await walk_bot(top,"expert stairs %d"%seed_index)
		print("BOT ROUTE ",seed_index)

func compare_bots() -> void:
	await prepare("assessment_yard")
	var floor_body:=box(Vector3(0,19.8,0),Vector3(50,.4,50))
	for mode in ["legacy","expert"]:
		for movement in ["static","strafe","reverse","jump"]:
			var times: Array[float]=[]
			var kills:=0
			for trial in 30:
				var previous=game.duel.bot
				previous.free()
				var script=load("res://tests/legacy_duel_bot.gd" if mode=="legacy" else "res://scripts/duel_bot.gd")
				var bot=script.new()
				bot.game=game
				bot.layout=game.arena.map_root.layout
				bot.position=Vector3(0,20.02,18)
				game.arena.map_root.add_child(bot)
				game.duel.bot=bot
				bot.rng.seed=trial+712
				bot.active=true
				game.player.reset_position(Vector3(-3,20.02,0))
				game.duel.player_alive=true
				game.player.collision_layer=4
				for region in game.duel.regions: region.collision_layer=16
				game.phase="training"
				game.settling=false
				game.projectiles.clear()
				var elapsed_time:=0.0
				for tick in 960:
					await get_tree().physics_frame
					elapsed_time+=dt
					var speed:=0.0
					if movement=="strafe": speed=3.0
					elif movement=="reverse": speed=4.0 if fmod(elapsed_time,2)<1 else -4.0
					elif movement=="jump": speed=1.0
					game.player.velocity.x=speed
					if game.player.is_on_floor():
						game.player.velocity.y=6.3 if movement=="jump" else -.1
					else: game.player.velocity.y-=20*dt
					game.player.move_and_slide()
					bot.step(dt)
					game.projectiles.advance(dt)
					if not game.duel.player_alive:
						kills+=1
						break
				times.append(elapsed_time)
				if mode=="expert":
					for shot in bot.shot_log:
						check(shot.grounded and shot.reaction>=.18,"expert shot respects grounding/reaction")
					for i in range(1,bot.shot_log.size()): check(bot.shot_log[i].time-bot.shot_log[i-1].time>=.0999,"expert respects AK cooldown")
			times.sort()
			comparison.append({"mode":mode,"movement":movement,"trials":30,"kills":kills,"median_seconds_capped_at_8":(times[14]+times[15])*.5})
			print("BOT COMPARE ",comparison[-1])
	for i in [0,1]: check(comparison[i+4].median_seconds_capped_at_8<comparison[i].median_seconds_capped_at_8,"expert improves "+comparison[i].movement)
	floor_body.free()

func demonstration() -> void:
	for scenario in ["pursuit","jump","cover-reload","lead-shot"]:
		await prepare("assessment_yard")
		var bot=game.duel.bot
		bot.active=true
		var fixture: Node3D
		var camera:=Camera3D.new()
		game.add_child(camera)
		game.player.weapon_root.hide()
		if scenario=="pursuit":
			bot.position=Vector3(0,.02,-34)
			game.player.reset_position(Vector3(0,.02,34))
		elif scenario=="jump":
			bot.position=Vector3(3,.02,34)
			game.player.reset_position(Vector3(-8,.02,34),-PI/2)
			bot.tactics.begin_move(Vector3(6,.02,34))
			bot.tactics.cover_left=10
		elif scenario=="cover-reload":
			fixture=box(Vector3(0,1.2,34),Vector3(1,2.4,.2))
			bot.layout.cells[34*21+10]=1
			bot.position=Vector3(0,.02,35)
			game.player.reset_position(Vector3(0,.02,33))
			bot.weapon.mag=4
		else:
			fixture=box(Vector3(0,19.8,0),Vector3(50,.4,50))
			bot.position=Vector3(0,20.02,18)
			game.player.reset_position(Vector3(-3,20.02,0))
		camera.current=true
		for i in 360:
			await get_tree().physics_frame
			if scenario=="lead-shot":
				game.player.velocity=Vector3(3,-.1,0)
				game.player.move_and_slide()
			bot.step(dt)
			game.projectiles.advance(dt)
			camera.position=bot.position+(Vector3(0,10,.2) if scenario=="pursuit" else Vector3(5,3,0))
			camera.look_at(bot.position+Vector3.UP)
			if i in [32,180,300]: await capture(scenario+"-%d"%i)
		if scenario=="jump": check(bot.tactics.jump_count>0,"rendered jump demonstration")
		if scenario=="cover-reload": check(bot.weapon.reload_serial>0,"rendered cover reload demonstration")
		camera.free()
		if is_instance_valid(fixture): fixture.free()
		game.player.camera.current=true
