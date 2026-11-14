extends Node
const Bot=preload("res://scripts/duel_bot.gd")
var game: Node3D
var bot: CharacterBody3D
var player_alive:=true
var regions: Array[Area3D]=[]

func initialize(controller: Node3D) -> void:
	game=controller
	game.player.collision_mask=1|8
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
	if is_instance_valid(game) and is_instance_valid(game.player): game.player.collision_mask=1

func step(delta: float) -> void:
	bot.active=game.phase=="training" and player_alive
	bot.step(delta)

func resolve() -> void:
	# Bot's ray was evaluated before player damage; both emitted rays count.
	if bot.shot_pending:
		var hit: Dictionary=bot.shot_collision
		if not hit.is_empty() and hit.collider.has_meta("player_region") and hit.collider.get_meta("headshot",false): player_alive=false
		bot.shot_pending=false
	var reason:=outcome(player_alive,bot.target.alive,game.weapon.mag+game.weapon.reserve,game.remaining)
	if not reason.is_empty(): game.finish_round(reason)

static func outcome(player_lives: bool,bot_lives: bool,ammo: int,seconds: float) -> String:
	if not player_lives and not bot_lives: return "平局 · 双方同时被击倒"
	if not bot_lives: return "获胜 · 对手已被击倒"
	if not player_lives: return "失败 · 被对手爆头"
	if ammo==0: return "失败 · 弹药耗尽"
	if seconds<=0: return "未分胜负 · 时间到"
	return ""

func stop() -> void:
	bot.active=false
	bot.weapon.active=false
	bot.target.active=false
	bot.shot_pending=false
	bot.velocity=Vector3.ZERO
	bot.sound.stop()
	bot.flash.hide()
