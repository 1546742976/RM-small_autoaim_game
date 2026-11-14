extends Node
const Bot=preload("res://scripts/duel_bot.gd")
var game: Node3D
var bot: CharacterBody3D
var player_alive:=true
var regions: Array[Area3D]=[]

func initialize(controller: Node3D) -> void:
	game=controller
	game.player.collision_mask=1|8|64
	for head in [false,true]:
		var area:=Area3D.new()
		area.collision_layer=16
		area.collision_mask=0
		area.monitoring=false
		area.set_meta("player_region",true)
		area.set_meta("headshot",head)
		var collision:=CollisionShape3D.new()
		if head:
			var sphere:=SphereShape3D.new()
			sphere.radius=0.105
			collision.shape=sphere
			area.position.y=1.65
		else:
			var capsule:=CapsuleShape3D.new()
			capsule.radius=0.3
			capsule.height=1.49
			collision.shape=capsule
			area.position.y=0.745
		area.add_child(collision)
		game.player.add_child(area)
		regions.append(area)
	bot=Bot.new()
	bot.game=game
	bot.layout=game.arena.map_root.layout
	bot.position=game.arena.map_root.bot_spawn
	bot.rotation.y=PI
	game.arena.map_root.add_child(bot)
	bot.pose(0)

func _exit_tree() -> void:
	for region in regions:
		if is_instance_valid(region): region.free()
	if is_instance_valid(game) and is_instance_valid(game.player): game.player.collision_mask=1|8|64

func step(delta: float) -> void:
	bot.active=game.phase=="training" and bot.target.alive
	bot.step(delta)

func receive_hit(hit: Dictionary) -> void:
	if not player_alive or hit.is_empty(): return
	if hit.collider.has_meta("player_region") and hit.collider.get_meta("headshot",false):
		player_alive=false
		game.player.active=false
		game.player.velocity=Vector3.ZERO
		game.player.collision_layer=0
		for region in regions: region.collision_layer=0

func resolve() -> void:
	if not bot.target.alive: bot.collision_layer=0
	var reason:=outcome(player_alive,bot.target.alive,game.weapon.mag+game.weapon.reserve)
	if not reason.is_empty(): game.begin_settlement(reason)
	if game.settling and game.projectiles.live_count()==0: game.finish_round(reason)

static func outcome(player_lives: bool,bot_lives: bool,ammo: int,_seconds: float=-1.0) -> String:
	if not player_lives and not bot_lives: return "平局 · 双方被击倒"
	if not bot_lives: return "获胜 · 对手已被击倒"
	if not player_lives: return "失败 · 被对手爆头"
	if ammo==0: return "失败 · 弹药耗尽"
	return ""

func stop() -> void:
	bot.active=false
	bot.weapon.active=false
	bot.target.active=false
	bot.velocity=Vector3.ZERO
	for voice in bot.shot_voices: voice.stop()
	bot.footsteps.reset()
	bot.flash.hide()
