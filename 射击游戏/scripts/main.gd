extends Node3D
signal phase_changed(phase: String)
signal score_changed
signal shot_resolved(origin: Vector3, direction: Vector3, collision: Dictionary)
const Rules = preload("res://scripts/game_rules.gd")
const ShotDirection = preload("res://scripts/shot_direction.gd")
const WeaponController = preload("res://scripts/weapon_controller.gd")
const PlayerController = preload("res://scripts/player_controller.gd")
const Arena = preload("res://scripts/arena.gd")
const GameHUD = preload("res://scripts/game_hud.gd")
var arena: Node3D
var player: CharacterBody3D
var weapon: Node
var ui: CanvasLayer
var phase := "menu"
var remaining := 0.0
var selected_map := "old_town"
var selected_weapon := "deagle"
var shots := 0
var hits := 0
var kills := 0
var headshots := 0
var pending_shots := 0
var manual_fire_held := false
var _left_button_down := false
var round_id := 0
var control_bridge: Node
var shot_rng := RandomNumberGenerator.new()
var shot_sound: AudioStreamPlayer
var hit_sound: AudioStreamPlayer
var sounds: Dictionary = {}
var duel: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 10
	shot_rng.randomize()
	DisplayServer.window_set_min_size(Vector2i(960,540))
	_setup_inputs()
	arena = Arena.new()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	player = PlayerController.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.control_changed.connect(clear_manual_fire)
	weapon = WeaponController.new()
	weapon.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(weapon)
	weapon.fired.connect(_on_fired)
	weapon.reload_started.connect(clear_manual_fire)
	weapon.depleted.connect(func():
		if not is_instance_valid(duel): finish_round("弹药耗尽"))
	ui = GameHUD.new()
	add_child(ui)
	ui.setup_requested.connect(show_setup)
	ui.selection_changed.connect(_select_loadout)
	ui.launch_requested.connect(start_round)
	ui.replay_requested.connect(start_round)
	ui.resume_requested.connect(resume_game)
	ui.menu_requested.connect(show_menu)
	ui.quit_requested.connect(func(): get_tree().quit())
	_setup_audio()
	show_menu()
	if "--control" in OS.get_cmdline_user_args():
		control_bridge = load("res://scripts/control_bridge.gd").new()
		add_child(control_bridge)
		if not control_bridge.configure(self):
			get_tree().quit(1)
			return
	if "--assessment-checks" in OS.get_cmdline_user_args() or "--assessment-demo" in OS.get_cmdline_user_args() or "--assessment-benchmark" in OS.get_cmdline_user_args():
		var checks=load("res://tests/assessment_checks.gd").new()
		add_child(checks)
		checks.call_deferred("run",self)
	elif "--smoke-test" in OS.get_cmdline_user_args():
		var smoke = load("res://tests/game_smoke.gd").new()
		add_child(smoke)
		smoke.call_deferred("run",self)
	elif "--control-smoke" in OS.get_cmdline_user_args():
		var checks = load("res://tests/control_checks.gd").new()
		add_child(checks)
		checks.call_deferred("run",self)
	elif "--input-checks" in OS.get_cmdline_user_args():
		var checks = load("res://tests/input_checks.gd").new()
		add_child(checks)
		checks.call_deferred("run",self)
	elif "--viewmodel-checks" in OS.get_cmdline_user_args():
		var checks = load("res://tests/viewmodel_checks.gd").new()
		add_child(checks)
		checks.call_deferred("run",self)
	elif "--reload-showcase" in OS.get_cmdline_user_args() or "--viewmodel-benchmark" in OS.get_cmdline_user_args():
		var showcase = load("res://tests/reload_showcase.gd").new()
		add_child(showcase)
		showcase.call_deferred("run",self)
	elif "--control-fixture" in OS.get_cmdline_user_args():
		var fixture = load("res://tests/control_fixture.gd").new()
		add_child(fixture)
		fixture.call_deferred("run",self)
	elif "--spread-demo" in OS.get_cmdline_user_args():
		var demo = load("res://tests/spread_demo.gd").new()
		add_child(demo)
		demo.call_deferred("run",self)
	elif "--showcase" in OS.get_cmdline_user_args() or "--benchmark" in OS.get_cmdline_user_args() or "--previews" in OS.get_cmdline_user_args():
		var presentation = load("res://tests/presentation_capture.gd").new()
		add_child(presentation)
		presentation.call_deferred("run",self)

