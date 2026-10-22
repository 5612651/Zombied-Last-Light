extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"chapter_01")
	game.director.active=false
	game.player.bot=true
	var chapter: Dictionary=game.catalog.definition("chapters","chapter_01")
	check(chapter.playable and chapter.stages.size()==6,"Chapter 01 deploys six actual stages")
	var layouts := {}
	for i in 6:
		if i>0: game.stage_manager.preview(i+1)
		game.director.active=false
		game.player.bot=true
		var definition: Dictionary=game.stage_manager.definition()
		layouts[definition.layout]=true
		var path: PackedVector3Array=game.world.path(Vector3(0,0,7),Vector3(0,0,-13))
		check(not path.is_empty() and path[-1].distance_to(Vector3(0,0,-13))<.75,definition.id+" has a navigable deployment-to-exit route")
		check(game.objective.missions.size()>=2 and game.objective.active and game.objective.mission_index==0,definition.id+" starts its authored mission sequence")
		check(game.world.indoor==(definition.id=="underground_garage"),definition.id+" uses the correct indoor/outdoor environment")
		await get_tree().process_frame
		await get_tree().process_frame
		check(game.director.spawn_position()!=Vector3.INF,definition.id+" has at least one usable offscreen entry")
	check(layouts.size()==6,"Each chapter sector loads a distinct assembled map")
	game.stage_manager.preview(1)
	game.director.active=false
	game.player.bot=true
	game.kills=5
	game.objective.finish()
	check(game.state=="upgrade" and game.rogue_manager.context=="objective_checkpoint" and game.stage_manager.phase=="objective" and game.world.gate.collision_layer!=0,"Intermediate objective offers a build choice without opening the stage exit")
	var world_id: int=game.world.get_instance_id()
	var upgrade: String=game.upgrade_choices[0].id
	game.choose_perk(upgrade)
	check(game.state=="combat" and game.objective.mission_index==1 and game.objective.kind=="survive" and game.world.get_instance_id()==world_id and game.has_perk(upgrade),"Choosing a checkpoint upgrade starts the next objective in the same loaded map")
	check(game.director.waves==game.objective.waves() and game.director.active,"Director takes the current mission's wave data")
	game.director.active=false
	game.objective.finish()
	game.choose_perk(game.upgrade_choices[0].id)
	if not game.mutation_manager.choices.is_empty(): game.mutation_manager.skip()
	check(game.objective.mission_index==2 and game.objective.kind=="clear" and game.world.gate.collision_layer!=0,"Final mission remains inside the same sector with the exit sealed")
	game.director.active=false
	game.objective.finish()
	var until: int=Time.get_ticks_msec()+2500
	while game.state!="upgrade" and Time.get_ticks_msec()<until:
		await get_tree().process_frame
	check(game.stage_manager.phase=="upgrade" and game.objective.mission_history.size()==3 and game.save_manager.profile.records.stages.has("rain_street"),"Only the final mission settles the stage's permanent reward and record")
	var actual_before: int=game.save_manager.profile.wallet.supply
	game.objective.finish()
	check(game.save_manager.profile.wallet.supply==actual_before,"Repeated mission completion cannot duplicate permanent stage rewards")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"note":"Mission completion is invoked to test transitions; this is not evidence of the full chapter duration. Full-run verification must use real time and actual combat."}
	var file:=FileAccess.open("res://artifacts/chapter-one-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("CHAPTER_ONE_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
