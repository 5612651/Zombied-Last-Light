extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"prototype")
	game.player.bot=true
	game.director.active=false
	var effects=game.screen_effects
	check(effects.layer<0 and effects.overlay.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Postprocess is behind the HUD and cannot intercept interface clicks")
	game.player.invulnerability=0
	game.player.take_damage(5)
	effects._process(0)
	check(float(effects.material.get_shader_parameter("blood"))>0,"Real incoming damage reaches the screen blood shader")
	game.player.hp=15
	effects._process(0)
	check(is_equal_approx(float(effects.material.get_shader_parameter("low_health")),.5),"Actual low health drives the pulsing vignette")
	game.player.apply_status("poison",2)
	effects._process(0)
	check(float(effects.material.get_shader_parameter("poison"))==1,"Poison status drives its actual color filter")
	game.player.apply_status("burn",2)
	effects._process(0)
	check(float(effects.material.get_shader_parameter("heat"))==1,"Burn status drives actual heat distortion")
	game.player.hp=100
	game.player.invulnerability=0
	await get_tree().create_timer(.7).timeout
	check(game.player.hp<100,"Poison and burn are real timed status effects rather than preview-only filters")
	game.feedback_manager.route("detonation",game.player.position)
	effects._process(0)
	check(effects.dust>0 and effects.shock_time>0 and float(effects.material.get_shader_parameter("shock_active"))==1,"Actual explosion feedback creates dust and a screen-space shockwave")
	game.feedback_manager.route("boss_slam",game.player.position)
	effects._process(0)
	check(float(effects.material.get_shader_parameter("boss_impact"))==1,"Actual Boss impact receives its screen-level presentation")
	var dust: float=effects.dust
	effects._process(.3)
	check(effects.dust<dust and effects.boss_impact<1,"Screen effects decay instead of accumulating permanently")
	game.state="base"
	check(game.lobby_manager.toggle_setting("reduced_effects") and effects.strength()==.2,"Safehouse reduced-effects option lowers the entire screen pipeline to twenty percent")
	game.state_manager.current="combat"
	game.save_manager.profile.settings.screen_blood=0
	effects._process(0)
	check(float(effects.material.get_shader_parameter("blood"))==0,"Screen blood can be disabled independently")
	game.state="base"
	effects._process(0)
	check(float(effects.material.get_shader_parameter("strength"))==0,"Base view bypasses all combat screen effects")
	game.deploy(true,"prototype")
	game.director.active=false
	check(effects.dust==0 and effects.shock_time==0 and effects.boss_impact==0 and game.player.poison_time==0 and game.player.burn_time==0,"New deployment clears screen transients and player statuses")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"note":"Shader parameters and actual status damage are tested here; Vulkan screenshots verify rendering separately."}
	var file:=FileAccess.open("res://artifacts/screen-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("SCREEN_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
