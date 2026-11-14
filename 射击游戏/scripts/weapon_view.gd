extends Node3D
## Presentation only. The weapon controller owns ammunition and the reload clock.

@export_enum("deagle", "ak47", "m4a1") var weapon_id := "deagle"
var model: Node3D
var magazine: Node3D
var left_arm: Node3D
var reload_arms: Node3D
var animator: AnimationPlayer
var skeleton: Skeleton3D
var palm: Node3D
var magazine_home: Transform3D
var _magazine_bind_basis: Basis
var palm_home: Vector3
var slide: Node3D
var bolt: Node3D
var flash: MeshInstance3D
var reload_progress := -1.0
var _clip: String
var _flash_left := 0.0
var _kick := 0.0

func _ready() -> void:
	model = load("res://assets/models/%s.glb" % weapon_id).instantiate()
	add_child(model)
	magazine = model.find_child("Magazine*", true, false)
	left_arm = model.find_child("LeftArm*", true, false)
	slide = model.find_child("Slide", true, false)
	bolt = model.find_child("Bolt", true, false)
	magazine_home = magazine.transform
	palm_home = model.find_child("LeftGrip", true, false).position
	reload_arms = preload("res://assets/models/reload_arms.glb").instantiate()
	model.add_child(reload_arms)
	reload_arms.rotation.y = PI
	animator = reload_arms.find_child("AnimationPlayer", true, false)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	skeleton = reload_arms.find_child("Skeleton3D", true, false)
	palm = reload_arms.find_child("LeftSidearmMagazineAnchorFrame" if weapon_id == "deagle" else "LeftGripAnchorFrame", true, false)
	reload_arms.scale = Vector3.ONE * 0.72
	reload_arms.find_child("LongGunReloadForearmsMesh", true, false).visible = weapon_id != "deagle"
	reload_arms.find_child("SidearmReloadForearmsMesh", true, false).visible = weapon_id == "deagle"
	_clip = {"deagle": "reload_desert_eagle_empty", "ak47": "reload_ak74_empty", "m4a1": "reload_m4a1_empty"}[weapon_id]
	animator.play(_clip)
	animator.seek(0.22 * animator.get_animation(_clip).length, true)
	animator.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	_magazine_bind_basis = _contact_in_model().basis.orthonormalized().inverse() * magazine_home.basis
	flash = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.027
	mesh.height = 0.09
	flash.mesh = mesh
	flash.visible = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ffe1a1")
	flash.material_override = mat
	model.find_child("Muzzle", true, false).add_child(flash)
	_disable_shadows(model)
	set_reload(0.0, 1.0)

func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)

func _physics_process(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	_kick = move_toward(_kick, 0.0, delta * 0.6)
	flash.visible = _flash_left > 0.0
	position.z = _kick

func play_shot() -> void:
	_flash_left = 0.035
	_kick = 0.035

func reset_pose() -> void:
	set_reload(0.0, 1.0)
	_flash_left = 0.0
	_kick = 0.0
	position = Vector3.ZERO
	flash.visible = false

func set_reload(left_ms: float, total_ms: float) -> void:
	if left_ms <= 0.0:
		reload_progress = -1.0
		model.rotation = Vector3.ZERO
		magazine.transform = magazine_home
		magazine.visible = true
		left_arm.visible = true
		reload_arms.visible = false
		slide.position = Vector3.ZERO
		bolt.position = Vector3.ZERO
		return
	var p := clampf(1.0 - left_ms / total_ms, 0.0, 1.0)
	reload_progress = p
	var tilt := smoothstep(0.0, 0.14, p) * (1.0 - smoothstep(0.88, 1.0, p))
	model.rotation = Vector3(0.10, -0.12, -0.34 if weapon_id == "deagle" else -0.46) * tilt
	left_arm.visible = p <= 0.015 or p >= 0.99
	reload_arms.visible = not left_arm.visible
	skeleton.reset_bone_poses()
	animator.play(_clip)
	animator.seek(p * animator.get_animation(_clip).length, true)
	animator.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	# Pin the authored glove to actual contacts on this weapon. The imported
	# finger curl and elbow motion remain skeletal; the magazine follows the hand.
	var grip := magazine_home.origin + Vector3(-0.025, 0.0, 0.0)
	var lower := grip + Vector3(-0.06, -0.20, 0.025)
	var pouch := grip + Vector3(-0.13, -0.40, 0.08)
	var mechanical: Vector3 = model.find_child("LeftGrip", true, false).position
	if weapon_id == "deagle":
		mechanical = Vector3(-0.025, 0.16, -0.17)
	elif weapon_id == "ak47":
		mechanical = Vector3(0.065, 0.20, -0.30)
	else:
		mechanical = Vector3(-0.035, 0.18, -0.12)
	var desired := _path(p, [0.0, 0.16, 0.22, 0.36, 0.45, 0.53, 0.68, 0.74, 0.82, 0.90, 1.0],
		[palm_home, grip, grip, lower, pouch, lower, grip, grip, mechanical, mechanical, palm_home])
	var contact_transform := _contact_in_model()
	var current := contact_transform.origin
	reload_arms.position += desired - current
	_fit_support_forearm()
	skeleton.force_update_all_bone_transforms()
	magazine.transform = magazine_home
	magazine.visible = not (p > 0.42 and p < 0.48)
	if p >= 0.22 and p < 0.68:
		magazine.basis = contact_transform.basis.orthonormalized() * _magazine_bind_basis
		magazine.basis = magazine.basis.slerp(magazine_home.basis, smoothstep(0.63, 0.68, p))
		magazine.position = desired - magazine.basis * Vector3(-0.025, 0.0, 0.0)
	var pull := smoothstep(0.81, 0.85, p) * (1.0 - smoothstep(0.88, 0.91, p))
	slide.position.z = 0.037 * pull if weapon_id == "deagle" else 0.0
	bolt.position.z = 0.045 * pull if weapon_id != "deagle" else 0.0

func _path(p: float, times: Array, points: Array) -> Vector3:
	for i in range(1, times.size()):
		if p <= times[i]:
			return points[i - 1].lerp(points[i], smoothstep(times[i - 1], times[i], p))
	return points[-1]

func _contact_in_model() -> Transform3D:
	var attachment: BoneAttachment3D = palm.get_parent()
	return model.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(attachment.bone_idx) * palm.transform

func _fit_support_forearm() -> void:
	# Keep the sleeve connected below the camera while the hand reaches the gun.
	# Preserve the authored wrist and finger pose exactly during this elbow solve.
	var elbow_index := skeleton.find_bone("L_elbow_02")
	var wrist_index := skeleton.find_bone("L_wrist_03")
	var arm_index := skeleton.find_bone("L_arm_01")
	var elbow_pose := skeleton.get_bone_global_pose(elbow_index)
	var wrist_pose := skeleton.get_bone_global_pose(wrist_index)
	var anchor := skeleton.to_local(model.to_global(Vector3(-0.12, -0.17, 0.06)))
	var fit_weight := smoothstep(0.0, 0.10, reload_progress) * (1.0-smoothstep(0.90,1.0,reload_progress))
	anchor = elbow_pose.origin.lerp(anchor, fit_weight)
	var old_direction := wrist_pose.origin - elbow_pose.origin
	var new_direction := wrist_pose.origin - anchor
	var rotation_delta := Basis(Quaternion(old_direction.normalized(), new_direction.normalized()))
	elbow_pose.basis = rotation_delta * elbow_pose.basis
	elbow_pose.origin = anchor
	var arm_pose := skeleton.get_bone_global_pose(arm_index)
	arm_pose.basis = arm_pose.basis.slerp(elbow_pose.basis, fit_weight)
	arm_pose.origin = arm_pose.origin.lerp(anchor + new_direction.normalized() * -6.0, fit_weight)
	skeleton.set_bone_global_pose(arm_index, arm_pose)
	skeleton.set_bone_global_pose(elbow_index, elbow_pose)
	skeleton.set_bone_global_pose(wrist_index, wrist_pose)
