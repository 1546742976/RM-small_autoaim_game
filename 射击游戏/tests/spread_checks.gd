extends Node
## Exercise the production raycast, RNG consumption and reticle against real regions.
const Direction = preload("res://scripts/shot_direction.gd")
var game: Node3D
var check: Callable
var observed: Dictionary = {}

func frames(count := 2) -> void:
	for i in count: await get_tree().physics_frame
	await get_tree().process_frame

func record(origin: Vector3, direction: Vector3, collision: Dictionary) -> void:
	observed = {"origin":origin,"direction":direction,"collision":collision}

func run(controller: Node3D, assertion: Callable) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = controller
	check = assertion
	game.shot_resolved.connect(record)
	for map_id: String in ["training_hall","old_town"]:
		game.show_setup()
		game.ui._select(map_id,"ak47")
		game.start_round()
		game.begin_training()
		await frames(3)
		var target: Node3D = game.arena.targets[0]
		target.set_physics_process(false)
		game.player.reset_position(game.arena.map_root.test_views[0])
		await frames(3)
		for id: String in ["deagle","ak47","m4a1"]:
			game.weapon.reset(id)
			game.weapon.active = true
			for speed: float in [0.339,0.34,0.341,1.0]:
				game.weapon.advance_ms(float(game.weapon.get_data().interval_ms))
				game.player._horizontal_speed = speed*game.player.MAX_SPEED
				game.shot_rng.seed = 106
				var before_state: int = game.shot_rng.state
				var shots_before: int = game.shots
				var mag_before: int = game.weapon.mag
				var camera_before: Transform3D = game.player.camera.global_transform
				check.call(game.weapon.try_fire() == "",map_id+id+" permits speed "+str(speed))
				check.call(game.shots == shots_before+1 and game.weapon.mag == mag_before-1,"moving/accurate shot counted and charged")
				check.call(game.player.camera.global_transform == camera_before,"spread leaves camera unchanged")
				var forward := -camera_before.basis.z.normalized()
				if speed < 0.34:
					check.call(observed.direction.is_equal_approx(forward) and game.shot_rng.state == before_state,"actual precise ray leaves RNG unchanged")
				else:
					check.call(not observed.direction.is_equal_approx(forward) and game.shot_rng.state != before_state,"actual moving ray consumes RNG")
				game._update_hud()
				check.call(game.ui.crosshair.accurate == (speed<0.34) and not game.ui.crosshair.can_fire,"accuracy independent from cooldown")
			# Rejected attempts must not change shots, ammunition or RNG.
			var before: int = game.shot_rng.state
			var shots_before: int = game.shots
			var mag_before: int = game.weapon.mag
			check.call(game.weapon.try_fire() == "cooldown","cooldown still refuses shot")
			check.call(game.weapon.mag == mag_before,"cooldown rejection preserves ammo")
			check.call(game.weapon.start_reload(),"reload starts after moving shots")
			check.call(game.weapon.try_fire() == "reloading","reload refuses shot")
			check.call(game.weapon.mag == mag_before,"reload rejection preserves ammo")
			game.weapon.reload_left_ms = 0
			game.weapon.mag = 0
			check.call(game.weapon.try_fire() == "mag_empty","empty magazine refuses shot")
			game.weapon.active = false
			check.call(game.weapon.try_fire() == "not_training","inactive weapon refuses shot")
			check.call(game.shot_rng.state == before and game.shots == shots_before,"rejected attempts never consume RNG or count shots")
			check.call(mag_before > 0,"test started rejections with ammunition")
			game.weapon.reset(id)
			game.weapon.active = true
			target.reset_target()
			await frames()
			var hits_before: int = game.hits
			fire_toward(target.get_node("Body").global_position,0.34)
			check.call(game.hits == hits_before+1 and target.hp == 100 and target.alive,map_id+id+" scattered body hit counts without damage")
			fire_toward(target.get_node("Head").global_position,0.341)
			check.call(not target.alive and observed.collision.collider.get_meta("headshot"),map_id+id+" scattered headshot kills")
			target.reset_target()
			var wall := StaticBody3D.new()
			wall.collision_layer = 1
			wall.position = game.player.camera.global_position.lerp(target.get_node("Head").global_position,0.5)
			var shape := BoxShape3D.new()
			shape.size = Vector3(4,4,0.3)
			var collider := CollisionShape3D.new()
			collider.shape = shape
			wall.add_child(collider)
			game.add_child(wall)
			await frames()
			hits_before = game.hits
			fire_toward(target.get_node("Head").global_position,1.0)
			check.call(observed.collision.get("collider") == wall and game.hits == hits_before and target.alive,map_id+id+" wall blocks scattered head ray")
			wall.free()
			await frames()
			game.weapon.mag = 1
			game.weapon.reserve = 0
			shots_before = game.shots
			var kills_before: int = game.kills
			fire_toward(target.get_node("Head").global_position,0.34)
			check.call(game.phase == "results" and game.shots == shots_before+1 and game.kills == kills_before+1,map_id+id+" last scattered bullet counts before results")
			game.start_round()
			game.begin_training()
			game.player.reset_position(game.arena.map_root.test_views[0])
			await frames(3)
		target.set_physics_process(true)
	# A short press/release during cooldown is not buffered. Deliberate rifle
	# holding is separately tested in input_checks.gd and may fire after cooldown.
	game.weapon.reset("ak47")
	game.weapon.active = true
	game.player._horizontal_speed = game.player.MAX_SPEED
	game.weapon.try_fire()
	var state_before: int = game.shot_rng.state
	var count_before: int = game.shots
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var release: InputEventMouseButton = click.duplicate()
	release.pressed = false
	if DisplayServer.get_name() == "headless":
		check.call(game.weapon.fire_error() == "cooldown","cooldown rejects before queueing")
	else:
		game._unhandled_input(click)
		game._unhandled_input(release)
	check.call(game.pending_shots == 0,"cooldown click is not queued")
	await frames(30)
	check.call(game.shot_rng.state == state_before and game.shots == count_before,"blocked click never fires later or consumes randomness")
	game.player._horizontal_speed = 0.339*game.player.MAX_SPEED
	var forward: Vector3 = -game.player.camera.global_basis.z.normalized()
	game.weapon.try_fire()
	check.call(observed.direction.is_equal_approx(forward) and game.shot_rng.state == state_before,"precision returns immediately below threshold")
	# The queued click is checked against speed when the ray is actually fired.
	for speeds in [[1.0,0.339],[0.339,1.0]]:
		game.weapon.advance_ms(float(game.weapon.get_data().interval_ms))
		game.player._horizontal_speed = speeds[0]*game.player.MAX_SPEED
		if DisplayServer.get_name() == "headless": game.pending_shots = 1
		else:
			game._unhandled_input(click)
			game._unhandled_input(release)
		check.call(game.pending_shots == 1,"firing-time test click accepted")
		game.player._horizontal_speed = speeds[1]*game.player.MAX_SPEED
		game._physics_process(0.0)
		check.call(observed.direction.is_equal_approx(forward) == (speeds[1]<0.34),"shot precision uses firing-time speed %s -> %s (angle %s)" % [speeds[0],speeds[1],observed.direction.angle_to(forward)])
	game.pause_game()
	state_before = game.shot_rng.state
	await frames(12)
	check.call(game.shot_rng.state == state_before,"pause leaves shot RNG frozen")
	game.show_menu()
	game.shot_resolved.disconnect(record)

func fire_toward(point: Vector3, speed: float) -> void:
	# Rotate the view so a known seeded offset reaches the real region. Center aim
	# is deliberately elsewhere; this tests the scattered ray, not the center ray.
	var probe := RandomNumberGenerator.new()
	probe.seed = 106
	var local := Direction.sample(Basis.IDENTITY,speed,probe)
	var desired: Vector3 = (point-game.player.camera.global_position).normalized()
	game.player.camera.global_basis = Basis(Quaternion(local,desired))
	game.player._horizontal_speed = speed*game.player.MAX_SPEED
	game.shot_rng.seed = 106
	game.weapon.advance_ms(float(game.weapon.get_data().interval_ms))
	check.call(game.weapon.try_fire() == "","controlled seeded shot fired")
