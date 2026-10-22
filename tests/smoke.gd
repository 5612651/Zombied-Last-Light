extends Node

var game: Node3D
var results: Array = []

func check(condition: bool, title: String, detail: String="") -> void:
	results.append({"test":title,"passed":condition,"detail":detail})
	print(("PASS " if condition else "FAIL ")+title+" "+detail)

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func clean() -> void:
	for e in game.enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	game.enemies.clear()
	game.director.active=false
	game.player.bot_fire=false
	game.player.test_motion=Vector3.ZERO
	game.player.shot_timer=0
	game.player.reload_timer=0
	game.player.hp=100
	game.player.armor=0
	game.player.invulnerability=0
	game.perks.clear()
	game.state_manager.current="combat"
	game.stage_manager.cancel_pending()
	game.stage_manager.phase="objective"

func run(target: Node3D) -> void:
	game=target
	game.deploy(true)
	game.director.active=false
	game.player.bot=true
	await frames(3)
	var p=game.player
	p.position=Vector3(0,.05,7)
	p.test_motion=Vector3.RIGHT
	await frames(60)
	check(p.position.x>5,"WASD-equivalent movement uses CharacterBody physics",str(p.position))
	p.test_motion=Vector3.ZERO
	p.position=Vector3(-11,.05,-5)
	p.test_motion=Vector3.RIGHT
	await frames(60)
	check(p.position.x < -9.2,"Player collides with parked car",str(p.position))
	p.position=Vector3(0,.05,7)
	p.test_motion=Vector3.RIGHT
	p.dash_cooldown=0
	p.dash()
	p.take_damage(50)
	check(p.hp==100,"Dash damage immunity")
	await frames(10)
	check(p.position.x>2.4 and p.dash_cooldown>0,"Dash displacement and cooldown",str(p.position))
	p.test_motion=Vector3.ZERO
	clean()
	await frames(2)
	p.position=Vector3(0,.05,5)
	var e=game.spawn_enemy(Vector3(0,.05,0))
	p.aim_point=e.position+Vector3(0,1.63,0)
	await frames(2)
	var hp: float=e.hp
	p.magazines[0]=30
	p.weapon=0
	p.shoot()
	check(e.hp<hp,"AR raycast damages visible enemy",str(e.hp))
	check(p.magazines[0]==29,"AR consumes one round")
	check(game.fx.particles.size()>0 and game.fx.damage_numbers.size()>0,"Muzzle, tracer, casing and damage feedback spawned")
	check(p.recoil>0 and p.flash.light_energy>0 and game.shake>0,"Shot triggers recoil, muzzle light and camera shake")
	await frames(1)
	check(e.limbs.torso.material_overlay!=null,"Surviving enemy flashes on impact")
	p.magazines[0]=2
	p.reserve[0]=40
	p.shot_timer=0
	p.reload()
	await frames(90)
	check(p.magazines[0]==30 and p.reserve[0]==12,"Timed magazine reload transfers exact ammunition")
	clean()
	await frames(2)
	p.position=Vector3(0,.05,5)
	p.weapon=1
	p.magazines[1]=8
	var sg=game.spawn_enemy(Vector3(0,.05,1))
	p.aim_point=sg.position+Vector3(0,1.15,0)
	await frames(3)
	p.shoot()
	await frames(3)
	check(not is_instance_valid(sg) or sg.dead,"Shotgun pellet burst kills at close range")
	check(p.magazines[1]==7,"Shotgun consumes one shell")
	check(game.fx.corpses.size()>0,"Physical articulated death created")
	if game.fx.corpses.size()>0:
		var corpse=game.fx.corpses.back()
		check(corpse.get_child_count()>=11,"Ragdoll contains six bodies and five joints")
		check(corpse.get_child(0).linear_velocity.length()>1,"Shotgun death imparts physical body motion")
	clean()
	await frames(2)
	p.position=Vector3(-8,.05,-9)
	var chaser=game.spawn_enemy(Vector3(-8,.05,0))
	var route: PackedVector3Array=game.world.path(chaser.position,p.position)
	check(route.size()>12,"A* routes around a car",str(route.size()))
	var initial: float=chaser.position.distance_to(p.position)
	await frames(240)
	check(chaser.navigation_steps>0 and chaser.position.distance_to(p.position)<initial-2,"Enemy follows obstacle-aware path",str(chaser.position))
	var recovery: PackedVector3Array=game.world.path(Vector3(-9.15,0,-5),p.position)
	check(not recovery.is_empty(),"Knockback at a blocked nav cell recovers a nearby path")
	clean()
	await frames(2)
	p.position=Vector3(0,.05,5)
	var attacker=game.spawn_enemy(Vector3(.7,.05,5))
	await frames(80)
	check(p.hp<100 and attacker.attack_count>0,"Enemy attack damages player")
	check(game.hurt_overlay>0,"Player damage activates screen blood overlay")
	# Car between an enemy and the player must stop bullets.
	clean()
	await frames(2)
	p.position=Vector3(-8,.05,-10)
	var covered=game.spawn_enemy(Vector3(-8,.05,0))
	p.weapon=0
	p.aim_point=covered.position+Vector3.UP
	await frames(2)
	p.shoot()
	check(covered.hp==covered.max_hp,"Static cover blocks weapon ray")
	clean()
	await frames(2)
	game.perks.assign(["heal_kill","kill_speed"])
	p.hp=70
	var victim=game.spawn_enemy(Vector3(1,.05,0),true)
	victim.take_damage(1000,Vector3.BACK,true,true,7)
	check(p.hp==72 and p.boost==3,"Kill recovery and momentum perks trigger")
	check(game.cinematic_until>Time.get_ticks_msec(),"Elite kill triggers slow motion and hit stop")
	check(game.PERKS.size()==30,"Thirty Rogue upgrades registered")
	await frames(3)
	game.present_upgrades()
	check(game.upgrade_choices.size()==3,"Three distinct upgrade options offered")
	var chosen: String=game.upgrade_choices[0].id
	game.choose_perk(chosen)
	check(chosen in game.perks and game.state=="combat","Selected upgrade persists and resumes combat")
	clean()
	await frames(2)
	p.position=Vector3(0,.05,-11)
	await settle_stage(game)
	var previous_world: WeakRef=weakref(game.world)
	await frames(85)
	check(game.world.gate.collision_layer==0,"Cleared sector opens physical gate")
	p.test_motion=Vector3.FORWARD
	await frames(150)
	check(game.stage==2 and game.transitions==1,"Player walks directly into the next sector")
	check(previous_world.get_ref()==null and game.world.obstacles.any(func(o):return o.name=="Market booth"),"Old sector is unloaded and commercial layout replaces it")
	check(game.highest_stage>=2,"Highest sector record advances")
	game.player.bot=true
	game.director.active=false
	game.perks.assign(["pierce"])
	game.player.hp=1
	game.player.take_damage(1000)
	check(game.state=="dead" and game.perks.is_empty(),"Death returns to base UI and clears temporary build")
	check(game.highest_stage>=2,"Death retains sector record")
	game.deploy(true)
	game.director.active=false
	game.player.bot=true
	p=game.player
	await frames(3)
	clean()
	p.position=Vector3(0,.05,6)
	var first=game.spawn_enemy(Vector3(0,.05,2))
	var second=game.spawn_enemy(Vector3(0,.05,-1))
	first.hp=1000
	second.hp=1000
	await frames(3)
	p.fire_ray(Vector3(0,1.1,5),Vector3.FORWARD,20,1)
	check(first.hp<1000 and second.hp<1000,"Piercing ray damages two aligned targets")
	clean()
	await frames(2)
	p.position=Vector3(0,.05,6)
	var bomb=game.spawn_enemy(Vector3(0,.05,1))
	var blast_target=game.spawn_enemy(Vector3(1,.05,1))
	game.perks.append("head_blast")
	bomb.take_damage(1000,Vector3.FORWARD,true,true)
	check(blast_target.hp<blast_target.max_hp,"Headshot explosion damages nearby target")
	clean()
	await frames(2)
	p.position=Vector3(0,.05,6)
	var chain_a=game.spawn_enemy(Vector3(0,.05,2))
	var chain_b=game.spawn_enemy(Vector3(1.5,.05,2))
	chain_a.hp=1000
	game.perks.append("ricochet")
	await frames(3)
	p.fire_ray(chain_a.position+Vector3(0,1.65,2),Vector3.FORWARD,20,0)
	check(chain_b.hp<chain_b.max_hp,"Critical hit ricochets into nearby enemy")
	clean()
	await frames(2)
	p.position=Vector3(0,.05,6)
	var burning=game.spawn_enemy(Vector3(0,.05,2))
	burning.hp=1000
	game.perks.append("burn")
	await frames(3)
	p.fire_ray(Vector3(0,1.1,5),Vector3.FORWARD,20,0)
	var after_bullet: float=burning.hp
	await frames(65)
	check(burning.hp<after_bullet and burning.burn_time>0,"Incendiary inflicts continuing damage")
	clean()
	await frames(2)
	p.position=Vector3(0,.05,6)
	p.weapon=0
	p.magazines[0]=30
	p.shoot()
	var regular_timer: float=p.shot_timer
	p.shot_timer=0
	game.perks.append("fire_rate")
	p.shoot()
	check(is_equal_approx(regular_timer/p.shot_timer,1.25),"Fire rate upgrade changes actual firing interval")
	clean()
	await frames(2)
	p.weapon=1
	p.magazines[1]=8
	game.perks.append("pellets")
	var rays: int=p.rays_fired
	p.shoot()
	check(p.rays_fired-rays==10,"Buckshot upgrade emits ten actual pellet rays")
	clean()
	await frames(2)
	p.position=Vector3(0,.05,6)
	var pushed=game.spawn_enemy(Vector3(2,.05,6))
	game.perks.append("dash_wave")
	p.dash_cooldown=0
	p.dash()
	check(pushed.hp<pushed.max_hp and pushed.knockback.length()>5,"Dash shockwave damages and repels")
	clean()
	await frames(15)
	p.position=Vector3(0,.05,6)
	var pushed_reload=game.spawn_enemy(Vector3(2,.05,6))
	game.perks.append("reload_wave")
	p.magazines[p.weapon]=0
	p.reserve[p.weapon]=30
	p.reload()
	check(pushed_reload.hp<pushed_reload.max_hp and pushed_reload.knockback.length()>5,"Reload shockwave damages and repels")
	clean()
	await frames(2)
	game.paused=true
	get_tree().paused=true
	var held: Vector3=p.position
	p.test_motion=Vector3.RIGHT
	await get_tree().create_timer(.15,true,false,true).timeout
	check(p.position.is_equal_approx(held),"Pause stops player physics")
	get_tree().paused=false
	game.paused=false
	clean()
	await frames(2)
	game.stage=2
	await settle_stage(game)
	game.next_stage()
	await frames(110)
	game.director.active=false
	check(game.stage==3 and game.world.obstacles.any(func(o):return o.name=="Barricade"),"Final stage loads distinct arena layout")
	var boss=game.spawn_enemy(Vector3(0,.05,0),false,true)
	check(boss.max_hp==1400 and boss.scale.x>1.5,"Boss has distinct scale and health")
	boss.position=Vector3(-3.5,.05,-12)
	for i in 8:
		boss.take_damage(1,Vector3.FORWARD,false,false,12)
	await frames(90)
	check(boss.position.y>-1 and boss.position.z>-14,"Boss knockback stays inside the sealed arena")
	boss.position=Vector3(0,-4,-20)
	await frames(3)
	check(boss.position.y>-1 and boss.position.z>=-12,"Out-of-bounds enemy recovers into playable navigation")
	boss.take_damage(2000,Vector3.BACK)
	await frames(3)
	await settle_stage(game)
	game.next_stage()
	check(game.state=="victory","Final clear reaches extraction result")
	game.highest_stage=3
	game.lifetime_kills=123
	game.save_progress("user://smoke-progress.json")
	game.highest_stage=1
	game.lifetime_kills=0
	game.load_progress("user://smoke-progress.json")
	check(game.highest_stage==3 and game.lifetime_kills==123,"Progress is written, reopened and restored from disk")
	await frames(3)
	var failed: Array=results.filter(func(r):return not r.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"engine":Engine.get_version_info().string}
	var file := FileAccess.open("res://artifacts/smoke-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("SMOKE_COMPLETE "+str(report.passed)+"/"+str(results.size()))
	game.shutdown(0 if failed.is_empty() else 1)

func settle_stage(game: Node3D) -> void:
	game.clear_stage()
	await frames(80)
	if game.state=="upgrade":
		game.choose_perk(game.upgrade_choices[0].id)
