extends Node3D

signal phase_changed(phase: String)
signal score_changed

const Rules = preload("res://scripts/game_rules.gd")
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
var money := 5000
var hp := 100
var armor := 0
var bought := false
var shots := 0
var hits := 0
var kills := 0
var headshots := 0
var pending_shots := 0
var was_shop_open := false
var shot_sound: AudioStreamPlayer
var hit_sound: AudioStreamPlayer
var sounds: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 10
	DisplayServer.window_set_min_size(Vector2i(960, 540))
	_setup_inputs()
	arena = Arena.new()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	player = PlayerController.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.reset_position()
	weapon = WeaponController.new()
	weapon.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(weapon)
	weapon.fired.connect(_on_fired)
	weapon.depleted.connect(func(): finish_round("弹药耗尽 · 本轮结束"))
	ui = GameHUD.new()
	add_child(ui)
	ui.start_requested.connect(start_round)
	ui.purchase_requested.connect(confirm_purchase)
	ui.shop_closed.connect(close_shop)
	ui.resume_requested.connect(resume_game)
	ui.menu_requested.connect(show_menu)
	ui.quit_requested.connect(func(): get_tree().quit())
	_setup_audio()
	show_menu()
	# A shipped, opt-in smoke check exercises this exact exported build.
	if "--smoke-test" in OS.get_cmdline_user_args():
		var smoke = load("res://tests/game_smoke.gd").new()
		add_child(smoke)
		smoke.call_deferred("run", self)

func _setup_inputs() -> void:
	var bindings := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "reload": KEY_R, "shop": KEY_B, "interact": KEY_E}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = bindings[action]
			InputMap.action_add_event(action, event)

func show_menu() -> void:
	get_tree().paused = false
	phase = "menu"
	pending_shots = 0
	player.active = false
	weapon.active = false
	arena.set_active(false)
	player.reset_position()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_menu()
	phase_changed.emit(phase)

func start_round() -> void:
	get_tree().paused = false
	phase = "buy"
	remaining = 15.0
	money = 5000
	hp = 100
	armor = 0
	bought = false
	shots = 0
	hits = 0
	kills = 0
	headshots = 0
	pending_shots = 0
	weapon.reset("deagle")
	weapon.active = false
	player.set_weapon("deagle")
	player.reset_position()
	arena.reset_targets()
	arena.set_active(false)
	open_shop()
	_update_hud()
	phase_changed.emit(phase)

func confirm_purchase(weapon_id: String, wants_armor: bool) -> void:
	if phase != "buy" or get_tree().paused:
		return
	var result: Dictionary = Rules.purchase(weapon_id, wants_armor, money, bought)
	if not result.ok:
		ui.notify("装备已确认，本轮不能再次购买。")
		return
	money = result.money
	armor = result.armor
	bought = true
	weapon.reset(result.weapon)
	player.set_weapon(result.weapon)
	close_shop()
	ui.notify("装备已确认 · 剩余 $%d · 左侧装置可测试护甲" % money, 3.0)

func open_shop() -> void:
	if phase != "buy":
		return
	player.active = false
	pending_shots = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_buy(bought, weapon.current_weapon, armor, money)

