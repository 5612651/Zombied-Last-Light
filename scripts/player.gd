extends CharacterBody3D

var game: Node3D
var model: Node3D
var limbs: Dictionary
var gun: Node3D
var muzzle: Node3D
var flash: OmniLight3D
var facing := Vector3.FORWARD
var aim_point := Vector3(0,1.1,-10)
var hp := 100.0
var max_hp := 100.0
var armor := 0.0
var weapon: int:
	get: return game.weapon_manager.current
	set(value): game.weapon_manager.current=value
var magazines: Array:
	get: return game.weapon_manager.magazines
	set(value): game.weapon_manager.magazines=value
var capacity: Array:
	get: return game.weapon_manager.capacity
	set(value): game.weapon_manager.capacity=value
var reserve: Array:
	get: return game.weapon_manager.reserve
	set(value): game.weapon_manager.reserve=value
var shot_timer := 0.0
var reload_timer := 0.0
var reload_duration := 0.0
var dash_timer := 0.0
var dash_cooldown := 0.0
var invulnerability := 0.0
var dash_direction := Vector3.ZERO
var recoil := 0.0
var walk_phase := 0.0
var boost := 0.0
var bot := false
var bot_fire := false
var test_motion := Vector3.ZERO
var shots_fired := 0
var rays_fired := 0
var weapon_visual: Node3D
var poison_time := 0.0
var burn_time := 0.0
var status_tick := .6
var grenades := 3
var max_grenades := 3
var grenade_cooldown := 0.0
var aim_cursor := Vector2.ZERO

func _ready() -> void:
	aim_cursor=get_viewport().get_visible_rect().size*.5
	collision_layer = 2
	collision_mask = 1|16
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = .9
	add_child(collider)
	model = Node3D.new()
	add_child(model)
	limbs = ZVisuals.humanoid(model)
	var marker := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius=.37
	torus.outer_radius=.41
	torus.rings=20
	torus.ring_segments=6
	marker.mesh=torus
	marker.position.y=.07
	marker.material_override=ZVisuals.mat(Color("a6cfad"),0,.5,.5)
	add_child(marker)
	gun = Node3D.new()
	gun.position = Vector3(.35,1.22,-.32)
	model.add_child(gun)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0,.02,-.95)
	gun.add_child(muzzle)
	rebuild_weapon_visual()
	flash = OmniLight3D.new()
	flash.light_color = Color("ffc477")
	flash.omni_range = 5
	flash.light_energy = 0
	muzzle.add_child(flash)
	var torch := SpotLight3D.new()
	torch.position = Vector3(.25,1.4,-.5)
	torch.rotation_degrees.x = -12
	torch.spot_range = 14
	torch.spot_angle = 30
	torch.light_color = Color("d9ecd9")
	torch.light_energy = 2
	model.add_child(torch)

func rebuild_weapon_visual() -> void:
	if is_instance_valid(weapon_visual):
		weapon_visual.queue_free()
	weapon_visual=Node3D.new()
	gun.add_child(weapon_visual)
	var data: Dictionary=game.weapon_manager.definition()
	gun.scale.z=1.0 if data.has("model_scene") else float(data.gun_scale)
	if data.has("model_scene") and ResourceLoader.exists(data.model_scene):
		var authored: PackedScene=load(data.model_scene)
		weapon_visual.add_child(authored.instantiate())
	else:
		for part in data.get("model_parts",[]):
			ZVisuals.box(weapon_visual,Vector3(part.size[0],part.size[1],part.size[2]),Vector3(part.position[0],part.position[1],part.position[2]),Color(part.color))
	muzzle.position=Vector3(0,.02,float(data.get("muzzle_offset",-.95)))

