extends "res://tests/lock_checks.gd"
var results: Array=[]
func run(controller: Node3D) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	game=controller
	game.set_physics_process(false)
	game.weapon.set_physics_process(false)
	game.projectiles.set_physics_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): folder=arg.trim_prefix("--capture-dir=")
	if folder.is_empty(): folder="user://extreme-checks"
	DirAccess.make_dir_recursive_absolute(folder)
	Engine.physics_ticks_per_second=960
	Engine.time_scale=8
	await reset_case()
	var bot=game.duel.bot
	check(game.weapon.get_data().interval_ms==100 and game.weapon.get_data().reload_ms==2500,"player AK timings unchanged")
	await tick(2)
	check(bot.shot_count==0,"no fire before 30 ms reaction")
	await tick(2)
	check(bot.shot_count==1,"first shot on first physics step after 30 ms")
	await tick(40)
	check(bot.shot_count>=5,"continuous fire has no burst pause")
	for i in range(1,bot.shot_log.size()):
		var gap: float=bot.shot_log[i].time-bot.shot_log[i-1].time
		check(gap>=.07-.00001 and gap<=.07+dt+.00001,"NPC fires every 70 ms rounded to physics step")
	var before: int=bot.shot_count
	bot.weapon.start_reload()
	await tick(77)
	check(bot.shot_count==before,"reload blocks fire for 650 ms")
	await tick(3)
	check(bot.shot_count>before,"fast reload resumes fire")
	game.projectiles.clear()
	var player_bullet: Dictionary=game.projectiles.spawn(Vector3(0,50,0),Vector3.RIGHT,"player")
	var bot_bullet: Dictionary=game.projectiles.spawn(Vector3(0,52,0),Vector3.RIGHT,"bot",Profile.PROJECTILE_SPEED)
	game.projectiles.advance(.1)
	check(absf(player_bullet.distance-2.5)<.001,"player bullet remains 25 m/s")
	check(absf(bot_bullet.distance-15)<.001,"NPC physical bullet travels 150 m/s")
	game.projectiles.clear()
	var wall:=box(Vector3(0,22,9),Vector3(4,4,.002))
	await frames(3)
	var fast: Dictionary=game.projectiles.spawn(Vector3(0,22,10),Vector3.FORWARD,"bot",Profile.PROJECTILE_SPEED)
	game.projectiles.advance(1.0/60)
	check(not fast.live and fast.distance<1.01,"fast projectile sweep cannot penetrate a 2 mm wall")
	wall.free()
	game.projectiles.clear()
	await reset_case()
	bot=game.duel.bot
	wall=box(Vector3(-1.5,21.5,9),Vector3(8,4,.2))
	await frames(3)
	await tick(40)
	check(bot.shot_count==0,"wall still prevents lock fire")
	wall.free()
	game.pause_game()
	var old_clock: float=bot.clock
	bot.step(.5)
	check(bot.clock==old_clock,"pause freezes extreme bot")
	game.resume_game()
	game.begin_settlement("test")
	await tick(30)
	check(bot.shot_count==0,"settlement prohibits firing")
	for motion in ["static","strafe","reverse"]:
		var times: Array[float]=[]
		var kills:=0
		for trial in 5:
			await reset_case()
			var elapsed_time:=0.0
			for i in 120:
				var speed:=0.0 if motion=="static" else 3.0
				if motion=="reverse" and i>=12: speed=-3.0
				await tick(1,Vector3(speed,0,0))
				game.projectiles.advance(dt)
				elapsed_time+=dt
				if not game.duel.player_alive:
					kills+=1
					break
			times.append(elapsed_time)
		check(kills==5,"extreme bot wins five physical intercept trials: "+motion)
		times.sort()
		results.append({"target":motion,"kills":kills,"trials":5,"median_seconds_capped_at_1":times[2]})
	Engine.physics_ticks_per_second=120
	Engine.time_scale=1
	FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results},"\t"))
	print("EXTREME PASS: %d checks (%d failures)"%[checks,failures])
	game.show_menu()
	await get_tree().create_timer(.2,true).timeout
	get_tree().quit(1 if failures else 0)
