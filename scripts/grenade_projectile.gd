extends Node3D

var game: Node3D
var motion := Vector3.ZERO
var definition: Dictionary={}
var life := 0.0
var active := false
var core: MeshInstance3D
var trail_timer := 0.0

func _ready() -> void:
	core=ZVisuals.sphere(self,.16,Vector3.ZERO,Color("50ff9c"))

func launch(origin: Vector3, direction: Vector3, data: Dictionary) -> void:
	global_position=origin
	definition=data.duplicate(true)
	motion=direction*float(data.get("projectile_speed",18))+Vector3.UP*float(data.get("projectile_lift",1.5))
	life=1.7
	active=true
	trail_timer=0
	core.material_override=ZVisuals.mat(Color(data.get("tracer_color","50ff9c")),.2,.2,5)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not active:
		return
	if game.state!="combat":
		recycle()
		return
	life-=delta
	motion.y-=float(definition.get("projectile_gravity",6))*delta
	var next := global_position+motion*delta
	var ray:=PhysicsRayQueryParameters3D.create(global_position,next,1|8|16)
	var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		global_position=hit.position
		explode()
		return
	global_position=next
	trail_timer-=delta
	if trail_timer<=0:
		trail_timer=.08 if game.fx.reduced() else .04
		game.fx.energy_ring(global_position,motion.normalized(),Color(definition.get("tracer_color","50ff9c")),.1,.8,.22)
	if life<=0:
		explode()

func explode() -> void:
	if not active:
		return
	var radius: float=float(definition.get("blast_radius",3.3))*(1+game.rogue_manager.value("blast_radius_mult"))
	var base: float=float(definition.damage)*(1+game.rogue_manager.value("damage_mult"))*(1+game.rogue_manager.value("blast_damage_mult"))
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var target: Vector3=enemy.global_position+Vector3.UP
		var distance: float=target.distance_to(global_position)
		if distance>radius:
			continue
		var ray:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.05,target,1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var critical: bool=randf()<minf(.75,float(definition.crit_chance)+game.rogue_manager.value("crit_chance"))
		var damage: float=base*maxf(.35,1-distance/radius*.65)*(float(definition.crit_multiplier) if critical else 1)
		enemy.take_damage(damage,(enemy.global_position-global_position).normalized(),false,critical,float(definition.knockback),"explosion")
		game.rogue_manager.on_weapon_hit(enemy,critical)
		if game.rogue_manager.value("burn_duration")>0 and not enemy.dead:
			enemy.burn_time=game.rogue_manager.value("burn_duration")
		game.hit_marker=.14
		game.hit_critical=critical
	for target in game.objective.targets:
		if is_instance_valid(target) and target.kind=="nest" and not target.destroyed and target.global_position.distance_to(global_position)<radius:
			target.take_damage(base)
	game.world.environment_props.damage_props(global_position+Vector3.UP*.05,radius,base,float(definition.knockback))
	game.feedback_manager.route("detonation",global_position)
	game.fx.plasma_explosion(global_position,radius,Color(definition.get("tracer_color","50ff9c")))
	recycle()

func recycle() -> void:
	active=false
	game.weapon_manager.projectiles.erase(self)
	game.pool_manager.release(self)
