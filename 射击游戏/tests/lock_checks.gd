extends "res://tests/projectile_checks.gd"
const Profile=preload("res://scripts/bot_profile.gd")
var dt:=1.0/120.0
var floor_body: StaticBody3D
var live_demo:=false

func box(at: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new()
	var collider:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=size
	collider.shape=shape
	body.add_child(collider)
	game.add_child(body)
	body.position=at
	var view:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=size
	view.mesh=mesh
	body.add_child(view)
	return body

func reset_case() -> void:
	if is_instance_valid(floor_body): floor_body.free()
	await prepare("assessment_yard")
	floor_body=box(Vector3(0,19.8,0),Vector3(50,.4,50))
	game.player.reset_position(Vector3(-3,20.02,0))
	var bot=game.duel.bot
	bot.position=Vector3(0,20.02,18)
	bot.rotation.y=0
	bot.active=true
	await frames(3)
	game.player.velocity=Vector3(0,-.1,0)
	game.player.move_and_slide()
	bot.velocity=Vector3(0,-.1,0)
	bot.move_and_slide()
	bot.pose(0)

func tick(count: int,movement:=Vector3.ZERO) -> void:
	for i in count:
		await get_tree().physics_frame
		game.player.velocity=movement+Vector3(0,-.1,0)
		game.player.move_and_slide()
		game.duel.bot.step(dt)

func run(controller: Node3D) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	game=controller
	game.set_physics_process(false)
	game.weapon.set_physics_process(false)
	game.projectiles.set_physics_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): folder=arg.trim_prefix("--capture-dir=")
	if folder.is_empty(): folder="user://lock-checks"
	DirAccess.make_dir_recursive_absolute(folder)
	live_demo="--lock-demo" in OS.get_cmdline_user_args()
	Engine.physics_ticks_per_second=120 if live_demo else 960
	Engine.time_scale=1 if live_demo else 8
	await reset_case()
	var bot=game.duel.bot
	bot.tactics.begin_move(bot.position+Vector3.RIGHT*3)
	bot.velocity.x=4.5
	var rng_before: int=bot.rng.state
	await tick(21)
	check(bot.shot_count==0,"reaction never fires before 0.18 seconds")
	check(not bot.tactics.moving and bot.tactics.state=="lock","visible head interrupts relocation")
	check(bot.tactics.jump_count==0,"lock does not start a jump")
	await tick(70)
	check(bot.shot_count>=6,"stationary target receives two bursts")
	check(bot.rng.state==rng_before,"lock fire consumes no tactical or aiming random numbers")
	var log: Array=bot.shot_log
	for i in log.size():
		check(log[i].grounded and log[i].speed/4.5<.34,"shot requires grounded counter-strafe")
		check(log[i].reaction>=.18,"shot retains reaction delay")
		if i>0:
			var interval: float=log[i].time-log[i-1].time
			var expected:=.15 if i%3==0 else .1
			check(interval>=expected-.00001 and interval<=expected+dt+.00001,"burst interval matches 0.10/0.15 seconds")
	for bullet in game.projectiles.bullets:
		var origin: Vector3=bullet.area.global_position
		var expected: Vector3=(game.player.position+Vector3.UP*1.65-origin).normalized()
		check(bullet.direction.distance_to(expected)<.0001,"static shots contain no angular randomness")
	await capture("lock-braking")
	await reset_case()
	bot=game.duel.bot
	bot.weapon.mag=4
	bot.tactics.has_cover=true
	bot.tactics.cover=bot.position
	bot.tactics.cover_left=10
	await tick(30)
	check(bot.shot_count>0 and not bot.weapon.is_reloading(),"visible head overrides low-ammo tactical reload")
	bot.weapon.start_reload()
	var before: int=bot.shot_count
	await tick(299)
	check(bot.shot_count==before,"active reload blocks lock fire")
	await tick(4)
	check(bot.shot_count>before,"completed reload resumes lock without queued fire")
	await reset_case()
	bot=game.duel.bot
	await tick(10)
	var reaction_before: float=bot.reaction
	var wall:=box(Vector3(-1.5,21.5,9),Vector3(8,4,.2))
	await frames(2)
	await tick(8)
	check(bot.shot_count==0 and is_equal_approx(bot.reaction,reaction_before),"brief occlusion freezes accumulated reaction")
	await tick(12)
	check(bot.reaction==0 and bot.shot_count==0,"long occlusion resets reaction and prevents shooting")
	wall.free()
	await tick(10)
	check(bot.shot_count==0,"reappearance starts a new reaction window")
	await tick(30)
	check(bot.shot_count>0,"reacquisition fires after reaction")
	await reset_case()
	bot=game.duel.bot
	game.duel.regions[1].collision_layer=0
	await tick(60)
	check(bot.shot_count==0,"body visibility alone never locks head")
	game.duel.regions[1].collision_layer=16
	bot.position.y+=1
	bot.velocity=Vector3.ZERO
	await tick(10)
	check(bot.shot_count==0,"airborne bot cannot fire")
	await tick(80)
	check(bot.shot_count>0 and bot.is_on_floor(),"landing allows grounded lock")
	var clock_before: float=bot.clock
	game.pause_game()
	bot.step(.5)
	check(bot.clock==clock_before,"pause freezes reaction and weapon clocks")
	game.resume_game()
	game.begin_settlement("test")
	before=bot.shot_count
	await tick(40)
	check(bot.shot_count==before,"settlement prohibits new shots")
	await reset_case()
	bot=game.duel.bot
	await tick(22,Vector3(3,0,0))
	check(bot.shot_count==1,"moving target creates a physical first shot")
	var bullet=game.projectiles.bullets[0]
	var toward_head: Vector3=(game.player.position+Vector3.UP*1.65-bullet.area.position).normalized()
	check(bullet.direction.x>toward_head.x+.05,"moving target is led rather than aimed at current head")
	# Freeze new shots; test the already flying round against a sudden reversal.
	bot.active=false
	for i in 100:
		await get_tree().physics_frame
		game.player.velocity=Vector3(-3,-.1,0)
		game.player.move_and_slide()
		game.projectiles.advance(dt)
	check(game.duel.player_alive,"sudden reversal can dodge a non-homing bullet")
	await reset_case()
	bot=game.duel.bot
	for i in 160:
		await tick(1,Vector3(3,0,0))
		game.projectiles.advance(dt)
		if not game.duel.player_alive: break
	check(not game.duel.player_alive,"steady strafing is intercepted through real head collision")
	check(bot.shot_log.size()>0,"physical kill has a recorded shot")
	await capture("lock-intercept")
	await reset_case()
	bot=game.duel.bot
	check(bot.reaction==0 and bot.burst_left==0 and bot.shot_count==0,"new round clears lock and fire state")
	bot.target.alive=false
	await tick(30)
	check(bot.shot_count==0,"dead bot cannot fire")
	if live_demo:
		await reset_case()
		bot=game.duel.bot
		var camera:=Camera3D.new()
		game.add_child(camera)
		camera.position=Vector3(9,24,23)
		camera.look_at(Vector3(0,21,12))
		camera.current=true
		game.player.weapon_root.hide()
		bot.tactics.begin_move(bot.position+Vector3.RIGHT*3)
		bot.velocity.x=4.5
		for i in 180:
			await tick(1,Vector3(3,0,0))
			game.projectiles.advance(dt)
			if i in [10,24,70]: await capture("showcase-%d"%i)
		camera.free()
		game.player.camera.current=true
	FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("LOCK PASS: %d checks (%d failures)"%[checks,failures])
	Engine.physics_ticks_per_second=120
	Engine.time_scale=1
	game.show_menu()
	await get_tree().create_timer(.2,true).timeout
	get_tree().quit(1 if failures else 0)