func close_shop() -> void:
	ui.hide_overlay()
	player.active = phase == "buy" or phase == "training"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func begin_training() -> void:
	phase = "training"
	remaining = 60.0
	hp = 100
	armor = 100 if armor > 0 else 0
	shots = 0
	hits = 0
	kills = 0
	headshots = 0
	pending_shots = 0
	weapon.reset(weapon.current_weapon)
	weapon.active = true
	player.reset_position()
	player.active = true
	arena.reset_targets()
	arena.set_active(true)
	ui.hide_overlay()
	ui.notify("训练开始 · 速度比低于 0.34 时点击开火", 3.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	phase_changed.emit(phase)

func finish_round(reason: String) -> void:
	if phase != "training":
		return
	phase = "results"
	pending_shots = 0
	weapon.active = false
	player.active = false
	arena.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_results({"reason": reason, "kills": kills, "shots": shots, "hits": hits, "headshots": headshots, "accuracy": accuracy(), "headshot_rate": headshot_rate(), "weapon": weapon.get_data().name})
	phase_changed.emit(phase)

func accuracy() -> float:
	return 100.0 * hits / shots if shots > 0 else 0.0

func headshot_rate() -> float:
	return 100.0 * headshots / kills if kills > 0 else 0.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if phase == "buy" or phase == "training":
			if get_tree().paused:
				resume_game()
			else:
				pause_game()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or (phase != "buy" and phase != "training"):
		return
	if event.is_action_pressed("shop") and phase == "buy":
		if ui.overlay_kind == "buy":
			close_shop()
		else:
			open_shop()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("interact") and phase == "buy":
		test_armor()
	if event.is_action_pressed("reload") and phase == "training":
		if weapon.start_reload():
			ui.notify("换弹中 · 可以继续移动", 1.0)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if phase == "training":
			# Reject at click time as well as at the next physics raycast. A click
			# during cooldown/movement must never become a delayed valid shot.
			var error: String = weapon.fire_error(player.get_speed_ratio())
			if error.is_empty():
				pending_shots += 1
			else:
				ui.notify(_fire_error(error), 0.7)
		else:
			ui.notify("准备阶段 · 倒计时结束后可开火")

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if phase == "buy" or phase == "training":
		remaining = maxf(0.0, remaining - delta)
		if remaining <= 0.0:
			if phase == "buy":
				begin_training()
			else:
				finish_round("时间到 · 本轮结束")
		var attempts := pending_shots
		pending_shots = 0
		for _attempt in range(attempts):
			if phase == "training":
				var error: String = weapon.try_fire(player.get_speed_ratio())
				if not error.is_empty():
					ui.notify(_fire_error(error), 0.7)
		_update_hud()

func _fire_error(error: String) -> String:
	match error:
		"moving", "precision_threshold", "not_accurate", "speed_too_high": return "移动中，无法精准开火"
		"reloading": return "换弹中，无法开火"
		"cooldown", "fire_rate_cooldown": return "射击冷却中"
		"mag_empty", "empty": return "弹夹已空"
	return "暂时无法开火：" + error

func _on_fired(damage: int) -> void:
	shots += 1
	player.play_shot()
	shot_sound.stream = sounds[weapon.current_weapon]
	shot_sound.play()
	var origin: Vector3 = player.camera.global_position
	var endpoint: Vector3 = origin - player.camera.global_basis.z * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 3)
	query.collide_with_areas = true
	query.exclude = [player.get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var collider: Object = result.collider
		if collider.has_meta("target"):
			var target: Node3D = collider.get_meta("target")
			var headshot: bool = collider.get_meta("headshot", false)
			var hit_result: Dictionary = target.apply_hit(damage, headshot)
			if hit_result.hit:
				hits += 1
				if hit_result.killed:
					kills += 1
					if headshot:
						headshots += 1
				ui.show_hit(headshot, hit_result.killed)
				hit_sound.play()
	score_changed.emit()

func test_armor() -> void:
	if phase != "buy":
		return
	if player.position.distance_to(Vector3(-8, 0, 8)) > 3.0:
		ui.notify("靠近左侧青色测试装置后按 E", 2.0)
		return
	var result: Dictionary = Rules.damage_result(hp, armor, 40)
	ui.notify("伤害测试 40：护甲 %d → %d，生命 %d → %d（已恢复）" % [armor, result.armor, hp, result.hp], 4.0)
	# Preview the exact damage calculation, then preserve the purchased loadout.
	hp = 100
	armor = 100 if armor > 0 else 0

func pause_game() -> void:
	was_shop_open = ui.overlay_kind == "buy"
	pending_shots = 0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_pause()

func resume_game() -> void:
	get_tree().paused = false
	if was_shop_open and phase == "buy":
		open_shop()
	else:
		close_shop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(ui):
		if (phase == "buy" or phase == "training") and not get_tree().paused:
			pause_game()

func _update_hud() -> void:
	var speed: float = player.get_speed_ratio()
	var permission := "可以精准开火"
	var ready := true
	if phase != "training":
		permission = "准备阶段 · 暂不可开火"
		ready = false
	elif weapon.is_reloading():
		permission = "换弹中  %.1f s" % (weapon.reload_left_ms / 1000.0)
		ready = false
	elif speed >= 0.34:
		permission = "移动中 · 反向按键急停"
		ready = false
	elif weapon.time_ms - weapon.last_fire_ms < weapon.get_data().interval_ms:
		permission = "射击冷却中"
		ready = false
	elif weapon.mag <= 0:
		permission = "弹夹已空"
		ready = false
	ui.update_status({"phase": phase, "remaining": remaining, "kills": kills, "accuracy": accuracy(), "weapon": weapon.get_data().name, "mag": weapon.mag, "reserve": weapon.reserve, "hp": hp, "armor": armor, "speed": speed, "permission": permission, "ready": ready})

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
