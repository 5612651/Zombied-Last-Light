class_name CrowdCoordinator
extends RefCounted

var game: Node3D
var bins: Dictionary={}
var allocations: Dictionary={}
var targets: Dictionary={}
var pair_checks := 0
var queries := 0
const CELL_SIZE := 2.0
const INNER_SLOTS := 8
const MAX_SLOTS := 224
var slot_offsets: PackedVector3Array=PackedVector3Array()
var slot_rings: PackedInt32Array=PackedInt32Array()
var free_ring_template: Array=[]

func _init() -> void:
	# Geometry is independent of players, obstacles and slot ownership. Keep
	# walkability and allocation checks live; only precompute the fixed rings.
	for index in MAX_SLOTS:
		slot_offsets.append(slot_point(index,Vector3.ZERO))
		slot_rings.append(ring_number(index))
		while free_ring_template.size()<=slot_rings[index]:
			free_ring_template.append({})
		free_ring_template[slot_rings[index]][index]=true

func bucket(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x/CELL_SIZE),floori(point.z/CELL_SIZE))

func refresh(enemies: Array) -> void:
	bins.clear()
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var cell := bucket(enemy.position)
		if not bins.has(cell):
			bins[cell]=[]
		bins[cell].append(weakref(enemy))

func neighbors(enemy: Node3D) -> Array:
	var result: Array=[]
	var center := bucket(enemy.position)
	queries+=1
	for x in range(-1,2):
		for z in range(-1,2):
			for reference in bins.get(center+Vector2i(x,z),[]):
				var other: Node3D=reference.get_ref()
				if is_instance_valid(other) and other!=enemy and not other.dead:
					pair_checks+=1
					result.append(other)
	return result

func separation(enemy: Node3D) -> Vector3:
	var result := Vector3.ZERO
	for other in neighbors(enemy):
		var offset: Vector3=enemy.position-other.position
		offset.y=0
		var squared := offset.length_squared()
		var radius: float=.4*(float(enemy.scale.y)+float(other.scale.y))
		if squared<.0001:
			var angle: float=float(enemy.get_instance_id()%997)*TAU/997
			result+=Vector3(sin(angle),0,cos(angle))*.5
		elif squared<radius*radius:
			result+=offset/maxf(.05,squared)*.35
	return result.limit_length(1.4)

func slot_point(index: int, center: Vector3) -> Vector3:
	if index>=0 and index<slot_offsets.size():
		return center+slot_offsets[index]
	var count := INNER_SLOTS
	var ring := 0
	while index>=count:
		index-=count
		ring+=1
		count=INNER_SLOTS*(ring+1)
	var angle: float=TAU*float(index)/float(count)+float(ring%2)*.13
	return center+Vector3(sin(angle),0,cos(angle))*(1.05+ring*1.35)

func ring_number(index: int) -> int:
	if index>=0 and index<slot_rings.size():
		return slot_rings[index]
	var ring := 0
	var count := INNER_SLOTS
	while index>=count:
		index-=count
		ring+=1
		count=INNER_SLOTS*(ring+1)
	return ring

func release(enemy: Node3D) -> void:
	var id := enemy.get_instance_id()
	if not allocations.has(id):
		return
	var entry: Dictionary=allocations[id]
	if targets.has(entry.target):
		targets[entry.target].owners.erase(entry.slot)
		targets[entry.target].free_rings[ring_number(int(entry.slot))][entry.slot]=true
	allocations.erase(id)

func clear_target(id: int) -> void:
	if targets.has(id):
		for owner in targets[id].owners.values():
			allocations.erase(owner)
		targets.erase(id)

func reset() -> void:
	bins.clear()
	allocations.clear()
	targets.clear()
	pair_checks=0
	queries=0

func approach(enemy: Node3D, target: Node3D) -> Vector3:
	if target!=game.player or enemy.boss:
		return target.global_position
	var behavior: String=enemy.definition.behavior
	if behavior in ["spitter","screamer"]:
		var distance: float=7 if behavior=="spitter" else 5
		var outward: Vector3=enemy.position-target.position
		outward.y=0
		if outward.length_squared()<.01:
			outward=Vector3(sin(enemy.angle_offset),0,cos(enemy.angle_offset))
		var desired: Vector3=target.position+outward.normalized()*distance
		if game.world.walkable(desired):
			return desired
		var cell: Vector2i=game.world.nearest_open_cell(game.world.cell(desired))
		return Vector3(cell.x*.5,0,cell.y*.5)
	var target_id := target.get_instance_id()
	if targets.has(target_id) and Vector3(targets[target_id].origin).distance_to(target.position)>3:
		clear_target(target_id)
	if not targets.has(target_id):
		targets[target_id]={"origin":target.position,"owners":{},"free_rings":free_ring_template.duplicate(true)}
	var id := enemy.get_instance_id()
	if allocations.has(id) and allocations[id].target!=target_id:
		release(enemy)
	var owners: Dictionary=targets[target_id].owners
	var free_rings: Array=targets[target_id].free_rings
	if allocations.has(id):
		var slot: int=allocations[id].slot
		var point := slot_point(slot,target.position)
		# Waiting rows can fill newly vacated attack positions.
		var free_inner := false
		if slot>=INNER_SLOTS:
			for inner in free_rings[0]:
				if game.world.walkable(slot_point(int(inner),target.position)):
					free_inner=true
					break
		if game.world.walkable(point) and (slot<INNER_SLOTS or not free_inner):
			return point
		release(enemy)
	var best := -1
	var cost := INF
	for ring in free_rings.size():
		# Later rings cannot beat a candidate whose total cost is already lower.
		var ring_cost: float=ring*10000.0
		if ring_cost>cost: break
		for index in free_rings[ring]:
			var point := slot_point(int(index),target.position)
			if not game.world.walkable(point):
				continue
			# Released dictionary entries can have a different iteration order.
			# Preserve the original ascending-index tie break explicitly.
			var candidate: float=ring_cost+enemy.position.distance_squared_to(point)
			if candidate<cost or (candidate==cost and (best<0 or int(index)<best)):
				cost=candidate
				best=int(index)
	if best<0:
		return target.position
	owners[best]=id
	free_rings[ring_number(best)].erase(best)
	allocations[id]={"target":target_id,"slot":best}
	return slot_point(best,target.position)

func can_melee(enemy: Node3D, target: Node3D) -> bool:
	if target!=game.player or enemy.boss:
		return true
	var entry: Dictionary=allocations.get(enemy.get_instance_id(),{})
	return not entry.is_empty() and int(entry.slot)<INNER_SLOTS
