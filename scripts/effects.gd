class_name VFXManager
extends Node3D

var particles: Array = []
var corpses: Array[Node3D] = []
var damage_numbers: Array = []
var game: Node3D
var rng := RandomNumberGenerator.new()
var particle_mesh := BoxMesh.new()
var pulse_mesh := TorusMesh.new()
var flare_mesh := QuadMesh.new()
var flare_materials: Dictionary={}
const FlareShader=preload("res://shaders/combat_flare.gdshader")
var ragdoll_frame := -1
var frame_corpses := 0
var moving_corpses: Array[WeakRef]=[]
var sampled_deaths := 0

func _ready() -> void:
	rng.randomize()
	pulse_mesh.inner_radius=.85
	pulse_mesh.outer_radius=1.0
	pulse_mesh.rings=20
	pulse_mesh.ring_segments=6

func _process(delta: float) -> void:
	var profile_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	for i in range(particles.size()-1,-1,-1):
		var p: Dictionary = particles[i]
		p.life -= delta
		if p.life <= 0:
			game.pool_manager.release(p.node)
			particles.remove_at(i)
			continue
		p.velocity.y -= delta * p.gravity
		p.node.position += p.velocity*delta
		if p.node.position.y < .08 and p.gravity > 0:
			p.node.position.y = .08
			p.velocity = Vector3(p.velocity.x*.6, absf(p.velocity.y)*.32, p.velocity.z*.6)
		p.node.rotation += p.spin*delta
		if p.has("duration"):
			p.node.set_instance_shader_parameter("phase",1.0-p.life/p.duration)
		if p.has("expand"):
			p.node.scale+=Vector3.ONE*float(p.expand)*delta
		if p.fade:
			p.node.scale = p.base_scale * minf(1,p.life / .15)
	for i in range(damage_numbers.size()-1,-1,-1):
		var n: Dictionary = damage_numbers[i]
		n.life -= delta
		n.position.y += delta*.8
		if n.life <= 0:
			damage_numbers.remove_at(i)
	if game.combat_profiler.enabled: game.combat_profiler.note("vfx_update",profile_start)

func debris(pos: Vector3, velocity: Vector3, color: Color, size: Vector3, life: float = .5, gravity: float = 12, glow: float = 0) -> void:
	# Reserve foreground capacity for the player's muzzle, beam and impact layers.
	if particles.size() >= 300:
		return
	var node := obtain_particle(pos,size,color,glow)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.append({"node":node,"velocity":velocity,"life":life,"gravity":gravity,"spin":Vector3(randf(),randf(),randf())*8,"fade":true,"base_scale":size})

func tracer(a: Vector3, b: Vector3, color: Color = Color("ffd990")) -> void:
	var length := a.distance_to(b)
	if length < .01 or particles.size()>=450:
		return
	var node := obtain_particle((a+b)*.5,Vector3(.025,.025,length),color,4)
	node.look_at(b,Vector3.UP)
	particles.append({"node":node,"velocity":Vector3.ZERO,"life":.055,"gravity":0,"spin":Vector3.ZERO,"fade":false})

func muzzle(pos: Vector3, direction: Vector3, shotgun: bool) -> void:
	debris(pos,direction*2,Color("ffe0a0"),Vector3(.23,.18,.5) if shotgun else Vector3(.14,.12,.32),.045,0,8)
	for i in (5 if shotgun else 2):
		debris(pos,direction*randf_range(2,5)+Vector3(randf_range(-1,1),randf(),randf_range(-1,1)),Color("ff9d42"),Vector3.ONE*.045,.12,0,3)

func reduced() -> bool:
	return bool(game.save_manager.profile.settings.get("reduced_effects",false))

func energy_line(a: Vector3,b: Vector3,color: Color,width: float,life: float) -> void:
	if particles.size()>=450 or a.distance_squared_to(b)<.0001: return
	var node := obtain_particle((a+b)*.5,Vector3(width,width,a.distance_to(b)),color,5)
	# A white hot core and a colored outer rail remain visible from the overhead camera.
	node.look_at(b,Vector3.UP if absf((b-a).normalized().y)<.99 else Vector3.RIGHT)
	particles.append({"node":node,"velocity":Vector3.ZERO,"life":life,"gravity":0,"spin":Vector3.ZERO,"fade":true,"base_scale":node.scale})

func energy_ring(pos: Vector3,normal: Vector3,color: Color,size: float,growth: float,life: float) -> void:
	if particles.size()>=450: return
	var node := obtain_particle(pos,Vector3.ONE*size,color,4)
	node.mesh=pulse_mesh
	node.quaternion=Quaternion(Vector3.UP,normal.normalized())
	particles.append({"node":node,"velocity":Vector3.ZERO,"life":life,"gravity":0,"spin":Vector3.ZERO,"fade":false,"expand":growth})

