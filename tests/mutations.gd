extends Node

var game: Node3D
var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func set_upgrade() -> void:
	game.state_manager.current="upgrade"
	game.stage_manager.phase="upgrade"
	game.director.active=false

func run(target: Node3D) -> void:
	game=target
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	var mutation=game.mutation_manager
	check(game.catalog.items("mutations").size()==4,"Four authored AR and Shotgun evolution branches exist")
	game.kills=29
	game.perks.assign(["fire_rate","pierce","pellets"])
	check(mutation.available().is_empty(),"Mutation requires the actual run kill milestone")
	game.kills=40
	game.perks.assign(["fire_rate"])
	check(mutation.available().is_empty(),"Mutation requires an established temporary build")
	game.perks.assign(["armor","dash_cd"])
	check(mutation.available().is_empty(),"Unrelated build perks cannot bypass branch prerequisites")
	game.perks.assign(["fire_rate","pierce","pellets"])
	check(mutation.available().size()==4,"Matching build unlocks all applicable branches for the carried weapons")
	game.weapon_manager.loadout.assign(["smg"])
	check(mutation.available().is_empty(),"Uncarried weapons cannot evolve")
	game.weapon_manager.loadout.assign(["ar","shotgun"])
	game.weapon_manager.reset()
	check(not mutation.offer_available("stage_reward"),"Mutation offer cannot interrupt active combat")
	set_upgrade()
	check(mutation.offer_available("stage_reward") and game.world.gate.collision_layer!=0,"Mutation choice holds the real exit closed")
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	var ammo: Array=game.player.magazines.duplicate()
	check(not mutation.choose("unknown") and game.state=="upgrade","Invalid mutation cannot dismiss the choice")
	check(mutation.choose("vulcan_ar") and game.state=="cleared" and game.world.gate.collision_layer==0,"Choosing an evolution opens the gate through the stage lifecycle")
	check(game.save_manager.profile==before and game.player.magazines==ammo,"Evolution changes neither permanent weapon records nor loaded ammunition")
	var definition: Dictionary=game.weapon_manager.definition(0)
	check(definition.title=="VULCAN AR" and is_equal_approx(float(definition.interval),.115*.55),"Vulcan changes the actual weapon definition and cadence")
	check(not mutation.choose("heavy_ar") and mutation.active.ar=="vulcan_ar","A chosen branch cannot be replaced in the same run")
	game.player.position=Vector3(0,.05,-13.2)
	game.stage_manager.advance()
	var until: int=Time.get_ticks_msec()+3000
	while game.state!="combat" and Time.get_ticks_msec()<until:
		await get_tree().process_frame
	game.director.active=false
	check(game.stage==2 and mutation.active.get("ar")=="vulcan_ar" and game.weapon_manager.definition(0).title=="VULCAN AR","Evolution survives actual map unloading and continuous stage transition")
	game.player.bot=true
	game.player.position=Vector3(0,.05,6)
	game.player.aim_point=Vector3(0,1.1,0)
	game.catalog.tables.weapons.ar.crit_chance=0
	var enemy=game.spawn_enemy(Vector3.ZERO)
	enemy.hp=1000
	enemy.set_physics_process(false)
	for i in 3: await get_tree().physics_frame
	game.player.shot_timer=0
	game.player.shoot()
	check(is_equal_approx(1000-enemy.hp,24*.8) and game.player.shot_timer<.1,"Vulcan alters real bullet damage and actual firing interval")
	game.enemy_manager.clear()
	mutation.active={"ar":"heavy_ar"}
	game.player.shot_timer=0
	var front=game.spawn_enemy(Vector3(0,0,1))
	var rear=game.spawn_enemy(Vector3(0,0,-1))
	front.hp=1000
	rear.hp=1000
	front.set_physics_process(false)
	rear.set_physics_process(false)
	game.perks.clear()
	for i in 3: await get_tree().physics_frame
	game.player.shoot()
	check(is_equal_approx(1000-front.hp,24*1.65) and rear.hp<1000,"Heavy AR changes real damage and penetrates without a Pierce perk")
	game.enemy_manager.clear()
	mutation.active={"shotgun":"auto_shotgun"}
	game.player.equip_weapon(1)
	game.player.shot_timer=0
	game.player.shoot()
	check(is_equal_approx(game.player.shot_timer,.78*.48),"Auto Shotgun changes the actual firing cycle")
	game.player.magazines[1]=0
	game.player.reload_timer=0
	game.player.reload()
	check(is_equal_approx(game.player.reload_duration,1.8*.85),"Auto Shotgun changes the actual reload time")
	mutation.active={"shotgun":"breach_shotgun"}
	game.player.reload_timer=0
	game.player.shot_timer=0
	game.player.magazines[1]=8
	var victim=game.spawn_enemy(Vector3.ZERO)
	victim.hp=10000
	victim.set_physics_process(false)
	for i in 3: await get_tree().physics_frame
	var rays: int=game.player.rays_fired
	game.player.shoot()
	check(game.player.rays_fired-rays==12 and victim.knockback.length()>10,"Breach Shotgun emits twelve actual pellets and stronger impacts")
	game.run_manager.fail()
	check(mutation.active.is_empty() and mutation.choices.is_empty(),"Death clears all temporary weapon evolutions")
	game.deploy(true,"prototype")
	game.director.active=false
	game.kills=40
	game.perks.assign(["fire_rate"])
	set_upgrade()
	game.rogue_manager.context="stage_reward"
	game.rogue_manager.choices=[game.catalog.definition("perks","pierce")]
	check(game.rogue_manager.choose("pierce") and game.state=="upgrade" and not mutation.choices.is_empty() and game.world.gate.collision_layer!=0,"Actual Rogue selection hands eligible builds to evolution before opening the gate")
	check(mutation.skip() and game.state=="cleared" and mutation.active.is_empty(),"Skipping evolution resumes progression without altering the weapons")
	set_upgrade()
	check(not mutation.offer_available("stage_reward"),"An already handled stage cannot repeat its mutation offer")
	game.stage_manager.open_exit()
	mutation.active={"ar":"heavy_ar"}
	game.run_manager.complete()
	check(mutation.active.is_empty(),"Chapter completion also clears temporary evolutions")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size()}
	var file:=FileAccess.open("res://artifacts/mutation-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("MUTATION_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
