extends Node
## Opt-in comparison recording. Calibration board/impact marks exist only here.
var game: Node3D
var folder := ""
var aim_point := Vector3(0,3.25,-5.9)
var board: StaticBody3D
var caption: Label
var stage := "moving"
var records: Array[Dictionary] = []
var moving_count := 0
var accurate_count := 0

func frames(count: int) -> void:
	for i in count:
		game.player.camera.look_at(aim_point)
		await get_tree().process_frame

func capture(name_text: String) -> void:
	await RenderingServer.frame_post_draw
	get_window().get_texture().get_image().save_png(folder.path_join(name_text+".png"))

func run(controller: Node3D) -> void:
	game = controller
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): folder = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	game.show_setup()
	game.ui._select("training_hall","ak47")
	game.start_round()
	game.begin_training()
	game.shot_rng.seed = 20261114
	board = StaticBody3D.new()
	board.position = Vector3(0,3.25,-6)
	board.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(8,6.3,0.2)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	board.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("1a242a")
	material.roughness = 0.95
	mesh.material_override = material
	board.add_child(mesh)
	game.add_child(board)
	caption = Label.new()
	caption.text = "移动射击 · 随机散布"
	caption.add_theme_font_size_override("font_size",28)
	caption.add_theme_color_override("font_color",Color("d9ad66"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.ui.root.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	caption.offset_left = -360
	caption.offset_right = 360
	caption.offset_top = 88
	game.shot_fired.connect(record_launch)
	game.shot_resolved.connect(record)
	await frames(60)
	var tick := 0
	while moving_count < 18 and tick < 900:
		var right := (tick/45)%2 == 0
		Input.action_release("move_left" if right else "move_right")
		Input.action_press("move_right" if right else "move_left")
		if tick%12 == 0 and game.player.get_speed_ratio() >= 0.34 and game.weapon.fire_error().is_empty():
			game.pending_shots = 1
		await frames(1)
		tick += 1
	while game.projectiles.live_count()>0: await frames(1)
	await capture("moving-spread")
	Input.action_release("move_right")
	Input.action_release("move_left")
	# Counter input brakes real velocity, rather than resetting the player's speed.
	var brake := "move_left" if game.player.velocity.x>0 else "move_right"
	Input.action_press(brake)
	while game.player.get_speed_ratio()>=0.34: await frames(1)
	Input.action_release(brake)
	stage = "accurate"
	caption.text = "急停后 · 精准命中"
	caption.add_theme_color_override("font_color",Color("f2f0ea"))
	await frames(30)
	for i in 6:
		game.pending_shots = 1
		await frames(16)
	while game.projectiles.live_count()>0: await frames(1)
	await capture("stopped-precision")
	await frames(120)
	var file := FileAccess.open(folder.path_join("shots.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t"))
	print("SPREAD DEMO: %d moving, %d accurate shots" % [moving_count,accurate_count])
	game.shot_fired.disconnect(record_launch)
	game.shot_resolved.disconnect(record)
	game.shot_sound.stop()
	game.hit_sound.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().quit(0 if moving_count == 18 and accurate_count == 6 else 1)

func record_launch(origin: Vector3, direction: Vector3) -> void:
	if stage == "moving": moving_count += 1
	else: accurate_count += 1
	records.append({"stage":stage,"speed_ratio":game.player.get_speed_ratio(),
		"origin":[origin.x,origin.y,origin.z],"direction":[direction.x,direction.y,direction.z]})

func record(origin: Vector3, direction: Vector3, hit: Dictionary) -> void:
	var impact: Vector3 = hit.get("position",origin+direction*100)
	for entry in records:
		if entry.has("impact"): continue
		var recorded_origin:=Vector3(entry.origin[0],entry.origin[1],entry.origin[2])
		var recorded_direction:=Vector3(entry.direction[0],entry.direction[1],entry.direction[2])
		if recorded_origin.is_equal_approx(origin) and recorded_direction.is_equal_approx(direction):
			entry.impact=[impact.x,impact.y,impact.z]
			entry.board_hit=hit.get("collider")==board
			break
	if hit.get("collider") != board: return
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07 if stage == "moving" else 0.11
	sphere.height = sphere.radius*2
	sphere.radial_segments = 12
	sphere.rings = 6
	dot.mesh = sphere
	dot.position = impact+Vector3(0,0,0.025)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("d9ad66") if stage == "moving" else Color("f2f0ea")
	dot.material_override = material
	game.add_child(dot)
