extends Node
## Samples actual imported animation/skeleton transforms, not authored predictions.
var game: Node3D
var checks := 0
var failures := 0
var folder := ""
var clip_reports: Array = []

func check(value: bool, label_text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("VIEWMODEL FAIL: "+label_text)

func frames(count: int = 2) -> void:
	for _i in count: await get_tree().physics_frame
	await get_tree().process_frame

func equip(id: String) -> void:
	game.show_setup()
	game.ui._select("training_hall",id)
	game.start_round()
	game.begin_training()

func snapshot(view) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for i: int in view.skeleton.get_bone_count():
		poses.append(view.skeleton.global_transform*view.skeleton.get_bone_global_pose(i))
	poses.append(view.magazine.global_transform)
	for name_text: String in ["Gun","Slide","Bolt"]:
		var node: Node3D = view.model.find_child(name_text,true,false)
		if node: poses.append(node.global_transform)
	return poses

func difference(a: Array[Transform3D], b: Array[Transform3D]) -> Vector2:
	var result := Vector2.ZERO
	if a.size()!=b.size(): return Vector2(INF,INF)
	for i: int in a.size():
		result.x=maxf(result.x,a[i].origin.distance_to(b[i].origin))
		result.y=maxf(result.y,a[i].basis.orthonormalized().get_rotation_quaternion().angle_to(
			b[i].basis.orthonormalized().get_rotation_quaternion()))
	return result

func run(controller: Node3D) -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	game=controller
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): folder=argument.trim_prefix("--capture-dir=")
	if folder.is_empty(): folder="user://viewmodel-checks"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(3)
	for id: String in ["deagle","ak47","m4a1"]:
		equip(id)
		await frames()
		game.set_physics_process(false)
		game.weapon.set_physics_process(false)
		game.player.active=false
		var view=game.player.view
		check(view.animator!=null and view.skeleton!=null,id+" has bound persistent arms")
		for clip: String in ["idle","reload_empty","reload_tactical"]:
			check(view.animator.has_animation(clip),id+" imported "+clip)
		for kind: String in ["empty","tactical"]:
			await check_clip(id,kind,view)
		game.set_physics_process(true)
		game.weapon.set_physics_process(true)
		await pause_and_completion(id)
	game.show_menu()
	check(clip_reports.size()==6,"all six dense animation checks completed")
	var report := {"checks":checks,"failures":failures,"sample_hz":120,"clips":clip_reports,
		"limits":{"contact_mm":2,"contact_degrees":5,"bone_length_percent":1,
			"boundary_mm":1,"boundary_degrees":0.5},
		"note":"Numerical contact and skeleton checks supplement, not replace, rendered inspection of finger and cloth intersections."}
	var file:=FileAccess.open(folder.path_join("viewmodel-checks.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("VIEWMODEL CHECKS: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)

func check_clip(id: String, kind: String, view) -> void:
	var clip := "reload_"+kind
	var duration: float=game.weapon.get_data().reload_ms/1000.0
	var data: Dictionary=view.manifest["clips"][clip]
	var contacts: Array=data.get("contacts",[])
	var transitions: Array=data.get("transitions",[])
	check(not contacts.is_empty(),id+" "+kind+" supplies measured contact intervals")
	check(not transitions.is_empty(),id+" "+kind+" supplies transition times")
	var skeleton: Skeleton3D=view.skeleton
	var lengths: Dictionary={}
	for side: String in ["L","R"]:
		var chain: Array=["L_arm_01","L_elbow_02","L_wrist_03"] if side=="L" else ["R_arm_024","R_elbow_025","R_wrist_026"]
		for j: int in range(2):
			var a:=skeleton.find_bone(chain[j])
			var b:=skeleton.find_bone(chain[j+1])
			check(a>=0 and b>=0,id+" "+chain[j]+" chain exists")
			if a>=0 and b>=0:
				lengths[Vector2i(a,b)]=skeleton.get_bone_global_rest(a).origin.distance_to(skeleton.get_bone_global_rest(b).origin)
	view.reset_pose()
	var idle:=snapshot(view)
	var camera: Transform3D=game.player.camera.transform
	var max_contact:=0.0
	var max_angle:=0.0
	var max_length_error:=0.0
	var contact_peak: Dictionary={}
	var bone_peak: Dictionary={}
	var max_step:=Vector2.ZERO
	var previous: Array[Transform3D]=[]
	var samples:=int(ceil(duration*120.0))
	var event_start: int=view.audio_event_count
	var serial:=100 if kind=="empty" else 101
	for i: int in range(samples+1):
		var p:=float(i)/samples
		# Use the normal event path for every sample except exact end, where the
		# production path resets to idle. Exact authored end is checked separately.
		if i<samples: view.set_reload(duration*1000.0*(1.0-p),duration*1000.0,kind,serial)
		else: view._sample(clip,1.0)
		for pair: Vector2i in lengths:
			var length: float=skeleton.get_bone_global_pose(pair.x).origin.distance_to(skeleton.get_bone_global_pose(pair.y).origin)
			var length_error:=absf(length/float(lengths[pair])-1.0)
			if length_error>max_length_error:
				max_length_error=length_error
				bone_peak={"p":p,"bone":skeleton.get_bone_name(pair.x),"rest":lengths[pair],"actual":length}
		for contact: Dictionary in contacts:
			if p<float(contact.start) or p>float(contact.end): continue
			var a: Node3D=view.model.find_child(str(contact.a),true,false)
			var b: Node3D=view.model.find_child(str(contact.b),true,false)
			if a==null or b==null:
				check(false,id+" missing contact marker "+str(contact))
				continue
			var ta: Transform3D=view.contact_transform(a)
			var tb: Transform3D=view.contact_transform(b)
			var gap:=ta.origin.distance_to(tb.origin)
			if gap>max_contact:
				max_contact=gap
				contact_peak={"p":p,"a":contact.a,"b":contact.b,"a_position":str(ta.origin),"b_position":str(tb.origin)}
			max_angle=maxf(max_angle,ta.basis.orthonormalized().get_rotation_quaternion().angle_to(tb.basis.orthonormalized().get_rotation_quaternion()))
		var current:=snapshot(view)
		if not previous.is_empty():
			var step:=difference(previous,current)
			max_step.x=maxf(max_step.x,step.x)
			max_step.y=maxf(max_step.y,step.y)
		previous=current
	check(max_contact<=0.002,id+" "+kind+" hand/prop contact <=2mm, actual "+str(max_contact*1000.0))
	check(rad_to_deg(max_angle)<=5.0,id+" "+kind+" contact direction <=5deg")
	check(max_length_error<=0.01,id+" "+kind+" fixed arm segment lengths")
	check(game.player.camera.transform==camera,id+" "+kind+" camera invariant")
	var events: int=data.events.size()
	check(view.audio_event_count-event_start==events,id+" "+kind+" each sound emitted once")
	view.set_reload(0.001,duration*1000.0,kind,serial)
	view.set_reload(duration*0.5*1000.0,duration*1000.0,kind,serial)
	view.set_reload(0.001,duration*1000.0,kind,serial)
	check(view.audio_event_count-event_start==events,id+" "+kind+" repeated seek cannot duplicate sound")
	var boundary:=Vector2.ZERO
	for p: float in transitions:
		view._sample(clip,maxf(0,p-0.0001/duration))
		var before:=snapshot(view)
		view._sample(clip,minf(1,p+0.0001/duration))
		var delta:=difference(before,snapshot(view))
		boundary.x=maxf(boundary.x,delta.x)
		boundary.y=maxf(boundary.y,delta.y)
	for p: float in [0.0,1.0]:
		view._sample(clip,p)
		var delta:=difference(idle,snapshot(view))
		boundary.x=maxf(boundary.x,delta.x)
		boundary.y=maxf(boundary.y,delta.y)
	check(boundary.x<=0.001,id+" "+kind+" transition/idle position continuity <=1mm")
	check(rad_to_deg(boundary.y)<=0.5,id+" "+kind+" transition/idle angular continuity <=0.5deg")
	if not contact_peak.is_empty():
		view._sample(clip,float(contact_peak.p))
		await frames(2)
		var a: Node3D=view.model.find_child(str(contact_peak.a),true,false)
		var b: Node3D=view.model.find_child(str(contact_peak.b),true,false)
		contact_peak["after_frame_global_gap_mm"]=a.global_position.distance_to(b.global_position)*1000.0
		contact_peak["direct_vs_global_mm"]=view.contact_transform(a).origin.distance_to(a.global_position)*1000.0
		check(float(contact_peak.direct_vs_global_mm)<=0.1,id+" sampled bone contacts agree with rendered attachment position")
	view.reset_pose()
	check(difference(idle,snapshot(view)).x<=0.00001,id+" "+kind+" reset restores same rig")
	for player: AudioStreamPlayer in view.audio_players.values():
		check(not player.playing,id+" reset stops mechanical sound")
	clip_reports.append({"weapon":id,"kind":kind,"samples":samples+1,
		"contact_peak":contact_peak,"bone_peak":bone_peak,
		"max_contact_mm":max_contact*1000.0,"max_contact_degrees":rad_to_deg(max_angle),
		"max_bone_length_percent":max_length_error*100.0,"max_boundary_mm":boundary.x*1000.0,
		"max_boundary_degrees":rad_to_deg(boundary.y),"max_sample_step_mm":max_step.x*1000.0,
		"max_sample_step_degrees":rad_to_deg(max_step.y),"sound_events":events})

func pause_and_completion(id: String) -> void:
	equip(id)
	await frames()
	game.weapon.mag=0
	check(game.weapon.start_reload(),id+" live empty reload starts")
	while game.weapon.reload_left_ms>float(game.weapon.get_data().reload_ms)*0.795: await frames(1)
	var playing_positions: Dictionary={}
	for name_text: String in game.player.view.audio_players:
		var audio: AudioStreamPlayer=game.player.view.audio_players[name_text]
		if audio.playing: playing_positions[name_text]=audio.get_playback_position()
	game.pause_game()
	var view=game.player.view
	var frozen:=snapshot(view)
	var clock: float=game.weapon.reload_left_ms
	var event_count: int=view.audio_event_count
	await frames(8)
	check(difference(frozen,snapshot(view)).x<0.000001 and game.weapon.reload_left_ms==clock,id+" pause freezes pose and clock")
	check(view.audio_event_count==event_count,id+" pause adds no sounds")
	check(not playing_positions.is_empty(),id+" pause exercised an active mechanical sound")
	for name_text: String in playing_positions:
		var audio: AudioStreamPlayer=view.audio_players[name_text]
		check(absf(audio.get_playback_position()-float(playing_positions[name_text]))<0.03,id+" pause freezes active sound playback")
	game.resume_game()
	while game.weapon.is_reloading():
		check(game.weapon.mag==0,id+" ammo only added at completion")
		await frames(1)
	await frames()
	check(game.weapon.mag==game.weapon.get_data().mag_size,id+" completion fills magazine")
	check(view.reload_progress<0,id+" completion returns to idle")
	game.weapon.mag-=1
	game.weapon.start_reload()
	await frames(4)
	game.show_menu()
	check(view.reload_progress<0,id+" menu interrupts and restores idle")
	for player: AudioStreamPlayer in view.audio_players.values():
		check(not player.playing,id+" interruption stops sound")
