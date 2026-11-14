extends CharacterBody3D
const Target=preload("res://scripts/training_target.gd")
const Weapon=preload("res://scripts/weapon_controller.gd")
var game: Node3D
var layout: RefCounted
var target: Node3D
var weapon: Node
var gun: Node3D
var flash: MeshInstance3D
var magazine: Node3D
var magazine_home:=Transform3D.IDENTITY
var sound: AudioStreamPlayer3D
var rng:=RandomNumberGenerator.new()
var route:=PackedVector3Array()
var waypoint:=0
var goal:=Vector3.ZERO
var patrol:=PackedVector3Array()
var patrol_index:=0
var last_seen:=Vector3.ZERO
var memory:=0.0
var reaction:=0.0
var burst_left:=0
var burst_wait:=0.0
var aim_offset:=Vector2.ZERO
var aim_direction:=Vector3.FORWARD
var visible_player:=false
var clock:=0.0
var repath:=0.0
var shot_count:=0
var flash_left:=0.0
var active:=false
var dead_time:=0.0
var pose_elapsed:=0.0

func _ready() -> void:
	collision_layer=8
	collision_mask=1|4|64
	floor_snap_length=0.35
	var shape:=CollisionShape3D.new()
	var capsule:=CapsuleShape3D.new()
	capsule.radius=0.3
	capsule.height=1.8
	shape.shape=capsule
	shape.position.y=0.9
	add_child(shape)
	target=Target.new()
	target.solid_enabled=false
	target.setup(0,false)
	# Source actor faces +Z; controller and weapon use Godot's -Z forward.
	target.rotation.y=PI
	add_child(target)
	target.set_physics_process(false)
	weapon=Weapon.new()
	add_child(weapon)
	weapon.reset("ak47")
	weapon.set_physics_process(false)
	weapon.fired.connect(_fire)
	gun=preload("res://assets/models/bot_ak47.glb").instantiate()
	add_child(gun)
	for node in gun.find_children("*Arm*","Node3D",true,false):
		if node is MeshInstance3D: node.hide()
	gun.position=Vector3(0.16,1.20,-0.04)
	magazine=gun.find_child("Magazine*",true,false)
	if magazine: magazine_home=magazine.transform
	flash=MeshInstance3D.new()
	var sphere:=SphereMesh.new()
	sphere.radius=0.055
	sphere.height=0.13
	flash.mesh=sphere
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("ffd58a")
	flash.material_override=material
	gun.add_child(flash)
	flash.position=Vector3(0,0.1975,-0.84)
	flash.hide()
	sound=AudioStreamPlayer3D.new()
	sound.stream=game.sounds.ak47
	sound.volume_db=-6
	sound.max_distance=70
	add_child(sound)
	rng.seed=layout.seed_value^185723
	_new_patrol()

func _new_patrol() -> void:
	patrol.clear()
	var band:=rng.randi_range(0,2)
	var points: Array=layout.lanes[band].duplicate()
	var toward_far:=global_position.z>0
	if toward_far: points.reverse()
	for p in points: patrol.append(layout.world(p))
	patrol.insert(patrol.size()/2,layout.platform_center(layout.platforms[band]))
	patrol.append(layout.world(Vector2i(10,1 if toward_far else 34)))
	patrol_index=0
	goal=patrol[0]

func can_see(point: Vector3) -> bool:
	var eye:=global_position+Vector3(0,1.65,0)
	var offset:=point-eye
	if offset.length()>45: return false
	if -global_basis.z.dot(offset.normalized())<cos(deg_to_rad(60)): return false
	var query:=PhysicsRayQueryParameters3D.create(eye,point,1|16)
	query.collide_with_areas=true
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider.has_meta("player_region")

func step(delta: float) -> void:
	if not active or not target.alive: return
	target.active=true
	weapon.active=not game.settling
	# NPC reserve is replenished, but the real magazine and reload clock are used.
	weapon.reserve=50
	weapon.advance_ms(delta*1000)
	clock+=delta
	burst_wait=maxf(0,burst_wait-delta)
	repath-=delta
	visible_player=can_see(game.player.global_position+Vector3(0,1.65,0)) or can_see(game.player.global_position+Vector3(0,1.1,0))
	if visible_player:
		last_seen=game.player.global_position
		memory=2.0
		reaction+=delta
	else:
		reaction=0
		if memory>0 and memory<=delta: _new_patrol()
		memory=maxf(0,memory-delta)
		burst_left=0
	var desired:=Vector3.ZERO
	if visible_player:
		goal=last_seen
		var desired_yaw:=atan2(-(last_seen.x-global_position.x),-(last_seen.z-global_position.z))
		rotation.y=rotate_toward(rotation.y,desired_yaw,PI*delta)
	else:
		if memory>0: goal=last_seen
		elif global_position.distance_to(goal)<0.5:
			patrol_index+=1
			if patrol_index>=patrol.size(): _new_patrol()
			else: goal=patrol[patrol_index]
			repath=0
		if repath<=0:
			route=game.arena.map_root.navigation_path(global_position,goal)
			waypoint=1 if route.size()>1 else 0
			repath=0.35
		if waypoint<route.size():
			var offset:=route[waypoint]-global_position
			offset.y=0
			if offset.length()<0.18: waypoint+=1
			else: desired=offset.normalized()*minf(3.5,offset.length()/delta)
		if desired.length()>0.1: rotation.y=rotate_toward(rotation.y,atan2(-desired.x,-desired.z),PI*delta)
	var horizontal:=Vector3(velocity.x,0,velocity.z).move_toward(desired,12*delta if desired.is_zero_approx() else 30*delta)
	velocity=Vector3(horizontal.x,-0.1 if is_on_floor() else velocity.y-20*delta,horizontal.z)
	move_and_slide()
	if visible_player:
		var muzzle: Vector3=gun.global_transform*Vector3(0,0.1975,-0.8215)
		var desired_aim: Vector3=(last_seen+Vector3(0,1.65,0)-muzzle).normalized()
		var amount:=minf(1,PI*delta/maxf(0.0001,aim_direction.angle_to(desired_aim)))
		aim_direction=aim_direction.slerp(desired_aim,amount).normalized()
		if not game.settling and is_on_floor() and reaction>=0.45 and horizontal.length()/3.5<0.34 and aim_direction.angle_to(desired_aim)<deg_to_rad(0.6):
			if burst_left==0 and burst_wait<=0 and not weapon.is_reloading():
				burst_left=3
				var angle:=rng.randf()*TAU
				aim_offset=Vector2(cos(angle),sin(angle))*tan(deg_to_rad(1.2))*sqrt(rng.randf())
			if burst_left>0 and weapon.fire_error().is_empty():
				weapon.try_fire()
				burst_left-=1
				if burst_left==0: burst_wait=0.6
	else: aim_direction=-global_basis.z
	# Skinning and arm constraints need only 30 Hz. Child hit regions retain
	# the sampled skeleton pose and inherit continuous body movement.
	pose_elapsed+=delta
	if pose_elapsed>=1.0/30.0:
		pose(pose_elapsed)
		pose_elapsed=0

