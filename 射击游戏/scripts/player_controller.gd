extends CharacterBody3D
## Movement and view feedback. Shot direction always remains the camera center.

const MAX_SPEED := 6.0
const ACCELERATION := 30.0
const FRICTION := 12.0
const COUNTER_ACCELERATION := 48.0
const SENSITIVITY := 0.0022

var active: bool = false
var camera: Camera3D
var weapon_root: Node3D
var muzzle: MeshInstance3D
var _pitch: float = 0.0
var _flash_left: float = 0.0
var _kick: float = 0.0
var _horizontal_speed: float = 0.0
var _weapon_id: String = "deagle"


func _ready() -> void:
	name = "Player"
	collision_layer = 4
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0, 1.65, 0)
	camera.fov = 75.0
	camera.near = 0.04
	camera.current = true
	add_child(camera)
	weapon_root = Node3D.new()
	weapon_root.position = Vector3(0.28, -0.25, -0.48)
	camera.add_child(weapon_root)
	set_weapon(_weapon_id)


func _unhandled_input(event: InputEvent) -> void:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * SENSITIVITY, -1.42, 1.42)
		camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	_kick = move_toward(_kick, 0.0, delta * 0.7)
	if is_instance_valid(muzzle):
		muzzle.visible = _flash_left > 0.0
	weapon_root.position.z = -0.48 + _kick
	if not active:
		velocity = Vector3.ZERO
		_horizontal_speed = 0.0
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_vector.x, 0, input_vector.y)).normalized()
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var rate: float = ACCELERATION
	if direction.is_zero_approx():
		rate = FRICTION
	elif horizontal.dot(direction) < 0.0:
		rate = COUNTER_ACCELERATION
	horizontal = horizontal.move_toward(direction * MAX_SPEED, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = -0.1
	else:
		velocity.y -= 20.0 * delta
	move_and_slide()
	var real_velocity: Vector3 = get_real_velocity()
	_horizontal_speed = Vector2(real_velocity.x, real_velocity.z).length()


func get_speed_ratio() -> float:
	return _horizontal_speed / MAX_SPEED


func reset_position(pos: Vector3 = Vector3(0, 0.02, 9)) -> void:
	position = pos
	rotation = Vector3.ZERO
	_pitch = 0.0
	velocity = Vector3.ZERO
	_horizontal_speed = 0.0
	_flash_left = 0.0
	_kick = 0.0
	if is_instance_valid(camera):
		camera.rotation = Vector3.ZERO


func set_weapon(id: String) -> void:
	_weapon_id = id
	if not is_instance_valid(weapon_root):
		return
	for child: Node in weapon_root.get_children():
		weapon_root.remove_child(child)
		child.queue_free()
	var metal := _material(Color("333e49"))
	var grip := _material(Color("17212b"))
	var accent := _material(Color("4ed8c7"))
	var length: float = 0.32 if id == "deagle" else 0.65
	_box(weapon_root, Vector3(0.11, 0.12, length), Vector3(0, 0, -length * 0.35), metal)
	_box(weapon_root, Vector3(0.09, 0.22, 0.11), Vector3(0, -0.12, 0.035), grip)
	_box(weapon_root, Vector3(0.08, 0.025, 0.10), Vector3(0, 0.07, -0.02), accent)
	_box(weapon_root, Vector3(0.035, 0.045, 0.03), Vector3(0, 0.09, -length * 0.72), metal)
	if id != "deagle":
		var stock_color: Color = Color("9b6d42") if id == "ak47" else Color("28343e")
		_box(weapon_root, Vector3(0.10, 0.11, 0.23), Vector3(0, 0, 0.24), _material(stock_color))
		_box(weapon_root, Vector3(0.08, 0.22, 0.14), Vector3(0, -0.14, -0.15), grip)
		_box(weapon_root, Vector3(0.13, 0.10, 0.22), Vector3(0, -0.01, -0.28), _material(stock_color))
	var flash_material := _material(Color("ffd68a"))
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle = _box(weapon_root, Vector3(0.10, 0.10, 0.14), Vector3(0, 0.015, -length * 0.88 - 0.03), flash_material)
	muzzle.visible = false
	weapon_root.visible = true


func play_shot() -> void:
	_flash_left = 0.045
	_kick = 0.045


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.65
	return mat


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh
