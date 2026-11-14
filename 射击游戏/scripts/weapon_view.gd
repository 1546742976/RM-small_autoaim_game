extends Node3D
## Presentation only: sample baked arms/props using the controller's clock.
## Neither animation nor audio changes ammunition, camera or shot direction.

@export_enum("deagle", "ak47", "m4a1") var weapon_id := "deagle"
var model: Node3D
var magazine: Node3D
var magazine_home: Transform3D
var animator: AnimationPlayer
var skeleton: Skeleton3D
var palm: Node3D
var flash: MeshInstance3D
var reload_progress := -1.0
var reload_kind := "empty"
var reload_serial := -1
var audio_event_count := 0
var audio_event_log: Array[Dictionary] = []
var audio_players: Dictionary = {}
var manifest: Dictionary = {}
var _clip := "reload_empty"
var _sampled_clip := ""
var _event_cursor := -0.000001
var _played_events: Dictionary = {}
var _flash_left := 0.0
var _kick := 0.0


func _ready() -> void:
	model = load("res://assets/models/%s.glb" % weapon_id).instantiate()
	add_child(model)
	magazine = model.find_child("Magazine", true, false)
	animator = model.find_child("AnimationPlayer", true, false)
	skeleton = model.find_child("Skeleton3D", true, false)
	palm = model.find_child("LeftMagazineContact", true, false)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animator.playback_auto_capture = false
	var manifest_path := "res://assets/models/viewmodel_manifest.json"
	manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))[weapon_id]
	_sample("idle", 0.0)
	magazine_home = magazine.transform
	for event_name: String in ["remove", "insert", "mechanism"]:
		var player := AudioStreamPlayer.new()
		player.name = "Reload_" + event_name
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		player.stream = load("res://assets/audio/reload/%s_%s.wav" % [weapon_id, event_name])
		player.volume_db = -13.0
		add_child(player)
		audio_players[event_name] = player
	flash = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.027
	mesh.height = 0.09
	flash.mesh = mesh
	flash.visible = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ffe1a1")
	flash.material_override = material
	model.find_child("Muzzle", true, false).add_child(flash)
	_disable_shadows(model)
	reset_pose()


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
	reload_serial = -1
	_flash_left = 0.0
	_kick = 0.0
	position = Vector3.ZERO
	flash.visible = false
	_stop_audio()


func _stop_audio() -> void:
	for player: AudioStreamPlayer in audio_players.values():
		player.stop()


func _sample(clip: String, progress: float) -> void:
	if _sampled_clip != clip:
		animator.play(clip, 0.0)
		_sampled_clip = clip
	animator.seek(progress * animator.get_animation(clip).length, true)
	animator.advance(0.0)
	skeleton.force_update_all_bone_transforms()


func set_reload(left_ms: float, total_ms: float, kind: String = "empty", serial: int = 0) -> void:
	if left_ms <= 0.0:
		if reload_progress >= 0.0:
			_stop_audio()
		reload_progress = -1.0
		if _sampled_clip != "idle":
			_sample("idle", 0.0)
		return
	var p := clampf(1.0 - left_ms / total_ms, 0.0, 1.0)
	if serial != reload_serial or reload_progress < 0.0 or kind != reload_kind:
		_stop_audio()
		reload_serial = serial
		reload_kind = kind
		_event_cursor = -0.000001
		_played_events.clear()
	reload_progress = p
	_clip = "reload_" + reload_kind
	_sample(_clip, p)
	# Event crossings follow the pose clock. Repeated/backwards inspection cannot
	# replay an already consumed event during this reload.
	for event: Dictionary in manifest["clips"][_clip]["events"]:
		var event_name: String = event["name"]
		var at: float = event["progress"]
		if at > _event_cursor and at <= p and not _played_events.has(event_name):
			_played_events[event_name] = true
			audio_event_count += 1
			audio_event_log.append({"serial": serial, "kind": kind, "name": event_name, "progress": at})
			var player: AudioStreamPlayer = audio_players[event_name]
			# Consume missed old sounds without a late burst after a long frame.
			var elapsed := (p - at) * total_ms / 1000.0
			if elapsed < player.stream.get_length():
				player.play(elapsed)
	_event_cursor = maxf(_event_cursor, p)


func contact_transform(marker: Node3D) -> Transform3D:
	# BoneAttachment notifications may lag a manual animation seek.
	var attachment := marker.get_parent() as BoneAttachment3D
	if attachment:
		return skeleton.global_transform * skeleton.get_bone_global_pose(attachment.bone_idx) * marker.transform
	return marker.global_transform
