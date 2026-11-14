extends Node3D
## Owns one map and its training targets; the duel owns its opponent separately.
const Target = preload("res://scripts/training_target.gd")
const MAPS := {
	"assessment_yard": {"name":"箱阵考核 · 每局随机 · 1v1", "scene":"res://scenes/maps/assessment_yard.tscn", "preview":"res://assets/ui/assessment_yard.png"},
	"old_town": {"name":"旧镇街区", "scene":"res://scenes/maps/old_town.tscn", "preview":"res://assets/ui/old_town.png"},
	"training_hall": {"name":"训练馆", "scene":"res://scenes/maps/training_hall.tscn", "preview":"res://assets/ui/training_hall.png"},
}
var targets: Array = []
var map_id := ""
var map_root: Node3D
var previous_roads := ""
var layout_rng := RandomNumberGenerator.new()

func _ready() -> void:
	layout_rng.randomize()
	load_map("old_town")

func load_map(id: String) -> void:
	if id == map_id and id != "assessment_yard":
		reset_targets()
		return
	if is_instance_valid(map_root):
		# Release geometry before its map-owned materials (also on the headless renderer).
		for child in map_root.get_children(): child.free()
		remove_child(map_root)
		map_root.free()
	targets.clear()
	map_id = id
	map_root = load(MAPS[id].scene).instantiate()
	if id == "assessment_yard":
		var seed_override := -1
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--assessment-seed="): seed_override=int(arg.trim_prefix("--assessment-seed="))
		var candidate=preload("res://scripts/yard_layout.gd").new()
		for attempt in 32:
			map_root.generation_seed=seed_override if seed_override>=0 else layout_rng.randi()
			candidate.generate(map_root.generation_seed)
			if candidate.valid() and (seed_override>=0 or candidate.road_signature!=previous_roads): break
		if not candidate.valid():
			push_error("Invalid assessment layout")
			return
		previous_roads=candidate.road_signature
	add_child(map_root)
	for i in map_root.target_configs.size():
		var config: Dictionary = map_root.target_configs[i]
		var target := Target.new()
		target.setup(i, config.moving)
		target.position = config.position
		target.rotation.y = config.yaw
		target.path_start = config.from
		target.path_end = config.to
		map_root.add_child(target)
		targets.append(target)

func get_spawn() -> Transform3D:
	return map_root.spawn_transform

func set_active(value: bool) -> void:
	for target in targets:
		target.active = value

func reset_targets() -> void:
	for target in targets:
		target.reset_target()
