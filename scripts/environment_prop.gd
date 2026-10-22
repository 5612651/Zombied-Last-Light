extends RigidBody3D

var game: Node3D
var manager: Node3D
var kind := "barrel"
var definition: Dictionary={}
var hp := 40.0
var destroyed := false
var armed := false
var fuse := 0.0
var settle_time := 0.0
var obstacle: Dictionary={}
var visual: Node3D
var warning: MeshInstance3D
var title: Label3D

func _ready() -> void:
	freeze=true
	freeze_mode=RigidBody3D.FREEZE_MODE_STATIC
	mass=float(definition.get("mass",20))
	collision_layer=1|16
	collision_mask=1|2|16
	hp=float(definition.health)
	var size:=Vector3(definition.size[0],definition.size[1],definition.size[2])
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=size
	shape.shape=box
	shape.position.y=size.y*.5
	add_child(shape)
	visual=Node3D.new()
	add_child(visual)
	var models: Dictionary={"car":"compact_car","barrel":"oil_barrel","electric_box":"electric_box","fuel_pump":"fuel_pump","trash_bin":"trash_bin","barrier":"low_barrier"}
	if models.has(kind):
		var path: String="res://assets/models/v5/kit/"+str(models[kind])+".glb"
		var scene: PackedScene=load(path if ResourceLoader.exists(path) else "res://assets/models/kit/"+str(models[kind])+".glb")
		visual.add_child(scene.instantiate())
	else:
		var body:=ZVisuals.box(visual,size,Vector3.UP*size.y*.5,Color(definition.color))
		if kind=="glass":
			var glass:=StandardMaterial3D.new()
			glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color=Color(.4,.7,.65,.3)
			glass.roughness=.12
			body.material_override=glass
		elif kind in ["barrel","fuel_pump","electric_box"]:
			ZVisuals.box(visual,Vector3(size.x*.8,.1,size.z*1.03),Vector3(0,size.y*.65,0),Color("d2b16c"))
			ZVisuals.box(visual,Vector3(.2,.35,.04),Vector3(0,size.y*.6,size.z*.52),Color("e4bf61"),.4)
	title=Label3D.new()
	title.font=GameLocale.font()
	title.position.y=size.y+.3
	title.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	title.font_size=24
	title.pixel_size=.007
	title.modulate=Color("e4bf61")
	title.text="易爆" if definition.effect in ["blast","electric"] else ""
	add_child(title)
	add_obstacle()

func add_obstacle() -> void:
	if not obstacle.is_empty() or destroyed:
		return
	var size:=Vector3(definition.size[0],definition.size[1],definition.size[2])
	var center: Vector3=global_position+global_basis*Vector3.UP*size.y*.5
	var extent: Vector3=global_basis.x.abs()*size.x+global_basis.y.abs()*size.y+global_basis.z.abs()*size.z
	obstacle={"name":"Interactive "+str(get_instance_id()),"position":[center.x,center.y,center.z],"size":[extent.x,extent.y,extent.z]}
	manager.world.obstacles.append(obstacle)
	manager.nav_dirty=true

func remove_obstacle() -> void:
	if not obstacle.is_empty():
		manager.world.obstacles.erase(obstacle)
		obstacle={}
		manager.nav_dirty=true

func _physics_process(delta: float) -> void:
	if is_instance_valid(game.player) and not destroyed:
		title.visible=armed or game.player.global_position.distance_to(global_position)<8
	if settle_time>0:
		settle_time-=delta
		if settle_time<=0:
			freeze=true
			linear_velocity=Vector3.ZERO
			angular_velocity=Vector3.ZERO
			add_obstacle()
	if armed and not destroyed and game.state in ["combat","cleared"]:
		fuse-=delta
		title.modulate=Color("ff6846") if sin(fuse*30)>0 else Color("ffe5a2")
		if fuse<=0:
			detonate()

func take_damage(amount: float, direction: Vector3=Vector3.ZERO, _headshot: bool=false, _critical: bool=false, force: float=2) -> void:
	if destroyed or armed or game.state!="combat":
		return
	game.hit_marker=.14
	game.fx.number(global_position,amount)
	game.feedback_manager.route("elemental" if definition.effect=="electric" else "normal_hit",global_position+Vector3.UP,direction)
	if definition.effect=="movable":
		freeze=false
		remove_obstacle()
		apply_central_impulse((direction.normalized()*maxf(4,force)*.8+Vector3.UP*2)*mass)
		settle_time=3
		hp=maxf(1,hp-amount)
		return
	hp-=amount
	if hp>0:
		return
	if definition.effect=="shatter":
		destroyed=true
		game.stage_manager.props_destroyed+=1
		collision_layer=0
		remove_obstacle()
		visual.visible=false
		for i in 12:
			game.fx.debris(global_position+Vector3.UP,direction*3+Vector3.UP*randf_range(1,4),Color("b0d4ce"),Vector3(.12,.15,.02),.8,10)
		game.sound.play("casing",-6,1.8)
		return
	armed=true
	fuse=float(definition.warning)
	title.text="危险 / "+str(definition.warning)+"秒"
	warning=MeshInstance3D.new()
	var disk:=CylinderMesh.new()
	disk.top_radius=float(definition.radius)
	disk.bottom_radius=float(definition.radius)
	disk.height=.025
	disk.radial_segments=32
	warning.mesh=disk
	warning.position=Vector3.UP*.05
	add_child(warning)
	var material:=StandardMaterial3D.new()
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(.85,.25,.05,.12)
	warning.material_override=material

func detonate() -> void:
	if destroyed:
		return
	destroyed=true
	game.stage_manager.props_destroyed+=1
	armed=false
	collision_layer=0
	remove_obstacle()
	visual.visible=false
	title.visible=false
	if is_instance_valid(warning): warning.visible=false
	manager.detonate(self)
	for i in 10:
		game.fx.debris(global_position+Vector3.UP,Vector3(randf_range(-4,4),randf_range(2,6),randf_range(-4,4)),Color("4f4940"),Vector3.ONE*.2,1,10)
