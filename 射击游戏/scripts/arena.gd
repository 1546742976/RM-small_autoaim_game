extends Node3D
## Owns exactly one map and its six targets.
const Target = preload("res://scripts/training_target.gd")
const MAPS := {
	"old_town": {"name":"旧镇街区", "scene":"res://scenes/maps/old_town.tscn", "preview":"res://assets/ui/old_town.png"},
	"training_hall": {"name":"训练馆", "scene":"res://scenes/maps/training_hall.tscn", "preview":"res://assets/ui/training_hall.png"},
}
var targets: Array = []
var map_id := ""
var map_root: Node3D

func _ready() -> void:
	load_map("old_town")

func load_map(id: String) -> void:
	if id == map_id:
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
