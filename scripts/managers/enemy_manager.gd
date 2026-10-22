class_name EnemyManager
extends Node

const EnemyScript = preload("res://scripts/enemy.gd")
const AcidScript = preload("res://scripts/hostile_projectile.gd")
var game: Node3D
var active: Array = []
var projectiles: Array=[]
var crowd := CrowdCoordinator.new()
var neighbor_timer := 0.0

func _ready() -> void:
	crowd.game=game

func _physics_process(delta: float) -> void:
	neighbor_timer-=delta
	if neighbor_timer<=0:
		neighbor_timer=.1
		crowd.refresh(active)

func spit(origin: Vector3, target: Vector3, speed: float, damage: float) -> Node3D:
	var factory := func() -> Node3D:
		var projectile=AcidScript.new()
		projectile.game=game
		return projectile
	var projectile: Node3D=game.pool_manager.acquire("hostile_acid",factory,game)
	projectile.launch(origin,target,speed,damage)
	projectiles.append(projectile)
	return projectile

func spawn(pos: Vector3, definition_id: String="normal") -> CharacterBody3D:
	var profile_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	var definition: Dictionary=game.catalog.definition("enemies",definition_id)
	if definition.is_empty():
		push_warning("Unknown enemy "+definition_id)
		return null
	var factory := func() -> CharacterBody3D:
		var actor: CharacterBody3D=EnemyScript.new()
		actor.game=game
		actor.definition=definition
		return actor
	var enemy: CharacterBody3D=game.pool_manager.acquire("enemy:"+definition_id,factory,game)
	enemy.reset_for_spawn(definition,pos)
	active.append(enemy)
	if definition.tier=="elite": game.sound.play_at("elite_warning",pos,-12)
	if game.combat_profiler.enabled: game.combat_profiler.note("enemy_spawn",profile_start)
	return enemy

func release(enemy: CharacterBody3D) -> void:
	var profile_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	active.erase(enemy)
	if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
		crowd.release(enemy)
		game.pool_manager.release(enemy)
	if game.combat_profiler.enabled: game.combat_profiler.note("enemy_release",profile_start)

func clear() -> void:
	for projectile in projectiles.duplicate():
		if is_instance_valid(projectile):
			projectile.recycle()
	for enemy in active.duplicate():
		if is_instance_valid(enemy):
			release(enemy)
	active.clear()
	crowd.reset()
	neighbor_timer=0
	game.pool_manager.prune_invalid_leases()

func nearest(pos: Vector3, excluding: Node=null, radius: float=100, visible_only: bool=false) -> Node3D:
	var best: Node3D
	var dist := radius
	for enemy in active:
		if not is_instance_valid(enemy) or enemy.dead or enemy==excluding:
			continue
		var d: float=enemy.position.distance_to(pos)
		if d>=dist:
			continue
		if visible_only:
			var ray := PhysicsRayQueryParameters3D.create(game.player.muzzle.global_position,enemy.position+Vector3(0,1.6*enemy.scale.y,0),1|16)
			if not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
		dist=d
		best=enemy
	return best
