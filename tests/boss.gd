extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	game.player.position=Vector3(0,.05,4)
	game.world.environment_props.clear()
	var boss=game.spawn_enemy(Vector3(0,.05,-3),false,false,"chapter_warden")
	boss.set_physics_process(false)
	var brain=boss.boss_brain
	for i in 3: await get_tree().physics_frame
	check(boss.boss and boss.scale.y>2 and brain!=null,"Chapter Boss uses a distinct large body and reusable Boss controller")
	check(brain.update(.01,game.player,Vector3(0,0,7),7)==Vector3.INF,"Idle Boss follows ordinary obstacle-aware movement")
	brain.begin_attack("charge",game.player)
	check(brain.state=="windup" and brain.warning.visible and brain.timer>=1,"Charge provides a visible committed-lane warning before movement")
	var locked: Vector3=brain.charge_direction
	brain.timer=0
	brain.update(.01,game.player,Vector3(0,0,7),7)
	var movement: Vector3=brain.update(.01,game.player,Vector3(7,0,0),7)
	check(brain.state=="charge" and movement.is_equal_approx(locked*9),"Boss charge follows its locked lane rather than homing")
	game.player.invulnerability=0
	game.player.hp=100
	brain.update(.01,game.player,Vector3(0,0,1),1)
	check(game.player.hp==74 and brain.charge_hit,"Boss charge applies real impact damage")
	game.player.invulnerability=0
	brain.update(.01,game.player,Vector3(0,0,1),1)
	check(game.player.hp==74,"A single charge can only hit its victim once")
	brain.timer=0
	brain.update(.01,game.player,Vector3(0,0,7),7)
	check(brain.state=="recovery" and brain.timer>=1,"Charge ends in a punishable recovery period")
	brain.reset()
	game.player.position=Vector3(1,.05,-3)
	brain.begin_attack("slam",game.player)
	check(brain.warning.visible and brain.warning.mesh is CylinderMesh,"Slam warns with an actual circular ground telegraph")
	game.player.invulnerability=0
	game.player.hp=100
	brain.timer=0
	brain.update(.01,game.player,Vector3.RIGHT,1)
	check(game.player.hp==76 and brain.state=="recovery","Telegraphed slam applies its actual radius damage and recovery")
	brain.reset()
	game.player.position=Vector3(0,.05,4)
	brain.begin_attack("aoe",game.player)
	var center: Vector3=brain.locked_point
	game.player.position=Vector3(8,.05,4)
	game.player.invulnerability=0
	game.player.hp=100
	brain.timer=0
	brain.update(.01,game.player,Vector3(8,0,7),10)
	check(center.distance_to(brain.locked_point)<.01 and game.player.hp==100,"Moving out of the targeted AOE before impact avoids its damage")
	brain.reset()
	game.player.position=Vector3(4,.05,4)
	brain.begin_attack("aoe",game.player)
	game.player.invulnerability=0
	brain.timer=0
	brain.update(.01,game.player,Vector3(8,0,7),10)
	print("BOSS_AOE_OBSERVATION "+JSON.stringify({"health":game.player.hp,"target":str(game.player.position),"center":str(brain.locked_point),"invulnerability":game.player.invulnerability,"state":brain.state,"walkable":game.world.walkable(game.player.position)}))
	check(game.player.hp==82,"Remaining inside targeted AOE receives its authored damage")
	game.player.position=Vector3.ZERO
	await get_tree().process_frame
	await get_tree().process_frame
	brain.reset()
	brain.begin_attack("summon",game.player)
	brain.timer=0
	var before: int=game.enemies.size()
	brain.update(.01,game.player,Vector3(0,0,3),3)
	check(game.enemies.size()==before+6 and int(brain.counts.get("summon",0))==1,"Summon attack creates six real offscreen reinforcements")
	var reinforcements_safe := true
	for enemy in game.enemies:
		if enemy!=boss: reinforcements_safe=reinforcements_safe and game.director.offscreen(enemy.position)
	check(reinforcements_safe,"Boss reinforcements respect actual offscreen placement")
	brain.reset()
	boss.hp=boss.max_hp*.39
	brain.update(.01,game.player,Vector3(0,0,3),3)
	check(brain.enraged and brain.damage_multiplier()>1 and brain.counts.get("enrage",0)==1,"Low Boss health triggers an actual enrage phase")
	brain.update(.01,game.player,Vector3(0,0,3),3)
	check(brain.counts.enrage==1,"Enrage cannot retrigger every frame")
	brain.begin_attack("aoe",game.player)
	var dodge: Vector3=game.player.autopilot(.01)
	check(dodge.length()>0 and game.player.dash_cooldown>0,"Automated playtest can respond to the same visible warning available to a player")
	game.enemy_manager.release(boss)
	var reused=game.spawn_enemy(Vector3(0,.05,-3),false,false,"chapter_warden")
	check(reused==boss and not reused.boss_brain.enraged and reused.boss_brain.state=="idle" and not reused.boss_brain.warning.visible,"Pooled Boss fully resets its attacks, warning and enrage")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"note":"Ability boundaries use explicit timer advancement; spawned reinforcements, damage, telegraphs and pooling use the actual engine nodes."}
	var file:=FileAccess.open("res://artifacts/boss-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("BOSS_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
