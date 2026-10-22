class_name BossBrain
extends RefCounted

var actor: CharacterBody3D
var game: Node3D
var state := "idle"
var attack := ""
var timer := 0.0
var cooldown := 3.0
var cycle := 0
var enraged := false
var locked_point := Vector3.ZERO
var charge_direction := Vector3.ZERO
var charge_hit := false
var warning: MeshInstance3D
var warning_text: Label3D
var counts: Dictionary={}

func setup(enemy: CharacterBody3D) -> void:
	actor=enemy
	game=enemy.game
	warning=MeshInstance3D.new()
	actor.add_child(warning)
	var material:=StandardMaterial3D.new()
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(1,.33,.08,.25)
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	warning.material_override=material
	warning_text=Label3D.new()
	warning_text.font=GameLocale.font()
	warning_text.position=Vector3(0,2.6,0)
	warning_text.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	warning_text.text=""
	warning_text.font_size=32
	warning_text.pixel_size=.006
	warning_text.modulate=Color("ffc176")
	actor.add_child(warning_text)
	reset()

func reset() -> void:
	state="idle"
	attack=""
	timer=0
	cooldown=3
	cycle=0
	enraged=false
	charge_hit=false
	counts.clear()
	if is_instance_valid(warning): warning.visible=false
	if is_instance_valid(warning_text): warning_text.text=""

func damage_multiplier() -> float:
	return 1.2 if enraged else 1.0

func update(delta: float, target: Node3D, difference: Vector3, distance: float) -> Vector3:
	if not enraged and actor.hp<=actor.max_hp*float(actor.definition.get("enrage_ratio",.4)):
		enraged=true
		game.announcement=actor.definition.title.to_upper()+" / 狂暴"
		game.announcement_time=3
		game.feedback_manager.route("boss_slam",actor.position)
		counts.enrage=1
		cooldown=minf(cooldown,1)
	if state=="idle":
		cooldown-=delta
		if cooldown<=0:
			var pattern: Array=actor.definition.get("boss_pattern",["charge","slam","aoe","summon"])
			begin_attack(str(pattern[cycle%pattern.size()]),target)
			cycle+=1
		return Vector3.INF
	if state=="windup":
		timer-=delta
		if timer<=0:
			warning.visible=false
			warning_text.text=""
			counts[attack]=int(counts.get(attack,0))+1
			if attack=="charge":
				state="charge"
				timer=float(actor.definition.get("boss_charge_duration",.9))
				charge_hit=false
			else:
				execute_attack(target)
				start_recovery()
		return Vector3.ZERO
	if state=="charge":
		timer-=delta
		if not charge_hit and distance<2.0:
			charge_hit=true
			deal_damage(target,float(actor.definition.get("boss_charge_damage",26)))
			game.feedback_manager.route("boss_slam",actor.position)
		if timer<=0:
			start_recovery()
			return Vector3.ZERO
		return charge_direction*float(actor.definition.get("boss_charge_speed",9))*(1.15 if enraged else 1)
	if state=="recovery":
		timer-=delta
		if timer<=0:
			state="idle"
			cooldown=float(actor.definition.get("boss_cooldown",2.5))*(.7 if enraged else 1)
		return Vector3.ZERO
	return Vector3.INF

func begin_attack(kind: String, target: Node3D) -> void:
	attack=kind
	state="windup"
	timer=float(actor.definition.get("boss_windup",1.2))
	locked_point=target.global_position if kind in ["charge","aoe"] else actor.global_position
	charge_direction=locked_point-actor.global_position
	charge_direction.y=0
	charge_direction=charge_direction.normalized()
	var inverse: Transform3D=actor.global_transform.affine_inverse()
	warning.position=inverse*Vector3(locked_point.x,.06,locked_point.z)
	warning.rotation=Vector3.ZERO
	var attack_name: String={"charge":"锁向冲锋","slam":"重击砸地","aoe":"区域轰击","summon":"召唤尸潮"}.get(kind,"危险")
	warning_text.text=("狂暴 / " if enraged else "")+attack_name+" / 立即躲避"
	if kind=="charge":
		var mesh:=BoxMesh.new()
		var length: float=minf(12,actor.global_position.distance_to(locked_point)+3)
		mesh.size=Vector3(2.4/actor.scale.x,.035/actor.scale.y,length/actor.scale.z)
		warning.mesh=mesh
		warning.position=inverse*(actor.global_position+charge_direction*length*.5+Vector3.UP*.05)
		warning.rotation.y=atan2(-charge_direction.x,-charge_direction.z)
	else:
		var disk:=CylinderMesh.new()
		var radius: float=float(actor.definition.get("slam_radius",5)) if kind=="slam" else float(actor.definition.get("boss_aoe_radius",3.2))
		if kind=="summon": radius=2
		disk.top_radius=radius/actor.scale.x
		disk.bottom_radius=radius/actor.scale.x
		disk.height=.035/actor.scale.y
		disk.radial_segments=40
		warning.mesh=disk
	warning.visible=true
	game.sound.play("hurt",-13,.65)

func start_recovery() -> void:
	state="recovery"
	timer=float(actor.definition.get("boss_recovery",1.25))
	actor.ability_state="recovery"

func execute_attack(target: Node3D) -> void:
	if attack=="summon":
		for i in int(actor.definition.get("boss_summon_count",6)):
			if game.enemies.size()>=60: break
			var point: Vector3=game.director.spawn_position()
			if point!=Vector3.INF: game.spawn_enemy(point,false,false,"runner" if i%3==0 else "normal")
		game.feedback_manager.route("elemental",actor.position)
		return
	var radius: float=float(actor.definition.get("slam_radius",5)) if attack=="slam" else float(actor.definition.get("boss_aoe_radius",3.2))
	var amount: float=float(actor.definition.get("slam_damage",22)) if attack=="slam" else float(actor.definition.get("boss_aoe_damage",18))
	var origin: Vector3=actor.global_position if attack=="slam" else locked_point
	var delta: Vector3=target.global_position-origin
	delta.y=0
	if delta.length()<radius:
		var ray:=PhysicsRayQueryParameters3D.create(origin+Vector3.UP,target.global_position+Vector3.UP,1)
		if game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): deal_damage(target,amount)
	game.feedback_manager.route("boss_slam",origin)
	game.world.environment_props.damage_props(origin+Vector3.UP,radius,80,10)

func deal_damage(target: Node3D, amount: float) -> void:
	if target.has_method("damage_by_enemy"): target.damage_by_enemy(amount*damage_multiplier())
	else: target.take_damage(amount*damage_multiplier())
