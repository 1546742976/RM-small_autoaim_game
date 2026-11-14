extends SceneTree
## Run: Godot --headless --path <project> --script res://tests/test_rules.gd

const Rules = preload("res://scripts/game_rules.gd")
const Direction = preload("res://scripts/shot_direction.gd")
const Weapon = preload("res://scripts/weapon_controller.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label_text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label_text)


func new_weapon(id: String = "deagle") -> Node:
	var weapon: Node = Weapon.new()
	weapon.reset(id)
	weapon.active = true
	return weapon


func _run() -> void:
	test_cooldowns()
	test_spread()
	test_reload()
	test_complete_ammo_cycle()
	test_damage()
	if failures == 0:
		print("PASS: %d rule checks" % checks)
	else:
		printerr("FAIL: %d / %d rule checks failed" % [failures, checks])
	quit(1 if failures > 0 else 0)


func test_cooldowns() -> void:
	for id: String in Rules.WEAPONS:
		var weapon: Node = new_weapon(id)
		var capacity: int = Rules.WEAPONS[id].mag_size
		check(weapon.mag == capacity and weapon.reserve == capacity * 2, id + " initial ammo")
		check(weapon.try_fire() == "", id + " successful single shot")
		check(weapon.mag == capacity - 1, id + " successful single shot")
		check(weapon.try_fire() == "cooldown", id + " cannot fire twice at same instant")
		weapon.advance_ms(float(Rules.WEAPONS[id].interval_ms) - 0.001)
		check(weapon.try_fire() == "cooldown", id + " no early cooldown")
		weapon.advance_ms(0.001)
		check(weapon.try_fire() == "", id + " exact cooldown permits firing")
		weapon.active = false
		var frozen_time: float = weapon.time_ms
		weapon.advance_ms(1000.0)
		check(weapon.time_ms == frozen_time, id + " inactive clock remains frozen")
		check(weapon.try_fire() == "not_training", id + " no firing outside training")
		check(not weapon.start_reload(), id + " no reload outside training")
		weapon.free()


func test_reload() -> void:
	var weapon: Node = new_weapon("ak47")
	check(not weapon.start_reload(), "full magazine cannot reload")
	weapon.mag = 10
	check(weapon.start_reload(), "partial magazine reload starts")
	check(not weapon.start_reload(), "duplicate reload cannot restart timer")
	check(weapon.try_fire() == "reloading", "cannot fire during reload")
	weapon.advance_ms(2499.0)
	check(weapon.mag == 10 and weapon.reserve == 50, "reload does not load early")
	weapon.active = false
	weapon.advance_ms(1000.0)
	check(weapon.reload_left_ms == 1.0, "inactive reload clock remains frozen")
	weapon.active = true
	weapon.advance_ms(1.0)
	check(weapon.mag == 25 and weapon.reserve == 35, "partial reload conserves ammunition")
	check(not weapon.is_reloading(), "reload finishes at exact duration")
	weapon.mag = 20
	weapon.reserve = 3
	check(weapon.start_reload(), "insufficient reserve may reload")
	weapon.advance_ms(2500.0)
	check(weapon.mag == 23 and weapon.reserve == 0, "only available reserve loaded")
	check(not weapon.start_reload(), "zero reserve cannot reload")
	weapon.reset("m4a1")
	check(weapon.mag == 30 and weapon.reserve == 60 and weapon.last_fire_ms < 0.0, "reset restores new weapon")
	check(not weapon.is_reloading() and weapon.time_ms == 0.0, "reset clears timers")
	weapon.free()


func test_complete_ammo_cycle() -> void:
	for id: String in Rules.WEAPONS:
		var weapon: Node = new_weapon(id)
		var observed: Dictionary = {"shots": 0, "depleted": 0, "final_shots": 0}
		weapon.fired.connect(func() -> void: observed.shots += 1)
		weapon.depleted.connect(func() -> void:
			observed.depleted += 1
			observed.final_shots = observed.shots
		)
		var total: int = int(Rules.WEAPONS[id].mag_size) * 3
		for index: int in range(total):
			if weapon.is_reloading():
				check(weapon.mag == 0 and weapon.reserve > 0, id + " auto reload only when ammo available")
				weapon.advance_ms(float(Rules.WEAPONS[id].reload_ms))
			else:
				weapon.advance_ms(float(Rules.WEAPONS[id].interval_ms))
			check(weapon.try_fire() == "", "%s total shot %d" % [id, index + 1])
		check(observed.shots == total and observed.depleted == 1, id + " exactly three magazines")
		check(observed.final_shots == total, id + " final shot handled before depletion")
		check(weapon.mag == 0 and weapon.reserve == 0 and not weapon.is_reloading(), id + " ammo finishes without extra reload")
		check(weapon.try_fire() == "mag_empty", id + " empty magazine rejects")
		check(observed.shots == total and observed.depleted == 1, id + " empty click cannot repeat shots/depletion")
		weapon.free()


func test_damage() -> void:
	for id: String in Rules.WEAPONS:
		var result: Dictionary = Rules.damage_result(100, false)
		check(result.hp == 100 and not result.killed, id + " body/limb never damages")
		result = Rules.damage_result(100, true)
		check(result.hp == 0 and result.killed, id + " headshot kills instantly")
		result = Rules.damage_result(0, true)
		check(not result.killed, id + " dead target cannot count twice")
	var hp := 100
	for i in 100:
		hp = Rules.damage_result(hp, false).hp
	check(hp == 100, "repeated non-head hits never accumulate damage")

func test_spread() -> void:
	var rng := RandomNumberGenerator.new()
	var aimed := Basis.from_euler(Vector3(-0.25,0.7,0.1))
	for id: String in Rules.WEAPONS:
		var weapon: Node = new_weapon(id)
		for speed: float in [0.0,0.339,0.34,0.341,1.0]:
			rng.seed = 4812
			var before: int = rng.state
			var mag_before: int = weapon.mag
			check(weapon.try_fire() == "" and weapon.mag == mag_before-1,id+" speed-independent fire "+str(speed))
			var ray := Direction.sample(aimed,speed,rng)
			check(ray.is_normalized(),id+" normalized shot")
			if speed < 0.34:
				check(ray.is_equal_approx(-aimed.z) and rng.state == before,id+" precise shot and unchanged RNG")
			else:
				var local: Vector3 = aimed.inverse()*ray
				var radius_at_ten := Vector2(local.x,local.y).length()/(-local.z)*10.0
				check(radius_at_ten > 0.01 and radius_at_ten <= 2.00001,id+" moving spread within two metres at ten metres")
			weapon.advance_ms(float(weapon.get_data().interval_ms))
		weapon.free()
	rng.seed = 451
	var boundary := Direction.sample(Basis.IDENTITY,0.34,rng)
	rng.seed = 451
	check(boundary.is_equal_approx(Direction.sample(Basis.IDENTITY,1.8,rng)),"spread does not grow above the threshold")
	rng.seed = 20261114
	var mean := Vector2.ZERO
	var mean_r2 := 0.0
	var quadrants := [0,0,0,0]
	var bounded := true
	var samples: Array[Vector3] = []
	for i in 10000:
		var ray := Direction.sample(Basis.IDENTITY,0.34,rng)
		var plane := Vector2(ray.x,ray.y)/(-ray.z)
		mean += plane
		mean_r2 += plane.length_squared()
		bounded = bounded and plane.length() <= 0.200001
		quadrants[(0 if plane.x < 0 else 1)+(0 if plane.y < 0 else 2)] += 1
		if i < 8: samples.append(ray)
	mean /= 10000.0
	mean_r2 /= 10000.0
	check(bounded,"all ten thousand disk samples obey the cone bound")
	check(mean.length() < 0.003,"disk distribution is centered")
	check(absf(mean_r2-0.02)<0.001,"uniform area radial second moment")
	for count in quadrants: check(abs(count-2500)<180,"uniform disk quadrant balance")
	check(samples[0] != samples[1] and samples[1] != samples[2],"successive shots vary independently")
	rng.seed = 20261114
	for direction in samples: check(direction.is_equal_approx(Direction.sample(Basis.IDENTITY,0.34,rng)),"fixed seed reproduces sequence")
