extends Node

var game: Node3D
var results: Array = []

func check(condition: bool, name_: String) -> void:
	results.append({"test":name_,"passed":condition})
	print(("PASS " if condition else "FAIL ")+name_)

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func setup_trial(index: int) -> void:
	game.deploy(true,"objective_trials")
	game.stage_manager.preview(index)
	game.director.active=false
	game.player.bot=true
	game.player.bot_fire=false
	game.player.invulnerability=30
	game.enemy_manager.clear()
	await frames(3)

func run(target: Node3D) -> void:
	game=target
	await setup_trial(1)
	check(game.objective.kind=="clear" and game.objective.active,"Clear template activates through StageManager")
	game.objective.assault_cleared()
	check(not game.objective.finished and game.state=="combat","Clear cannot complete before the whole assault has spawned")
	game.director.active=true
	for i in 12:
		game.director.timer=0
		game.director._process(.01)
	check(game.director.spawned==12 and game.enemies.size()==12,"Clear template produces its authored assault")
	for enemy in game.enemies.duplicate():
		enemy.take_damage(1000,Vector3.ZERO)
	await frames(3)
	var limit := Time.get_ticks_msec()+1000
	while not game.objective.finished and Time.get_ticks_msec()<limit:
		await get_tree().process_frame
	print("CLEAR_OBSERVATION "+JSON.stringify({"finished":game.objective.finished,"state":game.state,"active":game.director.active,"remaining":game.enemies.size()}))
	check(game.objective.finished and game.state in ["area_clear","reward","upgrade","cleared"],"Clear completes after the assault is eliminated")
	await setup_trial(2)
	var survival=game.objective
	check(survival.kind=="survive" and survival.config.duration==90,"Survival content uses a real ninety-second objective")
	survival.assault_cleared()
	check(not survival.finished,"Killing an assault does not finish survival early")
	var elapsed: float=survival.elapsed
	game.paused=true
	await get_tree().create_timer(.2,true,false,true).timeout
	check(survival.elapsed==elapsed,"Pause stops the objective timer")
	game.paused=false
	survival.elapsed=0
	survival._physics_process(89.95)
	check(not survival.finished and game.state=="combat","Survival timer does not finish below its threshold")
	survival._physics_process(.1)
	check(survival.finished and game.state=="area_clear","Survival timer completes at its authored threshold")
	await setup_trial(3)
	var power=game.objective
	var unit=power.generator
	check(power.kind=="generator" and not power.activated and unit.hp==240,"Generator starts inactive with a protected health pool")
	game.player.position=Vector3(0,.05,8)
	power.interact(3,true)
	check(power.activation==0 and not power.activated,"Generator cannot be activated from outside interaction range")
	game.player.position=Vector3(0,.05,-.9)
	power.interact(1,true)
	check(power.activation>0 and not power.activated,"Activation requires holding the interaction")
	power.interact(1.1,true)
	check(power.activated and power.elapsed==0,"Completed interaction starts generator defense")
	game.player.position=Vector3(7,.05,5)
	var attacker=game.spawn_enemy(Vector3(0,.05,-1.3))
	var attack_limit := Time.get_ticks_msec()+5000
	while unit.hp>=240 and Time.get_ticks_msec()<attack_limit:
		await get_tree().physics_frame
	print("DEFENSE_OBSERVATION "+JSON.stringify({"attacks":attacker.attack_count,"position":str(attacker.position),"unit_hp":unit.hp}))
	check(attacker.attack_count>0 and unit.hp<240,"Enemy AI attacks the defended generator")
	var before: float=unit.hp
	game.player.fire_ray(unit.global_position+Vector3(0,0,4),Vector3.FORWARD,1000,0)
	check(unit.hp==before,"Player gunfire does not damage the friendly generator")
	game.enemy_manager.clear()
	power.elapsed=74.95
	power._physics_process(.1)
	check(power.finished and game.state=="area_clear","Protecting the generator for its duration completes the objective")
	await setup_trial(3)
	var failed=game.objective
	game.player.position=Vector3(0,.05,-.9)
	failed.interact(3,true)
	failed.generator.damage_by_enemy(1000)
	check(game.state=="dead" and game.run_manager.outcome=="generator_destroyed","Destroyed generator fails the mission")
	await setup_trial(4)
	var nests=game.objective
	check(nests.kind=="nests" and nests.targets.size()==3,"Purge template creates three physical targets")
	game.player.position=Vector3(0,.05,7)
	var first=nests.targets[0]
	var origin: Vector3=game.player.position+Vector3.UP*1.1
	game.player.fire_ray(origin,(first.global_position-origin).normalized(),200,0)
	await frames(2)
	check(first.destroyed and nests.destroyed_count==1,"Actual weapon ray destroys an infection nest")
	first.take_damage(1000)
	check(nests.destroyed_count==1,"Destroyed nest cannot count twice")
	game.spawn_enemy(Vector3(9,.05,8))
	for nest in nests.targets:
		if not nest.destroyed:
			game.player.fire_ray(origin,(nest.global_position-origin).normalized(),200,0)
			await frames(2)
	check(nests.finished and game.state=="area_clear","Destroying nests completes purge while hostiles remain")
	check(game.enemies.is_empty(),"Objective completion ends remaining combat safely")
	var failed_checks: Array=results.filter(func(c):return not c.passed)
	var report := {"checks":results,"passed":results.size()-failed_checks.size(),"failed":failed_checks.size(),"timing_scope":"Unit threshold checks use injected deltas; real-time campaign is verified separately."}
	var file := FileAccess.open("res://artifacts/objectives-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("OBJECTIVES_COMPLETE "+str(report.passed)+"/"+str(results.size()))
	game.shutdown(0 if failed_checks.is_empty() else 1)
