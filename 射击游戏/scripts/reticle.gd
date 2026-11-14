extends Control
## Thin geometric reticle, independent from font glyph metrics and weapon aim.
var can_fire := false
var hit_left := 0.0
var headshot := false
var gap := 8.0
const WHITE := Color("f2f0ea")
const AMBER := Color("d9ad66")

func _process(delta: float) -> void:
	if get_tree().paused: return
	gap = move_toward(gap,3.0 if can_fire else 8.0,delta*55.0)
	hit_left = maxf(0,hit_left-delta)
	queue_redraw()

func _draw() -> void:
	var center := size/2
	var color := WHITE if can_fire else AMBER
	for direction: Vector2 in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
		var a := center + direction*gap
		var b := center + direction*(gap+5)
		draw_line(a,b,Color(0,0,0,0.7),3.5,true)
		draw_line(a,b,color,1.5,true)
	if hit_left > 0:
		for direction: Vector2 in [Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
			draw_line(center+direction*9,center+direction*14,AMBER if headshot else WHITE,2.0,true)

func show_hit(is_headshot: bool) -> void:
	headshot = is_headshot
	hit_left = 0.18
