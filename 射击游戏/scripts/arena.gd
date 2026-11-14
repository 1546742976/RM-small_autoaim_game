extends Node3D
## Self-contained graybox range. World geometry blocks rays on layer 1.

const Target = preload("res://scripts/training_target.gd")
const STATION_POSITION := Vector3(-8, 0, 8)

var targets: Array = []


func _ready() -> void:
	name = "PrecisionRange"
	_build_lighting()
	_build_hall()
	_build_targets()
	_build_station()


func set_active(value: bool) -> void:
	for target in targets:
		target.active = value


func reset_targets() -> void:
	for target in targets:
		target.reset_target()


func _build_lighting() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101c28")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a8c3d7")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -25, 0)
	sun.light_color = Color("e5edf4")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	for z: float in [8.0, -6.0, -20.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(0, 5.8, z)
		light.light_color = Color("a5d9e8")
		light.light_energy = 2.0
		light.omni_range = 18.0
		add_child(light)


func _build_hall() -> void:
	var floor_mat := _material(Color("34444d"))
	var wall_mat := _material(Color("263641"))
	var panel_mat := _material(Color("1a2934"))
	var teal := _material(Color("51c9bc"), true)
	var white := _material(Color("93a5ad"))
	var amber := _material(Color("e2a05a"), true)
	_box(Vector3(26, 0.4, 44), Vector3(0, -0.2, -8), floor_mat, true)
	_box(Vector3(0.5, 7, 44), Vector3(-13.25, 3.5, -8), wall_mat, true)
	_box(Vector3(0.5, 7, 44), Vector3(13.25, 3.5, -8), wall_mat, true)
	_box(Vector3(26, 7, 0.5), Vector3(0, 3.5, -30), wall_mat, true)
	_box(Vector3(26, 7, 0.5), Vector3(0, 3.5, 14), wall_mat, true)
	_box(Vector3(26, 0.25, 44), Vector3(0, 7.1, -8), panel_mat, false)
	# Floor grid, lane strips and a clearly marked starting line.
	for x: int in range(-12, 13, 2):
		_box(Vector3(0.018, 0.005, 43), Vector3(x, 0.006, -8), panel_mat, false)
	for z: int in range(-28, 14, 2):
		_box(Vector3(25.8, 0.005, 0.018), Vector3(0, 0.006, z), panel_mat, false)
	for x: float in [-10.0, -3.4, 3.4, 10.0]:
		_box(Vector3(0.045, 0.008, 31), Vector3(x, 0.012, -9), white, false)
	_box(Vector3(20, 0.01, 0.13), Vector3(0, 0.014, 5.5), amber, false)
	_box(Vector3(20, 0.01, 0.06), Vector3(0, 0.014, 5.8), amber, false)
	for z: float in [-25.0, -17.0, -9.0, -1.0, 7.0]:
		for x: float in [-12.9, 12.9]:
			_box(Vector3(0.15, 6.2, 0.35), Vector3(x, 3.1, z), panel_mat, false)
			_box(Vector3(0.18, 0.08, 4.5), Vector3(x, 1.0, z), teal, false)
		_box(Vector3(21, 0.06, 0.18), Vector3(0, 6.96, z), teal, false)
	_box(Vector3(14.4, 2.6, 0.12), Vector3(0, 4.6, -29.65), panel_mat, false)
	_label("RM / PRECISION LAB", Vector3(0, 5.1, -29.52), 100, 0.012, Color("e3edf0"))
	_label("COUNTER-STRAFE   /   SINGLE SHOT   /   REPEAT", Vector3(0, 4.15, -29.51), 40, 0.010, Color("52d7c5"))
	for index: int in range(3):
		var x: float = float(index - 1) * 7.0
		_box(Vector3(2.4, 0.75, 0.10), Vector3(x, 0.6, -29.55), panel_mat, false)
		_label("0%d / RANGE" % (index + 1), Vector3(x, 0.65, -29.45), 48, 0.009, Color("a8bec8"))
	# Side cover is outside the target lanes, but provides a real occluder to test rays.
	_box(Vector3(1.3, 1.5, 2.0), Vector3(11.0, 0.75, 0), panel_mat, true)
	_box(Vector3(1.35, 0.08, 2.05), Vector3(11.0, 1.52, 0), amber, false)


func _build_targets() -> void:
	var positions: Array[Vector3] = [
		Vector3(-6, 0, -5), Vector3(0, 0, -8), Vector3(6, 0, -5),
		Vector3(-7, 0, -18), Vector3(0, 0, -23), Vector3(7, 0, -18)
	]
	for index: int in range(6):
		var target := Target.new()
		target.setup(index, index >= 3, index % 2 == 1)
		target.position = positions[index]
		add_child(target)
		targets.append(target)
		var base_color: Color = Color("3a6264") if index % 2 == 1 else Color("705b46")
		var width: float = 5.2 if index >= 3 else 1.4
		_box(Vector3(width, 0.012, 0.8), positions[index] + Vector3(0, 0.015, 0), _material(base_color), false)


func _build_station() -> void:
	var base := _material(Color("243541"))
	var teal := _material(Color("54d9c4"), true)
	_box(Vector3(1.4, 1.15, 0.8), STATION_POSITION + Vector3(0, 0.575, 0), base, true)
	_box(Vector3(1.3, 0.5, 0.12), STATION_POSITION + Vector3(0, 1.45, 0), base, true)
	_box(Vector3(1.1, 0.34, 0.04), STATION_POSITION + Vector3(0, 1.45, 0.09), teal, false)
	_label("ARMOR TEST / E", STATION_POSITION + Vector3(0, 2.15, 0), 48, 0.007, Color("78efda"))
	_label("40 DAMAGE / BUY PHASE", STATION_POSITION + Vector3(0, 1.95, 0), 30, 0.006, Color("bcced4"))


func _material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.4
	return mat


func _box(size: Vector3, pos: Vector3, mat: Material, solid: bool) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = pos
	instance.material_override = mat
	add_child(instance)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 4
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.position = pos
		body.add_child(collision)
		add_child(body)


func _label(text: String, pos: Vector3, font_size: int, pixel_size: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	add_child(label)
