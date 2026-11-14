extends Node
## Local opt-in harness only; the network protocol cannot start a round.
var game: Node3D
var measure_path := ""
var warmup := 0
var times: Array[float] = []
var elapsed := 0.0
var last_us := 0
var done := false
var motion := false
var motion_time := 0.0
var exit_after := 0.0
var started_us := 0
func run(controller: Node3D) -> void:
	game = controller
	started_us = Time.get_ticks_usec()
	var map_id := "training_hall"
	var weapon_id := "ak47"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-map="): map_id = arg.trim_prefix("--fixture-map=")
		elif arg.begins_with("--fixture-weapon="): weapon_id = arg.trim_prefix("--fixture-weapon=")
		elif arg.begins_with("--control-measure="): measure_path = arg.trim_prefix("--control-measure=")
		elif arg=="--fixture-motion": motion = true
		elif arg.begins_with("--fixture-exit-after="): exit_after = float(arg.trim_prefix("--fixture-exit-after="))
	game.show_setup()
	game.ui._select(map_id,weapon_id)
	game.start_round()

func _process(delta: float) -> void:
	if exit_after>0 and Time.get_ticks_usec()-started_us>exit_after*1000000:
		get_tree().quit()
		return
	if not is_instance_valid(game) or measure_path.is_empty() or done: return
	if not game.player.remote_controlled or game.phase!="training" or get_tree().paused:
		last_us = 0
		return
	if motion:
		motion_time += delta
		var right := int(motion_time/0.6)%2==0
		Input.action_release("move_left" if right else "move_right")
		Input.action_press("move_right" if right else "move_left")
	warmup += 1
	var now := Time.get_ticks_usec()
	if warmup<=240 or last_us==0:
		last_us = now
		return
	var interval := (now-last_us)/1000.0
	last_us = now
	times.append(interval)
	elapsed += interval/1000.0
	if elapsed<30.0: return
	done = true
	Input.action_release("move_left")
	Input.action_release("move_right")
	times.sort()
	var result := {"seconds":elapsed,"frames":times.size(),"mean_fps":times.size()/elapsed,
		"p95_ms":times[int(times.size()*0.95)],"p99_ms":times[int(times.size()*0.99)],
		"worst_ms":times[-1],"gpu":RenderingServer.get_video_adapter_name(),"map":game.selected_map,
		"resolution":[get_viewport().get_texture().get_width(),get_viewport().get_texture().get_height()]}
	var file := FileAccess.open(measure_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("CONTROL PERFORMANCE saved")