func _physics_process(delta: float) -> void:
	if game.state not in ["combat","cleared"] or game.paused:
		return
	shot_timer = maxf(0,shot_timer-delta)
	dash_cooldown = maxf(0,dash_cooldown-delta)
	grenade_cooldown=maxf(0,grenade_cooldown-delta)
	invulnerability = maxf(0,invulnerability-delta)
	poison_time=maxf(0,poison_time-delta)
	burn_time=maxf(0,burn_time-delta)
	if game.state=="combat" and (poison_time>0 or burn_time>0):
		status_tick-=delta
		if status_tick<=0:
			status_tick=.6
			take_damage((2.0 if poison_time>0 else 0.0)+(3.0 if burn_time>0 else 0.0))
			if game.state!="combat":
				return
	boost = maxf(0,boost-delta)
	recoil = move_toward(recoil,0,delta*4)
	flash.light_energy = move_toward(flash.light_energy,0,delta*90)
	if reload_timer > 0:
		reload_timer -= delta
		if reload_timer <= 0:
			game.weapon_manager.complete_reload()
			game.sound.play("weapon_mechanism",-10)
	var movement := input_movement()
	if bot:
		movement = test_motion
		if game.autoplay:
			movement=autopilot(delta)
		if bot_fire:
			var target = game.nearest_enemy(position,null,100,true)
			var mission_target: Node3D=game.objective.combat_target() if game.autoplay else null
			if is_instance_valid(mission_target):
				target=mission_target
			if is_instance_valid(target):
				aim_point = target.global_position+(Vector3(0,1.62*target.scale.y,0) if target.is_in_group("hostiles") else Vector3.ZERO)
	else:
		update_aim()
	var dir := aim_point - global_position
	dir.y = 0
	if dir.length_squared() > .01:
		facing = dir.normalized()
		model.rotation.y = atan2(-facing.x,-facing.z)
	if dash_timer > 0:
		dash_timer -= delta
		velocity = dash_direction * 18
	else:
		var mobility: float=float(game.weapon_manager.definition().get("move_multiplier",1))
		velocity.x = movement.x*5.8*mobility
		velocity.z = movement.z*5.8*mobility
	velocity.y = -3
	move_and_slide()
	position.x = clampf(position.x,-15,15)
	position.z = clampf(position.z,-15.8,12.8)
	walk_phase += delta*13*movement.length()
	limbs.left_leg.rotation.x = sin(walk_phase)*.5*movement.length()
	limbs.right_leg.rotation.x = -sin(walk_phase)*.5*movement.length()
	gun.position.z = -.32+recoil*.45
	gun.rotation.z = sin(reload_timer*8)*.6 if reload_timer>0 else 0.0
	if (bot and bot_fire) or (not bot and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		if not bot or is_instance_valid(game.nearest_enemy(position,null,100,true)) or (game.autoplay and is_instance_valid(game.objective.combat_target())):
			shoot()

func input_movement() -> Vector3:
	var v := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	var right: Vector3 = game.camera.global_basis.x
	var forward: Vector3 = game.camera.global_basis.z
	right.y=0
	forward.y=0
	return (right.normalized()*v.x+forward.normalized()*v.y).limit_length()

func autopilot(_delta: float) -> Vector3:
	if game.state=="cleared":
		var path: PackedVector3Array=game.world.path(position,Vector3(0,0,-13))
		if path.size()>1:
			var d: Vector3=path[1]-position
			d.y=0
			return d.normalized()
		return (Vector3(0,0,-13.2)-Vector3(position.x,0,position.z)).normalized()
	var mission_goal: Vector3=game.objective.steering_goal()
	if game.objective.kind=="generator" and not game.objective.activated:
		var path: PackedVector3Array=game.world.path(position,mission_goal)
		if position.distance_to(mission_goal)<.35:
			return Vector3.ZERO
		if path.size()>1:
			return (path[1]-Vector3(position.x,0,position.z)).normalized()
		return (mission_goal-Vector3(position.x,0,position.z)).normalized()
	var desired := Vector3.ZERO
	var telegraph_danger := false
	for prop in game.world.environment_props.props:
		if is_instance_valid(prop) and prop.armed and not prop.destroyed:
			var radial: Vector3=position-prop.global_position
			radial.y=0
			if radial.length()<float(prop.definition.radius)+1:
				desired+=(radial.normalized() if radial.length()>.1 else Vector3.RIGHT)*12
				telegraph_danger=true
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var away: Vector3=position-enemy.position
		away.y=0
		var d := away.length()
		if d<6:
			desired+=away.normalized()*(6-d)
		if enemy.boss and enemy.boss_brain!=null and enemy.boss_brain.state in ["windup","charge"]:
			var brain=enemy.boss_brain
			if brain.attack=="charge":
				var along: float=away.dot(brain.charge_direction)
				var side: Vector3=away-brain.charge_direction*away.dot(brain.charge_direction)
				if along>0 and along<14 and side.length()<2.2:
					var escape: Vector3=side.normalized() if side.length()>.1 else brain.charge_direction.rotated(Vector3.UP,PI*.5)
					desired+=escape*12
					telegraph_danger=true
			elif brain.attack in ["slam","aoe"]:
				var center: Vector3=enemy.global_position if brain.attack=="slam" else brain.locked_point
				var radial: Vector3=position-center
				radial.y=0
				var radius: float=float(enemy.definition.get("slam_radius",5)) if brain.attack=="slam" else float(enemy.definition.get("boss_aoe_radius",3.2))
				if radial.length()<radius+1:
					var escape: Vector3=radial.normalized() if radial.length()>.1 else Vector3(cos(game.clock),0,sin(game.clock))
					desired+=escape*12
					telegraph_danger=true
	var orbit := Vector3(sin(game.clock*.22)*5,0,cos(game.clock*.22)*5)
	if mission_goal!=Vector3.INF:
		orbit=mission_goal
	desired+=(orbit-Vector3(position.x,0,position.z)).normalized()*.8
	var nearest = game.nearest_enemy(position)
	if magazines[weapon]<=0 and reserve[weapon]<=0 and game.weapon_manager.loadout.size()>1:
		for index in game.weapon_manager.loadout.size():
			if index!=weapon and (magazines[index]>0 or reserve[index]>0):
				switch_weapon()
				break
	if is_instance_valid(nearest):
		var close: float=nearest.position.distance_to(position)
		if (close<3 or telegraph_danger) and dash_cooldown<=0:
			test_motion=desired.normalized()
			dash()
		var desired_weapon := weapon
		for index in game.weapon_manager.loadout.size():
			var data: Dictionary=game.weapon_manager.definition(index)
			if close<5 and data.family=="shotgun":
				desired_weapon=index
			elif close>6 and data.family=="ballistic" and (game.weapon_manager.definition(desired_weapon).family!="ballistic" or float(data.range)>float(game.weapon_manager.definition(desired_weapon).range)):
				desired_weapon=index
		if desired_weapon!=weapon:
			equip_weapon(desired_weapon)
	# Rotate a candidate steering direction until both clearance samples are walkable.
	for angle in [0.0,.6,-.6,1.2,-1.2,2.0,-2.0,PI]:
		var candidate := desired.normalized().rotated(Vector3.UP,angle)
		if game.world.walkable(position+candidate*.9) and game.world.walkable(position+candidate*1.6):
			return candidate
	var escape: PackedVector3Array=game.world.path(position,Vector3.ZERO)
	if escape.size()>1:
		return (escape[1]-Vector3(position.x,0,position.z)).normalized()
	return Vector3.ZERO

func move_aim_cursor(relative: Vector2) -> void:
	var sensitivity: float=clampf(float(game.save_manager.profile.settings.aim_sensitivity),.25,3)
	aim_cursor=(aim_cursor+relative*sensitivity).clamp(Vector2.ZERO,get_viewport().get_visible_rect().size)

func update_aim() -> void:
	var mouse: Vector2=aim_cursor if game.manage_pointer else get_viewport().get_mouse_position()
	var origin: Vector3 = game.camera.project_ray_origin(mouse)
	var dir: Vector3 = game.camera.project_ray_normal(mouse)
	var hit = Plane(Vector3.UP,1.2).intersects_ray(origin,dir)
	if hit != null:
		aim_point = hit
	# Aim assistance only resolves which visible height the cursor actually points at.
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+dir*150,8|16)
	var result := get_world_3d().direct_space_state.intersect_ray(ray)
	if not result.is_empty():
		aim_point = result.position

