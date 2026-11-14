extends RefCounted
## Shared training rules. All three weapons are freely selectable.

const PRECISION_THRESHOLD: float = 0.34
const MAX_HEALTH: int = 100
const WEAPONS: Dictionary = {
	"deagle": {"name": "沙鹰", "mag_size": 7, "interval_ms": 225,
		"reload_ms": 2200},
	"ak47": {"name": "AK-47", "mag_size": 25, "interval_ms": 100,
		"reload_ms": 2500},
	"m4a1": {"name": "M4A1", "mag_size": 30, "interval_ms": 90,
		"reload_ms": 3100},
}


static func damage_result(hp: int, headshot: bool) -> Dictionary:
	var health: int = maxi(0, hp)
	var killed: bool = headshot and health > 0
	if killed:
		health = 0
	return {"hp": health, "killed": killed}
