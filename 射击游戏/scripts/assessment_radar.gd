extends Control
const Snapshot = preload("res://scripts/radar_snapshot.gd")
const WHITE := Color("f2f0ea")
const AMBER := Color("d9ad66")
var snapshot := Snapshot.new()
var game: Node3D
var was_visible := false

func configure(controller: Node3D) -> void:
	game = controller
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	hide()
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	var enabled: bool = game.selected_map == "assessment_yard" and game.phase == "training" and is_instance_valid(game.duel)
	if not enabled:
		if snapshot.round_id != -1: snapshot.reset()
		visible = false
		was_visible = false
		return
	visible = not get_tree().paused and game.ui.hud.visible
	if not visible:
		was_visible = false
		return
	if snapshot.round_id != game.round_id:
		snapshot.reset()
		snapshot.round_id=game.round_id
	if snapshot.advance(delta, game.player.global_position, game.duel.bot.global_position, game.duel.player_alive, game.duel.bot.target.alive, game.player.rotation.y, not was_visible): queue_redraw()
	was_visible = true

func _draw() -> void:
	var center:=size*0.5
	var radius:=size.x*0.38
	draw_circle(center,radius+12,Color(0.055,0.065,0.075,0.78),true,-1,true)
	draw_arc(center,radius,0,TAU,64,Color(0.65,0.65,0.62,0.25),1,true)
	draw_circle(center,3,WHITE,true,-1,true)
	draw_line(center+Vector2(0,-8),center+Vector2(0,-14),WHITE,1.5,true)
	if not snapshot.present: return
	if snapshot.overlap:
		draw_arc(center,radius*0.6,0,TAU,64,Color(AMBER,0.35),4,true)
		return
	var angle: float=snapshot.sector*PI/4-PI/2
	for width in [12,8,4]:
		draw_arc(center,radius-4,angle-deg_to_rad(18),angle+deg_to_rad(18),24,Color(AMBER,0.12 if width>4 else 0.85),width,true)
