extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"director_trials")
	game.player.bot=true
	game.player.position=Vector3.ZERO
	game.director.active=false
	var director=game.director
	var baseline: Dictionary=director.assess(0).duplicate(true)
	game.player.hp=20
	var hurt: Dictionary=director.assess(0).duplicate(true)
	check(hurt.mode=="recovery" and hurt.active_cap<baseline.active_cap and hurt.interval_multiplier>baseline.interval_multiplier and hurt.elite_limit==0,"Low actual health lowers active population, slows spawning and withholds elites")
	game.player.hp=100
	game.weapon_manager.magazines.assign([0,0])
	game.weapon_manager.reserve.assign([0,0])
	var empty: Dictionary=director.assess(0).duplicate(true)
	check(empty.mode=="recovery" and empty.ammo==0,"Exhausted actual loadout ammunition activates recovery")
	game.weapon_manager.reset()
	game.perks.assign(["heavy_rounds","fire_rate","burn","lightning","death_blast","armor"])
	var built: Dictionary=director.assess(0).duplicate(true)
	check(built.build>baseline.build and built.pressure>baseline.pressure,"A real equipped Rogue build contributes to encounter pressure")
	game.perks.clear()
	director.kill_rate=3
	var fast: Dictionary=director.assess(0).duplicate(true)
	check(fast.kill_rate==3 and fast.pressure>baseline.pressure,"Fast recent kill pace increases pressure")
	director.kill_rate=0
	game.kills+=3
	director.assess(.5)
	check(director.kill_rate>0,"Runtime sampling derives kill pace from actual kill-count changes")
	director.kill_rate=0
	game.run_manager.elapsed=900
	var late: Dictionary=director.assess(0).duplicate(true)
	check(late.pressure>baseline.pressure,"Run duration gradually raises encounter pressure")
	director.last_wave_ended=game.run_manager.elapsed
	var respite: Dictionary=director.assess(0).duplicate(true)
	check(respite.pressure<late.pressure and respite.gap>=6,"A recently cleared wave creates a pressure dip and breathing gap")
	director.last_wave_ended=-1000
	game.player.hp=20
	director.assess(0)
	var safe_mix := true
	for i in 100:
		safe_mix=safe_mix and director.choose_enemy()=="normal"
	check(safe_mix,"Recovery mix withholds ranged, charger, screamer and elite threats")
	game.player.hp=100
	game.perks.assign(["heavy_rounds","fire_rate","burn"])
	director.kill_rate=3
	director.assess(0)
	var observed := {}
	for i in 500:
		observed[director.choose_enemy()]=true
	check(observed.size()>=5 and not observed.has("warden"),"Combat mix selects distinct ordinary threats without random Bosses")
	director.tuning.enemy_weights={"heavy":1}
	var one=game.spawn_enemy(Vector3(-3,.05,-5),false,false,"heavy")
	var two=game.spawn_enemy(Vector3(3,.05,-5),false,false,"heavy")
	one.set_physics_process(false)
	two.set_physics_process(false)
	check(director.choose_enemy()=="normal","Concurrent elite cap prevents additional elite selection")
	game.enemy_manager.clear()
	director.tuning.enemy_weights={"normal":55,"runner":20,"spitter":10,"screamer":5,"charger":7,"heavy":3}
	game.run_manager.elapsed=0
	game.perks.clear()
	director.kill_rate=0
	game.player.hp=20
	director.assess(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var directions := {}
	var valid := true
	for i in 50:
		var point: Vector3=director.spawn_position()
		valid=valid and point!=Vector3.INF
		if point!=Vector3.INF:
			directions[director.last_spawn_direction]=true
			valid=valid and director.offscreen(point) and game.world.walkable(point)
	check(valid and directions.size()>=2,"Director varies actual entry directions while preserving offscreen navigation")
	for i in 8:
		var enemy=game.spawn_enemy(Vector3(i-4,.05,-6))
		enemy.set_physics_process(false)
	var count: int=director.spawned
	director.active=true
	director.timer=0
	director._process(.01)
	check(director.spawned==count,"Actual spawn loop stops at its recovery population cap")
	game.enemy_manager.clear()
	director.timer=0
	director._process(.01)
	check(director.spawned==count+1 and game.enemies.size()==1,"Actual spawn loop resumes after the population drops")
	check(director.timer>.45,"Actual recovery spawn interval is longer than its authored base")
	director.active=false
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"note":"Input sensitivity uses injected run counters; spawn caps, type selection and viewport placement exercise the actual director."}
	var file:=FileAccess.open("res://artifacts/director-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("DIRECTOR_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
