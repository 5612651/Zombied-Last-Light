extends Node

var game: Node3D
var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func equip(id: String) -> void:
	game.weapon_manager.loadout.assign([id])
	game.weapon_manager.reset()
	game.player.shot_timer=0
	game.player.reload_timer=0
	game.player.rebuild_weapon_visual()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func run(target: Node3D) -> void:
	game=target
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	game.player.position=Vector3(0,.05,6)
	game.player.aim_point=Vector3(0,1.1,0)
	check(game.catalog.items("weapons").size()==6,"Six authored weapons are available to progression and crates")
	var sounds := {}
	for weapon in game.catalog.items("weapons"):
		sounds[weapon.sound]=true
	check(sounds.size()==6 and sounds.keys().all(func(id):return game.sound.clips.has(id)),"Each weapon has its own loaded shot audio")
	for id in ["ar","smg","magnum","lmg"]:
		game.enemy_manager.clear()
		equip(id)
		game.catalog.tables.weapons[id].crit_chance=0
		var enemy=game.spawn_enemy(Vector3.ZERO)
		enemy.hp=1000
		enemy.set_physics_process(false)
		await frames(3)
		var before: int=game.player.magazines[0]
		var rays: int=game.player.rays_fired
		game.player.shoot()
		var data: Dictionary=game.weapon_manager.definition()
		check(is_equal_approx(1000-enemy.hp,float(data.damage)) and game.player.magazines[0]==before-1 and game.player.rays_fired==rays+1,"Actual "+id+" shot applies authored damage and spends one round")
		check(is_equal_approx(game.player.shot_timer,float(data.interval)) and is_equal_approx(game.player.recoil,float(data.recoil)) and enemy.knockback.length()>0,"Actual "+id+" firing uses distinct cadence, recoil and hit reaction")
		var model: Node3D=game.player.weapon_visual.get_child(0)
		var meshes: Array=model.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==1 and meshes[0].mesh.get_surface_count()==6,id+" loads the Blender model with six authored material surfaces")
	game.enemy_manager.clear()
	equip("magnum")
	var front=game.spawn_enemy(Vector3(0,0,1))
	var rear=game.spawn_enemy(Vector3(0,0,-1))
	front.hp=1000
	rear.hp=1000
	front.set_physics_process(false)
	rear.set_physics_process(false)
	await frames(3)
	game.player.shoot()
	check(front.hp<1000 and rear.hp<1000,"Magnum innate penetration hits two aligned infected without a Rogue perk")
	game.enemy_manager.clear()
	equip("lmg")
	game.player.magazines[0]=0
	game.player.reload()
	check(is_equal_approx(game.player.reload_duration,3.4),"LMG pays for its large magazine with the actual long reload")
	game.player.test_motion=Vector3.RIGHT
	await frames(3)
	check(is_equal_approx(game.player.velocity.x,5.8*.8),"Equipped LMG applies its actual mobility cost")
	game.player.test_motion=Vector3.ZERO
	game.player.position=Vector3(0,.05,6)
	game.player.aim_point=Vector3(0,1.1,0)
	equip("grenade_launcher")
	game.catalog.tables.weapons.grenade_launcher.crit_chance=0
	front=game.spawn_enemy(Vector3.ZERO)
	rear=game.spawn_enemy(Vector3(1.5,0,0))
	front.hp=1000
	rear.hp=1000
	front.set_physics_process(false)
	rear.set_physics_process(false)
	await frames(3)
	var rays: int=game.player.rays_fired
	game.player.shoot()
	check(game.weapon_manager.projectiles.size()==1 and game.player.rays_fired==rays and game.player.magazines[0]==5,"Grenade launcher creates a real moving projectile instead of a hitscan ray")
	await get_tree().create_timer(.7).timeout
	check(front.hp<1000 and rear.hp<1000 and game.weapon_manager.projectiles.is_empty(),"Real grenade impact damages neighboring infected and recycles its projectile")
	game.enemy_manager.clear()
	var blocked=game.spawn_enemy(Vector3(-8,0,-8))
	blocked.hp=1000
	blocked.set_physics_process(false)
	await frames(3)
	var data: Dictionary=game.weapon_manager.definition()
	data.blast_radius=10
	var grenade=game.weapon_manager.launch_grenade(Vector3(-8,1,-2),Vector3.FORWARD,data)
	grenade.explode()
	check(blocked.hp==1000,"Solid vehicle occlusion prevents grenade blast damage through cover")
	grenade=game.weapon_manager.launch_grenade(Vector3(0,5,2),Vector3.FORWARD,data)
	var vertical: float=grenade.motion.y
	await frames(4)
	check(grenade.motion.y<vertical,"Grenade flight obeys actual downward acceleration")
	game.weapon_manager.clear_projectiles()
	check(game.weapon_manager.projectiles.is_empty() and not grenade.active,"New deployment cleanup safely recycles player projectiles")
	for id in ["smg","magnum","lmg","grenade_launcher"]:
		equip(id)
		var reserve: int=game.player.reserve[0]
		game.weapon_manager.grant_supply("kill_resupply")
		check(game.player.reserve[0]>reserve,"Kill milestones resupply actual "+id+" ammunition")
		reserve=game.player.reserve[0]
		game.weapon_manager.resupply({},true)
		check(game.player.reserve[0]>reserve,"Stage transitions resupply actual "+id+" ammunition")
	for weapon in game.catalog.items("weapons"):
		game.save_manager.profile.weapons[weapon.id].level=10
		game.save_manager.profile.weapons[weapon.id].stars=5
		for trait_id in game.progression_manager.config.traits:
			game.save_manager.profile.weapons[weapon.id].trait=trait_id
			var tuned: Dictionary=game.progression_manager.apply_definition(weapon)
			check(float(tuned.permanent_power_ratio)<=1.300001,"Permanent power cap remains valid for "+weapon.id+" / "+trait_id)
	# Mesh reuse must reset a ring back to the shared box used by bullet trails.
	game.fx.clear_transients()
	game.fx.energy_ring(Vector3(0,2,0),Vector3.UP,Color.CYAN,.2,1,.2)
	check(game.fx.particles[0].node.mesh is TorusMesh,"Energy pulse acquires a ring mesh from the bounded VFX pool")
	game.fx.clear_transients()
	var reused: MeshInstance3D=game.fx.obtain_particle(Vector3.ZERO,Vector3.ONE,Color.WHITE,0)
	check(reused.mesh is BoxMesh,"Recycled energy ring resets its mesh before reuse as a bullet particle")
	game.pool_manager.release(reused)
	for effect_data in game.catalog.items("weapons"):
		game.fx.clear_transients()
		game.save_manager.profile.settings.reduced_effects=false
		game.fx.weapon_muzzle(Vector3.ZERO,Vector3.FORWARD,effect_data)
		game.fx.weapon_tracer(Vector3.ZERO,Vector3(0,0,-5),effect_data)
		game.fx.weapon_impact(Vector3(0,0,-5),Vector3.FORWARD,effect_data)
		var full_count: int=game.fx.particles.size()
		game.fx.clear_transients()
		game.save_manager.profile.settings.reduced_effects=true
		game.fx.weapon_muzzle(Vector3.ZERO,Vector3.FORWARD,effect_data)
		game.fx.weapon_tracer(Vector3.ZERO,Vector3(0,0,-5),effect_data)
		game.fx.weapon_impact(Vector3(0,0,-5),Vector3.FORWARD,effect_data)
		check(game.fx.particles.size()<full_count and full_count<30,effect_data.id+" reduced effects removes secondary pulses and sparks")
	game.fx.clear_transients()
	for i in 500: game.fx.energy_ring(Vector3.ZERO,Vector3.UP,Color.CYAN,.2,1,.2)
	check(game.fx.particles.size()==450,"New energy effects respect the shared hard cap of 450 active particles")
	game.fx.clear_transients()
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size()}
	var file:=FileAccess.open("res://artifacts/weapon-roster-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("WEAPON_ROSTER_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
