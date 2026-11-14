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
	if snapshot.round_id != game.round_id: snapshot.load_layout(game.arena.map_root.layout, game.round_id)
	if snapshot.advance(delta, game.player.global_position, game.duel.bot.global_position, game.duel.player_alive, game.duel.bot.target.alive, not was_visible): queue_redraw()
	was_visible = true

func map_rect() -> Rect2:
	var extent := size - Vector2(32, 24)
	var factor := minf(extent.x / Snapshot.BOUNDS.size.x, extent.y / Snapshot.BOUNDS.size.y)
	var map_size := Snapshot.BOUNDS.size * factor
	return Rect2((size - map_size) / 2, map_size)

func project(point: Vector2) -> Vector2:
	var rect := map_rect()
	return rect.position + (point - Snapshot.BOUNDS.position) / Snapshot.BOUNDS.size * rect.size

func _draw() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.055, 0.065, 0.075, 0.84)
	panel.set_corner_radius_all(6)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	var rect := map_rect()
	draw_rect(rect, Color(0.11, 0.13, 0.14, 0.72))
	for region in snapshot.regions:
		draw_rect(Rect2(project(region.position), region.size / Snapshot.BOUNDS.size * rect.size), Color(0.31, 0.33, 0.33, 0.38))
	draw_rect(rect, Color(0.65, 0.65, 0.62, 0.32), false, 1.0)
	# Soft area marks, with an open self ring readable even in the same cell.
	for id in ["opponent", "player"]:
		if not snapshot.contacts.has(id): continue
		var p := project(snapshot.contacts[id])
		var color := WHITE if id == "player" else AMBER
		var radius := 7.5 if id == "player" else 5.0
		for ring in range(4, 0, -1):
			var haze := color
			haze.a = 0.025 * (5 - ring)
			draw_circle(p, radius + ring * 1.6, haze, false, 2.0, true)
		if id == "player": draw_arc(p, radius, 0, TAU, 40, color, 1.6, true)
		else: draw_circle(p, radius, Color(color, 0.85), true, -1.0, true)
