extends "res://scripts/map_geometry.gd"

func _ready() -> void:
	_build_lighting()
	_build_hall()
	var points := [Vector3(-6,0,-5),Vector3(0,0,-8),Vector3(6,0,-5),Vector3(-7,0,-18),Vector3(0,0,-23),Vector3(7,0,-18)]
	for i in 6:
		var half := Vector3(2.2,0,0) if i >= 3 else Vector3.ZERO
		target_configs.append({"position":points[i],"yaw":0.0,"moving":i >= 3,"from":points[i]-half,"to":points[i]+half})
		test_views.append(Vector3(0,0.02,9))
	route = [Vector3(0,0.02,9),Vector3(-9,0.02,9),Vector3(-9,0.02,-1),Vector3(9,0.02,-1),Vector3(9,0.02,9),Vector3(0,0.02,9)]

func _build_lighting() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101c28")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d2d9e1")
	environment.ambient_light_energy = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("7b8b9b")
	sky_material.sky_horizon_color = Color("d8e3e8")
	sky_material.ground_bottom_color = Color("26323c")
	sky_material.ground_horizon_color = Color("9aa8b0")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -25, 0)
	sun.light_color = Color("e5edf4")
	sun.light_energy = 1.4
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


