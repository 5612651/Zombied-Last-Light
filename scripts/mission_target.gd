class_name MissionTarget
extends StaticBody3D

var game: Node3D
var objective: Node3D
var kind := "nest"
var target_id := ""
var hp := 160.0
var max_hp := 160.0
var destroyed := false
var lamp: OmniLight3D

func _ready() -> void:
	collision_layer=16
	collision_mask=0
	var shape := BoxShape3D.new()
	shape.size=Vector3(1.65,1.6,1.65) if kind=="nest" else Vector3(1.8,1.4,1.3)
	var collider := CollisionShape3D.new()
	collider.shape=shape
	add_child(collider)
	if kind=="nest":
		ZVisuals.sphere(self,.65,Vector3.ZERO,Color("633d38"))
		for offset in [Vector3(-.48,-.2,.2),Vector3(.4,-.15,.35),Vector3(.1,.4,-.1)]:
			ZVisuals.sphere(self,.4,offset,Color("8e4c3a"))
		ZVisuals.box(self,Vector3(1.7,.15,1.7),Vector3(0,-.7,0),Color("273b35"))
		for x in [-.3,0,.3]:
			ZVisuals.box(self,Vector3(.08,.5,.08),Vector3(x,.15,-.6),Color("e7a35e"),2)
	else:
		ZVisuals.box(self,Vector3(1.8,1.25,1.25),Vector3.ZERO,Color("5f6851"))
		ZVisuals.box(self,Vector3(1.9,.14,1.4),Vector3(0,-.66,0),Color("222f2c"))
		for x in [-.65,-.42,-.19,.04,.27,.5]:
			ZVisuals.box(self,Vector3(.1,.65,.06),Vector3(x,0,-.66),Color("172d28"))
		ZVisuals.box(self,Vector3(.5,.3,.08),Vector3(.4,.38,.66),Color("ba853f"),1)
	lamp=OmniLight3D.new()
	lamp.position.y=1
	lamp.light_color=Color("de8252")
	lamp.light_energy=2.2
	lamp.omni_range=4
	add_child(lamp)

func take_damage(amount: float, direction: Vector3=Vector3.ZERO, _headshot: bool=false, _critical: bool=false, _force: float=0) -> void:
	if destroyed or kind!="nest" or game.state!="combat":
		return
	hp=maxf(0,hp-amount)
	game.fx.blood(global_position,direction,true)
	game.fx.number(global_position,amount)
	game.sound.play("impact",-12,.7)
	if hp<=0:
		destroyed=true
		set_deferred("collision_layer",0)
		visible=false
		game.fx.shockwave(global_position,Color("dd9561"))
		game.sound.play("kill",-8,.6)
		objective.target_destroyed(self)

func damage_by_enemy(amount: float) -> void:
	if destroyed or kind!="generator" or not objective.activated or game.state!="combat":
		return
	hp=maxf(0,hp-amount)
	game.fx.debris(global_position+Vector3.UP,Vector3.UP*2,Color("f2b268"),Vector3.ONE*.08,.3,8,2)
	if hp<=0:
		destroyed=true
		objective.generator_failed()

func melee_distance_from(pos: Vector3) -> float:
	var delta := (pos-global_position).abs()
	# Account for the unit's larger footprint rather than requiring a zombie
	# to place its centre inside the generator's collider to attack a corner.
	return Vector2(maxf(0,delta.x-.9),maxf(0,delta.z-.65)).length()+.32
