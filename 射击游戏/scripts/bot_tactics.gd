extends RefCounted
## Navigation and tactics consume omniscient position, never bypass collision.
const Profile=preload("res://scripts/bot_profile.gd")
var bot: CharacterBody3D
var state := "pursue"
var decision_left := 0.0
var cover_left := 0.0
var jump_left := 0.0
var lost := 0.0
var blocked_time := 0.0
var bursts := 0
var cover := Vector3.ZERO
var peek := Vector3.ZERO
var has_cover := false
var move_goal := Vector3.ZERO
var move_origin := Vector3.ZERO
var moving := false
var jumped := false
var jump_velocity := Vector3.ZERO
var stuck_time := 0.0
var stuck_origin := Vector3.ZERO
var stuck_count := 0
var jump_count := 0
var relocation_count := 0
var recovery_count := 0

func initialize(actor: CharacterBody3D) -> void:
	bot=actor
	stuck_origin=bot.global_position

func clear_line(a: Vector3,b: Vector3) -> bool:
	return bot.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1)).is_empty()

func free_capsule(point: Vector3) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	var shape:=CapsuleShape3D.new()
	shape.radius=0.31
	shape.height=1.8
	query.shape=shape
	query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*0.93)
	query.collision_mask=1|4
	query.exclude=[bot.get_rid()]
	return bot.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func reachable(point: Vector3) -> bool:
	var path: PackedVector3Array=bot.game.arena.map_root.navigation_path(bot.global_position,point)
	return not path.is_empty() and path[-1].distance_to(point)<0.5

func pick_cover(player: Vector3) -> void:
	has_cover=false
	var best:=INF
	var cell: Vector2i=bot.layout.cell(bot.global_position)
	# Grid corners shared with crate geometry; navigation handles stairs separately.
	for z in range(maxi(0,cell.y-4),mini(36,cell.y+5)):
		for x in range(maxi(0,cell.x-4),mini(21,cell.x+5)):
			var c:=Vector2i(x,z)
			if bot.layout.height_at(c)!=0: continue
			var point: Vector3=bot.layout.world(c)
			if point.distance_to(bot.global_position)>8: continue
			var adjacent:=false
			for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if bot.layout.height_at(c+d)>0: adjacent=true
			if not adjacent: continue
			if clear_line(player+Vector3.UP*1.65,point+Vector3.UP*1.1): continue
			if clear_line(player+Vector3.UP*1.65,point+Vector3.UP*1.65): continue
			if not free_capsule(point): continue
			for offset in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
				var exposed: Vector3=point+offset*1.8
				if not free_capsule(exposed) or not clear_line(exposed+Vector3.UP*1.65,player+Vector3.UP*1.65): continue
				if not clear_line(point+Vector3.UP,exposed+Vector3.UP): continue
				var distance:=exposed.distance_to(player)
				var score:=maxf(8-distance,0)+maxf(distance-18,0)
				if score>best: continue
				var path: PackedVector3Array=bot.game.arena.map_root.navigation_path(bot.global_position,point)
				if path.is_empty() or path[-1].distance_to(point)>0.5 or not reachable(exposed): continue
				var length:=0.0
				for i in range(1,path.size()): length+=path[i].distance_to(path[i-1])
				score=score*100+length+bot.rng.randf()*0.001
				if score<best:
					best=score
					cover=point
					peek=exposed
					has_cover=true

func begin_move(destination: Vector3) -> void:
	move_origin=bot.global_position
	move_goal=destination
	moving=true
	jumped=false
	bot.repath=0
	relocation_count+=1

func side_step(player: Vector3) -> Vector3:
	var side: Vector3=(player-bot.global_position).cross(Vector3.UP).normalized()
	if bot.rng.randf()<0.5: side=-side
	for sign_value in [1,-1]:
		var candidate: Vector3=bot.global_position+side*3.0*sign_value
		if free_capsule(candidate) and reachable(candidate): return candidate
	return player

