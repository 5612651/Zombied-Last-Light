extends CharacterBody3D

var definition: Dictionary = {}
var game: Node3D
var model: Node3D
var limbs: Dictionary
var elite := false
var boss := false
var hp := 80.0
var max_hp := 80.0
var speed := 2.0
var attack_timer := 0.0
var path_timer := 0.0
var path := PackedVector3Array()
var path_index := 0
var knockback := Vector3.ZERO
var burn_time := 0.0
var burn_tick := 0.0
var flash_timer := 0.0
var dead := false
var phase := 0.0
var angle_offset := 0.0
var charge_timer := 4.0
var attack_count := 0
var navigation_steps := 0
var slam_warning := false
var stun_time := 0.0
var ability_state := "idle"
var ability_time := 0.0
var ability_cooldown := 2.0
var locked_target := Vector3.ZERO
var charge_direction := Vector3.ZERO
var charge_hit := false
var rally_time := 0.0
var rally_multiplier := 1.0
var ability_count := 0
var warning: MeshInstance3D
var boss_brain: BossBrain
var distant_model: Node3D
var decision_timer := 0.0
var animation_timer := 0.0
var approach_point := Vector3.ZERO
var separation_force := Vector3.ZERO
var flash_visible := false
var lod_tier := 0
var decision_steps := 0
var animation_steps := 0
var path_queries := 0

func _ready() -> void:
	add_to_group("hostiles")
	collision_layer = 8
	collision_mask = 1|16
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.9
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = .95
	add_child(collider)
	model = Node3D.new()
	add_child(model)
	elite=definition.tier=="elite"
	boss=definition.tier=="boss"
	limbs = ZVisuals.humanoid(model,true,elite or boss)
	max_hp = float(definition.health)
	hp = max_hp
	speed = randf_range(float(definition.speed_min),float(definition.speed_max))
	if elite or boss:
		scale = Vector3.ONE*float(definition.scale)
		ZVisuals.box(model,Vector3(.75,.3,.5),Vector3(0,1.4,0),Color("6c412e"))
	angle_offset = randf()*TAU
	path_timer = randf()*.4
	phase = randf()*TAU
	warning=ZVisuals.box(self,Vector3(.1,.03,4),Vector3(0,.08,-2),Color("e9a54d"),1)
	warning.visible=false
	if boss:
		boss_brain=BossBrain.new()
		boss_brain.setup(self)
		ZVisuals.box(model,Vector3(1.1,.25,.6),Vector3(0,1.55,0),Color("a15f38"))
		ZVisuals.box(model,Vector3(.4,.6,.2),Vector3(0,1.15,.35),Color("b28b43"),.4)
	match definition.behavior:
		"spitter":
			ZVisuals.sphere(model,.36,Vector3(0,1.3,.35),Color("94a347"))
		"screamer":
			ZVisuals.box(model,Vector3(.55,.2,.45),Vector3(0,1.9,0),Color("b27a34"))
		"charger":
			ZVisuals.box(model,Vector3(.9,.45,.48),Vector3(0,1.35,-.15),Color("5e4d42"))
	distant_model=Node3D.new()
	add_child(distant_model)
	var batched:=MeshInstance3D.new()
	batched.mesh=ZVisuals.bake_pose(model)
	batched.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	distant_model.add_child(batched)
	distant_model.visible=false

