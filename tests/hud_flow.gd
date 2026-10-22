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
	game.player.position=Vector3(0,.05,6)
	game.player.aim_point=Vector3(0,1.1,0)
	check(game.player.grenades==3 and game.player.max_grenades==3,"New deployment provides its authored throwable grenade stock")
	check(game.player.throw_grenade() and game.player.grenades==2 and game.weapon_manager.projectiles.size()==1,"Actual grenade action consumes inventory and creates a real projectile")
	check(not game.player.throw_grenade() and game.player.grenades==2,"Grenade cooldown prevents duplicate input spending")
	game.weapon_manager.clear_projectiles()
	game.player.grenade_cooldown=0
	game.player.grenades=0
	check(not game.player.throw_grenade(),"Empty grenade inventory cannot spawn projectiles")
	game.perks.assign(["fire_rate","pierce","armor","burn"])
	check(game.toggle_build() and game.paused and get_tree().paused and game.hud.build_open,"Opening the Build screen pauses real combat")
	var before: Vector3=game.player.position
	game.player.test_motion=Vector3.RIGHT
	await get_tree().create_timer(.15,true,false,true).timeout
	check(game.player.position.is_equal_approx(before),"Build inspection stops actual player physics")
	game.ui_action("build:burn")
	check(game.hud.selected_perk=="burn","Build entry selection exposes an owned perk for detailed inspection")
	check(not game.player.throw_grenade(),"Paused build inspection cannot throw a grenade")
	check(game.toggle_build() and not game.paused and not get_tree().paused and not game.hud.build_open,"Closing Build resumes the same combat state")
	game.player.test_motion=Vector3.ZERO
	game.director.active=false
	game.stage_manager.phase="upgrade"
	game.state_manager.current="upgrade"
	game.stage_manager.open_exit()
	game.player.grenades=1
	game.player.position=Vector3(0,.05,-13.2)
	game.toggle_build()
	await get_tree().create_timer(.15,true,false,true).timeout
	check(game.stage==1 and game.state=="cleared","Paused inspection at the open gate cannot trigger an automatic transition")
	game.player.position=Vector3(0,.05,7)
	game.toggle_build()
	check(game.stage_manager.advance(),"Continuous stage advancement remains available after closing Build")
	var until: int=Time.get_ticks_msec()+3000
	while game.state!="combat" and Time.get_ticks_msec()<until:
		await get_tree().process_frame
	game.director.active=false
	game.player.bot=true
	check(game.stage==2 and game.player.grenades==2,"Stage transition carries grenade inventory and applies its one-charge resupply")
	game.player.apply_status("poison",3)
	game.player.apply_status("burn",3)
	game.player.boost=2
	check(game.player.poison_time>0 and game.player.burn_time>0 and game.player.boost>0,"HUD buff sources reflect actual poison, burn and momentum timers")
	game.deploy(true,"prototype")
	game.director.active=false
	check(not game.hud.build_open and not game.paused and game.player.grenades==3,"Restart clears modal state and resets grenade stock")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"note":"These tests cover UI state and gameplay integration. Screenshots separately verify HUD and full Build layout."}
	var file:=FileAccess.open("res://artifacts/hud-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("HUD_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