func switch_weapon() -> void:
	equip_weapon((weapon+1)%game.weapon_manager.loadout.size())

func equip_weapon(index: int) -> void:
	if index==weapon or index<0 or index>=game.weapon_manager.loadout.size():
		return
	if reload_timer > 0:
		reload_timer = 0
	game.weapon_manager.equip(index)
	gun.scale.z = float(game.weapon_manager.definition().gun_scale)
	rebuild_weapon_visual()
	game.sound.play("weapon_mechanism",-13)

func reload() -> void:
	if reload_timer > 0 or magazines[weapon]>=capacity[weapon] or reserve[weapon]<=0:
		return
	var definition: Dictionary=game.weapon_manager.definition()
	reload_duration = maxf(.2,float(definition.reload)*(1-game.rogue_manager.value("shotgun_reload") if definition.family=="shotgun" else 1.0))
	reload_timer = reload_duration
	game.sound.play("reload",-8)
	game.rogue_manager.on_reload()

func dash() -> void:
	if dash_cooldown > 0:
		return
	dash_direction = input_movement() if not bot else test_motion
	if dash_direction.length_squared()<.01:
		dash_direction = facing
	dash_timer = .16
	dash_cooldown = maxf(.4,1.6*(1-game.rogue_manager.value("dash_cooldown")))
	invulnerability = .26
	game.feedback_manager.route("dash",position)
	game.rogue_manager.on_dash()

func throw_grenade() -> bool:
	if game.state!="combat" or game.paused or grenades<=0 or grenade_cooldown>0:
		return false
	var data: Dictionary=game.catalog.definition("weapons","grenade_launcher")
	data.damage=120
	data.blast_radius=4
	data.projectile_speed=12
	data.projectile_lift=3
	data.projectile_gravity=9
	data.crit_chance=0
	grenades-=1
	grenade_cooldown=.6
	game.weapon_manager.launch_grenade(muzzle.global_position,(aim_point-muzzle.global_position).normalized(),data)
	game.sound.play("weapon_mechanism",-10,.8)
	return true

