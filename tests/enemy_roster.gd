extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func run(game: Node3D) -> void:
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"threat_trials")
	game.director.active=false
	game.player.bot=true
	game.player.position=Vector3.ZERO
	check(["normal","runner","heavy","spitter","screamer","charger","elite_runner","warden"].all(func(id):return game.catalog.has("enemies",id)),"Enemy roster includes all seven ordinary and elite roles plus Boss")
	var runner=game.spawn_enemy(Vector3(0,.05,-6),false,false,"runner")
	runner.ability_cooldown=0
	runner.path_timer=0
	runner.update_ability(.01,game.player,Vector3(0,0,6),6)
	check(runner.ability_state=="sprint" and runner.ability_time>0,"Runner starts a timed sprint burst")
	await frames(3)
	check(Vector2(runner.velocity.x,runner.velocity.z).length()>runner.speed*1.5,"Runner sprint increases actual movement speed")
	runner.ability_time=0
	runner.update_ability(.01,game.player,Vector3(0,0,6),6)
	check(runner.ability_state=="idle" and runner.ability_cooldown>0,"Sprint returns to baseline with a cooldown")
	game.enemy_manager.clear()
	var heavy=game.spawn_enemy(Vector3(0,.05,-5),false,false,"heavy")
	check(heavy.max_hp>200 and float(heavy.definition.knockback_resistance)<1,"Heavy role resists hits and carries substantially more health")
	game.enemy_manager.clear()
	var spitter=game.spawn_enemy(Vector3(0,.05,-6),false,false,"spitter")
	spitter.set_physics_process(false)
	spitter.ability_cooldown=0
	await frames(2)
	spitter.update_ability(.01,game.player,Vector3(0,0,6),6)
	check(spitter.ability_state=="windup" and spitter.warning.visible and game.enemy_manager.projectiles.is_empty(),"Spitter telegraphs before releasing acid")
	spitter.ability_time=0
	spitter.update_ability(.01,game.player,Vector3(0,0,6),6)
	check(game.enemy_manager.projectiles.size()==1,"Spitter releases a real pooled acid projectile")
	game.player.invulnerability=0
	game.player.hp=100
	await get_tree().create_timer(.8).timeout
	check(game.player.hp==86 and game.enemy_manager.projectiles.is_empty(),"Acid projectile travels, hits player and returns to pool")
	spitter.ability_cooldown=100
	var retreat: Vector3=spitter.update_ability(.01,game.player,Vector3(0,0,3),3)
	check(retreat.z<0,"Spitter retreats from a nearby melee threat")
	var blocked=game.enemy_manager.spit(Vector3(-8,1,-2),Vector3(-8,1,-8),20,14)
	await get_tree().create_timer(.5).timeout
	check(not blocked.active,"Solid parked vehicle blocks acid projectile travel")
	game.enemy_manager.clear()
	var screamer=game.spawn_enemy(Vector3(0,.05,-5),false,false,"screamer")
	screamer.set_physics_process(false)
	var ally=game.spawn_enemy(Vector3(2,.05,-5))
	ally.set_physics_process(false)
	screamer.rally_allies()
	check(ally.rally_time==5 and ally.rally_multiplier>1,"Screamer rallies nearby infected for a limited speed boost")
	check(game.enemies.size()==4,"Screamer summons two additional infected within population cap")
	game.enemy_manager.clear()
	var charger=game.spawn_enemy(Vector3(0,.05,-6),false,false,"charger")
	charger.set_physics_process(false)
	charger.ability_cooldown=0
	await frames(2)
	charger.update_ability(.01,game.player,Vector3(0,0,6),6)
	check(charger.ability_state=="windup" and charger.warning.visible,"Charger locks a visible telegraphed lane before moving")
	var locked: Vector3=charger.charge_direction
	charger.ability_time=0
	charger.update_ability(.01,game.player,Vector3(0,0,6),6)
	var charge: Vector3=charger.update_ability(.01,game.player,Vector3(6,0,0),6)
	check(charger.ability_state=="charge" and charge.is_equal_approx(locked*11),"Charge follows its committed lane instead of tracking the player")
	game.player.invulnerability=0
	game.player.hp=100
	charger.update_ability(.01,game.player,Vector3(0,0,1),1)
	check(game.player.hp==72 and charger.charge_hit,"Charge applies its dedicated impact damage")
	game.player.invulnerability=0
	charger.update_ability(.01,game.player,Vector3(0,0,1),1)
	check(game.player.hp==72,"One charge cannot damage the target twice")
	charger.ability_time=0
	charger.update_ability(.01,game.player,Vector3(0,0,1),1)
	check(charger.ability_state=="recovery","Charge ends in a punishable recovery period")
	charger.stun_time=1
	check(charger.update_ability(.01,game.player,Vector3(0,0,1),1)==Vector3.ZERO,"Stun suppresses special movement")
	game.enemy_manager.release(charger)
	var reused=game.spawn_enemy(Vector3(0,.05,-6),false,false,"charger")
	check(reused==charger and reused.ability_state=="idle" and not reused.charge_hit and not reused.warning.visible and reused.rally_time==0,"Pooled special enemy resets its entire ability state")
	var elite=game.spawn_enemy(Vector3(2,.05,-6),false,false,"elite_runner")
	check(elite.elite and elite.definition.behavior=="runner" and elite.max_hp==210,"Ravager combines elite resilience and the actual sprint behavior")
	game.enemy_manager.spit(Vector3(0,1,-5),Vector3(0,1,5),1,14)
	game.enemy_manager.clear()
	check(game.enemy_manager.projectiles.is_empty(),"Stage cleanup also recycles in-flight enemy projectiles")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"note":"Ability state boundaries use injected deltas; movement and projectile collisions use real physics ticks."}
	var file:=FileAccess.open("res://artifacts/enemy-roster-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("ENEMY_ROSTER_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
