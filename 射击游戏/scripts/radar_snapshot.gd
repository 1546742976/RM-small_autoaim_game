extends RefCounted
const INTERVAL := 0.5
var round_id := -1
var clock := 0.0
var bearing := 0.0
var sector := -1
var present := false
var overlap := false

func reset() -> void:
	round_id=-1
	clock=0
	sector=-1
	present=false
	overlap=false

func advance(delta: float, player_position: Vector3, opponent_position: Vector3, player_alive: bool, opponent_alive: bool, yaw: float, force:=false) -> bool:
	clock+=delta
	present=player_alive and opponent_alive
	if not present:
		sector=-1
		return true
	if force or clock>=INTERVAL:
		clock=0 if force else fmod(clock,INTERVAL)
		var offset:=opponent_position-player_position
		overlap=Vector2(offset.x,offset.z).length()<0.5
		bearing=atan2(offset.x,-offset.z)
	var angle:=wrapf(bearing+yaw,-PI,PI)
	if force or sector<0 or absf(wrapf(angle-sector*PI/4,-PI,PI))>deg_to_rad(27.5):
		sector=posmod(roundi(angle/(PI/4)),8)
	return true
