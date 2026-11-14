extends SceneTree
## Run: Godot --headless --path <project> --script res://tests/test_rules.gd

const Rules = preload("res://scripts/game_rules.gd")
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
	test_precision_and_cooldowns()
	test_reload()
	test_complete_ammo_cycle()
	test_damage()
	test_purchases()
	if failures == 0:
		print("PASS: %d rule checks" % checks)
	else:
		printerr("FAIL: %d / %d rule checks failed" % [failures, checks])
	quit(1 if failures > 0 else 0)


func test_precision_and_cooldowns() -> void:
	for id: String in Rules.WEAPONS:
		var weapon: Node = new_weapon(id)
		var capacity: int = Rules.WEAPONS[id].mag_size
		check(weapon.mag == capacity and weapon.reserve == capacity * 2, id + " initial ammo")
		check(weapon.try_fire(0.34) == "moving", id + " strict threshold equality")
		check(weapon.try_fire(0.341) == "moving", id + " above threshold")
		check(weapon.mag == capacity and weapon.last_fire_ms < 0.0, id + " denied shots do not change ammo/time")
		check(weapon.try_fire(0.339) == "", id + " below threshold")
		check(weapon.mag == capacity - 1, id + " successful single shot")
		check(weapon.try_fire(0.0) == "cooldown", id + " cannot fire twice at same instant")
		weapon.advance_ms(float(Rules.WEAPONS[id].interval_ms) - 0.001)
		check(weapon.try_fire(0.0) == "cooldown", id + " no early cooldown")
		weapon.advance_ms(0.001)
		check(weapon.try_fire(0.0) == "", id + " exact cooldown permits firing")
		weapon.active = false
		var frozen_time: float = weapon.time_ms
		weapon.advance_ms(1000.0)
		check(weapon.time_ms == frozen_time, id + " inactive clock remains frozen")
		check(weapon.try_fire(0.0) == "not_training", id + " no firing outside training")
		check(not weapon.start_reload(), id + " no reload outside training")
		weapon.free()


func test_reload() -> void:
	var weapon: Node = new_weapon("ak47")
	check(not weapon.start_reload(), "full magazine cannot reload")
	weapon.mag = 10
	check(weapon.start_reload(), "partial magazine reload starts")
	check(not weapon.start_reload(), "duplicate reload cannot restart timer")
	check(weapon.try_fire(0.0) == "reloading", "cannot fire during reload")
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
		weapon.fired.connect(func(_damage: int) -> void: observed.shots += 1)
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
			check(weapon.try_fire(0.0) == "", "%s total shot %d" % [id, index + 1])
		check(observed.shots == total and observed.depleted == 1, id + " exactly three magazines")
		check(observed.final_shots == total, id + " final shot handled before depletion")
		check(weapon.mag == 0 and weapon.reserve == 0 and not weapon.is_reloading(), id + " ammo finishes without extra reload")
		check(weapon.try_fire(0.0) == "mag_empty", id + " empty magazine rejects")
		check(observed.shots == total and observed.depleted == 1, id + " empty click cannot repeat shots/depletion")
		weapon.free()


func test_damage() -> void:
	var result: Dictionary = Rules.damage_result(100, 10, 40)
	check(result.hp == 70 and result.armor == 0 and not result.killed, "armor overflow preserves full damage")
	result = Rules.damage_result(100, 100, 40)
	check(result.hp == 100 and result.armor == 60, "armor absorbs damage without reduction")
	result = Rules.damage_result(100, 40, 40)
	check(result.hp == 100 and result.armor == 0, "exact armor depletion does not damage health")
	for id: String in Rules.WEAPONS:
		var damage: int = Rules.WEAPONS[id].damage
		result = Rules.damage_result(100, 0, damage)
		check(result.hp == 100 - damage, id + " unarmored body damage")
		result = Rules.damage_result(100, 100, damage, true)
		check(result.hp == 0 and result.killed and result.armor == 100, id + " armored headshot bypasses armor")
		result = Rules.damage_result(100, 0, damage, true)
		check(result.hp == 0 and result.killed, id + " unarmored headshot kills")
	result = Rules.damage_result(5, 0, 40)
	check(result.hp == 0 and result.killed, "health clamps to zero on lethal hit")


func test_purchases() -> void:
	var result: Dictionary = Rules.purchase("deagle", false, 5000, false)
	check(result.ok and result.money == 5000 and result.armor == 0, "free default pistol")
	result = Rules.purchase("deagle", true, 5000, false)
	check(result.ok and result.money == 4000 and result.armor == 100, "pistol plus full armor")
	result = Rules.purchase("ak47", true, 5000, false)
	check(result.ok and result.money == 1300 and result.weapon == "ak47", "AK and armor price")
	result = Rules.purchase("m4a1", true, 5000, false)
	check(result.ok and result.money == 900, "M4 and armor price")
	result = Rules.purchase("m4a1", true, 900, true)
	check(not result.ok and result.reason == "already_bought" and result.money == 900, "duplicate purchase cannot deduct money")
	result = Rules.purchase("m4a1", true, 4000, false)
	check(not result.ok and result.reason == "insufficient_funds" and result.money == 4000, "cannot overspend")
	result = Rules.purchase("deagle", false, 0, false)
	check(result.ok and result.money == 0, "default pistol requires no funds")
	result = Rules.purchase("unknown", false, 5000, false)
	check(not result.ok and result.reason == "unknown_weapon", "only three permitted weapons")
