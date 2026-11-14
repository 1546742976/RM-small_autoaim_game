extends "res://scripts/weapon_controller.gd"
## Deliberately asymmetric NPC tuning; player weapons retain their own data.
const Profile=preload("res://scripts/bot_profile.gd")
func get_data() -> Dictionary:
	var data: Dictionary=super.get_data().duplicate()
	data.interval_ms=Profile.SHOT_INTERVAL_MS
	data.reload_ms=Profile.RELOAD_MS
	return data
