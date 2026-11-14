extends CharacterBody3D
const Profile=preload("res://scripts/bot_profile.gd")
const Tactics=preload("res://scripts/bot_tactics.gd")
var tactics: RefCounted
var navigation_only := false
var navigation_destination := Vector3.ZERO
var shot_log: Array[Dictionary]=[]
const Target=preload("res://scripts/training_target.gd")
const Weapon=preload("res://scripts/bot_weapon.gd")
var game: Node3D
var layout: RefCounted
var target: Node3D
var weapon: Node
var gun: Node3D
var flash: MeshInstance3D
var magazine: Node3D
var magazine_home:=Transform3D.IDENTITY
var shot_voices: Array[AudioStreamPlayer3D]=[]
var sound_index:=0
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
var aim_direction:=Vector3.FORWARD
var visible_player:=false
var clock:=0.0
var repath:=0.0
var shot_count:=0
var flash_left:=0.0
var footsteps: Node
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
	shot_voices.append(sound)
	for i in 3:
		var voice:=AudioStreamPlayer3D.new()
		voice.volume_db=-6
		voice.max_distance=70
		add_child(voice)
		shot_voices.append(voice)
	footsteps=preload("res://scripts/footsteps.gd").new()
	add_child(footsteps)
	footsteps.configure(self,game.player.camera,false)
	rng.seed=layout.seed_value^185723
	_new_patrol()
	tactics=Tactics.new()
	tactics.initialize(self)

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
	if offset.length()>80: return false
	if -global_basis.z.dot(offset.normalized())<cos(deg_to_rad(60)): return false
	var query:=PhysicsRayQueryParameters3D.create(eye,point,1|16)
	query.collide_with_areas=true
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider.has_meta("player_region") and hit.collider.get_meta("headshot",false)

func navigate(destination: Vector3,delta: float) -> Vector3:
	if repath<=0:
		route=game.arena.map_root.navigation_path(global_position,destination)
		waypoint=1 if route.size()>1 else 0
		repath=0.25
	while waypoint<route.size():
		var offset:=route[waypoint]-global_position
		offset.y=0
		if offset.length()<0.18: waypoint+=1
		else: return offset.normalized()*minf(Profile.SPEED,offset.length()/delta)
	return Vector3.ZERO

