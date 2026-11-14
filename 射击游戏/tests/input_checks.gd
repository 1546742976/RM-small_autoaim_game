extends Node
## Real game input/ray/statistics checks, with a deterministic 120 Hz clock.
## Run with -- --input-checks. No input-only alternative weapon implementation.

var game: Node3D
var checks := 0
var failures := 0
var fired_at: Array[float] = []

func check(ok: bool, label_text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("INPUT FAIL: " + label_text)

func button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = get_viewport().get_visible_rect().size / 2.0
	game._input(event)
	if DisplayServer.get_name() == "headless":
		# The headless display cannot capture a mouse. Exercise the same mapped
		# primary-button handler; graphical runs also cover the capture/input gate.
		game.set_primary_pressed(pressed)
	else:
		game._unhandled_input(event)

func ticks(count: int = 1) -> void:
	for _i in count:
		game.weapon.advance_ms(1000.0 / 120.0)
		game._physics_process(1.0 / 120.0)

func prepare(map_id: String, weapon_id: String) -> void:
	button(false)
	game.show_setup()
	game._select_loadout(map_id, weapon_id)
	game.start_round()
	game.begin_training()
	game.player.active = false
	game.arena.set_active(false)
	fired_at.clear()

func shot_record() -> void:
	fired_at.append(game.weapon.time_ms)

func run(controller: Node3D) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = controller
	await get_tree().process_frame
	game.set_physics_process(false)
	game.weapon.set_physics_process(false)
	game.player.set_physics_process(false)
	game.weapon.fired.connect(shot_record)
	for map_id: String in ["old_town", "training_hall"]:
		for weapon_id: String in ["deagle", "ak47", "m4a1"]:
			prepare(map_id, weapon_id)
			var label_text := map_id + " / " + weapon_id
			if DisplayServer.get_name() != "headless":
				check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, label_text + " captured input")
			button(true)
			ticks(55)
			check(game.shots == (1 if weapon_id == "deagle" else 5), label_text + " hold respects fire mode")
			for i in range(1, fired_at.size()):
				check(fired_at[i] - fired_at[i - 1] + 0.000001 >= float(game.weapon.get_data().interval_ms), label_text + " no early shot")
			button(false)
			var stopped: int = game.shots
			ticks(50)
			check(game.shots == stopped, label_text + " release stops continuous fire")
			button(true)
			button(false)
			ticks()
			check(game.shots == stopped + 1, label_text + " same-frame tap is one shot")
			stopped = game.shots
			button(true)
			button(false)
			ticks(50)
			check(game.shots == stopped, label_text + " rejected cooldown tap is not queued")
			button(true)
			ticks()
			button(false)
			stopped = game.shots
			button(true)
			ticks()
			check(game.shots == stopped, label_text + " held press during cooldown cannot fire early")
			ticks(30)
			check(game.shots == stopped if weapon_id == "deagle" else game.shots > stopped, label_text + " only rifles retain held intent through cooldown")
			button(false)
			game.weapon.advance_ms(float(game.weapon.get_data().interval_ms))

			button(true)
			ticks()
			stopped = game.shots
			check(game.weapon.start_reload(), label_text + " manual reload starts")
			check(game.weapon.reload_kind == "tactical" and not game.manual_fire_held, label_text + " partial reload cancels hold")
			var serial: int = game.weapon.reload_serial
			button(false)
			button(true)
			check(not game.manual_fire_held and game.pending_shots == 0, label_text + " press during reload is discarded")
			game.weapon.advance_ms(float(game.weapon.get_data().reload_ms))
			ticks(40)
			check(game.shots == stopped and game.weapon.reload_serial == serial, label_text + " reload completion never resumes hold")
			button(false)
			button(true)
			ticks()
			check(game.shots == stopped + 1, label_text + " fresh post-reload press fires")

			button(false)
			game.weapon.mag = 1
			game.weapon.advance_ms(float(game.weapon.get_data().interval_ms))
			button(true)
			ticks()
			stopped = game.shots
			check(game.weapon.is_reloading() and game.weapon.reload_kind == "empty", label_text + " last magazine shot starts empty animation")
			check(not game.manual_fire_held, label_text + " automatic reload cancels hold")
			game.weapon.advance_ms(float(game.weapon.get_data().reload_ms))
			ticks(40)
			check(game.shots == stopped, label_text + " automatic reload requires fresh press")

			button(false)
			button(true)
			game.pause_game()
			check(not game.manual_fire_held and game.pending_shots == 0, label_text + " pause clears pending and held input")
			game.resume_game()
			ticks(40)
			check(game.shots == stopped, label_text + " resume does not inherit hold")
			button(false)
			button(true)
			game.player.remote_controlled = true
			check(not game.manual_fire_held and game.pending_shots == 0, label_text + " takeover clears manual intent")
			button(false)
			button(true)
			ticks(40)
			check(game.shots == stopped, label_text + " remote ownership blocks manual fire")
			game.player.remote_controlled = false
			ticks(40)
			check(game.shots == stopped, label_text + " release of ownership cannot inherit hold")
			button(false)
			button(true)
			ticks()
			check(game.shots == stopped + 1, label_text + " fresh manual press after ownership release fires")
			button(false)
			button(true)
			game.show_menu()
			check(not game.manual_fire_held and game.pending_shots == 0, label_text + " menu clears firing")

			prepare(map_id, weapon_id)
			game.weapon.mag = 1
			game.weapon.reserve = 0
			button(true)
			ticks(30)
			check(game.phase == "results" and game.shots == 1, label_text + " final actual shot enters results once")
			check(not game.manual_fire_held and game.pending_shots == 0, label_text + " result clears hold")
			game.start_round()
			game.begin_training()
			ticks(20)
			check(game.shots == 0 and game.weapon.mag == int(game.weapon.get_data().mag_size), label_text + " replay needs fresh press")
	button(false)
	game.show_menu()
	print("PASS: %d input checks; failures: %d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
