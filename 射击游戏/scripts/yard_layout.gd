extends RefCounted
## Integer grid is the single source for geometry, navigation and validation.
const SIZE := Vector2i(21,36)
const DIRS := [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
var cells := PackedInt32Array()
var lanes: Array = []
var links: Array = []
var seed_value := 0
var road_signature := ""
var navigation := AStarGrid2D.new()

func generate(value: int) -> void:
	seed_value=value
	var rng:=RandomNumberGenerator.new()
	rng.seed=value
	cells.resize(SIZE.x*SIZE.y)
	cells.fill(1)
	lanes.clear()
	links.clear()
	for z in [0,1,2,33,34,35]:
		for x in SIZE.x: cells[z*SIZE.x+x]=0
	for band in 3:
		var points: Array[Vector2i]=[]
		var x:=band*7+rng.randi_range(1,4)
		points.append(Vector2i(x,2))
		for z in [7,13,19,25,33]:
			var nx:=band*7+rng.randi_range(1,4)
			if nx==x: nx=band*7+1+(nx-band*7)%4
			points.append(Vector2i(x,z))
			points.append(Vector2i(nx,z))
			x=nx
		lanes.append(points)
		for i in range(1,points.size()): carve(points[i-1],points[i])
	for pair in 2:
		for interval in [Vector2i(8,12),Vector2i(22,28)]:
			var z:=rng.randi_range(interval.x,interval.y)
			var a:=Vector2i(pair*7+1,z)
			var b:=Vector2i((pair+1)*7+5,z)
			carve(a,b)
			links.append([a,b])
	road_signature=var_to_str([lanes,links]).sha256_text()
	# Retain a continuous crate footprint; random stacks vary every outline.
	for i in cells.size():
		if cells[i]!=0: cells[i]=rng.randi_range(1,3)
	navigation.region=Rect2i(Vector2i.ZERO,SIZE)
	navigation.cell_size=Vector2(2,2)
	navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	for z in SIZE.y:
		for x in SIZE.x: navigation.set_point_solid(Vector2i(x,z),height_at(Vector2i(x,z))>0)

func carve(a: Vector2i,b: Vector2i) -> void:
	for z in range(mini(a.y,b.y),maxi(a.y,b.y)+2):
		for x in range(mini(a.x,b.x),maxi(a.x,b.x)+2):
			if inside(Vector2i(x,z)): cells[z*SIZE.x+x]=0

func inside(p: Vector2i) -> bool:
	return p.x>=0 and p.y>=0 and p.x<SIZE.x and p.y<SIZE.y

func height_at(p: Vector2i) -> int:
	return cells[p.y*SIZE.x+p.x] if inside(p) else 3

func world(p: Vector2i) -> Vector3:
	return Vector3(p.x*2-20,0.02,p.y*2-35)

func cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(roundi((p.x+20)/2),0,20),clampi(roundi((p.z+35)/2),0,35))

func path(a: Vector3,b: Vector3) -> PackedVector3Array:
	var result:=PackedVector3Array()
	var start:=cell(a)
	var end:=cell(b)
	if height_at(start)>0 or height_at(end)>0: return result
	for p: Vector2i in navigation.get_id_path(start,end): result.append(world(p))
	return result

func valid() -> bool:
	var visited: Dictionary={Vector2i(10,1):true}
	var queue: Array[Vector2i]=[Vector2i(10,1)]
	var index:=0
	while index<queue.size():
		var p:=queue[index]
		index+=1
		for d: Vector2i in DIRS:
			var n:=p+d
			if inside(n) and height_at(n)==0 and not visited.has(n):
				visited[n]=true
				queue.append(n)
	if not visited.has(Vector2i(10,34)): return false
	for z in SIZE.y:
		for x in SIZE.x:
			var p:=Vector2i(x,z)
			if height_at(p)==0 and not visited.has(p): return false
	return lanes.size()==3 and links.size()==4
