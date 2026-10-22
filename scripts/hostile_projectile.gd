extends Node3D

var game: Node3D
var motion := Vector3.ZERO
var damage := 14.0
var life := 0.0
var active := false

func _ready() -> void:
	ZVisuals.sphere(self,.13,Vector3.ZERO,Color("b6d34e"))

func launch(origin: Vector3, target: Vector3, speed: float, amount: float) -> void:
	global_position=origin
	motion=(target-origin).normalized()*speed
	damage=amount
	life=3
	active=true
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not active:
		return
	if game.state!="combat":
		recycle()
		return
	life-=delta
	var next := global_position+motion*delta
	var ray:=PhysicsRayQueryParameters3D.create(global_position,next,1|2|16)
	var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var victim: Node=hit.collider
		if victim==game.player:
			victim.take_damage(damage)
			victim.apply_status("poison",3)
		elif victim.has_method("damage_by_enemy"):
			victim.damage_by_enemy(damage)
		game.fx.shockwave(hit.position,Color("b6d34e"))
		recycle()
		return
	global_position=next
	if life<=0:
		recycle()

func recycle() -> void:
	active=false
	game.enemy_manager.projectiles.erase(self)
	game.pool_manager.release(self)
