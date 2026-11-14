extends Node3D
## The skinned character is independent of damage and round rules.

var skeleton: Skeleton3D
var animator: AnimationPlayer
var moving := false

func _ready() -> void:
	var actor := preload("res://assets/models/trainee.glb").instantiate()
	add_child(actor)
	skeleton = actor.find_child("Skeleton3D", true, false)
	animator = actor.find_child("AnimationPlayer", true, false)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var body: MeshInstance3D = actor.find_child("Male", true, false)
	for i in body.mesh.get_surface_count():
		var source := body.mesh.surface_get_material(i)
		if source.resource_name == "TrainingTop":
			var material: StandardMaterial3D = source.duplicate()
			material.albedo_color = Color("53c8c3") if moving else Color("ebae68")
			body.set_surface_override_material(i, material)
		elif source.resource_name == "TrainingBoots":
			var material: StandardMaterial3D = source.duplicate()
			material.albedo_color = Color("4a4d50")
			material.roughness = 0.70
			body.set_surface_override_material(i, material)
	sample(0.0, -1.0)

func sample(time: float, death_time: float) -> void:
	var clip := "death" if death_time >= 0.0 else ("sidestep" if moving else "idle")
	var duration := animator.get_animation(clip).length
	animator.play(clip)
	animator.seek(minf(death_time, duration) if death_time >= 0.0 else fmod(time, duration), true)
	animator.advance(0.0)
	skeleton.force_update_all_bone_transforms()

func bone_point(bone_name: String) -> Vector3:
	var index := skeleton.find_bone("mixamorig_" + bone_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