func step(delta: float) -> void:
	if not active or not target.alive or get_tree().paused:
		if not active or not target.alive: footsteps.reset()
		return
	target.active=true
	weapon.active=not game.settling
	weapon.reserve=50
	weapon.advance_ms(delta*1000)
	clock+=delta
	burst_wait=maxf(0,burst_wait-delta)
	repath-=delta
	last_seen=game.player.global_position
	var head:=last_seen+Vector3.UP*1.65
	var to_player:=last_seen-global_position
	var desired_yaw:=atan2(-to_player.x,-to_player.z)
	rotation.y=rotate_toward(rotation.y,desired_yaw,Profile.BODY_TURN*delta)
	visible_player=can_see(head)
	if visible_player:
		tactics.lost=0
		reaction+=delta
	else:
		tactics.lost+=delta
		if tactics.lost>Profile.LOST_SIGHT: reaction=0
		burst_left=0
	var desired: Vector3=navigate(navigation_destination,delta) if navigation_only else tactics.desired(delta,visible_player)
	if navigation_only and desired.length()>0.1:
		rotation.y=rotate_toward(rotation.y,atan2(-desired.x,-desired.z),Profile.BODY_TURN*delta)
	var horizontal:=Vector3(velocity.x,0,velocity.z)
	var rate:=Profile.BRAKE if desired.is_zero_approx() or horizontal.dot(desired)<0 else 30.0
	horizontal=horizontal.move_toward(desired,rate*delta)
	velocity.x=horizontal.x
	velocity.z=horizontal.z
	if is_on_floor():
		if velocity.y<=0: velocity.y=-0.1
	else: velocity.y-=Profile.GRAVITY*delta
	move_and_slide()
	footsteps.advance(delta,true)
	var muzzle: Vector3=gun.global_transform*Vector3(0,0.1975,-0.8215)
	var floor_head:=head.y
	if not game.player.is_on_floor():
		var floor_hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(last_seen,last_seen-Vector3.UP*20,1))
		if not floor_hit.is_empty(): floor_head=floor_hit.position.y+1.65
	var prediction: Vector3=Profile.intercept(muzzle,head,game.player.get_real_velocity(),not game.player.is_on_floor(),floor_head,Profile.PROJECTILE_SPEED)
	var desired_aim: Vector3=(prediction-muzzle).normalized()
	aim_direction=desired_aim
	if visible_player and not weapon.is_reloading():
		gun.look_at(gun.global_position+aim_direction,Vector3.UP)
		muzzle=gun.global_transform*Vector3(0,0.1975,-0.8215)
		prediction=Profile.intercept(muzzle,head,game.player.get_real_velocity(),not game.player.is_on_floor(),floor_head,Profile.PROJECTILE_SPEED)
		aim_direction=(prediction-muzzle).normalized()
	var real:=get_real_velocity()
	var stopped:=Vector2(real.x,real.z).length()/Profile.SPEED<0.34
	var clear: bool=tactics.clear_line(global_position+Vector3.UP*1.65,muzzle) and tactics.clear_line(muzzle,head) and tactics.clear_line(muzzle,prediction)
	if not navigation_only and not game.settling and visible_player and clear and is_on_floor() and stopped and desired.length()<0.1 and reaction>=Profile.REACTION:
		if burst_left==0 and burst_wait<=0 and not weapon.is_reloading(): burst_left=4 if to_player.length()<=12 else 3
		if burst_left>0 and weapon.fire_error().is_empty():
			weapon.try_fire()
			burst_left-=1
			if burst_left==0:
				burst_wait=Profile.BURST_PAUSE
				tactics.bursts+=1
	pose_elapsed+=delta
	if pose_elapsed>=1.0/30.0:
		pose(pose_elapsed)
		pose_elapsed=0

func _fire() -> void:
	shot_count+=1
	if "--extreme-checks" in OS.get_cmdline_user_args() or "--bot-checks" in OS.get_cmdline_user_args() or "--lock-checks" in OS.get_cmdline_user_args(): shot_log.append({"time":clock,"position":global_position,"grounded":is_on_floor(),"reaction":reaction,"speed":Vector2(get_real_velocity().x,get_real_velocity().z).length(),"direction":aim_direction})
	var origin: Vector3=gun.global_transform*Vector3(0,0.1975,-0.8215)
	var eye:=global_position+Vector3(0,1.65,0)
	var guard:=PhysicsRayQueryParameters3D.create(eye,origin,17)
	guard.collide_with_areas=true
	var obstruction:=get_world_3d().direct_space_state.intersect_ray(guard)
	if not obstruction.is_empty(): origin=obstruction.position+(eye-origin).normalized()*0.011
	var direction: Vector3=aim_direction
	game.projectiles.spawn(origin,direction,"bot",Profile.PROJECTILE_SPEED)
	flash_left=0.065
	var voice: AudioStreamPlayer3D=shot_voices[sound_index]
	sound_index=(sound_index+1)%shot_voices.size()
	voice.stream=game.combat_sound("ak47")
	voice.play()

func pose(delta: float) -> void:
	flash_left=maxf(0,flash_left-delta)
	flash.visible=flash_left>0
	target._visuals.moving=Vector2(velocity.x,velocity.z).length()>0.2
	target._visuals.sample(clock,-1)
	var reload_p: float=1.0-weapon.reload_left_ms/float(weapon.get_data().reload_ms) if weapon.is_reloading() else 0.0
	gun.rotation=Vector3(0,0,sin(reload_p*PI)*0.3)
	if visible_player and not weapon.is_reloading(): gun.look_at(gun.global_position+aim_direction,Vector3.UP)
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
