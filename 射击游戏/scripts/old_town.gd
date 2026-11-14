extends "res://scripts/map_geometry.gd"
## Original compact Mediterranean block. One continuous, flat loop.
var plaster: Material
var stone: Material
var wood: Material
var roof: Material
var trim: Material
var dark: Material
var shutters: Material

func _ready() -> void:
	spawn_transform = Transform3D(Basis.IDENTITY, Vector3(-14, 0.02, 16))
	route = [Vector3(-14,0.02,16),Vector3(-14,0.02,-15),Vector3(14,0.02,-15),Vector3(14,0.02,16),Vector3(-14,0.02,16)]
	var points := [Vector3(-17,0,-4),Vector3(5,0,-18),Vector3(18,0,7),Vector3(-14,0,-12),Vector3(4,0,-14),Vector3(14,0,-4)]
	for i in 6:
		var half := Vector3.ZERO
		if i >= 3: half = Vector3(0,0,3) if i == 4 else Vector3(3,0,0)
		target_configs.append({"position":points[i],"yaw":-PI/2 if i == 1 or i == 4 else 0.0,"moving":i >= 3,"from":points[i]-half,"to":points[i]+half})
		test_views.append(Vector3(-14,0.02,10) if i == 0 or i == 3 else (Vector3(-10,0.02,-15) if i == 1 or i == 4 else Vector3(14,0.02,16)))
	plaster = _pbr("plaster", Color("e3bd90"), 0.38)
	stone = _pbr("stone", Color("c3bfb1"), 0.38)
	wood = _pbr("wood", Color("665243"), 0.55)
	roof = _pbr("roof", Color("bd7657"), 0.4)
	trim = _material(Color("c6b79e"))
	dark = _material(Color("233333"))
	shutters = _material(Color("4c6860"))
	_lighting()
	_box(Vector3(48,0.4,44),Vector3(0,-0.2,0),stone,true)
	# Closed boundary, with decorative facades facing inward.
	for x in [-24.5,24.5]: _box(Vector3(1,7,45),Vector3(x,3.5,0),plaster,true)
	for z in [-22.5,22.5]: _box(Vector3(49,7,1),Vector3(0,3.5,z),plaster,true)
	_building(Vector3(0,0,0),Vector3(14,7.4,20),Color("e5c49c"))
	_building(Vector3(-22.4,0,-12),Vector3(3.2,8.5,18),Color("c8a181"))
	_building(Vector3(-22.4,0,12),Vector3(3.2,6.4,12),Color("e6d2ae"))
	_building(Vector3(22.3,0,-11),Vector3(3.4,7.4,20),Color("d9ac8d"))
	_building(Vector3(22.3,0,13),Vector3(3.4,8.5,10),Color("d7c3a1"))
	_building(Vector3(-12,0,-21),Vector3(18,7.8,2),Color("d3b188"))
	_building(Vector3(12,0,-21),Vector3(18,6.2,2),Color("e1c9a6"))
	_building(Vector3(0,0,21),Vector3(45,6,2),Color("bda48d"))
	# A shallow balcony breaks up the central facade, entirely above head height.
	_box(Vector3(0.85,0.16,3.2),Vector3(7.4,3.4,3),trim,false)
	_box(Vector3(0.07,0.07,3.2),Vector3(7.8,4.25,3),dark,false)
	for i in 9: _box(Vector3(0.035,0.82,0.035),Vector3(7.8,3.83,1.5+float(i)*0.375),dark,false)
	_arch(Vector3(-14,0,6),8.3)
	_arch(Vector3(14,0,12),8.0)
	# Courtyard well is outside the traversable loop and all shooting lanes.
	_cylinder(Vector3(0,0.38,-19),0.8,0.76,trim)
	_cylinder(Vector3(0,0.8,-19),1.0,0.12,trim)
	for position: Vector3 in [Vector3(-19.4,0,11),Vector3(-19.4,0,12.2),Vector3(19.6,0,-12),Vector3(8.5,0,8)]:
		_barrel(position)
	for position: Vector3 in [Vector3(-8.8,0,7.8),Vector3(19.3,0,17.8),Vector3(-19.4,0,-18.5)]:
		_box(Vector3(1.1,1.05,1.1),position+Vector3(0,0.525,0),wood,true)
		for y in [0.12,0.94]: _box(Vector3(1.14,0.08,1.14),position+Vector3(0,y,0),trim,false)
	for position: Vector3 in [Vector3(-8.2,0,-8.6),Vector3(8.2,0,-8.6),Vector3(-19.5,0,2),Vector3(19.5,0,2)]:
		_pot(position)
	# Overhead utility wires and small wall lamps keep eye-level silhouettes clear.
	for z in [-8.0,8.0]:
		_box(Vector3(12,0.025,0.025),Vector3(-14,5.2,z),dark,false)
		_box(Vector3(12,0.025,0.025),Vector3(14,5.5,z),dark,false)

func _pbr(id: String, tint: Color, tiling: float) -> StandardMaterial3D:
	var mat := _material(tint)
	for kind in ["Color","NormalGL","Roughness"]:
		var path := "res://assets/town/%s_%s.jpg" % [id,kind]
		if not ResourceLoader.exists(path): continue
		var texture: Texture2D = load(path)
		match kind:
			"Color": mat.albedo_texture = texture
			"NormalGL":
				mat.normal_enabled = true
				mat.normal_texture = texture
				mat.normal_scale = 0.25 if id == "plaster" else 0.7
			"Roughness": mat.roughness_texture = texture
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * tiling
	return mat

