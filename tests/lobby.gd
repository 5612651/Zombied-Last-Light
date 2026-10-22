extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	game.save_manager.profile=SaveManager.fresh_profile()
	var lobby=game.lobby_manager
	# process_frame resumes before nodes receive _process on the first frame.
	await get_tree().process_frame
	await get_tree().process_frame
	check(lobby.visible and not game.world.visible and not game.player.visible,"Base displays safehouse instead of the combat district")
	check(lobby.get_child(0).find_children("*","MeshInstance3D",true,false).size()>100,"Lobby uses the actual exported Blender environment")
	check(lobby.stations.size()==6,"Six spatial service stations are present")
	for id in ["briefing","armory","crates","research","records","settings"]:
		check(lobby.open_station(id) and game.hud.base_page==id,"Service station opens "+id)
	check(not lobby.open_station("invalid"),"Unknown service station is rejected")
	check(not lobby.upgrade_research(),"Insufficient research cannot upgrade salvage")
	game.save_manager.profile.wallet.research=50
	check(lobby.upgrade_research() and lobby.research_level()==1 and game.save_manager.profile.wallet.research==45,"Research spends exact cost and grants a permanent salvage level")
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	lobby.save_callback=func():return false
	check(not lobby.upgrade_research() and game.save_manager.profile==before,"Research persistence failure restores the whole transaction")
	check(not lobby.toggle_setting("master") and game.save_manager.profile==before,"Settings persistence failure restores the old value")
	lobby.save_callback=Callable()
	check(lobby.toggle_setting("master") and AudioServer.is_bus_mute(0),"Master quick setting immediately mutes output")
	check(lobby.toggle_setting("master") and not AudioServer.is_bus_mute(0),"Master quick setting restores output")
	check(lobby.toggle_setting("camera_shake") and game.save_manager.profile.settings.camera_shake==0,"Quick setting disables camera shake")
	check(lobby.toggle_setting("screen_blood") and game.save_manager.profile.settings.screen_blood==0,"Quick setting disables screen blood")
	check(lobby.toggle_setting("slow_motion") and not game.save_manager.profile.settings.slow_motion,"Quick setting disables cinematic slow motion")
	check(not lobby.toggle_setting("invalid"),"Unknown quick setting is rejected")
	lobby.upgrade_research()
	lobby.upgrade_research()
	var money: int=game.save_manager.profile.wallet.research
	check(lobby.research_level()==3 and not lobby.upgrade_research() and game.save_manager.profile.wallet.research==money,"Salvage stops at level three without spending")
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	await get_tree().process_frame
	check(not lobby.visible and game.world.visible and game.player.visible,"Deployment restores the combat district and player")
	check(not lobby.open_station("crates") and not lobby.upgrade_research(),"Base services cannot mutate progression during combat")
	var supplies: int=game.save_manager.profile.wallet.supply
	game.clear_stage()
	var until: int=Time.get_ticks_msec()+2500
	while game.state!="upgrade" and Time.get_ticks_msec()<until:
		await get_tree().process_frame
	check(game.save_manager.profile.wallet.supply==supplies+52,"Salvage research modifies the real stage settlement by thirty percent")
	game.run_manager.fail()
	check(game.run_manager.return_to_base(),"Death can return to the spatial safehouse")
	await get_tree().process_frame
	check(lobby.visible and game.hud.base_page=="lobby","Returning from death restores the station overview")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size()}
	var file:=FileAccess.open("res://artifacts/lobby-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("LOBBY_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
