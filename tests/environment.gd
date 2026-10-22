extends Node

var game: Node3D
var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func reset_field() -> void:
	game.enemy_manager.clear()
	game.world.environment_props.clear()
	game.player.poison_time=0
	game.player.burn_time=0
	game.player.hp=100
	game.player.invulnerability=0
	game.player.position=Vector3(0,.05,7)
	await frames(3)

func run(target: Node3D) -> void:
	game=target
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	var environment=game.world.environment_props
	check(environment.props.size()>=5,"Playable district contains actual interactive environmental props")
	check(environment.definitions.size()==7,"Seven interactive prop types cover every requested category")
	await reset_field()
	var barrel=environment.spawn("barrel",Vector3(0,0,-2))
	var enemy=game.spawn_enemy(Vector3(1.5,0,-2))
	enemy.hp=1000
	enemy.set_physics_process(false)
	environment.refresh_navigation()
	await frames(3)
	check(not game.world.walkable(barrel.position),"Intact explosive prop blocks actual path navigation")
	game.player.aim_point=Vector3(0,.7,-2)
	game.player.fire_ray(game.player.muzzle.global_position,(game.player.aim_point-game.player.muzzle.global_position).normalized(),50,0)
	check(barrel.armed and not barrel.destroyed and barrel.warning.visible,"Actual weapon hit arms a visible explosive warning before detonation")
	check(enemy.hp==1000,"Explosive warning leaves time to react before damage")
	await get_tree().create_timer(1).timeout
	check(barrel.destroyed and barrel.collision_layer==0 and not barrel.visual.visible,"Timed barrel explosion removes its physical obstacle and intact visual")
	check(enemy.hp==870,"Barrel blast damages a nearby infected through the actual damage pipeline")
	check(game.world.walkable(barrel.position),"Destroyed explosive releases its navigation cell")
	var health: float=enemy.hp
	barrel.detonate()
	check(enemy.hp==health,"A detonated prop cannot apply its blast twice")
	await reset_field()
	var first=environment.spawn("barrel",Vector3(0,0,-2))
	var second=environment.spawn("barrel",Vector3(2,0,-2))
	await frames(3)
	first.take_damage(50)
	await get_tree().create_timer(.8).timeout
	check(first.destroyed and second.armed,"Environmental explosion arms a neighboring volatile prop")
	await get_tree().create_timer(.9).timeout
	check(second.destroyed,"Chain reaction observes the second prop's own warning fuse")
	for kind in ["car","fuel_pump"]:
		await reset_field()
		var prop=environment.spawn(kind,Vector3(0,0,-2))
		enemy=game.spawn_enemy(Vector3(2,0,-2))
		enemy.hp=1000
		enemy.set_physics_process(false)
		await frames(3)
		prop.take_damage(1000)
		await get_tree().create_timer(1.2).timeout
		check(prop.destroyed and enemy.hp<1000,"Actual "+kind+" destruction produces its authored blast")
	await reset_field()
	var box=environment.spawn("electric_box",Vector3(0,0,-2))
	enemy=game.spawn_enemy(Vector3(2,0,-2))
	enemy.hp=1000
	enemy.set_physics_process(false)
	await frames(3)
	box.take_damage(1000)
	await get_tree().create_timer(.9).timeout
	check(box.destroyed and enemy.hp==940 and enemy.stun_time>0,"Destroyed electric box applies real damage and stun")
	await reset_field()
	var glass=environment.spawn("glass",Vector3(0,0,-2))
	environment.refresh_navigation()
	await frames(3)
	glass.take_damage(1,Vector3.FORWARD)
	await frames(2)
	var nav_until: int=Time.get_ticks_msec()+1000
	while environment.nav_dirty and Time.get_ticks_msec()<nav_until:
		await get_tree().process_frame
	check(glass.destroyed and glass.collision_layer==0 and not glass.visual.visible and game.world.walkable(glass.position),"Broken glass clears both collision and navigation")
	for kind in ["trash_bin","barrier"]:
		await reset_field()
		var prop=environment.spawn(kind,Vector3(0,.05,-2))
		await frames(3)
		var origin: Vector3=prop.position
		prop.take_damage(20,Vector3.RIGHT,false,false,8)
		await get_tree().create_timer(.25).timeout
		check(not prop.freeze and prop.position.distance_to(origin)>.2,"Actual "+kind+" is launched by a physical impulse")
		if kind=="barrier":
			await get_tree().create_timer(3.2).timeout
			var settle_nav_until: int=Time.get_ticks_msec()+1000
			while environment.nav_dirty and Time.get_ticks_msec()<settle_nav_until:
				await get_tree().process_frame
			check(prop.freeze and not prop.obstacle.is_empty() and not game.world.walkable(Vector3(prop.obstacle.position[0],0,prop.obstacle.position[2])),"Settled physics barrier freezes and reserves its transformed navigation footprint")
	await reset_field()
	barrel=environment.spawn("barrel",Vector3(0,0,-2))
	game.player.position=Vector3(2,.05,-2)
	await frames(3)
	barrel.take_damage(1000)
	await get_tree().create_timer(.9).timeout
	check(game.player.hp<100 and game.player.burn_time>0,"Nearby environmental blast damages the player and applies real burning")
	await reset_field()
	barrel=environment.spawn("barrel",Vector3(0,0,-2))
	await frames(3)
	game.area_blast(Vector3(1,0,-2),4,100,8)
	check(barrel.armed,"Rogue area damage can trigger environmental explosives")
	var old_world: Node3D=game.world
	game.deploy(true,"prototype")
	game.director.active=false
	await frames(3)
	check(not is_instance_valid(old_world) and game.world.environment_props.props.size()>=5,"Redeployment unloads old props and rebuilds fresh interactables")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size()}
	var file:=FileAccess.open("res://artifacts/environment-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("ENVIRONMENT_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