func safe_jump(direction: Vector3) -> bool:
	if direction.is_zero_approx(): return false
	var start:=bot.global_position
	var flight:=2*Profile.JUMP_SPEED/Profile.GRAVITY
	var end:=start+direction*Profile.SPEED*flight
	var space:=bot.get_world_3d().direct_space_state
	var ground:=space.intersect_ray(PhysicsRayQueryParameters3D.create(end+Vector3.UP*0.6,end-Vector3.UP*0.55,1))
	if ground.is_empty() or ground.normal.y<0.82 or absf(ground.position.y-start.y)>0.5: return false
	if not reachable(ground.position+Vector3.UP*0.02): return false
	var query:=PhysicsShapeQueryParameters3D.new()
	var capsule:=CapsuleShape3D.new()
	capsule.radius=0.31
	capsule.height=1.8
	query.shape=capsule
	query.collision_mask=1|4
	query.exclude=[bot.get_rid()]
	var previous:=start+Vector3.UP*0.05
	for i in range(1,17):
		var t:=flight*i/16
		var next:=start+direction*Profile.SPEED*t+Vector3.UP*(Profile.JUMP_SPEED*t-0.5*Profile.GRAVITY*t*t+0.05)
		query.transform=Transform3D(Basis.IDENTITY,previous+Vector3.UP*0.9)
		query.motion=next-previous
		if not space.intersect_shape(query,1).is_empty(): return false
		var fraction:=space.cast_motion(query)
		if fraction[0]<0.999: return false
		previous=next
	return true

func desired(delta: float, visible_head: bool) -> Vector3:
	var player: Vector3=bot.game.player.global_position
	decision_left-=delta
	cover_left-=delta
	jump_left=maxf(0,jump_left-delta)
	blocked_time=0 if visible_head else blocked_time+delta
	if visible_head:
		moving=false
		bursts=0
		stuck_time=0
		stuck_origin=bot.global_position
		state="lock"
		# Finish an airborne trajectory, but never initiate a jump while locked.
		if not bot.is_on_floor() and jumped: return jump_velocity
		return Vector3.ZERO
	if state=="lock": decision_left=0
	if not bot.is_on_floor() and jumped:
		state="jump"
		return jump_velocity
	if cover_left<=0:
		cover_left=0.5
		pick_cover(player)
	if moving and bot.global_position.distance_to(move_goal)<0.4:
		moving=false
		bursts=0
		blocked_time=0
	if decision_left<=0:
		decision_left=0.25
		if bot.weapon.mag<=5 and not bot.weapon.is_reloading() and has_cover and bot.global_position.distance_to(cover)<0.65:
			bot.weapon.start_reload()
		if bot.weapon.is_reloading():
			state="reload"
			if has_cover and (not moving or move_goal.distance_to(cover)>0.5): begin_move(cover)
		elif not moving:
			if bursts>=2 or (blocked_time>=0.5 and visible_head==false):
				state="relocate"
				var destination: Vector3=peek if has_cover and peek.distance_to(bot.global_position)>=2 else (side_step(player) if visible_head or bursts>=2 else player)
				begin_move(destination)
			elif visible_head: state="fire"
			else: state="pursue"
	var destination: Vector3=move_goal if moving else player
	var desired_velocity:=Vector3.ZERO
	if moving or (not visible_head and not bot.weapon.is_reloading()):
		bot.goal=destination
		desired_velocity=bot.navigate(destination,delta)
	if not bot.weapon.is_reloading() and bot.is_on_floor() and moving and not jumped and jump_left<=0:
		var distance:=player.distance_to(bot.global_position)
		var threatened: bool=(-bot.game.player.global_basis.z).dot((bot.global_position-player).normalized())>0.5
		var direction:=desired_velocity.normalized()
		var obstacle:=not clear_line(bot.global_position+Vector3.UP*0.3,bot.global_position+direction*1.2+Vector3.UP*0.3)
		var low_obstacle:=obstacle and clear_line(bot.global_position+Vector3.UP*0.65,bot.global_position+direction*1.2+Vector3.UP*0.65)
		if ((threatened and distance>=6 and distance<=20) or low_obstacle) and safe_jump(direction):
			jumped=true
			jump_left=Profile.JUMP_COOLDOWN
			jump_velocity=direction*Profile.SPEED
			bot.velocity.y=Profile.JUMP_SPEED
			jump_count+=1
			state="jump"
	stuck_time+=delta
	if stuck_time>=1:
		if desired_velocity.length()>0.2 and bot.global_position.distance_to(stuck_origin)<0.2:
			stuck_count+=1
			bot.repath=0
			recovery_count+=1
			if stuck_count>=2:
				begin_move(side_step(player))
				stuck_count=0
		else: stuck_count=0
		stuck_time=0
		stuck_origin=bot.global_position
	return desired_velocity
