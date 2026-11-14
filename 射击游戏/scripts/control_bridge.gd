extends Node
## Opt-in, single-controller TCP bridge. No target data crosses this boundary.
const Direction = preload("res://scripts/shot_direction.gd")
const MAX_HEADER := 16384
const TIMEOUT_US := 2000000
const FRAME_INTERVAL_US := 33334
var game: Node3D
var server := TCPServer.new()
var token := ""
var peers: Array[Dictionary] = []
var controller_peer: Dictionary = {}
var pending_action: Dictionary = {}
var pending_observe: Dictionary = {}
var epoch := 0
var frame_id := 0
var issued: Dictionary = {}
var last_capture_us := -FRAME_INTERVAL_US

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.frame_post_draw.connect(_capture)

func configure(controller: Node3D) -> bool:
	var address := "0.0.0.0"
	var port := 47650
	var secret := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--control-bind="): address = arg.trim_prefix("--control-bind=")
		elif arg.begins_with("--control-port="):
			var value := arg.trim_prefix("--control-port=")
			if not value.is_valid_int():
				printerr("CONTROL: invalid port")
				return false
			port = int(value)
		elif arg.begins_with("--control-token="): secret = arg.trim_prefix("--control-token=")
	if port < 1 or port > 65535 or secret.is_empty():
		printerr("CONTROL: port must be 1..65535 and --control-token must be supplied")
		return false
	return start(controller,address,port,secret)

func start(controller: Node3D, address: String, port: int, secret: String) -> bool:
	game = controller
	token = secret
	var error := server.listen(port,address)
	if error != OK:
		printerr("CONTROL: cannot listen (%s)" % error_string(error))
		return false
	print("CONTROL listening on %s:%d" % [address,server.get_local_port()])
	return true

func _process(_delta: float) -> void:
	if not server.is_listening(): return
	while server.is_connection_available():
		var socket := server.take_connection()
		socket.set_no_delay(true)
		if peers.size() >= 8:
			socket.disconnect_from_host()
			continue
		peers.append({"socket":socket,"rx":PackedByteArray(),"tx":PackedByteArray(),
			"offset":0,"auth":false,"seen":Time.get_ticks_usec(),"last_id":0,
			"pending":false,"closing":false})
	for c in peers.duplicate():
		c.socket.poll()
		if c.socket.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_usec()-int(c.seen)>TIMEOUT_US:
			_drop(c)
			continue
		_flush(c)
		if not peers.has(c): continue
		var available: int = c.socket.get_available_bytes()
		if available > 0:
			var part: Array = c.socket.get_partial_data(mini(available,65536))
			if part[0] != OK:
				_drop(c)
				continue
			c.rx.append_array(part[1])
			if c.rx.size()>65536:
				_drop(c)
				continue
		# Responses are bounded: at most one command or image is outstanding.
		for i in 8:
			if c.pending or not c.tx.is_empty() or c.closing or c.rx.size()<4: break
			var length: int = (int(c.rx[0])<<24)|(int(c.rx[1])<<16)|(int(c.rx[2])<<8)|int(c.rx[3])
			if length<2 or length>MAX_HEADER:
				_drop(c)
				break
			if c.rx.size()<4+length: break
			var json := JSON.new()
			var parse_error := json.parse(c.rx.slice(4,4+length).get_string_from_utf8())
			c.rx = c.rx.slice(4+length)
			if parse_error != OK or not json.data is Dictionary:
				_drop(c)
				break
			_dispatch(c,json.data)
			_flush(c)
			if not peers.has(c): break

func _flush(c: Dictionary) -> void:
	if c.tx.is_empty(): return
	var end: int = mini(c.offset+262144,c.tx.size())
	var result: Array = c.socket.put_partial_data(c.tx.slice(c.offset,end))
	if result[0] != OK:
		_drop(c)
		return
	c.offset += int(result[1])
	if c.offset == c.tx.size():
		c.tx = PackedByteArray()
		c.offset = 0
		if c.closing: _drop(c)

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and absf(float(value))<=9007199254740991.0

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _dispatch(c: Dictionary, request: Dictionary) -> void:
	if not _integer(request.get("id")) or int(request.id)<=int(c.last_id) or request.get("v")!=1 or request.get("payload_bytes",0)!=0 or not request.get("type") is String:
		_reply(c,int(request.get("id",0)) if _integer(request.get("id")) else 0,{"ok":false,"error":"invalid_request"})
		c.closing = true
		return
	c.last_id = int(request.id)
	c.seen = Time.get_ticks_usec()
	var id: int = request.id
	var kind: String = request.type
	if not c.auth:
		if kind != "hello" or request.get("token") != token:
			_reply(c,id,{"ok":false,"error":"unauthorized"})
			c.closing = true
		elif not controller_peer.is_empty():
			_reply(c,id,{"ok":false,"error":"busy"})
			c.closing = true
		else:
			controller_peer = c
			c.auth = true
			invalidate("new_session")
			game.pending_shots = 0
			game.player.remote_controlled = true
			_reply(c,id,{"ok":true,"type":"hello","max_fps":30,"timeout_ms":2000})
		return
	match kind:
		"ping": _reply(c,id,{"ok":true,"state":state()})
		"disconnect":
			_reply(c,id,{"ok":true})
			c.closing = true
		"observe":
			if DisplayServer.get_name() == "headless":
				_reply(c,id,{"ok":false,"error":"image_unavailable"})
			else:
				c.pending = true
				pending_observe = {"peer":c,"id":id}
		"act", "reload":
			var error := _action_error(request)
			if not error.is_empty():
				_reply(c,id,{"ok":false,"error":error})
				return
			if kind == "act" and (not _number(request.get("yaw_deg")) or not _number(request.get("pitch_deg")) or not request.get("fire") is bool or absf(float(request.yaw_deg))>360.0 or absf(float(request.pitch_deg))>180.0):
				_reply(c,id,{"ok":false,"error":"invalid_action"})
				return
			c.pending = true
			pending_action = {"peer":c,"request":request,"epoch":epoch,
				"fire_error":game.weapon.fire_error() if request.get("fire",false) else ""}
		_:
			_reply(c,id,{"ok":false,"error":"unknown_type"})

