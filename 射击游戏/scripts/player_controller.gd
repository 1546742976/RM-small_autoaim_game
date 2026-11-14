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
var view: Node3D
var _pitch: float = 0.0
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
	weapon_root.position = Vector3(0.22, -0.29, -0.46)
	camera.add_child(weapon_root)
	set_weapon(_weapon_id)


func _unhandled_input(event: InputEvent) -> void:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		for flag in ["--smoke-test", "--showcase", "--benchmark"]:
			if flag in OS.get_cmdline_user_args() and not event.has_meta("smoke_motion"):
				return
		rotate_y(-event.relative.x * SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * SENSITIVITY, -1.42, 1.42)
		camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
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


func reset_position(pos: Vector3 = Vector3(0, 0.02, 9), yaw: float = 0.0) -> void:
	position = pos
	rotation = Vector3(0, yaw, 0)
	_pitch = 0.0
	velocity = Vector3.ZERO
	_horizontal_speed = 0.0
	if is_instance_valid(camera):
		camera.rotation = Vector3.ZERO
	if is_instance_valid(view):
		view.reset_pose()


func set_weapon(id: String) -> void:
	_weapon_id = id
	if not is_instance_valid(weapon_root):
		return
	for child: Node in weapon_root.get_children():
		weapon_root.remove_child(child)
		child.queue_free()
	view = load("res://scenes/weapons/%s.tscn" % id).instantiate()
	weapon_root.add_child(view)
	weapon_root.visible = true

func play_shot() -> void:
	view.play_shot()

func update_reload(left_ms: float, total_ms: float) -> void:
	view.set_reload(left_ms, total_ms)
