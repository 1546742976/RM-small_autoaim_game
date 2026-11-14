extends RefCounted
## Shared gameplay values. Prices/reload times are tuning values; all other
## weapon numbers below define the training rules.

const PRECISION_THRESHOLD: float = 0.34
const MAX_HEALTH: int = 100
const STARTING_MONEY: int = 5000
const WEAPONS: Dictionary = {
	"deagle": {"name": "沙鹰", "mag_size": 7, "interval_ms": 225,
		"reload_ms": 2200, "price": 700},
	"ak47": {"name": "AK-47", "mag_size": 25, "interval_ms": 100,
		"reload_ms": 2500, "price": 2700},
	"m4a1": {"name": "M4A1", "mag_size": 30, "interval_ms": 90,
		"reload_ms": 3100, "price": 3100},
}


static func damage_result(hp: int, headshot: bool) -> Dictionary:
	var health: int = maxi(0, hp)
	var killed: bool = headshot and health > 0
	if killed:
		health = 0
	return {"hp": health, "killed": killed}


static func purchase(weapon_id: String, money: int, already_bought: bool) -> Dictionary:
	var result: Dictionary = {
		"ok": false, "reason": "", "weapon": weapon_id, "money": money,
	}
	if already_bought:
		result.reason = "already_bought"
		return result
	if not WEAPONS.has(weapon_id):
		result.reason = "unknown_weapon"
		return result
	# The default pistol is issued free, although its nominal price stays $700.
	var cost: int = 0 if weapon_id == "deagle" else int(WEAPONS[weapon_id].price)
	if money < cost:
		result.reason = "insufficient_funds"
		return result
	result.ok = true
	result.money = money - cost
	return result