func _setup_inputs() -> void:
	var bindings := {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"reload":KEY_R}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = bindings[action]
			InputMap.action_add_event(action,event)

func _reset_player() -> void:
	var spawn: Transform3D = arena.get_spawn()
	player.reset_position(spawn.origin,spawn.basis.get_euler().y)

func _stop_play() -> void:
	if is_instance_valid(duel): duel.stop()
	if is_instance_valid(control_bridge): control_bridge.invalidate("state_changed")
	get_tree().paused = false
	clear_manual_fire()
	player.active = false
	weapon.active = false
	arena.set_active(false)
	player.update_reload(0,1)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_menu() -> void:
	_stop_play()
	phase = "menu"
	_reset_player()
	player.weapon_root.hide()
	ui.show_menu()
	phase_changed.emit(phase)

func show_setup() -> void:
	_stop_play()
	phase = "setup"
	player.weapon_root.hide()
	ui.show_setup(selected_map,selected_weapon)
	phase_changed.emit(phase)

func _select_loadout(map_id: String, weapon_id: String) -> void:
	if phase != "setup": return
	selected_map = map_id
	selected_weapon = weapon_id

func start_round() -> void:
	if phase != "setup" and phase != "results": return
	_stop_play()
	if is_instance_valid(duel):
		remove_child(duel)
		duel.free()
	round_id += 1
	arena.load_map(selected_map)
	arena.reset_targets()
	weapon.reset(selected_weapon)
	weapon.active = false
	player.set_weapon(selected_weapon)
	_reset_player()
	if selected_map=="assessment_yard":
		duel=preload("res://scripts/assessment_duel.gd").new()
		add_child(duel)
		duel.initialize(self)
	shots = 0
	hits = 0
	kills = 0
	headshots = 0
	remaining = 3.0
	phase = "countdown"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.show_countdown(3)
	phase_changed.emit(phase)

func begin_training() -> void:
	if phase != "countdown": return
	phase = "training"
	remaining = 60.0
	weapon.active = true
	player.active = true
	arena.set_active(true)
	ui.hide_overlay()
	_update_hud()
	phase_changed.emit(phase)

func finish_round(reason: String) -> void:
	if phase != "training": return
	_stop_play()
	phase = "results"
	player.weapon_root.hide()
	ui.show_results({"reason":reason,"kills":kills,"accuracy":accuracy(),"duel":is_instance_valid(duel)})
	phase_changed.emit(phase)

func accuracy() -> float:
	return 100.0 * hits / shots if shots > 0 else 0.0

func headshot_rate() -> float:
	return 100.0 * headshots / kills if kills > 0 else 0.0

func _input(event: InputEvent) -> void:
	# Releases must be observed even when a UI control consumes the event.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_left_button_down = false
		manual_fire_held = false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if ui.overlay_kind == "help":
			ui.close_help()
		elif phase == "setup":
			show_menu()
		elif phase == "countdown" or phase == "training":
			if get_tree().paused: resume_game()
			else: pause_game()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		set_primary_pressed(event.pressed)
	if get_tree().paused or phase != "training": return
	if player.remote_controlled: return
	if event.is_action_pressed("reload"): weapon.start_reload()

func set_primary_pressed(pressed: bool) -> void:
	if not pressed:
		_left_button_down = false
		manual_fire_held = false
		return
	if _left_button_down: return
	_left_button_down = true
	if get_tree().paused or phase != "training" or player.remote_controlled: return
	var error: String = weapon.fire_error()
	# Holding is ongoing intent, not a queue of future shots. A reload never arms it.
	manual_fire_held = weapon.current_weapon in ["ak47", "m4a1"] and error in ["", "cooldown"]
	if error.is_empty(): pending_shots += 1

func clear_manual_fire() -> void:
	manual_fire_held = false
	pending_shots = 0

