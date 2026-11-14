extends RefCounted
## Shared gameplay values. Prices/reload times are tuning values; all other
## weapon numbers below define the training rules.

const PRECISION_THRESHOLD: float = 0.34
const MAX_HEALTH: int = 100
const MAX_ARMOR: int = 100
const ARMOR_PRICE: int = 1000
const STARTING_MONEY: int = 5000
const WEAPONS: Dictionary = {
	"deagle": {"name": "沙鹰", "mag_size": 7, "interval_ms": 225,
		"damage": 45, "reload_ms": 2200, "price": 700},
	"ak47": {"name": "AK-47", "mag_size": 25, "interval_ms": 100,
		"damage": 40, "reload_ms": 2500, "price": 2700},
	"m4a1": {"name": "M4A1", "mag_size": 30, "interval_ms": 90,
		"damage": 30, "reload_ms": 3100, "price": 3100},
}


static func damage_result(hp: int, armor: int, damage: int, headshot: bool = false) -> Dictionary:
	var health: int = maxi(0, hp)
	var remaining_armor: int = maxi(0, armor)
	if headshot:
		health = 0
	else:
		var incoming: int = maxi(0, damage)
		var absorbed: int = mini(remaining_armor, incoming)
		remaining_armor -= absorbed
		health = maxi(0, health - (incoming - absorbed))
	return {"hp": health, "armor": remaining_armor, "killed": health == 0}


static func purchase(weapon_id: String, wants_armor: bool, money: int, already_bought: bool) -> Dictionary:
	var result: Dictionary = {
		"ok": false, "reason": "", "weapon": weapon_id, "armor": 0, "money": money,
	}
	if already_bought:
		result.reason = "already_bought"
		return result
	if not WEAPONS.has(weapon_id):
		result.reason = "unknown_weapon"
		return result
	# The default pistol is issued free, although its nominal price stays $700.
	var cost: int = 0 if weapon_id == "deagle" else int(WEAPONS[weapon_id].price)
	if wants_armor:
		cost += ARMOR_PRICE
	if money < cost:
		result.reason = "insufficient_funds"
		return result
	result.ok = true
	result.money = money - cost
	result.armor = MAX_ARMOR if wants_armor else 0
	return result
