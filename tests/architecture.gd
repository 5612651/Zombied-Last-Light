extends Node

var results: Array = []
var fixture_prefix := "res://artifacts/save-fixture-"+str(Time.get_ticks_usec())

func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func run(game: Node3D) -> void:
	check(game.catalog.tables.size()==ContentCatalog.TABLES.size() and game.catalog.errors.is_empty(),"Content tables resolve all playable references")
	var validator := ContentCatalog.new()
	var weapons := {"schema_version":1,"items":game.catalog.items("weapons")}
	weapons.items.append(weapons.items[0].duplicate(true))
	check(not validator.validate_document("weapons",weapons),"Duplicate content IDs are rejected")
	validator.errors.clear()
	weapons.items.pop_back()
	weapons.items[0].interval=0
	check(not validator.validate_document("weapons",weapons),"Invalid weapon timing is rejected")
	validator.errors.clear()
	check(not validator.validate_document("perks",{"schema_version":1,"items":[{"id":"bad"}]}),"Missing content fields fail validation")
	var plan: Dictionary=game.catalog.definition("chapters","chapter_01")
	check(plan.stages.size()==6 and plan.target_seconds==1800 and plan.playable and game.catalog.definition("chapters","prototype").stages.size()==3,"Six-stage chapter keeps its thirty-minute target separately from the short prototype")
	var save := SaveManager.new()
	add_child(save)
	var legacy := fixture_prefix+"-legacy.json"
	write_json(legacy,{"highest_stage":2,"kills":17})
	check(save.load_profile(legacy) and save.profile.schema_version==SaveManager.VERSION and save.profile.records.highest_stage==2 and save.profile.totals.kills==17,"Legacy save migrates without losing records")
	check(save.profile.wallet.supply==0 and save.profile.weapons.ar.unlocked and save.profile.settings.has("slow_motion"),"Migration supplies progression and settings defaults")
	save.profile.wallet.supply=777
	save.profile.weapons.ar.level=4
	save.profile.weapons.ar.blueprints=19
	save.profile.research["medkit"]=2
	save.profile.records.stages["street"]={"rating":"A","time":111.0,"kills":28,"damage_taken":9,"optional_objective":true}
	save.profile.settings.camera_shake=.4
	check(save.save_profile(legacy),"Profile writes through verified temporary file")
	save.profile=SaveManager.fresh_profile()
	check(save.load_profile(legacy) and save.profile.wallet.supply==777 and save.profile.weapons.ar.level==4 and save.profile.weapons.ar.blueprints==19 and save.profile.records.stages.street.rating=="A" and is_equal_approx(save.profile.settings.camera_shake,.4),"Progression and settings survive reopening")
	save.profile.wallet.supply=888
	check(save.save_profile(legacy) and FileAccess.file_exists(legacy+".bak"),"Save rotates a recoverable previous version")
	var damaged := FileAccess.open(legacy,FileAccess.WRITE)
	damaged.store_string("{ truncated")
	damaged.close()
	check(save.load_profile(legacy) and save.last_load_status=="backup" and save.profile.wallet.supply==777,"Corrupt primary restores valid backup")
	check(save.save_profile(legacy) and save.load_profile(legacy) and save.profile.wallet.supply==777,"Recovered save commits safely")
	var future := fixture_prefix+"-future.json"
	write_json(future,{"schema_version":999,"important":"keep me"})
	var original := FileAccess.get_file_as_string(future)
	check(not save.load_profile(future) and save.write_blocked and not save.save_profile(future) and FileAccess.get_file_as_string(future)==original,"Future-version save cannot be overwritten")
	var invalid := fixture_prefix+"-invalid.json"
	write_json(invalid,{"wrong":"shape"})
	check(not save.load_profile(invalid) and not save.save_profile(invalid),"Unrecognized save is preserved")
	save.profile=SaveManager.fresh_profile()
	check(save.award_stage("run-a","street",{"supply":40,"research":2}) and not save.award_stage("run-a","street",{"supply":40,"research":2}) and save.profile.wallet.supply==40,"Reward ledger prevents duplicate grants")
	game.deploy(true)
	game.director.active=false
	game.player.bot=true
	await frames(3)
	var actor=game.spawn_enemy(Vector3(2,.05,0))
	var identity: int=actor.get_instance_id()
	actor.burn_time=2
	actor.knockback=Vector3.ONE*8
	actor.attack_timer=3
	game.enemy_manager.release(actor)
	check(not actor.visible and actor.collision_layer==0 and actor.process_mode==Node.PROCESS_MODE_DISABLED,"Pooled idle enemies disable processing and collisions")
	check(not game.pool_manager.release(actor),"Double pool release is rejected")
	var reused=game.spawn_enemy(Vector3(3,.05,0))
	check(reused.get_instance_id()==identity and reused.hp==72 and reused.burn_time==0 and reused.knockback==Vector3.ZERO and reused.attack_timer==0 and not reused.dead and reused.visible and reused.collision_layer==8,"Enemy reuse resets combat state and collisions")
	game.enemy_manager.clear()
	game.fx.clear_transients()
	game.fx.debris(Vector3.ZERO,Vector3.UP,Color.WHITE,Vector3.ONE,.01)
	var particle_id: int=game.fx.particles[0].node.get_instance_id()
	await frames(5)
	game.fx.debris(Vector3.ZERO,Vector3.UP,Color.WHITE,Vector3.ONE,.5)
	check(game.fx.particles[0].node.get_instance_id()==particle_id,"Expired VFX reuse an existing mesh instance")
	var authored_weapon: Dictionary=game.catalog.definition("weapons","ar")
	authored_weapon.id="test_authored"
	authored_weapon.magazine=7
	authored_weapon.damage=31
	authored_weapon.pellets=3
	game.catalog.tables.weapons[authored_weapon.id]=authored_weapon
	game.weapon_manager.loadout.append(authored_weapon.id)
	game.weapon_manager.reset()
	game.weapon_manager.equip(2)
	var p=game.player
	p.shot_timer=0
	p.aim_point=p.position+Vector3(0,1,-6)
	var before: int=p.rays_fired
	p.shoot()
	check(p.magazines[2]==6 and p.rays_fired-before==3 and game.weapon_manager.definition().damage==31,"New weapon data changes firing without actor edits")
	game.weapon_manager.loadout.remove_at(2)
	game.catalog.tables.weapons.erase(authored_weapon.id)
	game.weapon_manager.reset()
	var authored_perk: Dictionary=game.catalog.definition("perks","heal_kill")
	authored_perk.id="test_recovery"
	authored_perk.effects.heal_on_kill=7
	game.catalog.tables.perks[authored_perk.id]=authored_perk
	game.perks.append(authored_perk.id)
	p.hp=60
	var victim=game.spawn_enemy(Vector3(4,.05,0))
	victim.take_damage(1000,Vector3.ZERO)
	check(p.hp==67,"New Perk ID uses data-driven event effects")
	await frames(2)
	game.catalog.tables.perks.erase(authored_perk.id)
	game.perks.clear()
	var authored_enemy: Dictionary=game.catalog.definition("enemies","normal")
	authored_enemy.id="test_infected"
	authored_enemy.health=145
	authored_enemy.damage=23
	game.catalog.tables.enemies[authored_enemy.id]=authored_enemy
	var infected=game.spawn_enemy(Vector3(4,.05,1),false,false,authored_enemy.id)
	check(infected.hp==145 and infected.definition.damage==23,"Enemy variant takes health and attack tuning from data")
	game.enemy_manager.clear()
	game.catalog.tables.enemies.erase(authored_enemy.id)
	game.perks.append("pierce")
	game.stage=game.stage_manager.stage_count()
	await settle_stage(game)
	game.next_stage()
	check(game.state=="victory" and game.perks.is_empty(),"Chapter completion clears temporary build")
	var resources: int=game.save_manager.profile.wallet.supply
	game.deploy(true)
	game.director.active=false
	game.perks.append("fire_rate")
	game.player.hp=1
	game.player.invulnerability=0
	game.player.take_damage(5)
	check(game.state=="dead" and game.perks.is_empty() and game.save_manager.profile.wallet.supply==resources,"Death clears run but retains permanent resources")
	var failed: Array=results.filter(func(r):return not r.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"pool_stats":game.pool_manager.stats}
	write_json("res://artifacts/architecture-report.json",report)
	print("ARCHITECTURE_COMPLETE "+str(report.passed)+"/"+str(results.size()))
	game.shutdown(0 if failed.is_empty() else 1)

func settle_stage(game: Node3D) -> void:
	game.clear_stage()
	await frames(80)
	if game.state=="upgrade":
		game.choose_perk(game.upgrade_choices[0].id)