func _physics_process(delta: float) -> void:
	if get_tree().paused: return
	if phase == "countdown":
		remaining = maxf(0,remaining-delta)
		ui.update_countdown(ceili(remaining))
		if remaining <= 0: begin_training()
	elif phase == "training":
		remaining = maxf(0,remaining-delta)
		if remaining <= 0 and not is_instance_valid(duel):
			finish_round("时间到")
			return
		if is_instance_valid(duel): duel.step(delta)
		if is_instance_valid(control_bridge): control_bridge.apply_pending()
		var attempts := pending_shots
		pending_shots = 0
		for i in attempts:
			if phase == "training": weapon.try_fire()
		if phase == "training" and manual_fire_held and not player.remote_controlled and attempts == 0:
			weapon.try_fire()
		if is_instance_valid(duel) and phase=="training": duel.resolve()
		if phase == "training":
			player.update_reload(weapon.reload_left_ms,float(weapon.get_data().reload_ms),weapon.reload_kind,weapon.reload_serial)
			_update_hud()

func _on_fired() -> void:
	shots += 1
	player.play_shot()
	shot_sound.stream = sounds[weapon.current_weapon]
	shot_sound.play()
	var origin: Vector3 = player.camera.global_position
	var direction := ShotDirection.sample(player.camera.global_basis, player.get_speed_ratio(), shot_rng)
	var endpoint: Vector3 = origin + direction * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin,endpoint,3)
	query.collide_with_areas = true
	query.exclude = [player.get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty() and result.collider.has_meta("target"):
		var target: Node3D = result.collider.get_meta("target")
		var headshot: bool = result.collider.get_meta("headshot",false)
		var hit_result: Dictionary = target.apply_hit(headshot)
		if hit_result.hit:
			hits += 1
			if hit_result.killed:
				kills += 1
				if headshot: headshots += 1
			ui.show_hit(headshot,hit_result.killed)
			hit_sound.play()
	shot_resolved.emit(origin,direction,result)
	score_changed.emit()

func pause_game() -> void:
	if phase != "countdown" and phase != "training": return
	if is_instance_valid(control_bridge): control_bridge.invalidate("paused")
	clear_manual_fire()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_pause()

func resume_game() -> void:
	if get_tree().paused and is_instance_valid(control_bridge): control_bridge.invalidate("resumed")
	get_tree().paused = false
	if phase != "countdown" and phase != "training": return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if phase == "countdown": ui.show_countdown(ceili(remaining))
	else: ui.hide_overlay()

func _notification(what: int) -> void:
	for flag in ["--assessment-checks","--assessment-demo","--assessment-benchmark"]:
		if flag in OS.get_cmdline_user_args(): return
	if is_instance_valid(player) and player.remote_controlled: return
	for flag in ["--smoke-test","--showcase","--benchmark","--previews","--spread-demo","--control-smoke","--control-fixture","--input-checks","--viewmodel-checks","--reload-showcase","--viewmodel-benchmark"]:
		if flag in OS.get_cmdline_user_args(): return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(ui) and not get_tree().paused:
		pause_game()

func _update_hud() -> void:
	ui.update_status({"remaining":remaining,"mag":weapon.mag,"reserve":weapon.reserve,
		"ready":weapon.fire_error().is_empty(),"accurate":ShotDirection.is_accurate(player.get_speed_ratio()),"reloading":weapon.is_reloading()})

func _setup_audio() -> void:
	shot_sound = AudioStreamPlayer.new()
	shot_sound.volume_db = -17
	shot_sound.max_polyphony = 4
	add_child(shot_sound)
	hit_sound = AudioStreamPlayer.new()
	hit_sound.volume_db = -22
	add_child(hit_sound)
	for id in ["deagle", "ak47", "m4a1"]:
		sounds[id] = _tone(100.0 if id == "deagle" else 160.0, 0.10, true)
	hit_sound.stream = _tone(1300.0, 0.065, false)

func _tone(frequency: float, duration: float, noise: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count := int(duration * stream.mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in count:
		var envelope: float = pow(1.0 - float(i) / count, 3.0)
		var sample: float = sin(TAU * frequency * float(i) / stream.mix_rate)
		if noise:
			sample = sample * 0.3 + rng.randf_range(-0.7, 0.7)
		bytes.encode_s16(i * 2, int(sample * envelope * 24000))
	stream.data = bytes
	return stream