func shoot() -> void:
	if shot_timer > 0 or reload_timer > 0:
		return
	if magazines[weapon]<=0:
		reload()
		return
	magazines[weapon]-=1
	shots_fired += 1
	var definition: Dictionary=game.weapon_manager.definition()
	var shotgun: bool=definition.family=="shotgun"
	var rate: float=1.0+game.rogue_manager.value("fire_rate")+(game.rogue_manager.value("kill_speed_rate") if boost>0 else 0.0)+(game.rogue_manager.value("shotgun_rate") if shotgun else 0.0)
	shot_timer = float(definition.interval)/rate
	recoil = float(definition.recoil)
	var origin := muzzle.global_position
	var direction := (aim_point-origin).normalized()
	game.fx.weapon_muzzle(origin,direction,definition)
	flash.light_color=Color(definition.get("tracer_color","ffd990"))
	flash.light_energy = float(definition.flash)
	game.feedback_manager.weapon_fired(definition)
	game.fx.debris(origin,model.global_basis.x*3+Vector3.UP*2,Color("b59b56"),Vector3(.035,.035,.1),1.4,12)
	get_tree().create_timer(.22).timeout.connect(game.sound.play.bind("casing",-23))
	if definition.behavior=="projectile":
		game.weapon_manager.launch_grenade(origin,direction,definition)
		return
	var pellets: int=int(definition.pellets)+(int(game.rogue_manager.value("pellets")) if shotgun else 0)
	for i in pellets:
		var spread: float=definition.spread
		var shot_dir := (direction+Vector3(randf_range(-spread,spread),randf_range(-spread*float(definition.vertical_spread),spread*float(definition.vertical_spread)),randf_range(-spread,spread))).normalized()
		fire_ray(origin,shot_dir,float(definition.damage)*(1+game.rogue_manager.value("damage_mult")),int(game.rogue_manager.value("pierce"))+int(definition.get("pierce",0)))

func fire_ray(origin: Vector3, direction: Vector3, damage: float, penetration: int) -> void:
	rays_fired+=1
	var definition: Dictionary=game.weapon_manager.definition()
	var end := origin+direction*float(definition.range)
	var visual_end := end
	var excludes: Array[RID] = [get_rid()]
	var first := origin
	for step in range(penetration+1):
		var ray := PhysicsRayQueryParameters3D.create(origin,end,1|8|16,excludes)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			break
		end = hit.position
		visual_end = end
		if hit.collider.has_method("take_damage"):
			var enemy = hit.collider
			var hostile: bool=enemy.is_in_group("hostiles")
			var headshot: bool = hostile and hit.position.y > enemy.position.y+1.43*enemy.scale.y
			var critical: bool = hostile and (randf()<minf(.75,float(definition.crit_chance)+game.rogue_manager.value("crit_chance")) or headshot)
			var dealt := damage*(float(definition.crit_multiplier) if critical else 1.0)
			if definition.family=="shotgun" and first.distance_to(hit.position)<6:
				dealt*=1+game.rogue_manager.value("shotgun_close_damage")
			var force: float=float(definition.knockback)*(1+game.rogue_manager.value("shotgun_knockback") if definition.family=="shotgun" else 1.0)
			enemy.take_damage(dealt,direction,headshot,critical,force)
			game.hit_marker = .14
			game.hit_critical = critical
			if hostile and game.rogue_manager.value("burn_duration")>0 and is_instance_valid(enemy):
				enemy.burn_time = game.rogue_manager.value("burn_duration")
			if hostile and critical and game.rogue_manager.value("ricochet_damage")>0:
				game.ricochet(enemy,damage)
			if hostile:
				game.rogue_manager.on_weapon_hit(enemy,critical)
			excludes.append(enemy.get_rid())
			origin = hit.position+direction*.1
			end = first+direction*float(definition.range)
		else:
			game.fx.debris(hit.position,Vector3.UP*2,Color("e4b777"),Vector3.ONE*.06,.15,8,2)
			break
	game.fx.weapon_tracer(first,visual_end,definition)
	if visual_end!=end or visual_end.distance_to(first)<float(definition.range)-.1:
		game.fx.weapon_impact(visual_end,direction,definition)

func apply_status(kind: String, duration: float) -> void:
	if game.state!="combat":
		return
	if kind=="poison": poison_time=maxf(poison_time,duration)
	if kind=="burn": burn_time=maxf(burn_time,duration)
	status_tick=.6

func take_damage(amount: float) -> void:
	if invulnerability>0 or game.state!="combat":
		return
	game.stage_manager.damage_taken+=minf(hp+armor,maxf(0,amount))
	var absorbed := minf(armor,amount)
	armor-=absorbed
	amount-=absorbed
	hp = maxf(0,hp-amount)
	invulnerability = .55
	game.feedback_manager.player_hurt()
	if hp<=0:
		game.fail_run()
