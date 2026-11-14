extends Node3D
## Real moving volumes. Sweeps cover the interval between discrete Area updates.
signal impacted(origin: Vector3, direction: Vector3, collision: Dictionary, owner_id: String)
const SPEED := 25.0
const RADIUS := 0.01
const MAX_DISTANCE := 100.0
const LIFETIME := MAX_DISTANCE / SPEED
var bullets: Array[Dictionary] = []
var sphere := SphereShape3D.new()
var material := StandardMaterial3D.new()
var ball_mesh := SphereMesh.new()

func _ready() -> void:
	sphere.radius=RADIUS
	ball_mesh.radius=RADIUS
	ball_mesh.height=RADIUS*2
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("ffd991")
	material.emission_enabled=true
	material.emission=Color("ffcb70")
	material.emission_energy_multiplier=2.0
	ball_mesh.material=material

func spawn(origin: Vector3, direction: Vector3, owner_id: String, speed: float=SPEED) -> Dictionary:
	var area:=Area3D.new()
	area.name="Projectile"
	area.collision_layer=32
	area.collision_mask=3 if owner_id=="player" else 17
	area.monitorable=false
	var shape:=CollisionShape3D.new()
	shape.shape=sphere
	area.add_child(shape)
	var ball:=MeshInstance3D.new()
	ball.mesh=ball_mesh
	ball.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(ball)
	var sweep:=ShapeCast3D.new()
	sweep.shape=sphere
	sweep.collision_mask=area.collision_mask
	sweep.collide_with_areas=true
	sweep.collide_with_bodies=true
	sweep.enabled=false
	sweep.margin=0.0
	area.add_child(sweep)
	add_child(area)
	area.global_position=origin
	var trail:=MeshInstance3D.new()
	var cylinder:=CylinderMesh.new()
	cylinder.top_radius=0.003
	cylinder.bottom_radius=0.006
	cylinder.height=0.01
	cylinder.radial_segments=6
	cylinder.material=material
	trail.mesh=cylinder
	trail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)
	trail.hide()
	var bullet: Dictionary={"area":area,"ball":ball,"sweep":sweep,"trail":trail,"origin":origin,"direction":direction.normalized(),"owner":owner_id,"speed":speed,"age":0.0,"distance":0.0,"live":true,"fade":0.08,"overlap":null}
	area.area_entered.connect(func(other: Area3D):
		if bullet.live: bullet.overlap=other)
	area.body_entered.connect(func(other: Node3D):
		if bullet.live: bullet.overlap=other)
	bullets.append(bullet)
	return bullet

func advance(delta: float) -> void:
	for bullet in bullets.duplicate():
		if not bullet.live:
			bullet.fade-=delta
			if bullet.fade<=0: _remove(bullet)
			else: bullet.trail.scale=Vector3.ONE*(bullet.fade/0.08)
			continue
		var motion: Vector3=bullet.direction*minf(bullet.speed*delta,MAX_DISTANCE-bullet.distance)
		var sweep: ShapeCast3D=bullet.sweep
		# Cast motion alone may miss a shape the muzzle already overlaps.
		sweep.target_position=Vector3.ZERO
		sweep.force_shapecast_update()
		var starting_overlap:=sweep.is_colliding()
		if not starting_overlap:
			sweep.target_position=motion
			sweep.force_shapecast_update()
		var result: Dictionary={}
		var fraction:=1.0
		if sweep.is_colliding():
			fraction=0.0 if starting_overlap else sweep.get_closest_collision_safe_fraction()
			var closest:=INF
			for index in sweep.get_collision_count():
				var point:=sweep.get_collision_point(index)
				var distance: float=bullet.area.global_position.distance_squared_to(point)
				if distance<closest:
					closest=distance
					result={"collider":sweep.get_collider(index),"position":point,"normal":sweep.get_collision_normal(index)}
		elif is_instance_valid(bullet.overlap):
			result={"collider":bullet.overlap,"position":bullet.area.global_position,"normal":Vector3.ZERO}
			fraction=0.0
		bullet.area.global_position+=motion*fraction
		bullet.distance+=motion.length()*fraction
		bullet.age+=delta
		_update_trail(bullet)
		if not result.is_empty() or bullet.age>=MAX_DISTANCE/bullet.speed or bullet.distance>=MAX_DISTANCE-0.00001:
			bullet.live=false
			bullet.ball.hide()
			bullet.area.collision_layer=0
			bullet.area.collision_mask=0
			impacted.emit(bullet.origin,bullet.direction,result,bullet.owner)

func _update_trail(bullet: Dictionary) -> void:
	var length:=minf(0.75,bullet.distance)
	if length<0.001: return
	var trail: MeshInstance3D=bullet.trail
	trail.mesh.height=length
	trail.global_position=bullet.area.global_position-bullet.direction*length*0.5
	trail.global_basis=Basis(Quaternion(Vector3.UP,bullet.direction))
	_update_visibility(bullet)

func _update_visibility(bullet: Dictionary) -> void:
	var camera:=get_viewport().get_camera_3d()
	var tip: Vector3=bullet.area.global_position
	var tail: Vector3=tip-bullet.direction*minf(0.75,bullet.distance)
	# The tip may already be behind the eye while its trailing segment crosses
	# the near plane. Test the entire segment, including the short impact fade.
	var near_eye:=false
	if camera:
		var nearest:=Geometry3D.get_closest_point_to_segment(camera.global_position,tail,tip)
		near_eye=nearest.distance_to(camera.global_position)<0.4
	bullet.trail.visible=bullet.distance>=0.001 and not near_eye
	bullet.ball.visible=bullet.live and (not camera or tip.distance_to(camera.global_position)>=0.15)

func _process(_delta: float) -> void:
	for bullet in bullets: _update_visibility(bullet)

func live_count() -> int:
	var count:=0
	for bullet in bullets:
		if bullet.live: count+=1
	return count

func _remove(bullet: Dictionary) -> void:
	bullet.area.free()
	bullet.trail.free()
	bullets.erase(bullet)

func clear() -> void:
	for bullet in bullets.duplicate(): _remove(bullet)
