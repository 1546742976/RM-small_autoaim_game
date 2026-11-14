extends Node
## The weapon owns ammo/cooldown/reload state, but never performs hit detection.
## All timing uses simulated time so SceneTree pause freezes it naturally.

const Rules = preload("res://scripts/game_rules.gd")

signal fired(damage: int)
signal changed
signal depleted

var current_weapon: String = "deagle"
var mag: int = 7
var reserve: int = 14
var time_ms: float = 0.0
var last_fire_ms: float = -1.0e20
var reload_left_ms: float = 0.0
var active: bool = false


func _physics_process(delta: float) -> void:
	if active:
		advance_ms(delta * 1000.0)


func get_data() -> Dictionary:
	return Rules.WEAPONS[current_weapon]


func reset(weapon_id: String) -> void:
	assert(Rules.WEAPONS.has(weapon_id), "Unknown weapon: " + weapon_id)
	current_weapon = weapon_id
	mag = int(get_data().mag_size)
	reserve = mag * 2
	time_ms = 0.0
	last_fire_ms = -1.0e20
	reload_left_ms = 0.0
	changed.emit()


func is_reloading() -> bool:
	return reload_left_ms > 0.0


func advance_ms(delta_ms: float) -> void:
	if not active or delta_ms <= 0.0:
		return
	time_ms += delta_ms
	if not is_reloading():
		return
	reload_left_ms = maxf(0.0, reload_left_ms - delta_ms)
	if reload_left_ms < 0.000001:
		reload_left_ms = 0.0
		var loaded: int = mini(int(get_data().mag_size) - mag, reserve)
		mag += loaded
		reserve -= loaded
		changed.emit()


func start_reload() -> bool:
	if not active or is_reloading() or reserve <= 0 or mag >= int(get_data().mag_size):
		return false
	reload_left_ms = float(get_data().reload_ms)
	changed.emit()
	return true


func fire_error(speed_ratio: float) -> String:
	if not active:
		return "not_training"
	if is_reloading():
		return "reloading"
	if mag <= 0:
		return "mag_empty"
	if speed_ratio >= Rules.PRECISION_THRESHOLD:
		return "moving"
	# Only compensate for accumulated floating point time error, never speed.
	if time_ms - last_fire_ms + 0.000001 < float(get_data().interval_ms):
		return "cooldown"
	return ""


func try_fire(speed_ratio: float) -> String:
	var error: String = fire_error(speed_ratio)
	if not error.is_empty():
		return error
	mag -= 1
	last_fire_ms = time_ms
	fired.emit(int(get_data().damage))
	# Hit/kill callbacks have now completed, including the very last bullet.
	changed.emit()
	if mag == 0:
		if reserve > 0:
			start_reload()
		else:
			depleted.emit()
	return ""
