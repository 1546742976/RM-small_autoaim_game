extends RefCounted
## Uniform area distribution on the plane one metre ahead of the camera.
const Rules = preload("res://scripts/game_rules.gd")

static func is_accurate(speed_ratio: float, grounded:=true) -> bool:
	return grounded and speed_ratio < Rules.PRECISION_THRESHOLD

static func sample(camera_basis: Basis, speed_ratio: float, rng: RandomNumberGenerator, grounded:=true) -> Vector3:
	var aim := camera_basis.orthonormalized()
	if is_accurate(speed_ratio,grounded):
		return -aim.z
	var radius := Rules.MOVING_SPREAD_RATIO * sqrt(rng.randf())
	var angle := TAU * rng.randf()
	return (-aim.z + aim.x * radius * cos(angle) + aim.y * radius * sin(angle)).normalized()
