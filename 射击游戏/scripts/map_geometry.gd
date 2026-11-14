extends Node3D

var spawn_transform := Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 9))
var target_configs: Array[Dictionary] = []
var route: Array[Vector3] = []
var test_views: Array[Vector3] = []

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
