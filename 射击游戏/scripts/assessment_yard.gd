extends "res://scripts/map_geometry.gd"
const Layout=preload("res://scripts/yard_layout.gd")
var layout=Layout.new()
var generation_seed:=0
var bot_spawn:=Vector3(0,0.02,-33)
var generation_ms:=0.0

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
	for x in [-21.25,21.25]: _box(Vector3(0.5,7,72),Vector3(x,3.5,0),wall,true)
	for z in [-36.25,36.25]: _box(Vector3(43,7,0.5),Vector3(0,3.5,z),wall,true)
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
			if count==0: continue
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
	generation_ms=(Time.get_ticks_usec()-start)/1000.0