func _fire() -> void:
	shot_count+=1
	var origin: Vector3=gun.global_transform*Vector3(0,0.1975,-0.8215)
	var eye:=global_position+Vector3(0,1.65,0)
	var guard:=PhysicsRayQueryParameters3D.create(eye,origin,17)
	guard.collide_with_areas=true
	var obstruction:=get_world_3d().direct_space_state.intersect_ray(guard)
	if not obstruction.is_empty(): origin=obstruction.position+(eye-origin).normalized()*0.011
	var basis:=Basis.looking_at(aim_direction)
	var direction: Vector3=(aim_direction+basis.x*aim_offset.x+basis.y*aim_offset.y).normalized()
	game.projectiles.spawn(origin,direction,"bot")
	flash_left=0.065
	sound.play()

func pose(delta: float) -> void:
	flash_left=maxf(0,flash_left-delta)
	flash.visible=flash_left>0
	target._visuals.moving=Vector2(velocity.x,velocity.z).length()>0.2
	target._visuals.sample(clock,-1)
	var reload_p: float=1.0-weapon.reload_left_ms/2500.0 if weapon.is_reloading() else 0.0
	gun.rotation=Vector3(0,0,sin(reload_p*PI)*0.3)
	if visible_player: gun.rotation.x=asin(clampf(aim_direction.y,-1,1))
	if magazine:
		magazine.transform=magazine_home
		magazine.position.y-=sin(reload_p*PI)*0.3
	var left: Vector3=gun.global_transform*Vector3(0,0.14,-0.475)
	if weapon.is_reloading() and magazine: left=magazine.global_position
	_arm("Right",gun.global_transform*Vector3(0,0.096,-0.132),global_position+global_basis*Vector3(0.55,0.9,0.1))
	_arm("Left",left,global_position+global_basis*Vector3(-0.5,0.85,-0.15))
	target._sync_regions()

func _arm(side: String,hand: Vector3,pole: Vector3) -> void:
	var skeleton: Skeleton3D=target._visuals.skeleton
	var upper:=skeleton.find_bone("mixamorig_"+side+"Arm")
	var fore:=skeleton.find_bone("mixamorig_"+side+"ForeArm")
	var wrist:=skeleton.find_bone("mixamorig_"+side+"Hand")
	var a:=skeleton.get_bone_global_pose(upper)
	var b:=skeleton.get_bone_global_pose(fore)
	var c:=skeleton.get_bone_global_pose(wrist)
	var inverse:=skeleton.global_transform.affine_inverse()
	var end:=inverse*hand
	var axis: Vector3=(end-a.origin).normalized()
	var l1:=a.origin.distance_to(b.origin)
	var l2:=b.origin.distance_to(c.origin)
	var distance:=clampf(a.origin.distance_to(end),absf(l1-l2)+0.001,l1+l2-0.001)
	end=a.origin+axis*distance
	var along: float=(l1*l1-l2*l2+distance*distance)/(2*distance)
	var bend: Vector3=inverse*pole-a.origin
	bend=(bend-axis*bend.dot(axis)).normalized()
	var elbow: Vector3=a.origin+axis*along+bend*sqrt(maxf(0,l1*l1-along*along))
	a.basis=Basis(Quaternion((b.origin-a.origin).normalized(),(elbow-a.origin).normalized()))*a.basis
	skeleton.set_bone_global_pose(upper,a)
	skeleton.force_update_all_bone_transforms()
	b=skeleton.get_bone_global_pose(fore)
	c=skeleton.get_bone_global_pose(wrist)
	b.basis=Basis(Quaternion((c.origin-b.origin).normalized(),(end-b.origin).normalized()))*b.basis
	skeleton.set_bone_global_pose(fore,b)
	skeleton.force_update_all_bone_transforms()

func _process(delta: float) -> void:
	if is_instance_valid(target) and not target.alive:
		dead_time+=delta
		target._visuals.sample(clock,minf(dead_time,0.78))
		gun.hide()
		flash.hide()