func weapon_muzzle(pos: Vector3,direction: Vector3,data: Dictionary) -> void:
	var color := Color(data.get("tracer_color","55ddff"))
	var id: String=data.id
	var heavy: bool=id in ["shotgun","magnum","grenade_launcher"]
	energy_line(pos,pos+direction*(.8 if heavy else .48),color,.16 if heavy else .085,.07)
	if reduced(): return
	flare(pos,color,.65 if heavy else .38,.09)
	energy_ring(pos,direction,color,.21 if heavy else .13,2.0,.12)
	var side := direction.cross(Vector3.UP).normalized()
	if id=="shotgun":
		for i in [-1,0,1]: energy_line(pos,pos+direction*.9+side*i*.35,color,.065,.09)
	elif id=="magnum":
		energy_ring(pos+direction*.25,direction,Color.WHITE,.12,3.0,.14)
	elif id=="lmg":
		for i in [-1,1]: debris(pos,side*i*3+Vector3.UP*2,color,Vector3(.045,.045,.16),.16,1,4)
	elif id=="grenade_launcher":
		energy_ring(pos+direction*.2,direction,color,.33,2.5,.18)

func weapon_tracer(a: Vector3,b: Vector3,data: Dictionary) -> void:
	var color := Color(data.get("tracer_color","55ddff"))
	var id: String=data.id
	var width: float={"ar":.045,"shotgun":.065,"smg":.035,"magnum":.11,"lmg":.07}.get(id,.05)
	var duration: float=.11 if id=="magnum" else .075
	energy_line(a,b,color,width,duration)
	if reduced(): return
	var direction := (b-a).normalized()
	if id in ["ar","magnum"]:
		energy_line(a,b,Color("e9fcff"),width*.32,duration)
		if id=="magnum":
			for fraction in [.2,.5,.8]: energy_ring(a.lerp(b,fraction),direction,color,.16,1.8,.16)
	elif id=="smg":
		var side := direction.cross(Vector3.UP).normalized()*.065
		energy_line(a+side,b+side,color,.018,.09)
	elif id=="lmg":
		energy_line(a.lerp(b,.65),b,Color("fff2ba"),.035,.1)

func weapon_impact(pos: Vector3,direction: Vector3,data: Dictionary) -> void:
	var color := Color(data.get("tracer_color","55ddff"))
	var heavy: bool=data.id in ["magnum","shotgun","grenade_launcher"]
	if reduced():
		debris(pos,Vector3.UP,color,Vector3.ONE*.1,.1,0,3)
		return
	energy_ring(pos,-direction,color,.12 if not heavy else .24,2.0,.16)
	flare(pos,color,.9 if heavy else .5,.13)
	if heavy: flare(pos,color,1.4,.22,1.0)
	for i in (4 if heavy else 2):
		debris(pos,Vector3(randf_range(-2,2),randf_range(1,4),randf_range(-2,2)),color,Vector3(.035,.035,.18),.18,3,4)

func plasma_explosion(pos: Vector3,radius: float,color: Color) -> void:
	energy_ring(pos+Vector3.UP*.12,Vector3.UP,color,.3,radius*5,.2)
	if reduced(): return
	flare(pos+Vector3.UP*.6,color,radius*1.2,.27)
	flare(pos+Vector3.UP*.6,color,radius*2.1,.36,1.0)
	energy_ring(pos+Vector3.UP*.3,Vector3.RIGHT,color,.25,radius*3,.22)
	for i in 10:
		var direction := Vector3(sin(i*TAU/10),.25,cos(i*TAU/10))
		energy_line(pos,pos+direction*radius*.7,color,.08,.18)

func flare(pos: Vector3,color: Color,size_: float,life: float,shape: float=0.0) -> void:
	if particles.size()>=450: return
	var node:=obtain_particle(pos,Vector3.ONE*size_,color,0)
	node.mesh=flare_mesh
	# Camera-facing layered light is independent from the projectile's gameplay ray.
	node.global_basis=game.camera.global_basis.scaled(Vector3.ONE*size_)
	var key: String=str(color)+str(shape)
	if not flare_materials.has(key):
		var material:=ShaderMaterial.new()
		material.shader=FlareShader
		material.set_shader_parameter("tint",color)
		material.set_shader_parameter("shape",shape)
		flare_materials[key]=material
	node.material_override=flare_materials[key]
	node.set_instance_shader_parameter("phase",0.0)
	particles.append({"node":node,"velocity":Vector3.ZERO,"life":life,"duration":life,"gravity":0,"spin":Vector3.ZERO,"fade":false})

