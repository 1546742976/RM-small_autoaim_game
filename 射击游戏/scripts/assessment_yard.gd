extends "res://scripts/map_geometry.gd"
const Layout=preload("res://scripts/yard_layout.gd")
var layout=Layout.new()
var generation_seed:=0
var bot_spawn:=Vector3(0,0.02,-33)
var generation_ms:=0.0
var navigation_ready:=false
var navigation_region: NavigationRegion3D

func _ready() -> void:
	var start:=Time.get_ticks_usec()
	layout.generate(generation_seed)
	spawn_transform=Transform3D(Basis.IDENTITY,Vector3(0,0.02,33))
	var env:=Environment.new()
	var sky:=Sky.new()
	var sky_material:=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("628fb2")
	sky_material.sky_horizon_color=Color("e8e3d5")
	sky_material.ground_bottom_color=Color("72736b")
	sky_material.ground_horizon_color=Color("c5c5b8")
	sky.sky_material=sky_material
	env.sky=sky
	env.background_mode=Environment.BG_SKY
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy=0.7
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	var world_env:=WorldEnvironment.new()
	world_env.environment=env
	add_child(world_env)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-62,-28,0)
	sun.light_energy=1.5
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=100
	add_child(sun)
	var floor_mat:=_material(Color("868780"))
	floor_mat.albedo_texture=load("res://assets/town/stone_Color.jpg")
	floor_mat.uv1_triplanar=true
	floor_mat.uv1_scale=Vector3.ONE*0.4
	_box(Vector3(42,0.4,72),Vector3(0,-0.2,0),floor_mat,true)
	var wall:=_material(Color("777c7b"))
	for x in [-21.25,21.25]: _box(Vector3(0.5,9,72),Vector3(x,4.5,0),wall,true)
	for z in [-36.25,36.25]: _box(Vector3(43,9,0.5),Vector3(0,4.5,z),wall,true)
	var materials: Array[Material]=[]
	for color in [Color("a98a60"),Color("8e785b"),Color("b49b76")]:
		var mat:=_material(color)
		mat.albedo_texture=load("res://assets/town/wood_Color.jpg")
		mat.normal_enabled=true
		mat.normal_texture=load("res://assets/town/wood_NormalGL.jpg")
		mat.normal_scale=0.45
		materials.append(mat)
	var transforms: Array=[[],[],[]]
	for z in Layout.SIZE.y:
		for x in Layout.SIZE.x:
			var p:=Vector2i(x,z)
			var count: int=layout.height_at(p)
			if count==0 or count==4: continue
			var pos: Vector3=layout.world(p)
			var body:=StaticBody3D.new()
			body.collision_layer=1
			body.collision_mask=12
			var shape:=CollisionShape3D.new()
			var box:=BoxShape3D.new()
			box.size=Vector3(2,count*2,2)
			shape.shape=box
			body.add_child(shape)
			body.position=Vector3(pos.x,count,pos.z)
			add_child(body)
			for level in count:
				transforms[(x+z+level)%3].append(Transform3D(Basis(Vector3.UP,((x+level)%4)*PI/2),Vector3(pos.x,level*2+1,pos.z)))
	for i in 3:
		var batch:=MultiMeshInstance3D.new()
		var mesh:=BoxMesh.new()
		mesh.size=Vector3.ONE*2
		mesh.material=materials[i]
		var multi:=MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=mesh
		multi.instance_count=transforms[i].size()
		for j in transforms[i].size(): multi.set_instance_transform(j,transforms[i][j])
		batch.multimesh=multi
		add_child(batch)
	for z in [-30.0,30.0]: _box(Vector3(41,0.01,0.12),Vector3(0,0.008,z),_material(Color("d9ad66")),false)
	for platform in layout.platforms: _platform(platform,materials[0])
	generation_ms=(Time.get_ticks_usec()-start)/1000.0
	_build_navigation()

func _platform(config: Dictionary,mat: Material) -> void:
	var center: Vector3=layout.platform_center(config)
	center.y=0
	_box(Vector3(4,2,4),center+Vector3(0,1,0),mat,true)
	get_child(get_child_count()-1).set_meta("footstep_surface","wood")
	var trim:=_material(Color("d9ad66"))
	for sign_z in [-1,1]:
		var stair_center:=center+Vector3(0,0,sign_z*4)
		# Ten visible treads share a smooth solid ramp for both characters.
		for step in 10:
			var height: float=(step+1)*0.2
			var z: float=sign_z*(5.8-step*0.4)
			_box(Vector3(2,height,0.4),center+Vector3(0,height*0.5,z),mat,false)
		var body:=StaticBody3D.new()
		var shape:=CollisionShape3D.new()
		var wedge:=ConvexPolygonShape3D.new()
		var points:=PackedVector3Array()
		for x in [-1.0,1.0]:
			points.append(Vector3(x,0,sign_z*2))
			points.append(Vector3(x,0,-sign_z*2))
			points.append(Vector3(x,2,-sign_z*2))
		wedge.points=points
		shape.shape=wedge
		body.add_child(shape)
		body.set_meta("footstep_surface","wood")
		body.position=stair_center
		add_child(body)
		_box(Vector3(2,0.02,0.12),center+Vector3(0,2.015,sign_z*1.9),trim,false)

func _build_navigation() -> void:
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map,0.1)
	add_to_group("yard_navigation_source")
	navigation_region=NavigationRegion3D.new()
	var mesh:=NavigationMesh.new()
	mesh.cell_size=0.25
	mesh.cell_height=0.1
	mesh.agent_height=1.8
	mesh.agent_radius=0.5
	mesh.agent_max_climb=0.2
	mesh.agent_max_slope=35.0
	mesh.geometry_parsed_geometry_type=NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_source_geometry_mode=NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name="yard_navigation_source"
	navigation_region.navigation_mesh=mesh
	add_child(navigation_region)
	navigation_region.bake_finished.connect(_navigation_baked)
	navigation_region.bake_navigation_mesh(true)

func _navigation_baked() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	navigation_ready=true

func navigation_path(from: Vector3,to: Vector3) -> PackedVector3Array:
	if not navigation_ready: return PackedVector3Array()
	return NavigationServer3D.map_get_path(get_world_3d().navigation_map,from,to,true)
