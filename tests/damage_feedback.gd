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
	var feedback=game.feedback_manager
	var enemy=game.spawn_enemy(Vector3.ZERO)
	enemy.hp=10000
	enemy.set_physics_process(false)
	for expected in ["normal_hit","critical","headshot","elite_kill","multi_kill","boss_weak","explosion","elemental"]:
		check(feedback.profiles.has(expected),"Authored feedback profile exists for "+expected)
	feedback.reset()
	enemy.take_damage(1,Vector3.FORWARD)
	check(feedback.history[-1].kind=="normal_hit" and enemy.flash_timer>0 and game.hit_marker>0 and not game.fx.damage_numbers.is_empty(),"Actual normal hit routes flash, marker, damage number and impact feedback")
	enemy.take_damage(1,Vector3.FORWARD,false,true)
	check(feedback.history[-1].kind=="critical","Actual critical hit receives its own feedback classification")
	enemy.take_damage(1,Vector3.FORWARD,true,true)
	check(feedback.history[-1].kind=="headshot","Headshot takes precedence over ordinary critical classification")
	enemy.take_damage(1,Vector3.ZERO,false,false,0,"fire")
	check(feedback.history[-1].kind=="elemental","Actual burning damage routes to elemental feedback")
	enemy.take_damage(1,Vector3.ZERO,false,false,0,"electric")
	check(feedback.counts.elemental==2,"Actual electric damage shares the bounded elemental channel")
	enemy.take_damage(1,Vector3.FORWARD,false,false,1,"explosion")
	check(feedback.history[-1].kind=="explosion","Actual explosive damage routes to its explosion profile")
	var boss=game.spawn_enemy(Vector3(3,0,0),false,true)
	boss.set_physics_process(false)
	boss.take_damage(1,Vector3.ZERO,true,true)
	check(feedback.history[-1].kind=="boss_weak","Boss head weak point overrides normal headshot presentation")
	feedback.reset()
	var elite=game.spawn_enemy(Vector3(-3,0,0),true)
	elite.take_damage(10000,Vector3.FORWARD)
	check(feedback.counts.get("elite_kill",0)==1 and game.cinematic_until>Time.get_ticks_msec() and game.frozen_until>Time.get_ticks_msec(),"Real elite kill produces the standardized slow motion and hit stop")
	feedback.reset()
	for i in 3:
		var victim=game.spawn_enemy(Vector3(i,0,-3))
		victim.take_damage(1000,Vector3.FORWARD)
	check(feedback.counts.get("multi_kill",0)==1,"Three actual kills within the window trigger the multi-kill tier")
	feedback.kill_times.clear()
	var reference: Array[int]=[]
	var moment := 0
	var classifications_match := true
	var bounded := true
	for i in 2000:
		moment+=1300 if i%71==0 else (11 if i%5==0 else 1)
		reference=reference.filter(func(stamp):return moment-stamp<1200)
		reference.append(moment)
		if feedback.record_kill(moment)!=(reference.size()>=3): classifications_match=false
		if feedback.kill_times.size()>3: bounded=false
	check(classifications_match,"Bounded multi-kill window matches the full-history rule across 2000 burst and gap events")
	check(bounded,"Multi-kill storage stays at three timestamps during sustained bursts")
	feedback.kill_times.clear()
	feedback.record_kill(0)
	feedback.record_kill(1)
	check(not feedback.record_kill(1200),"Kill exactly 1200ms old is excluded from multi-kill")
	check(feedback.record_kill(1201)==false and feedback.record_kill(1202),"Recent kills rebuild the multi-kill tier after expiry")
	feedback.reset()
	for i in 100:
		feedback.route("explosion",Vector3.ZERO)
	check(feedback.counts.explosion==100 and feedback.applied.explosion==1,"Burst damage cannot spam one hundred sounds, shakes or VFX bursts")
	check(feedback.history.size()==64,"Feedback event history has a fixed memory bound")
	feedback.reset()
	feedback.route("boss_slam",Vector3.ZERO)
	var shake: float=game.shake
	feedback.route("normal_hit",Vector3.ZERO)
	check(is_equal_approx(game.shake,shake),"Lower-priority damage cannot add shake over an active Boss impact")
	check(game.frozen_until-Time.get_ticks_msec()<=40,"A feedback event cannot exceed the hit-stop ceiling")
	feedback.reset()
	game.save_manager.profile.settings.slow_motion=false
	feedback.route("elite_kill",Vector3.ZERO)
	check(game.cinematic_until==0,"Disabling cinematic slow motion is honored by the central feedback pipeline")
	check(not feedback.route("unknown",Vector3.ZERO),"Unknown feedback categories are rejected")
	game.player.invulnerability=0
	game.player.take_damage(5)
	check(feedback.counts.get("player_hurt",0)==1 and game.hurt_overlay>0,"Player damage uses the central hurt feedback channel")
	game.deploy(true,"prototype")
	game.director.active=false
	check(feedback.history.is_empty() and game.shake==0 and game.frozen_until==0,"New deployment resets transient feedback and cinematic budgets")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size()}
	var file:=FileAccess.open("res://artifacts/feedback-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("FEEDBACK_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
