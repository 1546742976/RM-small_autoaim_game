extends RefCounted
## Expert tuning and deterministic interception, independent of presentation.
const SPEED := 6.0
const BRAKE := 240.0
const REACTION := 0.03
const LOST_SIGHT := 0.15
const BODY_TURN := TAU*4.0
const AIM_TURN := PI*3.0
const ERROR := 0.0
const BURST_PAUSE := 0.0
const PROJECTILE_SPEED := 150.0
const SHOT_INTERVAL_MS := 70
const RELOAD_MS := 650
const JUMP_SPEED := 6.3
const GRAVITY := 20.0
const JUMP_COOLDOWN := 3.0

static func intercept(origin: Vector3, head: Vector3, movement: Vector3, airborne: bool, floor_head: float, projectile_speed := 25.0) -> Vector3:
	var relative := head-origin
	var a := movement.length_squared()-projectile_speed*projectile_speed
	var b := 2.0*relative.dot(movement)
	var c := relative.length_squared()
	var t := -1.0
	if absf(a)<0.00001:
		if absf(b)>0.00001: t=-c/b
	else:
		var discriminant := b*b-4*a*c
		if discriminant>=0:
			var first := (-b-sqrt(discriminant))/(2*a)
			var second := (-b+sqrt(discriminant))/(2*a)
			if first>0: t=first
			if second>0 and (t<0 or second<t): t=second
	if t<=0: return head
	t=minf(t,1.2)
	var point := head+movement*t
	if airborne:
		# Fixed-point refinement for vertical acceleration, constrained by support.
		for i in 4:
			point=head+movement*t
			point.y=maxf(floor_head,point.y-0.5*GRAVITY*t*t)
			t=minf(origin.distance_to(point)/projectile_speed,1.2)
	return point
