extends Control
## One game render. The local radar is composited only in the outer window.
var game: Node3D
var screen: SubViewport
var radar: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.focus_mode = Control.FOCUS_NONE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	screen = SubViewport.new()
	screen.name = "GameView"
	screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen.size_2d_override_stretch = true
	screen.audio_listener_enable_3d = true
	container.add_child(screen)
	resized.connect(_resize)
	_resize()
	game = preload("res://scripts/main.gd").new()
	game.name = "PrecisionLab"
	screen.add_child(game)
	radar = preload("res://scripts/assessment_radar.gd").new()
	add_child(radar)
	radar.configure(game)
	_resize()

func _resize() -> void:
	if not is_instance_valid(screen): return
	var factor := minf(size.x / 1280.0, size.y / 720.0)
	if factor <= 0: return
	screen.size_2d_override = Vector2i((size / factor).round())
	if is_instance_valid(radar):
		var compact := size.x < 1100
		radar.position = Vector2.ONE * (16 if compact else 24)
		radar.size = Vector2.ONE * (160 if compact else 200)