func _physics_process(delta: float) -> void:
	if dead or game.state!="combat":
		return
	var tick_profile: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	attack_timer -= delta
	stun_time=maxf(0,stun_time-delta)
	rally_time=maxf(0,rally_time-delta)
	path_timer -= delta
	burn_time = maxf(0,burn_time-delta)
	if burn_time>0:
		burn_tick -= delta
		if burn_tick<=0:
			burn_tick = maxf(.05,game.rogue_manager.value("burn_interval"))
			take_damage(game.rogue_manager.value("burn_damage"),Vector3.ZERO,false,false,0,"fire")
			game.fx.debris(position+Vector3(0,1,0),Vector3.UP,Color("ff832c"),Vector3.ONE*.12,.3,0,2)
			if dead:
				return
	var target_node: Node3D=game.objective.target_for(self)
	var target: Vector3 = target_node.global_position
	var difference := target-position
	difference.y=0
	var distance := difference.length()
	lod_tier=0 if boss or distance<4.5 else (1 if distance<18 else 2)
	decision_timer-=delta
	if decision_timer<=0:
		decision_timer=[.016,.1,.2][lod_tier]
		var decision_profile: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
		approach_point=game.enemy_manager.crowd.approach(self,target_node)
		if game.combat_profiler.enabled: game.combat_profiler.note("crowd_approach",decision_profile)
		decision_profile=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
		separation_force=game.enemy_manager.crowd.separation(self)
		if game.combat_profiler.enabled: game.combat_profiler.note("crowd_separation",decision_profile)
		decision_steps+=1
	var approach: Vector3=approach_point
	if path_timer<=0:
		path_timer = randf_range(.45,.75) if lod_tier==0 else randf_range(.9,1.4)
		var path_profile: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
		path = game.world.path(position,approach)
		if game.combat_profiler.enabled: game.combat_profiler.note("navigation_requests",path_profile)
		path_queries+=1
		path_index = 1 if path.size()>1 else 0
	var direction := Vector3.ZERO
	while path_index<path.size() and Vector2(path[path_index].x-position.x,path[path_index].z-position.z).length()<.45:
		path_index+=1
	if path_index<path.size():
		var waypoint: Vector3 = path[path_index]-position
		waypoint.y=0
		direction=waypoint.normalized()
		navigation_steps+=1
	elif position.distance_to(approach)>.18:
		var toward: Vector3=approach-position
		toward.y=0
		direction=toward.normalized()
	var separation: Vector3=separation_force
	var special: Vector3=update_ability(delta,target_node,difference,distance)
	var movement_speed: float=speed*(rally_multiplier if rally_time>0 else 1.0)
	if boss and boss_brain.enraged: movement_speed*=1.25
	if definition.behavior=="runner" and ability_state=="sprint":
		movement_speed*=float(definition.get("sprint_multiplier",1.8))
	velocity = (direction+separation).limit_length()*movement_speed if special==Vector3.INF else special
	velocity=velocity*(0.0 if stun_time>0 else 1.0)+knockback
	velocity.y = -3
	knockback = knockback.move_toward(Vector3.ZERO,delta*16)
	var motion_profile: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	move_and_slide()
	if game.combat_profiler.enabled: game.combat_profiler.note("kinematic_motion",motion_profile)
	if boss and boss_brain.state=="charge":
		for i in get_slide_collision_count():
			if absf(get_slide_collision(i).get_normal().y)<.5:
				boss_brain.start_recovery()
	if definition.behavior=="charger" and ability_state=="charge":
		if get_slide_collision_count()>0:
			for i in get_slide_collision_count():
				if absf(get_slide_collision(i).get_normal().y)<.5:
					ability_state="recovery"
					ability_time=float(definition.get("recovery",1))
	if position.y < -2 or absf(position.x)>16 or absf(position.z)>14:
		var safe: Vector2i = game.world.nearest_open_cell(game.world.cell(Vector3(clampf(position.x,-14,14),0,clampf(position.z,-12,12))))
		position=Vector3(safe.x*.5,.05,safe.y*.5)
		velocity=Vector3.ZERO
		knockback=Vector3.ZERO
	phase += delta*speed*5
	animation_timer+=delta
	if animation_timer>=[0,.066,.2][lod_tier]:
		if difference.length_squared()>.01:
			model.rotation.y=lerp_angle(model.rotation.y,atan2(-difference.x,-difference.z),minf(1,animation_timer*6))
		distant_model.rotation.y=model.rotation.y
		limbs.left_leg.rotation.x = sin(phase)*.45
		limbs.right_leg.rotation.x = -sin(phase)*.45
		model.position.y = absf(sin(phase))*.04
		distant_model.position.y=model.position.y
		distant_model.get_child(0).set_instance_shader_parameter("walk_phase",phase)
		model.visible=lod_tier==0
		distant_model.visible=lod_tier>0
		animation_timer=0
		animation_steps+=1
	var melee_distance: float=target_node.melee_distance_from(position) if target_node.has_method("melee_distance_from") else distance
	if melee_distance < float(definition.attack_range) and attack_timer<=0 and stun_time<=0 and ability_state not in ["windup","charge","recovery"] and game.enemy_manager.crowd.can_melee(self,target_node):
		# Environment occlusion prevents damage through cars and walls.
		var ray := PhysicsRayQueryParameters3D.create(position+Vector3.UP,target_node.global_position+Vector3.UP,1)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			attack_timer = float(definition.attack_interval)
			attack_count+=1
			if target_node.has_method("damage_by_enemy"):
				target_node.damage_by_enemy(float(definition.damage)*(boss_brain.damage_multiplier() if boss else 1))
			else:
				target_node.take_damage(float(definition.damage)*(boss_brain.damage_multiplier() if boss else 1))
			limbs.right_arm.rotation.x=-1.8
	flash_timer=maxf(0,flash_timer-delta)
	if flash_visible!=(flash_timer>0):
		flash_visible=flash_timer>0
		var overlay: Material=ZVisuals.mat(Color("f4e3bc"),0,.5,2) if flash_visible else null
		for limb in limbs.values(): limb.material_overlay=overlay
		distant_model.get_child(0).set_instance_shader_parameter("hit_flash",1.0 if flash_visible else 0.0)
	if game.combat_profiler.enabled: game.combat_profiler.note("enemy_tick_inclusive",tick_profile)

