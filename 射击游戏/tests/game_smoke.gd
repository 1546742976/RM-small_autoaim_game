extends Node
## Opt-in integration checks: run the game with -- --smoke-test.
## Also runs from the Windows export. Optional --capture-dir=<absolute folder>
## saves rendered menu/setup/training/pause/results captures on graphical runs.

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
	if game.ui.transition != null and game.ui.transition.is_running():
		await game.ui.transition.finished
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

	game.ui.action_buttons.help.pressed.emit()
	check(game.ui.overlay_kind == "help" and not get_tree().paused, "menu help preserves unpaused state")
	await capture("01-help")
	game.ui.close_help()
	game.ui.action_buttons.start.pressed.emit()
	check(game.phase == "setup" and game.ui.overlay_kind == "setup", "start opens untimed setup")
	check(game.selected_map == "old_town" and game.selected_weapon == "deagle", "first launch defaults")
	await capture("02-setup")
	game.ui.map_buttons.training_hall.pressed.emit()
	game.ui.weapon_buttons.ak47.pressed.emit()
	check(game.selected_map == "training_hall" and game.selected_weapon == "ak47", "map and weapon cards select loadout")
	await frames(3)
	game.ui.weapon_buttons.m4a1.grab_focus()
	Input.flush_buffered_events()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	Input.flush_buffered_events()
	enter = enter.duplicate()
	enter.pressed = false
	Input.parse_input_event(enter)
	Input.flush_buffered_events()
	await frames(3)
	check(game.selected_weapon == "m4a1", "keyboard Enter activates weapon card")
	game.ui.weapon_buttons.ak47.pressed.emit()
	game.ui.action_buttons.launch.pressed.emit()
	check(game.phase == "countdown" and game.remaining == 3.0, "launch starts three-second countdown")
	check(game.weapon.try_fire() == "not_training" and not game.weapon.start_reload(), "countdown blocks fire and reload")
	var countdown_position: Vector3 = game.player.position
	Input.action_press("move_forward")
	await frames(10)
	Input.action_release("move_forward")
	check(game.player.position.is_equal_approx(countdown_position) and not game.arena.targets[3].active, "countdown blocks movement and targets")
	await capture("02-countdown")
	game.pause_game()
	var frozen_countdown: float = game.remaining
	game.ui.show_help()
	await frames(8)
	check(game.remaining == frozen_countdown and get_tree().paused, "countdown and help freeze simulation")
	game.ui.close_help()
	check(game.ui.overlay_kind == "pause" and get_tree().paused, "help returns to pause without resuming")
	game.resume_game()
	check(game.ui.overlay_kind == "countdown", "resume restores countdown overlay")
	game.remaining = 0.001
	await frames()
	check(game.phase == "training" and game.remaining > 59.0, "countdown starts sixty-second training")
	check(game.weapon.mag == 25 and game.weapon.reserve == 50 and game.weapon.active, "chosen weapon starts with three magazines")
	check(game.player.position.distance_to(game.arena.get_spawn().origin) < 0.1, "map provides player spawn")
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

	# Input actions drive real movement; moving shots now fire with spread.
	game.player.reset_position()
	Input.action_press("move_right")
	await frames(32)
	check(game.player.position.x > 0.2 and game.player.get_speed_ratio() > 0.34, "WASD action moves player above precision threshold")
	var shots_before_moving: int = game.shots
	if DisplayServer.get_name() == "headless":
		game.pending_shots = 1
	else:
		var moving_click := InputEventMouseButton.new()
		moving_click.button_index = MOUSE_BUTTON_LEFT
		moving_click.pressed = true
		Input.parse_input_event(moving_click)
		moving_click = moving_click.duplicate()
		moving_click.pressed = false
		Input.parse_input_event(moving_click)
		Input.flush_buffered_events()
	await frames()
	check(game.shots == shots_before_moving + 1 and game.pending_shots == 0, "moving shot fires exactly once")
	check(not game.ui.crosshair.accurate, "moving reticle indicates spread")
	Input.action_release("move_right")
	var velocity_before_counter: float = absf(game.player.velocity.x)
	Input.action_press("move_left")
	await frames(4)
	check(absf(game.player.velocity.x) < velocity_before_counter - 0.5, "opposite input actively brakes")
	Input.action_release("move_left")
	await frames(90)
	check(game.player.get_speed_ratio() < 0.34, "release eventually reaches precision threshold")
	check(game.shots == shots_before_moving + 1, "single moving click never fires later")
	check(game.ui.crosshair.accurate, "counter-strafe restores accurate reticle")

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
	game.ui.action_buttons.replay.pressed.emit()
	check(game.phase == "countdown" and game.selected_map == "training_hall", "replay keeps map and enters countdown")
	check(game.shots == 0 and game.hits == 0 and game.kills == 0 and game.headshots == 0, "restart clears scores")
	check(game.weapon.current_weapon == "ak47" and game.weapon.mag == 25 and game.weapon.reserve == 50, "replay restores selected weapon ammo")
	game.remaining = 0.001
	await frames()
	game.remaining = 0.001
	await frames()
	check(game.phase == "results", "training countdown ends round")
	check(game.accuracy() == 0.0 and game.headshot_rate() == 0.0, "empty round statistics are zero")
	await check_models_and_regions()
	await check_maps_and_loadouts()
	var spread_checks = preload("res://tests/spread_checks.gd").new()
	add_child(spread_checks)
	await spread_checks.run(game,check)
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
	equip("training_hall","ak47")
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
		game.weapon.try_fire()
		game.player.update_reload(game.weapon.reload_left_ms,duration)
		check(game.weapon.is_reloading() and view.reload_progress >= 0.0, id + " auto reload uses same visual")
		game.finish_round("test interruption")
		check(view.reload_progress < 0.0 and view.magazine.transform.is_equal_approx(view.magazine_home), id + " round end restores pose")
		equip("training_hall","ak47")
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

