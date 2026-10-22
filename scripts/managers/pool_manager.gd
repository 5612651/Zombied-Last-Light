class_name PoolManager
extends Node3D

var available: Dictionary = {}
var leased: Dictionary = {}
var stats := {"created":0,"reused":0,"released":0,"discarded":0,"reparented":0}
var max_idle_per_key := 150
var idle_limits: Dictionary={"vfx":450}
var persistent_parents: Dictionary={}

func register_persistent_parent(parent: Node) -> void:
	persistent_parents[parent.get_instance_id()]=weakref(parent)

func acquire(key: String, factory: Callable, parent: Node) -> Node:
	if not available.has(key):
		available[key]=[]
	var node: Node
	while not available[key].is_empty():
		var candidate: Variant=available[key].pop_back()
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			node=candidate
			break
	if node==null:
		node=factory.call()
		stats.created+=1
		parent.add_child(node)
	else:
		stats.reused+=1
		if node.get_parent()!=parent:
			node.reparent(parent,false)
			stats.reparented+=1
	node.process_mode=Node.PROCESS_MODE_PAUSABLE
	if node is Node3D:
		node.visible=true
	leased[node.get_instance_id()]={"key":key,"node":weakref(node)}
	return node

func release(node: Node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	var id := node.get_instance_id()
	if not leased.has(id):
		return false
	var key: String=leased[id].key
	leased.erase(id)
	stats.released+=1
	if node is CollisionObject3D:
		node.collision_layer=0
		node.collision_mask=0
	node.process_mode=Node.PROCESS_MODE_DISABLED
	if node is Node3D:
		node.visible=false
	var host: Node=node.get_parent()
	var retained: WeakRef=persistent_parents.get(host.get_instance_id()) if host!=null else null
	if retained==null or retained.get_ref()!=host or host.is_queued_for_deletion():
		node.reparent(self,false)
		stats.reparented+=1
	if available[key].size()>=int(idle_limits.get(key,max_idle_per_key)):
		stats.discarded+=1
		node.queue_free()
	else:
		available[key].append(node)
	return true

func idle_count(key: String) -> int:
	return available.get(key,[]).size()

func prune_invalid_leases() -> void:
	for id in leased.keys():
		if leased[id].node.get_ref()==null:
			leased.erase(id)
