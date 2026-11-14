extends Node
## Opt-in integration checks: run the game with -- --smoke-test.
## Also runs from the Windows export. Optional --capture-dir=<absolute folder>
## saves rendered menu/buy/training/pause/results captures on graphical runs.

var checks: int = 0
var failures: int = 0
var game: Node3D
var capture_dir: String = ""


func check(condition: bool, label_text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("SMOKE FAIL: " + label_text)


func frames(count: int = 2) -> void:
	for _index: int in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame


func capture(label_text: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var error: Error = screenshot.save_png(capture_dir.path_join(label_text + ".png"))
	check(error == OK, "save " + label_text + " screenshot")


func shoot_at(target: Node3D, area: String) -> void:
	game.resume_game()
	game.weapon.advance_ms(float(game.weapon.get_data().interval_ms))
	game.player.camera.look_at(target.get_node(area).global_position, Vector3.UP)
	await frames()
	if DisplayServer.get_name() == "headless":
		game.pending_shots = 1
	else:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = get_viewport().get_visible_rect().size / 2
		Input.parse_input_event(click)
		click = click.duplicate()
		click.pressed = false
		Input.parse_input_event(click)
	await frames()


func run(controller: Node3D) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = controller
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty():
		var error: Error = DirAccess.make_dir_recursive_absolute(capture_dir)
		check(error == OK, "create screenshot directory")
	await frames(3)
	check(game.phase == "menu" and game.ui.overlay_kind == "menu", "initial menu")
	check(game.arena.targets.size() == 6, "six training targets exist")
	await capture("01-menu")

	# UI signals exercise the same routes used by visible menu/shop buttons.
	game.ui.start_requested.emit()
	check(game.phase == "buy" and game.remaining == 15.0, "start enters fifteen-second buy")
	check(game.money == 5000 and game.hp == 100, "round starting resources")
	check(game.weapon.current_weapon == "deagle" and game.weapon.mag == 7 and game.weapon.reserve == 14, "free default pistol and ammunition")
	check(game.weapon.try_fire(0.0) == "not_training" and game.shots == 0, "buy phase denies fire")
	game.ui.purchase_requested.emit("deagle")
	check(game.money == 5000 and game.bought, "confirming default pistol is free")
	game.start_round()
	await frames()
	await capture("02-buy")
	game.ui.purchase_requested.emit("ak47")
	check(game.money == 2300 and game.bought, "AK bought once")
	game.ui.purchase_requested.emit("m4a1")
	check(game.money == 2300 and game.weapon.current_weapon == "ak47", "repeated purchase cannot charge or replace")
	game.remaining = 0.001
	await frames()
	check(game.phase == "training" and game.remaining <= 60.0 and game.remaining > 59.0, "buy timeout automatically starts sixty-second training")
	check(game.weapon.mag == 25 and game.weapon.reserve == 50 and game.weapon.active, "training starts with chosen weapon three magazines")
	check(game.player.position.distance_to(Vector3(0, 0, 9)) < 0.1, "training resets player position")
	check(game.arena.targets[0].active and game.arena.targets[3].moving, "static and moving targets active")
	await frames(3)
	await capture("03-training")
	if DisplayServer.get_name() != "headless":
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(30, -10)
		motion.set_meta("smoke_motion", true)
		Input.flush_buffered_events()
		var yaw_before: float = game.player.rotation.y
		var pitch_before: float = game.player.camera.rotation.x
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		check(game.player.rotation.y < yaw_before and game.player.camera.rotation.x > pitch_before, "captured mouse motion controls first-person camera")
		await frames()
		game.player.reset_position()

	# Actual physics raycasts against separate body and head Area3Ds.
	var target: Node3D = game.arena.targets[1]
	await shoot_at(target, "Body")
	check(game.shots == 1 and game.hits == 1 and game.kills == 0, "body ray counts one shot and hit")
	check(target.hp == 100, "body ray causes no damage")
	await shoot_at(target, "Head")
	check(game.shots == 2 and game.hits == 2 and game.kills == 1 and game.headshots == 1, "head ray kills immediately")
	check(not target.alive, "killed target becomes inactive for hits")
	var duplicate: Dictionary = target.apply_hit(true)
	check(not duplicate.hit and not duplicate.killed, "dead target cannot be killed twice")
	check(game.accuracy() == 100.0 and game.headshot_rate() == 100.0, "statistics use actual shots and kills")

	# The existing front wall must occlude a target from an outside viewpoint.
	game.player.reset_position(Vector3(0, 0.02, 16))
	var untouched: Node3D = game.arena.targets[0]
	var hits_before_wall: int = game.hits
	await shoot_at(untouched, "Body")
	check(game.shots == 3 and game.hits == hits_before_wall and untouched.hp == 100, "wall blocks actual shot ray")
	game.player.reset_position()
	await frames()

	# Pause must freeze every simulation, while the HUD remains available.
	game.weapon.mag = 10
	game.weapon.reserve = 40
	check(game.weapon.start_reload(), "integration reload starts")
	target.reset_target()
	target.apply_hit(true)
	game.pause_game()
	var before_remaining: float = game.remaining
	var before_reload: float = game.weapon.reload_left_ms
	var before_clock: float = game.weapon.time_ms
	var before_position: Vector3 = game.arena.targets[3].position
	var before_player: Vector3 = game.player.position
	check(game.ui.overlay_kind == "pause" and game.ui.can_process(), "pause overlay remains interactive")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "pause releases mouse")
	await capture("04-pause")
	await get_tree().create_timer(1.1, true, false, true).timeout
	check(game.remaining == before_remaining and game.weapon.time_ms == before_clock, "pause freezes round and cooldown clocks")
	check(game.weapon.reload_left_ms == before_reload, "pause freezes reload")
	check(game.arena.targets[3].position == before_position and game.player.position == before_player, "pause freezes target and player movement")
	check(not target.alive, "pause freezes target respawn")
	game.ui.resume_requested.emit()
	check(not get_tree().paused, "resume button continues simulation")
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "resume captures mouse")
	await frames(135)
	check(target.alive and target.hp == 100, "target respawns at full state after resume")
	check(game.weapon.reload_left_ms < before_reload and game.remaining < before_remaining, "timers continue after resume")
	await frames(180)
	check(game.weapon.mag == 25 and game.weapon.reserve == 25 and not game.weapon.is_reloading(), "reload completes and conserves partial magazine")

	# Input actions drive real CharacterBody movement and a failed click is not queued.
	game.player.reset_position()
	Input.action_press("move_right")
	await frames(32)
	check(game.player.position.x > 0.2 and game.player.get_speed_ratio() > 0.34, "WASD action moves player above precision threshold")
	var shots_before_moving: int = game.shots
	game.pending_shots = 1
	await frames()
	check(game.shots == shots_before_moving and game.pending_shots == 0, "moving click rejected and consumed")
	Input.action_release("move_right")
	var velocity_before_counter: float = absf(game.player.velocity.x)
	Input.action_press("move_left")
	await frames(4)
	check(absf(game.player.velocity.x) < velocity_before_counter - 0.5, "opposite input actively brakes")
	Input.action_release("move_left")
	await frames(90)
	check(game.player.get_speed_ratio() < 0.34, "release eventually reaches precision threshold")
	check(game.shots == shots_before_moving, "rejected click never fires later")

	# Depletion must happen after synchronous hit/kill processing of the final shot.
	game.player.reset_position()
	game.weapon.reset("ak47")
	game.weapon.mag = 1
	game.weapon.reserve = 0
	target.reset_target()
	await frames()
	var kills_before_last: int = game.kills
	var shots_before_last: int = game.shots
	await shoot_at(target, "Head")
	check(game.phase == "results" and game.ui.overlay_kind == "results", "last bullet ends round")
	check(game.shots == shots_before_last + 1 and game.kills == kills_before_last + 1, "last bullet counted before results")
	check(game.weapon.mag == 0 and game.weapon.reserve == 0 and not game.weapon.active, "depleted weapon disabled")
	await capture("05-results")
	game.ui.start_requested.emit()
	check(game.phase == "buy" and game.money == 5000 and game.hp == 100 and not game.bought, "restart resets all resources")
	check(game.shots == 0 and game.hits == 0 and game.kills == 0 and game.headshots == 0, "restart clears score")
	check(game.weapon.current_weapon == "deagle" and game.weapon.mag == 7 and game.weapon.reserve == 14, "restart restores default weapon")
	game.remaining = 0.001
	await frames()
	check(game.phase == "training", "unconfirmed purchase retains free default")
	game.remaining = 0.001
	await frames()
	check(game.phase == "results", "training countdown ends round")
	check(game.accuracy() == 0.0 and game.headshot_rate() == 0.0, "empty round statistics are zero")
	await check_models_and_regions()
	Input.action_release("move_right")
	Input.action_release("move_left")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	# Let the audio thread release the last test shot before tearing down the game.
	game.shot_sound.stop()
	game.hit_sound.stop()
	await frames(12)
	print("%s: %d integration checks (%d failures)" % ["SMOKE PASS" if failures == 0 else "SMOKE FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func check_models_and_regions() -> void:
	game.start_round()
	game.begin_training()
	game.ui.toast.visible = false
	await frames(4)
	# Every rendered limb has a blocking ray region, and a body hit never kills.
	for target in game.arena.targets:
		for region in target._regions:
			var center: Vector3 = region.area.global_position
			var query := PhysicsRayQueryParameters3D.create(center + Vector3(0,0,0.7), center, 2)
			query.collide_with_areas = true
			var result := game.get_world_3d().direct_space_state.intersect_ray(query)
			check(not result.is_empty() and result.collider.get_meta("target") == target, "bone region blocks ray " + str(region.area.name))
		check(not target.apply_hit(false).killed and target.hp == 100, "non-head hit preserves full health")
	var moving_target: Node3D = game.arena.targets[3]
	for i in 8:
		await frames(4)
		var visual = moving_target._visuals
		var expected: Vector3 = visual.bone_point("Head").lerp(visual.bone_point("HeadTop_End"), 0.53)
		check(expected.distance_to(moving_target.get_node("Head").global_position) < 0.001, "moving head collider follows bone")
	await shoot_at(moving_target, "Head")
	check(not moving_target.alive, "moving headshot kills through real ray")
	for region in moving_target._regions:
		check(region.area.collision_layer == 0, "death immediately disables hit region")
	await frames(85)
	check(not moving_target.alive, "fall animation precedes one-second respawn")
	await capture("06-fall")
	await frames(45)
	check(moving_target.alive, "fall resets after one second")
	# Sample actual controller time, including all three reload lengths.
	for id: String in ["deagle", "ak47", "m4a1"]:
		game.weapon.reset(id)
		game.weapon.active = true
		game.player.set_weapon(id)
		var view = game.player.view
		check(view.animator.has_animation(view._clip), id + " has a skeletal reload clip")
		check(view.model.find_child("Muzzle", true, false) != null, id + " has muzzle marker")
		game._update_hud()
		await capture(id + "-idle")
		game.weapon.mag -= 1
		var old_mag: int = game.weapon.mag
		var old_reserve: int = game.weapon.reserve
		check(game.weapon.start_reload(), id + " manual reload starts")
		game.pause_game()
		game.ui.hide_overlay()
		var camera_before: Transform3D = game.player.camera.transform
		var duration: float = game.weapon.get_data().reload_ms
		var previous := 0.0
		for p: float in [0.0,0.2,0.35,0.60,0.84,0.999]:
			game.weapon.advance_ms((p-previous)*duration)
			previous = p
			game.player.update_reload(game.weapon.reload_left_ms, duration)
			await frames()
			check(game.weapon.mag == old_mag and game.weapon.reserve == old_reserve, id + " no ammunition before animation end")
			check(game.player.camera.transform == camera_before, id + " reload leaves aim unchanged")
			if p == 0.35 or p == 0.60:
				var contact: Vector3 = view.magazine.to_global(Vector3(-0.025,0,0))
				check(contact.distance_to(view.palm.global_position) < 0.002, id + " magazine stays in hand")
			await capture(id + "-reload-%03d" % int(p*100))
		game.weapon.advance_ms(duration*0.001+0.01)
		game.player.update_reload(game.weapon.reload_left_ms,duration)
		check(game.weapon.mag == old_mag+1 and game.weapon.reserve == old_reserve-1, id + " ammunition changes at completion")
		check(view.magazine.transform.is_equal_approx(view.magazine_home) and view.left_arm.visible and not view.reload_arms.visible, id + " final pose restored")
		game.resume_game()
		game.weapon.mag = 1
		game.weapon.try_fire(0.0)
		game.player.update_reload(game.weapon.reload_left_ms,duration)
		check(game.weapon.is_reloading() and view.reload_progress >= 0.0, id + " auto reload uses same visual")
		game.finish_round("test interruption")
		check(view.reload_progress < 0.0 and view.magazine.transform.is_equal_approx(view.magazine_home), id + " round end restores pose")
		game.start_round()
		game.begin_training()
		game.ui.toast.visible = false
	game.weapon.mag = 1
	if DisplayServer.get_name() == "headless":
		game.weapon.start_reload()
	else:
		var reload_key := InputEventKey.new()
		reload_key.keycode = KEY_R
		reload_key.physical_keycode = KEY_R
		reload_key.pressed = true
		Input.parse_input_event(reload_key)
		reload_key = reload_key.duplicate()
		reload_key.pressed = false
		Input.parse_input_event(reload_key)
	await frames(12)
	check(game.weapon.is_reloading(), "R input starts visual reload")
	if DisplayServer.get_name() == "headless":
		game.pause_game()
	else:
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		Input.parse_input_event(escape)
		escape = escape.duplicate()
		escape.pressed = false
		Input.parse_input_event(escape)
	await frames()
	check(get_tree().paused, "Esc input pauses game")
	var pose_before: Transform3D = game.player.view.magazine.transform
	var progress_before: float = game.player.view.reload_progress
	await get_tree().create_timer(0.15, true, false, true).timeout
	check(pose_before == game.player.view.magazine.transform and progress_before == game.player.view.reload_progress, "pause freezes visual reload pose")
	game.show_menu()
	check(game.player.view.reload_progress < 0.0, "menu restores reload pose")