func blood(pos: Vector3, direction: Vector3, strong: bool = false) -> void:
	for i in (15 if strong else 6):
		var size := randf_range(.04,.12)
		debris(pos,direction*randf_range(2,6)+Vector3(randf_range(-1.8,1.8),randf_range(1,3),randf_range(-1.8,1.8)),Color("7e2527"),Vector3.ONE*size,randf_range(.3,.7),14)

func number(pos: Vector3, amount: float, critical: bool = false) -> void:
	if damage_numbers.size()>=128:
		damage_numbers.pop_front()
	damage_numbers.append({"position":pos+Vector3(0,2.1,0),"amount":roundi(amount),"critical":critical,"life":.7})

func shockwave(pos: Vector3, color: Color = Color("a3d5bd")) -> void:
	for i in 28:
		var angle := float(i)*TAU/28
		debris(pos+Vector3(0,.15,0),Vector3(sin(angle),.05,cos(angle))*9,color,Vector3(.07,.06,.25),.3,0,2)

func ragdoll(enemy: Node3D, direction: Vector3, force: float) -> void:
	var frame: int=Engine.get_physics_frames()
	if ragdoll_frame!=frame:
		ragdoll_frame=frame
		frame_corpses=0
	# Every death keeps its damage/kill/blood feedback. Jointed bodies are a
	# bounded visual sample during mass chain kills, matching the 24-corpse cap.
	if frame_corpses>=4 and not enemy.boss:
		sampled_deaths+=1
		return
	frame_corpses+=1
	var profile_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	var root := Node3D.new()
	add_child(root)
	corpses.append(root)
	if corpses.size() > 24:
		corpses.pop_front().queue_free()
	var bodies: Dictionary = {}
	for key in enemy.limbs:
		var original: MeshInstance3D = enemy.limbs[key]
		var body := RigidBody3D.new()
		body.mass = 3 if key == "torso" else 1
		body.collision_layer = 4
		body.collision_mask = 1
		body.linear_damp = .8
		body.angular_damp = 1.2
		root.add_child(body)
		body.global_transform = original.global_transform
		body.global_basis = body.global_basis.orthonormalized()
		var visual := MeshInstance3D.new()
		visual.mesh = original.mesh
		visual.material_override = original.material_override
		visual.scale = original.global_basis.get_scale()
		body.add_child(visual)
		var shape := BoxShape3D.new()
		shape.size = original.mesh.size * enemy.scale.x
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		body.apply_central_impulse((direction+Vector3.UP*.25)*force*body.mass)
		body.apply_torque_impulse(Vector3(randf_range(-2,2),randf_range(-2,2),randf_range(-2,2)))
		bodies[key] = body
	for key in bodies:
		if key == "torso":
			continue
		var joint := PinJoint3D.new()
		root.add_child(joint)
		joint.global_position = (bodies[key].global_position+bodies.torso.global_position)*.5
		joint.node_a = bodies.torso.get_path()
		joint.node_b = bodies[key].get_path()
	moving_corpses.append(weakref(root))
	while moving_corpses.size()>8:
		var old: Node3D=moving_corpses.pop_front().get_ref()
		if is_instance_valid(old): freeze_corpse(old)
	var corpse_ref: WeakRef = weakref(root)
	get_tree().create_timer(3).timeout.connect(func():
		var existing: Node3D = corpse_ref.get_ref()
		if is_instance_valid(existing):
			freeze_corpse(existing)
	)
	if game.combat_profiler.enabled: game.combat_profiler.note("ragdoll_creation",profile_start)

func freeze_corpse(corpse: Node3D) -> void:
	for child in corpse.get_children():
		if child is RigidBody3D: child.freeze=true

func create_particle() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh=particle_mesh
	return node

func obtain_particle(pos: Vector3, size_: Vector3, color: Color, glow: float) -> MeshInstance3D:
	var node: MeshInstance3D=game.pool_manager.acquire("vfx",create_particle,self)
	node.mesh=particle_mesh
	node.transform=Transform3D.IDENTITY
	node.position=pos
	node.scale=size_
	node.material_override=ZVisuals.mat(color,.15,.5,glow)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func clear_transients() -> void:
	for particle in particles:
		if is_instance_valid(particle.node):
			game.pool_manager.release(particle.node)
	particles.clear()
	damage_numbers.clear()
	for corpse in corpses:
		if is_instance_valid(corpse):
			corpse.queue_free()
	corpses.clear()
	moving_corpses.clear()
	ragdoll_frame=-1
	frame_corpses=0