func update_ability(delta: float, target: Node3D, difference: Vector3, distance: float) -> Vector3:
	if stun_time>0:
		return Vector3.ZERO
	if boss:
		var movement: Vector3=boss_brain.update(delta,target,difference,distance)
		ability_state=boss_brain.state
		return movement
	ability_cooldown-=delta
	ability_time=maxf(0,ability_time-delta)
	var behavior: String=definition.behavior
	if behavior=="runner":
		if ability_state=="sprint" and ability_time<=0:
			ability_state="idle"
			ability_cooldown=float(definition.get("sprint_interval",3.2))
		elif ability_state=="idle" and ability_cooldown<=0 and distance>3:
			ability_state="sprint"
			ability_time=float(definition.get("sprint_duration",.8))
			ability_count+=1
		return Vector3.INF
	if behavior not in ["spitter","screamer","charger"]:
		return Vector3.INF
	if ability_state=="idle" and ability_cooldown<=0 and distance<13 and (behavior!="charger" or distance>3):
		var ray:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP,target.global_position+Vector3.UP,1)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			ability_state="windup"
			ability_time=float(definition.get("windup",.8))
			locked_target=target.global_position
			charge_direction=difference.normalized()
			warning.visible=true
			warning.scale=Vector3(2,1,maxf(1,distance/4))
			warning.rotation.y=atan2(-difference.x,-difference.z)
			warning.position=-Vector3(sin(warning.rotation.y),0,cos(warning.rotation.y))*distance*.5+Vector3.UP*.08
	if ability_state=="windup":
		if ability_time<=0:
			warning.visible=false
			ability_count+=1
			ability_cooldown=float(definition.get("ability_interval",5))
			if behavior=="spitter":
				game.enemy_manager.spit(global_position+Vector3.UP*1.3,locked_target+Vector3.UP,float(definition.get("projectile_speed",11)),float(definition.get("projectile_damage",14)))
				ability_state="idle"
			elif behavior=="screamer":
				rally_allies()
				ability_state="idle"
			else:
				ability_state="charge"
				ability_time=float(definition.get("charge_duration",.8))
				charge_hit=false
		return Vector3.ZERO
	if ability_state=="charge":
		if not charge_hit and distance<1.8:
			charge_hit=true
			if target.has_method("damage_by_enemy"):
				target.damage_by_enemy(float(definition.get("charge_damage",28)))
			else:
				target.take_damage(float(definition.get("charge_damage",28)))
		if ability_time<=0:
			ability_state="recovery"
			ability_time=float(definition.get("recovery",1))
			return Vector3.ZERO
		return charge_direction*float(definition.get("charge_speed",11))
	if ability_state=="recovery":
		if ability_time<=0:
			ability_state="idle"
		return Vector3.ZERO
	if behavior=="spitter" and distance<float(definition.get("preferred_range",7)):
		return -difference.normalized()*speed if distance<5 else Vector3.ZERO
	return Vector3.INF

