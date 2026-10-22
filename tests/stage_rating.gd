extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	var definition: Dictionary=game.catalog.definition("stages","rain_street")
	var cases := [
		{"time":300,"kills":360,"damage_taken":0,"expected":"S"},
		{"time":400,"kills":360,"damage_taken":40,"expected":"A"},
		{"time":800,"kills":360,"damage_taken":100,"expected":"B"},
		{"time":1500,"kills":10,"damage_taken":200,"expected":"C"}]
	for metrics in cases:
		var result: Dictionary=StageRating.evaluate(definition,metrics)
		check(result.rating==metrics.expected and result.score>=0 and result.score<=100,"Authored time, kills and damage produce grade "+str(metrics.expected))
	for test in [
		{"id":"convenience_store","metrics":{"props_destroyed":3}},
		{"id":"apartment_court","metrics":{"generator_health_ratio":.7}},
		{"id":"evacuation","metrics":{"boss_weak_hits":10}}]:
		var metrics: Dictionary={"time":300,"kills":300,"damage_taken":0}
		metrics.merge(test.metrics)
		check(StageRating.evaluate(game.catalog.definition("stages",test.id),metrics).optional_objective,"Optional objective evaluates real metric for "+test.id)
	var save:=SaveManager.new()
	add_child(save)
	var high: Dictionary=StageRating.evaluate(definition,cases[0])
	var low: Dictionary=StageRating.evaluate(definition,cases[3])
	save.award_stage("first","rain_street",{"supply":40},high)
	save.award_stage("second","rain_street",{"supply":40},low)
	var record: Dictionary=save.profile.records.stages.rain_street
	check(record.rating=="S" and record.last.rating=="C" and record.score==100 and record.clears==2,"Permanent best grade survives a later worse clear while retaining the last result")
	check(not save.award_stage("second","rain_street",{"supply":40},low) and record.clears==2,"Repeated settlement cannot duplicate a graded clear")
	var path: String="user://rating-test-"+str(Time.get_ticks_usec())+".json"
	check(save.save_profile(path),"Grade and its metrics write to the versioned disk save")
	var reopened:=SaveManager.new()
	add_child(reopened)
	check(reopened.load_profile(path) and reopened.profile.records.stages.rain_street.rating=="S" and reopened.profile.records.stages.rain_street.optional_objective,"Reopening preserves the highest grade and optional completion")
	DirAccess.remove_absolute(path)
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"chapter_01")
	game.director.active=false
	game.player.bot=true
	var prop=game.world.environment_props.spawn("glass",Vector3(0,0,2))
	prop.take_damage(1)
	check(game.stage_manager.props_destroyed==1,"Actual environmental destruction advances the optional-objective counter once")
	prop.take_damage(1)
	check(game.stage_manager.props_destroyed==1,"Destroyed prop cannot advance optional progress twice")
	var boss=game.spawn_enemy(Vector3(3,0,0),false,false,"chapter_warden")
	boss.set_physics_process(false)
	boss.take_damage(1,Vector3.ZERO,true,true)
	check(game.stage_manager.boss_weak_hits==1,"Actual Boss weak-point damage advances its optional-objective counter")
	game.enemy_manager.clear()
	game.clear_stage()
	var until: int=Time.get_ticks_msec()+2500
	while game.state!="upgrade" and Time.get_ticks_msec()<until:
		await get_tree().process_frame
	var actual: Dictionary=game.save_manager.profile.records.stages.get("rain_street",{})
	check(not actual.is_empty() and actual.has("rating") and actual.last.has("score") and actual.last.optional_objective,"Actual stage settlement produces and permanently records a grade")
	game.run_manager.fail()
	check(game.save_manager.profile.records.stages.rain_street.rating==actual.rating,"Death preserves the settled permanent stage grade")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"note":"Grade boundaries use explicit metrics; separate checks exercise real damage/destruction and stage settlement."}
	var file:=FileAccess.open("res://artifacts/rating-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("RATING_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
