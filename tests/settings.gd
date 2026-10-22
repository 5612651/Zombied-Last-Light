extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	game.save_manager.profile=SaveManager.fresh_profile()
	var manager=game.settings_manager
	var persist:=func():return game.save_manager.save_profile("user://settings-test.json")
	manager.save_callback=persist
	check(game.settings_panel.widgets.size()==13,"Settings panel exposes all display, audio, feedback and aiming controls")
	check(manager.set_value("fps_limit",60) and Engine.max_fps==60,"FPS limit changes the actual engine cap")
	check(manager.set_value("resolution",[1600,900]),"Supported window resolution is accepted")
	if DisplayServer.get_name()!="headless":
		await get_tree().process_frame
		check(DisplayServer.window_get_size()==Vector2i(1600,900),"Resolution changes the native window size")
		check(manager.set_value("fullscreen",true) and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN,"Fullscreen changes the native window mode")
		manager.set_value("fullscreen",false)
		check(manager.set_value("vsync",false) and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED,"VSync toggles the native presentation mode")
	check(not manager.set_value("resolution",[2,4]) and not manager.set_value("fps_limit",-1),"Unsupported display settings are rejected")
	check(not manager.set_value("master",NAN) and not manager.set_value("fullscreen",1),"Non-finite gain and wrong toggle types are rejected")
	check(manager.set_value("master",.4) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)),.4),"Master slider changes the actual mixer gain")
	manager.set_value("music",.3)
	manager.set_value("sfx",.2)
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))),.3) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))),.2),"Music and effects sliders independently affect their buses")
	manager.set_value("slow_motion_strength",0)
	check(manager.slow_scale()==1,"Zero slow-motion strength preserves normal simulation speed")
	manager.set_value("slow_motion_strength",.5)
	check(is_equal_approx(manager.slow_scale(),.625),"Slow-motion intensity interpolates the actual simulation scale")
	manager.set_value("slow_motion",false)
	check(manager.slow_scale()==1,"Slow-motion toggle bypasses cinematic time scaling")
	manager.set_value("aim_sensitivity",2)
	game.player.aim_cursor=Vector2(100,100)
	game.player.move_aim_cursor(Vector2(15,10))
	check(game.player.aim_cursor==Vector2(130,120),"Aim sensitivity scales the virtual reticle displacement")
	game.player.move_aim_cursor(Vector2(-10000,-10000))
	check(game.player.aim_cursor==Vector2.ZERO,"Reticle is clamped to the visible viewport")
	var before: Dictionary=game.save_manager.profile.settings.duplicate(true)
	manager.save_callback=func():return false
	check(not manager.set_value("master",.9) and game.save_manager.profile.settings==before,"Failed persistence restores the entire previous settings state")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)),.4),"Failed settings save leaves the live mixer unchanged")
	manager.save_callback=persist
	manager.set_value("camera_shake",.3)
	manager.set_value("screen_blood",.2)
	manager.set_value("reduced_effects",true)
	var reloaded:=SaveManager.new()
	check(reloaded.load_profile("user://settings-test.json") and is_equal_approx(float(reloaded.profile.settings.camera_shake),.3) and reloaded.profile.settings.reduced_effects,"Display, feedback, audio and aim settings survive a real disk reload")
	reloaded.free()
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	game.player.bot=false
	game.player.aim_cursor=Vector2(200,200)
	var motion:=InputEventMouseMotion.new()
	motion.relative=Vector2(10,5)
	game._input(motion)
	check(game.player.aim_cursor==Vector2(220,210),"Actual combat input route moves the reticle with the saved sensitivity")
	game.player.bot=true
	check(game.toggle_settings() and game.settings_panel.visible and game.paused and get_tree().paused,"Opening combat settings pauses the same run")
	var position_before: Vector3=game.player.position
	game.player.test_motion=Vector3.RIGHT
	await get_tree().create_timer(.15,true,false,true).timeout
	check(game.player.position==position_before and not game.toggle_build(),"Settings pause stops player motion and prevents conflicting Build modals")
	check(game.toggle_settings() and not game.paused and not game.settings_panel.visible,"Closing settings resumes combat")
	game.player.test_motion=Vector3.ZERO
	game.run_manager.fail()
	game.run_manager.return_to_base()
	check(game.lobby_manager.open_station("settings") and game.settings_panel.visible,"Spatial safehouse service opens the full settings panel")
	game.toggle_settings()
	# Leave a conventional window and mixer after this isolated test profile.
	game.save_manager.profile.settings=SaveManager.fresh_profile().settings
	manager.apply_settings()
	var failed: Array=results.filter(func(item):return not item.passed)
	var report: Dictionary={"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"display_server":DisplayServer.get_name(),"scope":"Native controls and actual engine/mixer effects. Manual aiming feel remains part of external playtesting."}
	var file:=FileAccess.open("res://artifacts/settings-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("SETTINGS_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