func _action_error(request: Dictionary) -> String:
	if get_tree().paused: return "paused"
	if game.phase != "training": return "not_training"
	if not _integer(request.get("round_id")) or not _integer(request.get("frame_id")): return "stale_observation"
	if issued.is_empty() or request.round_id!=game.round_id or request.frame_id!=issued.frame_id or issued.epoch!=epoch or issued.round_id!=game.round_id:
		return "stale_observation"
	return ""

func apply_pending() -> void:
	if pending_action.is_empty(): return
	var job := pending_action
	pending_action = {}
	var c: Dictionary = job.peer
	var request: Dictionary = job.request
	if not peers.has(c): return
	var error := _action_error(request)
	if job.epoch!=epoch: error = "stale_observation"
	if not error.is_empty():
		_reply(c,request.id,{"ok":false,"error":error})
		return
	var result := {"ok":true}
	if request.type == "act":
		game.player.apply_look_delta(float(request.yaw_deg),float(request.pitch_deg))
		result.look_applied = true
		result.fired = false
		result.fire_error = "not_requested"
		if request.fire:
			var fire_error: String = job.fire_error
			if fire_error.is_empty(): fire_error = game.weapon.try_fire()
			result.fired = fire_error.is_empty()
			result.fire_error = fire_error
	else:
		result.reloaded = game.weapon.start_reload()
		result.reload_error = "" if result.reloaded else "reloading" if game.weapon.is_reloading() else "no_reserve" if game.weapon.reserve<=0 else "mag_full"
	result.state = state()
	_reply(c,request.id,result)

func state() -> Dictionary:
	return {"round_id":game.round_id,"phase":game.phase,"paused":get_tree().paused,
		"game_time_s":60.0-game.remaining if game.phase in ["training","results"] else 0.0,
		"remaining_s":game.remaining,"weapon":game.weapon.current_weapon,
		"mag":game.weapon.mag,"reserve":game.weapon.reserve,"reloading":game.weapon.is_reloading(),
		"can_fire":not get_tree().paused and game.phase=="training" and game.weapon.fire_error().is_empty(),
		"is_accurate":Direction.is_accurate(game.player.get_speed_ratio()),"shot_count":game.shots,
		"yaw_deg":-rad_to_deg(game.player.rotation.y),"pitch_deg":rad_to_deg(game.player._pitch)}

func _capture() -> void:
	if pending_observe.is_empty() or Time.get_ticks_usec()-last_capture_us<FRAME_INTERVAL_US: return
	var job := pending_observe
	pending_observe = {}
	var c: Dictionary = job.peer
	if not peers.has(c): return
	var snapshot: Dictionary = state()
	var projection: Projection = game.player.camera.get_camera_projection()
	var picture: Image = get_viewport().get_texture().get_image()
	if picture.is_empty():
		_reply(c,job.id,{"ok":false,"error":"image_unavailable"})
		return
	var scale := minf(1.0,1280.0/maxi(picture.get_width(),picture.get_height()))
	if scale<1.0: picture.resize(maxi(1,roundi(picture.get_width()*scale)),maxi(1,roundi(picture.get_height()*scale)),Image.INTERPOLATE_BILINEAR)
	picture.convert(Image.FORMAT_RGB8)
	var width := picture.get_width()
	var height := picture.get_height()
	var jpeg := picture.save_jpg_to_buffer(0.85)
	last_capture_us = Time.get_ticks_usec()
	frame_id += 1
	issued = {"frame_id":frame_id,"epoch":epoch,"round_id":game.round_id}
	_reply(c,job.id,{"ok":true,"type":"observation","frame_id":frame_id,"round_id":game.round_id,
		"timestamp_us":last_capture_us,"width":width,"height":height,"encoding":"jpeg",
		"camera":{"fx":projection.x.x*width/2.0,"fy":projection.y.y*height/2.0,"cx":width/2.0,"cy":height/2.0},
		"state":snapshot},jpeg)
	_flush(c)

func _reply(c: Dictionary, id: int, body: Dictionary, payload := PackedByteArray()) -> void:
	c.pending = false
	body.v = 1
	body.id = id
	body.payload_bytes = payload.size()
	var bytes := JSON.stringify(body).to_utf8_buffer()
	var length := bytes.size()
	var packet := PackedByteArray([(length>>24)&255,(length>>16)&255,(length>>8)&255,length&255])
	packet.append_array(bytes)
	packet.append_array(payload)
	c.tx = packet
	c.offset = 0

func invalidate(reason: String) -> void:
	epoch += 1
	issued = {}
	if not pending_action.is_empty():
		var job := pending_action
		pending_action = {}
		_reply(job.peer,job.request.id,{"ok":false,"error":reason})

func _drop(c: Dictionary) -> void:
	peers.erase(c)
	c.socket.disconnect_from_host()
	if not pending_observe.is_empty() and pending_observe.peer==c: pending_observe = {}
	if c.auth:
		controller_peer = {}
		invalidate("disconnected")
		game.player.remote_controlled = false
		game.pending_shots = 0
		game.pause_game()

func _exit_tree() -> void:
	server.stop()
	for c in peers: c.socket.disconnect_from_host()
