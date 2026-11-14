extends Node3D
## A target follows a fixed track; it never perceives, attacks, or makes decisions.

const Rules = preload("res://scripts/game_rules.gd")
signal hit(headshot: bool, killed: bool)

var hp: int = 100
var armor: int = 0
var alive: bool = true
var active: bool = false
var moving: bool = false
var armored: bool = false
var target_index: int = 0
var _origin: Vector3
var _time: float = 0.0
var _respawn_left: float = 0.0
var _flash_left: float = 0.0
var _visuals: Node3D
var _shapes: Array[CollisionShape3D] = []
var _body_material: StandardMaterial3D
var _label: Label3D
var _base_color: Color


func setup(index: int, is_moving: bool, has_armor: bool) -> void:
	target_index = index
	moving = is_moving
	armored = has_armor
	armor = 100 if armored else 0


func _ready() -> void:
	_origin = position
	name = "Target_%02d" % (target_index + 1)
	_base_color = Color("50d9c8") if armored else Color("f0ad65")
	_body_material = _material(_base_color)
	_visuals = Node3D.new()
	add_child(_visuals)
	var steel := _material(Color("253743"))
	_box(_visuals, Vector3(0.10, 0.44, 0.12), Vector3(0, 0.26, 0), steel)
	_box(_visuals, Vector3(0.80, 0.06, 0.55), Vector3(0, 0.04, 0), steel)
	_box(_visuals, Vector3(0.66, 0.96, 0.20), Vector3(0, 1.0, 0), _body_material)
	_box(_visuals, Vector3(0.38, 0.40, 0.24), Vector3(0, 1.72, 0), _material(Color("e5edf0")))
	# A face-center orange square makes the lethal head region readable at range.
	_box(_visuals, Vector3(0.17, 0.14, 0.012), Vector3(0, 1.74, 0.126), _material(Color("fa805c")))
	_box(_visuals, Vector3(0.26, 0.26, 0.014), Vector3(0, 1.10, 0.11), steel)
	_box(_visuals, Vector3(0.13, 0.13, 0.016), Vector3(0, 1.10, 0.122), _material(Color("e5edf0")))
	_create_hitbox(Vector3(0.66, 0.96, 0.20), Vector3(0, 1.0, 0), false)
	_create_hitbox(Vector3(0.38, 0.40, 0.24), Vector3(0, 1.72, 0), true)
	_label = Label3D.new()
	_label.position = Vector3(0, 2.18, 0)
	_label.font_size = 48
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color("dceaf0")
	_label.outline_size = 8
	_label.no_depth_test = false
	add_child(_label)
	_update_label()


func _physics_process(delta: float) -> void:
	if not active:
		return
	_time += delta
	if moving:
		position.x = _origin.x + sin(_time * 0.8) * 2.2
	if not alive:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_restore()
		return
	_flash_left = maxf(0.0, _flash_left - delta)
	_body_material.albedo_color = Color.WHITE if _flash_left > 0.0 else _base_color


func apply_hit(damage: int, headshot: bool) -> Dictionary:
	if not alive or not active:
		return {"hit": false, "killed": false, "headshot": headshot}
	var result: Dictionary = Rules.damage_result(hp, armor, damage, headshot)
	hp = int(result.hp)
	armor = int(result.armor)
	var killed: bool = bool(result.killed)
	_flash_left = 0.10
	if killed:
		alive = false
		_respawn_left = 1.0
		_visuals.visible = false
		for shape: CollisionShape3D in _shapes:
			shape.set_deferred("disabled", true)
	_update_label()
	hit.emit(headshot, killed)
	return {"hit": true, "killed": killed, "headshot": headshot}


func reset_target() -> void:
	_time = 0.0
	position = _origin
	_restore()


func _restore() -> void:
	hp = 100
	armor = 100 if armored else 0
	alive = true
	_respawn_left = 0.0
	_flash_left = 0.0
	if is_instance_valid(_visuals):
		_visuals.visible = true
		_body_material.albedo_color = _base_color
		for shape: CollisionShape3D in _shapes:
			shape.set_deferred("disabled", false)
		_update_label()


func _update_label() -> void:
	if not is_instance_valid(_label):
		return
	var mode: String = "TRACK" if moving else "STATIC"
	if alive:
		_label.text = "%02d / %s\nHP %03d  AR %03d" % [target_index + 1, mode, hp, armor]
	else:
		_label.text = "%02d / RESET" % (target_index + 1)


func _create_hitbox(size: Vector3, pos: Vector3, headshot: bool) -> void:
	var area := Area3D.new()
	area.name = "Head" if headshot else "Body"
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("target", self)
	area.set_meta("headshot", headshot)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.position = pos
	area.add_child(shape)
	add_child(area)
	_shapes.append(shape)


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	return mat


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = mat
	instance.position = pos
	parent.add_child(instance)
