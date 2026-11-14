extends RefCounted
## Local presentation data only: no exact positions, headings or elevations.
const BOUNDS := Rect2(-21, -36, 42, 72)
const CELL := 4.0
const INTERVAL := 0.5
var round_id := -1
var clock := 0.0
var regions: Array[Rect2] = []
var contacts: Dictionary = {}

static func region_center(position: Vector3) -> Vector2:
	var p := Vector2(position.x, position.z)
	var index := ((p - BOUNDS.position) / CELL).floor()
	index = index.clamp(Vector2.ZERO, (BOUNDS.size / CELL).ceil() - Vector2.ONE)
	var low := BOUNDS.position + index * CELL
	var high := (low + Vector2.ONE * CELL).min(BOUNDS.end)
	return (low + high) * 0.5

func reset() -> void:
	round_id = -1
	clock = 0
	regions.clear()
	contacts.clear()

func load_layout(layout: RefCounted, current_round: int) -> void:
	reset()
	round_id = current_round
	# Coarse occupancy ignores stack heights and platform elevation.
	for z in range(0, layout.SIZE.y, 2):
		for x in range(0, layout.SIZE.x, 2):
			var open := false
			for dz in 2:
				for dx in 2:
					var cell := Vector2i(x + dx, z + dz)
					if layout.inside(cell) and layout.height_at(cell) in [0, 4]: open = true
			if open:
				var low := BOUNDS.position + Vector2(x, z) * 2
				regions.append(Rect2(low, (BOUNDS.end - low).min(Vector2.ONE * CELL)))

func sample(player_position: Vector3, opponent_position: Vector3, player_alive: bool, opponent_alive: bool) -> void:
	contacts.clear()
	if player_alive: contacts.player = region_center(player_position)
	if opponent_alive: contacts.opponent = region_center(opponent_position)

func advance(delta: float, player_position: Vector3, opponent_position: Vector3, player_alive: bool, opponent_alive: bool, force := false) -> bool:
	clock += delta
	var changed := false
	# Death removes the marker immediately; it does not disclose a new position.
	if not player_alive and contacts.has("player"):
		contacts.erase("player")
		changed = true
	if not opponent_alive and contacts.has("opponent"):
		contacts.erase("opponent")
		changed = true
	if force or clock >= INTERVAL:
		clock = 0.0 if force else fmod(clock, INTERVAL)
		sample(player_position, opponent_position, player_alive, opponent_alive)
		return true
	return changed