func equip(map_id: String, weapon_id: String) -> void:
	game.show_setup()
	game.ui._select(map_id,weapon_id)
	game.start_round()
	game.begin_training()

func check_maps_and_loadouts() -> void:
	for map_id: String in ["old_town","training_hall"]:
		for id: String in ["deagle","ak47","m4a1"]:
			equip(map_id,id)
			await frames(4)
			check(game.arena.get_child_count() == 1 and game.arena.targets.size() == 6, map_id+" exactly one map and six targets")
			check(game.weapon.current_weapon == id and game.weapon.mag == game.weapon.get_data().mag_size, map_id+" free selection "+id)
			check(game.player.position.distance_to(game.arena.get_spawn().origin) < 0.1, map_id+" correct spawn")
			game._select_loadout("old_town","m4a1")
			check(game.selected_map == map_id and game.selected_weapon == id, "training locks loadout")
			game.pause_game()
			check(not game.ui.hud.visible, "pause hides minimal HUD")
			game.resume_game()
			var hud_text := gather_text(game.ui.root)
			for forbidden in ["生命","速度","击杀","命中率","购买","爆头","WASD"]:
				check(not forbidden in hud_text,"minimal gameplay HUD omits "+forbidden)
			game.finish_round("时间到")
			game.ui.replay_requested.emit()
			check(game.phase == "countdown" and game.weapon.mag == game.weapon.get_data().mag_size, "replay fully resets "+map_id+id)
			game.show_menu()
			check(game.phase == "menu" and not get_tree().paused and not game.player.active, "menu stops round")
		equip(map_id,"ak47")
		await frames(5)
		await capture(map_id+"-training")
		# All visible targets can be shot from designed clear sightlines.
		for i in 6:
			game.player.reset_position(game.arena.map_root.test_views[i])
			await frames()
			var target: Node3D = game.arena.targets[i]
			var before_hits: int = game.hits
			await shoot_at(target,"Body")
			check(game.hits == before_hits+1 and target.alive and target.hp == 100, map_id+" reachable nonlethal body "+str(i))
			await shoot_at(target,"Head")
			check(not target.alive, map_id+" reachable head "+str(i))
		# Check the full swept path against world solids, above the floor.
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.34
		capsule.height = 1.7
		for target in game.arena.targets:
			for step in 17:
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = capsule
				q.collision_mask = 1
				q.transform.origin = target.path_start.lerp(target.path_end,float(step)/16)+Vector3(0,0.95,0)
				check(game.get_world_3d().direct_space_state.intersect_shape(q).is_empty(),map_id+" target route clears buildings")
		# Walk, using CharacterBody collision, around the complete route.
		equip(map_id,"ak47")
		await frames(3)
		var path: Array = game.arena.map_root.route
		game.player.reset_position(path[0])
		for index in range(1,path.size()):
			var destination: Vector3 = path[index]
			var direction: Vector3 = destination-game.player.position
			game.player.rotation.y = atan2(-direction.x,-direction.z)
			Input.action_press("move_forward")
			var ticks := 0
			while Vector2(game.player.position.x-destination.x,game.player.position.z-destination.z).length()>0.6 and ticks<1100:
				await frames(1)
				ticks += 1
			Input.action_release("move_forward")
			await frames(48)
			check(ticks<1100 and game.player.position.y>-0.1 and game.player.position.y<0.1,map_id+" walkable flat loop segment "+str(index))
		game.player.reset_position(Vector3(0,0.02,26 if map_id == "old_town" else 16))
		var before: int = game.hits
		await shoot_at(game.arena.targets[0],"Body")
		check(game.hits == before,map_id+" boundary blocks bullets")
		game.show_setup()
		await frames()
		check_ui_content()
	game.show_menu()

func check_ui_content() -> void:
	var all_text := gather_text(game.ui.root)
	for forbidden in ["生命","速度比","命中率","击杀","资金","价格","ms","购买","爆头率"]:
		check(not forbidden in all_text,"setup removes irrelevant display "+forbidden)
	var bounds := get_viewport().get_visible_rect()
	for button in game.ui.map_buttons.values()+game.ui.weapon_buttons.values()+game.ui.action_buttons.values():
		check(bounds.encloses(button.get_global_rect()),"setup control stays within window")
	check(get_viewport().gui_get_focus_owner() != null,"keyboard focus exists")

func gather_text(node: Node) -> String:
	var text := ""
	if node is Control and not node.is_visible_in_tree(): return text
	if node is Label or node is Button: text = node.text+" "
	for child in node.get_children(): text += gather_text(child)
	return text
