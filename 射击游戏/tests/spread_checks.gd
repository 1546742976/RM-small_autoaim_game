extends Node
## Sample real launches; flight/contact checks live in projectile_checks.gd.
var game: Node3D
var check: Callable
var observed:=Vector3.ZERO

func frames(count:=2) -> void:
	for i in count: await get_tree().physics_frame
	await get_tree().process_frame

func record(_origin: Vector3,direction: Vector3) -> void:
	observed=direction

func run(controller: Node3D,assertion: Callable) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	game=controller
	check=assertion
	game.shot_fired.connect(record)
	for map_id in ["training_hall","old_town"]:
		game.show_setup()
		game._select_loadout(map_id,"ak47")
		game.start_round()
		game.begin_training()
		await frames(12)
		game.player.set_physics_process(false)
		for id in ["deagle","ak47","m4a1"]:
			game.weapon.reset(id)
			game.weapon.active=true
			game.player.set_weapon(id)
			var precise:=Vector3.ZERO
			for speed in [0.339,0.34,0.341,1.0]:
				game.weapon.advance_ms(300)
				game.player._horizontal_speed=speed*game.player.MAX_SPEED
				game.shot_rng.seed=106
				var before: int=game.shot_rng.state
				var shots: int=game.shots
				var ammo: int=game.weapon.mag
				var camera: Transform3D=game.player.camera.global_transform
				check.call(game.weapon.try_fire().is_empty(),"real launch at "+str(speed))
				check.call(game.shots==shots+1 and game.weapon.mag==ammo-1,"one projectile one charge")
				check.call(game.player.camera.global_transform==camera,"launch leaves camera unchanged")
				if speed<0.34: precise=observed
				check.call((game.shot_rng.state==before)==(speed<0.34),"precision controls RNG consumption")
				check.call(observed.is_equal_approx(precise)==(speed<0.34),"moving launch differs from centre")
				check.call(observed.angle_to(precise)<=atan(0.2)+0.0001,"actual launch stays in 20 percent cone")
				game._update_hud()
				check.call(game.ui.crosshair.accurate==(speed<0.34) and not game.ui.crosshair.can_fire,"reticle separates accuracy and readiness")
				game.projectiles.clear()
			var before: int=game.shot_rng.state
			var count: int=game.shots
			check.call(game.weapon.try_fire()=="cooldown","cooldown rejection")
			check.call(game.weapon.start_reload(),"reload accepted")
			check.call(game.weapon.try_fire()=="reloading","reload rejection")
			game.weapon.reload_left_ms=0
			game.weapon.mag=0
			check.call(game.weapon.try_fire()=="mag_empty","empty rejection")
			game.weapon.active=false
			check.call(game.weapon.try_fire()=="not_training","inactive rejection")
			check.call(game.shots==count and game.shot_rng.state==before and game.projectiles.live_count()==0,"rejected shots create no projectile and consume no RNG")
		game.player.set_physics_process(true)
	game.show_menu()
	game.shot_fired.disconnect(record)
