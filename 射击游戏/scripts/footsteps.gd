extends Node
var actor: CharacterBody3D
var listener: Camera3D
var local := false
var voice: Node
var distance := 0.0
var grounded := false
var initialized := false
var air_time := 0.0
var obstruction_clock := 0.0
var blocked := false
var rng := RandomNumberGenerator.new()
var bus_name := ""
var filter: AudioEffectLowPassFilter
var count := 0

func configure(body: CharacterBody3D, camera: Camera3D, own: bool) -> void:
	actor=body
	listener=camera
	local=own
	rng.randomize()
	process_mode=Node.PROCESS_MODE_PAUSABLE
	voice=AudioStreamPlayer.new() if own else AudioStreamPlayer3D.new()
	if not own:
		voice.max_distance=24
		voice.unit_size=4
		bus_name="Footsteps_"+str(get_instance_id())
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,bus_name)
		filter=AudioEffectLowPassFilter.new()
		filter.cutoff_hz=20000
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus_name),filter)
		voice.bus=bus_name
	add_child(voice)
	voice.volume_db=-19 if own else -8

func reset() -> void:
	distance=0
	initialized=false
	air_time=0
	if voice: voice.stop()

func surface() -> String:
	var query:=PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*0.2,actor.global_position-Vector3.UP*0.5,1)
	var hit:=actor.get_world_3d().direct_space_state.intersect_ray(query)
	return "wood" if not hit.is_empty() and hit.collider.get_meta("footstep_surface","")=="wood" else "hard"

func emit_step(kind: String) -> void:
	voice.stream=load("res://assets/audio/combat/%s_%d.wav"%[kind,rng.randi_range(0,3)])
	voice.play()
	count+=1

func advance(delta: float, enabled: bool) -> void:
	if not enabled:
		reset()
		return
	if not local:
		voice.global_position=actor.global_position+Vector3.UP*0.2
		obstruction_clock-=delta
		if obstruction_clock<=0:
			obstruction_clock=0.1
			var query:=PhysicsRayQueryParameters3D.create(voice.global_position,listener.global_position,1)
			blocked=not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		voice.volume_db=move_toward(voice.volume_db,-16.0 if blocked else -8.0,delta*80)
		filter.cutoff_hz=lerpf(filter.cutoff_hz,1800.0 if blocked else 20000.0,1-exp(-delta*20))
	var on_floor:=actor.is_on_floor()
	if not initialized:
		grounded=on_floor
		initialized=true
	if not on_floor: air_time+=delta
	if on_floor and not grounded and air_time>0.12:
		emit_step("land")
		distance=0
	if on_floor:
		air_time=0
		var movement:=actor.get_real_velocity()
		distance+=Vector2(movement.x,movement.z).length()*delta
		if distance>=1.6:
			distance=fmod(distance,1.6)
			emit_step(surface())
	grounded=on_floor

func _exit_tree() -> void:
	if is_instance_valid(voice):
		voice.stop()
		voice.stream=null
		voice.bus="Master"
	if not bus_name.is_empty():
		var index:=AudioServer.get_bus_index(bus_name)
		if index>0: AudioServer.remove_bus(index)