func _lighting() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("5891b4")
	sky_material.sky_horizon_color = Color("ddd9c5")
	sky_material.ground_bottom_color = Color("665e50")
	sky_material.ground_horizon_color = Color("c2bca6")
	sky.sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56,-32,0)
	sun.light_color = Color("fff0d6")
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 85.0
	add_child(sun)

func _building(pos: Vector3, size: Vector3, tint: Color) -> void:
	var facade := plaster.duplicate() as StandardMaterial3D
	facade.albedo_color = tint
	_box(size,pos+Vector3(0,size.y/2,0),facade,true)
	_box(Vector3(size.x+0.12,0.38,size.z+0.12),pos+Vector3(0,0.19,0),trim,false)
	_box(Vector3(size.x+0.34,0.18,size.z+0.34),pos+Vector3(0,size.y-0.05,0),trim,false)
	_roof(pos+Vector3(0,size.y,0),size.x+0.65,size.z+0.65)
	for side in [-1,1]:
		for i in maxi(1,int(size.x/3.2)):
			var x: float = -size.x/2+1.6+i*3.2
			if x > size.x/2-0.6: continue
			_window(pos+Vector3(x,4.6,side*(size.z/2+0.045)),0.0)
		for i in maxi(1,int(size.z/3.2)):
			var z: float = -size.z/2+1.6+i*3.2
			if z > size.z/2-0.6: continue
			_window(pos+Vector3(side*(size.x/2+0.045),4.6,z),PI/2)
	# Doors on all sides; entirely decorative and flush with the solid building.
	for side in [-1,1]:
		_door(pos+Vector3(0,0,side*(size.z/2+0.065)),0.0)
		_door(pos+Vector3(side*(size.x/2+0.065),0,0),PI/2)

func _window(pos: Vector3, yaw: float) -> void:
	var group := Node3D.new()
	add_child(group)
	group.position = pos
	group.rotation.y = yaw
	_detail(group,Vector3(1.15,1.65,0.09),Vector3.ZERO,trim)
	_detail(group,Vector3(0.9,1.4,0.12),Vector3.ZERO,dark)
	for side in [-1,1]:
		_detail(group,Vector3(0.42,1.42,0.16),Vector3(side*0.73,0,0),shutters)
		for i in 6: _detail(group,Vector3(0.42,0.025,0.18),Vector3(side*0.73,-0.5+i*0.2,0),trim)
	_detail(group,Vector3(1.35,0.13,0.35),Vector3(0,-0.84,0),trim)

func _door(pos: Vector3, yaw: float) -> void:
	var group := Node3D.new()
	add_child(group)
	group.position = pos
	group.rotation.y = yaw
	_detail(group,Vector3(1.48,2.65,0.15),Vector3(0,1.325,0),trim)
	_detail(group,Vector3(1.17,2.45,0.19),Vector3(0,1.225,0),wood)
	_detail(group,Vector3(0.05,2.4,0.22),Vector3(0,1.2,0),dark)
	for y in [0.35,1.7]: _detail(group,Vector3(1.1,0.07,0.24),Vector3(0,y,0),dark)

func _detail(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = mat
	parent.add_child(mesh)

func _roof(pos: Vector3, width: float, depth: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := [Vector3(-width/2,0,-depth/2),Vector3(width/2,0,-depth/2),Vector3(width/2,0,depth/2),Vector3(-width/2,0,depth/2),Vector3(0,1.25,-depth/2),Vector3(0,1.25,depth/2)]
	for index in [0,4,5,0,5,3,4,1,2,4,2,5,0,1,4,3,5,2]:
		surface.add_vertex(p[index])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = roof
	mesh.position = pos
	add_child(mesh)

func _arch(pos: Vector3, width: float) -> void:
	for side in [-1,1]:
		_box(Vector3(0.65,3.1,0.85),pos+Vector3(side*(width/2),1.55,0),trim,true)
	for i in 16:
		var angle := PI * (float(i)+0.5)/16.0
		var block := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width*PI/32.0+0.04,0.48,0.85)
		block.mesh = mesh
		block.material_override = trim
		block.position = pos+Vector3(cos(angle)*width/2,3.1+sin(angle)*1.25,0)
		block.rotation.z = atan2(1.25*cos(angle),-width/2*sin(angle))
		add_child(block)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 4
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		collision.shape = shape
		body.add_child(collision)
		block.add_child(body)

func _cylinder(pos: Vector3, radius: float, height: float, mat: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = mat
	add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 4
	body.position = pos
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _barrel(pos: Vector3) -> void:
	_cylinder(pos+Vector3(0,0.5,0),0.42,1.0,wood)
	for y in [0.12,0.88]: _cylinder(pos+Vector3(0,y,0),0.43,0.065,dark)

func _pot(pos: Vector3) -> void:
	_cylinder(pos+Vector3(0,0.25,0),0.32,0.5,roof)
	var foliage := _material(Color("5c7147"))
	for i in 3:
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.24
		sphere.height = 0.48
		mesh.mesh = sphere
		mesh.position = pos+Vector3(sin(float(i)*2)*0.16,0.6+float(i)*0.08,cos(float(i)*2)*0.16)
		mesh.material_override = foliage
		add_child(mesh)
