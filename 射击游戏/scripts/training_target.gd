extends Node3D
## Fixed tracks only. Bone-following hit regions have no AI or attack behavior.

const Rules = preload("res://scripts/game_rules.gd")
const Visual = preload("res://scripts/trainee_visual.gd")
signal hit(headshot: bool, killed: bool)
var hp := 100
var alive := true
var active := false
var moving := false
var target_index := 0
var _origin: Vector3
var _time := 0.0
var _respawn_left := 0.0
var _visuals: Node3D
var _regions: Array[Dictionary] = []
var _label: Label3D

func setup(index: int, is_moving: bool) -> void:
	target_index = index
	moving = is_moving

func _ready() -> void:
	_origin = position
	name = "Target_%02d" % (target_index + 1)
	_visuals = Visual.new()
	_visuals.moving = moving
	add_child(_visuals)
	_region("Head", "Head", "HeadTop_End", 0.105, true)
	_region("Body", "Hips", "Spine2", 0.17)
	_region("Neck", "Spine2", "Neck", 0.075)
	for side in ["Left", "Right"]:
		_region(side + "Arm", side + "Arm", side + "ForeArm", 0.058)
		_region(side + "ForeArm", side + "ForeArm", side + "Hand", 0.047)
		_region(side + "Hand", side + "Hand", side + "HandMiddle2", 0.042)
		_region(side + "Thigh", side + "UpLeg", side + "Leg", 0.085)
		_region(side + "Leg", side + "Leg", side + "Foot", 0.062)
		_region(side + "Foot", side + "Foot", side + "ToeBase", 0.065)
	_label = Label3D.new()
	_label.position = Vector3(0, 2.15, 0)
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color("5bdacf") if moving else Color("f2bb7c")
	_label.outline_size = 8
	add_child(_label)
	_sync_regions()
	_update_label()

func _physics_process(delta: float) -> void:
	if not active:
		return
	_time += delta
	if not alive:
		_respawn_left -= delta
		_visuals.sample(_time, 1.0 - _respawn_left)
		if _respawn_left <= 0.0:
			_restore()
		return
	if moving:
		position.x = _origin.x + sin(_time * 0.8) * 2.2
	_visuals.sample(_time, -1.0)
	_sync_regions()

func apply_hit(headshot: bool) -> Dictionary:
	if not alive or not active:
		return {"hit": false, "killed": false, "headshot": headshot}
	var result := Rules.damage_result(hp, headshot)
	hp = int(result.hp)
	if result.killed:
		alive = false
		_respawn_left = 1.0
		for region in _regions:
			region.area.collision_layer = 0
		_update_label()
	hit.emit(headshot, result.killed)
	return {"hit": true, "killed": result.killed, "headshot": headshot}

func reset_target() -> void:
	_time = 0.0
	position = _origin
	_restore()

func _restore() -> void:
	hp = 100
	alive = true
	_respawn_left = 0.0
	_visuals.sample(_time, -1.0)
	_sync_regions()
	for region in _regions:
		region.area.collision_layer = 2
	_update_label()

func _update_label() -> void:
	_label.text = "%02d / %s" % [target_index + 1, ("TRACK" if moving else "STATIC") if alive else "RESET"]

func _region(region_name: String, start: String, end: String, radius: float, head := false) -> void:
	var area := Area3D.new()
	area.name = region_name
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("target", self)
	area.set_meta("headshot", head)
	var collision := CollisionShape3D.new()
	if head:
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		collision.shape = sphere
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		collision.shape = capsule
	area.add_child(collision)
	add_child(area)
	_regions.append({"area": area, "shape": collision.shape, "start": start, "end": end, "radius": radius, "head": head})

func _sync_regions() -> void:
	for region in _regions:
		var a: Vector3 = _visuals.bone_point(region.start)
		var b: Vector3 = _visuals.bone_point(region.end)
		region.area.global_position = a.lerp(b, 0.53 if region.head else 0.5)
		if not region.head:
			region.shape.height = a.distance_to(b) + 2.0 * region.radius
			region.area.global_basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
		region.area.force_update_transform()
