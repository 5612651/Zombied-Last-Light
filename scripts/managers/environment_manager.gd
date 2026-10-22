class_name EnvironmentManager
extends Node3D

const PropScript=preload("res://scripts/environment_prop.gd")
var game: Node3D
var world: Node3D
var definitions: Dictionary={}
var props: Array=[]
var nav_dirty := false

func _ready() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/environment.json"))
	definitions=data.types
	for placement in game.stage_manager.definition().get("environment_props",data.placements):
		var point:=Vector3(placement.position[0],placement.position[1],placement.position[2])
		var size: Array=definitions[placement.type].size
		var fits := true
		for x in [-1,1]:
			for z in [-1,1]:
				fits=fits and world.walkable(point+Vector3(x*float(size[0])*.5,0,z*float(size[2])*.5))
		if fits:
			spawn(placement.type,point)
	refresh_navigation()

func _process(_delta: float) -> void:
	if nav_dirty:
		refresh_navigation()

func spawn(kind: String, point: Vector3) -> RigidBody3D:
	var prop=PropScript.new()
	prop.game=game
	prop.manager=self
	prop.kind=kind
	prop.definition=definitions[kind].duplicate(true)
	prop.position=point
	add_child(prop)
	props.append(prop)
	return prop

func refresh_navigation() -> void:
	world.setup_navigation()
	nav_dirty=false

func clear() -> void:
	for prop in props:
		if is_instance_valid(prop):
			prop.remove_obstacle()
			prop.queue_free()
	props.clear()
	refresh_navigation()

func visible_from(origin: Vector3, point: Vector3, excluded: RID=RID(), target: Node=null) -> bool:
	var exclusions: Array[RID]=[]
	if excluded.is_valid(): exclusions.append(excluded)
	var query:=PhysicsRayQueryParameters3D.create(origin,point,1,exclusions)
	var hit:=game.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider==target

func damage_props(origin: Vector3, radius: float, damage: float, force: float) -> void:
	for prop in props.duplicate():
		if is_instance_valid(prop) and not prop.destroyed and prop.global_position.distance_to(origin)<radius and visible_from(origin,prop.global_position+Vector3.UP*.5,RID(),prop):
			prop.take_damage(damage,(prop.global_position-origin).normalized(),false,false,force)

func detonate(source: RigidBody3D) -> void:
	var data: Dictionary=source.definition
	var origin: Vector3=source.global_position+Vector3.UP
	var radius: float=data.radius
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var point: Vector3=enemy.global_position+Vector3.UP
		if point.distance_to(origin)>radius or not visible_from(origin,point,source.get_rid()):
			continue
		enemy.take_damage(float(data.damage),(point-origin).normalized(),false,false,float(data.force),"electric" if data.effect=="electric" else "explosion")
		if data.effect=="electric" and not enemy.dead:
			enemy.stun_time=maxf(enemy.stun_time,float(data.get("stun",1.8)))
			game.fx.tracer(origin,point,Color("91d8ff"))
	var player: Node3D=game.player
	if player.global_position.distance_to(source.global_position)<radius and visible_from(origin,player.global_position+Vector3.UP,source.get_rid()):
		player.take_damage(float(data.player_damage))
		if data.effect=="blast": player.apply_status("burn",3)
	for prop in props.duplicate():
		if is_instance_valid(prop) and prop!=source and not prop.destroyed and prop.global_position.distance_to(source.global_position)<radius and visible_from(origin,prop.global_position+Vector3.UP*.5,source.get_rid(),prop):
			prop.take_damage(float(data.damage),(prop.global_position-source.global_position).normalized(),false,false,float(data.force))
	game.feedback_manager.route("elemental" if data.effect=="electric" else "detonation",source.global_position)
