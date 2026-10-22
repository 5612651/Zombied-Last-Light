extends Node
var results: Array=[]
var game: Node3D

func check(condition: bool,title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func settle() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func item(action: String) -> Dictionary:
	for button in game.hud.buttons:
		if button.action==action: return button
	return {}

func click(action: String) -> void:
	var button: Dictionary=item(action)
	if button.is_empty(): return
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.position=button.rect.get_center()*game.hud.size/Vector2(1440,900)
	event.pressed=true
	get_viewport().push_input(event,true)
	event=event.duplicate()
	event.pressed=false
	get_viewport().push_input(event,true)

func run(target: Node3D) -> void:
	game=target
	game.save_manager.profile=SaveManager.fresh_profile()
	game.state_manager.current="base"
	game.hud.base_page="lobby"
	await settle()
	var stations: Array=game.hud.buttons.filter(func(b):return str(b.action).begins_with("station:"))
	check(stations.size()==6 and not item("deploy").is_empty(),"Lobby exposes six image destinations and one primary deployment action")
	var usable := true
	for i in stations.size():
		usable=usable and Rect2(0,20,1440,860).encloses(stations[i].rect)
		for j in range(i+1,stations.size()): usable=usable and not stations[i].rect.intersects(stations[j].rect)
	check(usable,"Destination cards stay inside the viewport without overlapping")
	var motion:=InputEventMouseMotion.new()
	motion.position=item("station:armory").rect.get_center()*game.hud.size/Vector2(1440,900)
	get_viewport().push_input(motion,true)
	var hover_deadline: int=Time.get_ticks_msec()+1500
	while game.hud.hover_elapsed<.22 and Time.get_ticks_msec()<hover_deadline:
		await get_tree().process_frame
	print("HOVER_OBSERVED "+JSON.stringify({"action":game.hud.hovered_action,"elapsed":game.hud.hover_elapsed,"point":str(game.hud.pointer)}))
	check(game.hud.hovered_action=="station:armory" and game.hud.hover_elapsed>=.22,"Real viewport mouse motion opens the delayed armory tooltip")
	check(not str(item("station:armory").description).is_empty(),"The armory hover exposes an actual explanation")
	click("station:armory")
	await settle()
	check(game.hud.base_page=="armory","Real card click routes to the armory")
	check(game.hud.buttons.filter(func(b):return str(b.action).begins_with("armory:select:")).size()==6,"Armory displays all six weapon image selections")
	var supply: int=game.save_manager.profile.wallet.supply
	click("armory:select:grenade_launcher")
	await settle()
	check(game.hud.selected_weapon=="grenade_launcher" and not game.progression_manager.owned("grenade_launcher"),"A locked weapon can be previewed without unlocking it")
	check(game.save_manager.profile.wallet.supply==supply and not item("armory:unlock:grenade_launcher").is_empty(),"Preview does not spend currency and shows a separate unlock action")
	check(ResourceLoader.exists("res://assets/textures/weapons/grenade_launcher.png"),"The selected weapon image is an imported resource")
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	game.perks.assign(game.catalog.items("perks").map(func(p):return p.id))
	game.toggle_build()
	await settle()
	var entries: Array=game.hud.buttons.filter(func(b):return str(b.action).begins_with("build:"))
	check(entries.size()==30 and game.paused,"All thirty owned perks appear as image entries while combat is paused")
	click("build:fire_linger")
	await settle()
	check(game.hud.selected_perk=="fire_linger" and game.paused,"Clicking a perk changes its explanation without resuming combat")
	check(game.hud.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Passive HUD root does not intercept gameplay clicks")
	game.toggle_build()
	check(not game.paused and not game.hud.build_open,"Closing the image build screen resumes the same run")
	var failed: Array=results.filter(func(r):return not r.passed)
	var report := {"passed":results.size()-failed.size(),"failed":failed.size(),"checks":results,"scope":"Rendered viewport mouse motion/click routing, locked preview, card bounds and build state. Screenshots are separate art evidence."}
	var file:=FileAccess.open("res://artifacts/v5-visual-ui-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("VISUAL_UI_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