func rally_allies() -> void:
	game.fx.shockwave(position,Color("d6aa4c"))
	game.sound.play("upgrade",-14,.65)
	for ally in game.enemies:
		if is_instance_valid(ally) and not ally.dead and ally.position.distance_to(position)<float(definition.get("buff_radius",8)):
			ally.rally_time=float(definition.get("buff_duration",5))
			ally.rally_multiplier=float(definition.get("buff_multiplier",1.3))
	for i in int(definition.get("summon_count",2)):
		if game.enemies.size()>=80:
			break
		var spawn: Vector3=game.director.spawn_position()
		if spawn!=Vector3.INF:
			game.spawn_enemy(spawn)

func take_damage(amount: float, direction: Vector3, headshot: bool=false, critical: bool=false, force: float=2, source: String="bullet") -> void:
	if dead:
		return
	hp -= amount
	var resistance: float=definition.knockback_resistance
	knockback = (knockback+direction*force*resistance).limit_length(float(definition.knockback_cap))
	game.feedback_manager.hit(self,amount,direction,headshot,critical,source)
	if hp<=0:
		dead=true
		collision_layer=0
		game.fx.ragdoll(self,direction,force*.7+1)
		game.enemy_killed(self,headshot,critical)
		game.enemy_manager.release.call_deferred(self)

func reset_for_spawn(data: Dictionary, pos: Vector3) -> void:
	definition=data
	elite=data.tier=="elite"
	boss=data.tier=="boss"
	max_hp=float(data.health)
	hp=max_hp
	speed=randf_range(float(data.speed_min),float(data.speed_max))
	scale=Vector3.ONE*float(data.scale)
	position=pos
	velocity=Vector3.ZERO
	knockback=Vector3.ZERO
	dead=false
	burn_time=0
	burn_tick=0
	flash_timer=0
	flash_visible=false
	decision_timer=0
	animation_timer=0
	approach_point=pos
	separation_force=Vector3.ZERO
	lod_tier=0
	decision_steps=0
	animation_steps=0
	path_queries=0
	model.visible=true
	distant_model.visible=false
	distant_model.get_child(0).set_instance_shader_parameter("hit_flash",0.0)
	distant_model.get_child(0).set_instance_shader_parameter("walk_phase",0.0)
	attack_timer=0
	attack_count=0
	navigation_steps=0
	path.clear()
	path_index=0
	path_timer=randf()*.4
	phase=randf()*TAU
	angle_offset=randf()*TAU
	charge_timer=4
	slam_warning=false
	stun_time=0
	ability_state="idle"
	ability_time=0
	ability_cooldown=2
	locked_target=Vector3.ZERO
	charge_direction=Vector3.ZERO
	charge_hit=false
	rally_time=0
	rally_multiplier=1
	ability_count=0
	warning.visible=false
	if boss and boss_brain!=null: boss_brain.reset()
	model.position=Vector3.ZERO
	model.rotation=Vector3.ZERO
	for limb in limbs.values():
		limb.material_overlay=null
		limb.rotation=Vector3.ZERO
	limbs.left_arm.rotation.x=-.7
	limbs.right_arm.rotation.x=-.9
	collision_layer=8
	collision_mask=1|16
	set_physics_process(true)
