extends Node3D

const FXScript = preload("res://scripts/effects.gd")
const SoundScript = preload("res://scripts/sound.gd")
const DirectorScript = preload("res://scripts/director.gd")
const HUDScript = preload("res://scripts/hud.gd")

var catalog = preload("res://scripts/managers/content_catalog.gd").new()
var state_manager = preload("res://scripts/managers/game_state_manager.gd").new()
var save_manager = preload("res://scripts/managers/save_manager.gd").new()
var pool_manager = preload("res://scripts/managers/pool_manager.gd").new()
var weapon_manager = preload("res://scripts/managers/weapon_manager.gd").new()
var enemy_manager = preload("res://scripts/managers/enemy_manager.gd").new()
var stage_manager = preload("res://scripts/managers/stage_manager.gd").new()
var run_manager = preload("res://scripts/managers/run_manager.gd").new()
var rogue_manager = preload("res://scripts/managers/rogue_upgrade_manager.gd").new()
var progression_manager = preload("res://scripts/managers/weapon_progression_manager.gd").new()
var crate_manager = preload("res://scripts/managers/supply_crate_manager.gd").new()
var lobby_manager = preload("res://scripts/managers/lobby_manager.gd").new()
var mutation_manager = preload("res://scripts/managers/mutation_manager.gd").new()
var feedback_manager = preload("res://scripts/managers/damage_feedback_manager.gd").new()
var screen_effects = preload("res://scripts/managers/screen_effect_manager.gd").new()
var settings_manager = preload("res://scripts/managers/settings_manager.gd").new()
var settings_panel: PanelContainer
var manage_pointer := false
var combat_profiler=preload("res://scripts/diagnostics/combat_profiler.gd").new()

# Compatibility properties keep actors, HUD and existing playtests stable while
# lifecycle and state ownership live in their managers.
var PERKS: Array:
	get: return catalog.items("perks")
var state: String:
	get: return state_manager.current
	set(value): state_manager.transition_to(value)
var stage: int:
	get: return stage_manager.number
	set(value): stage_manager.number=maxi(1,value)
var kills: int:
	get: return run_manager.kills
	set(value): run_manager.kills=value
var lifetime_kills: int:
	get: return int(save_manager.profile.totals.kills)
	set(value): save_manager.profile.totals.kills=maxi(0,value)
var highest_stage: int:
	get: return int(save_manager.profile.records.highest_stage)
	set(value): save_manager.profile.records.highest_stage=maxi(1,value)
var perks: Array[String]:
	get: return rogue_manager.active
	set(value): rogue_manager.active.assign(value)
var upgrade_choices: Array:
	get: return rogue_manager.choices
var enemies: Array:
	get: return enemy_manager.active
var paused: bool:
	get: return state_manager.paused
	set(value): state_manager.set_paused(value)
var transitions: int:
	get: return stage_manager.transitions

var world: Node3D
var player: CharacterBody3D
var objective: Node3D
var fx: Node3D
var sound: Node
var director: Node
var hud: Control
var camera: Camera3D
var announcement := ""
var announcement_time := 0.0
var hit_marker := 0.0
var hit_critical := false
var hurt_overlay := 0.0
var shake := 0.0
var shot_kick := Vector3.ZERO
var feedback_noise := FastNoiseLite.new()
var cinematic_until := 0
var frozen_until := 0
var clock := 0.0
var capture_mode := false
var autoplay := false
var camera_anchor := Vector3.ZERO
var next_audit_time := 0.0
var closing := false
var wall_started_ms := 0

func _ready() -> void:
	feedback_noise.frequency=.7
	wall_started_ms=Time.get_ticks_msec()
	process_mode=Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit=false
	randomize()
	if not initialize_managers():
		closing=true
		push_error("Content validation failed: "+str(catalog.errors))
		get_tree().quit(2)
		return
	load_progress()
	pool_manager.register_persistent_parent(self)
	settings_manager.game=self
	add_child(settings_manager)
	manage_pointer=not is_test_session()
	sound=SoundScript.new()
	sound.game=self
	sound.process_mode=Node.PROCESS_MODE_ALWAYS
	add_child(sound)
	fx=FXScript.new()
	fx.process_mode=Node.PROCESS_MODE_PAUSABLE
	fx.game=self
	add_child(fx)
	pool_manager.register_persistent_parent(fx)
	director=DirectorScript.new()
	director.process_mode=Node.PROCESS_MODE_PAUSABLE
	director.game=self
	add_child(director)
	build_stage()
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=19.5
	camera.far=120
	camera.position=Vector3(22,29,27)
	add_child(camera)
	camera.look_at(Vector3(0,0,-1))
	camera.current=true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud=HUDScript.new()
	hud.game=self
	canvas.add_child(hud)
	lobby_manager.game=self
	add_child(lobby_manager)
	screen_effects.game=self
	screen_effects.process_mode=Node.PROCESS_MODE_PAUSABLE
	add_child(screen_effects)
	lobby_manager.apply_settings()
	settings_panel=preload("res://scripts/settings_panel.gd").new()
	settings_panel.game=self
	hud.add_child(settings_panel)
	var args := OS.get_cmdline_user_args()
	capture_mode = "--capture" in args
	autoplay = "--autoplay" in args
	if "--weapon-lab" in args:
		# Separate launch mode uses the existing isolated test save path.
		save_manager.profile=SaveManager.fresh_profile()
		var ids: Array=catalog.items("weapons").map(func(item):return item.id)
		for id in ids: save_manager.profile.weapons[id].unlocked=true
		weapon_manager.loadout.assign(ids)
		deploy(true,"chapter_01")
		manage_pointer=true
		announcement="六枪试射 / 按Q切换武器"
		announcement_time=8
	if capture_mode or autoplay:
		if autoplay and "--fresh-run" in args:
			save_manager.profile=SaveManager.fresh_profile()
			weapon_manager.configure_owned_loadout()
			weapon_manager.reset()
		var requested_chapter := "prototype"
		for argument in args:
			if argument.begins_with("--chapter="):
				requested_chapter=argument.trim_prefix("--chapter=")
		deploy(capture_mode,requested_chapter)
		player.bot=true
		player.bot_fire=autoplay
		if capture_mode:
			for argument in args:
				if argument.begins_with("--sector="):
					stage_manager.preview(argument.trim_prefix("--sector=").to_int())
			for argument in args:
				if argument.begins_with("--layout="):
					var id: String=argument.trim_prefix("--layout=")
					if ResourceLoader.exists("res://assets/models/"+id+".glb") and FileAccess.file_exists("res://assets/"+id+"_layout.json"):
						catalog.tables.stages[stage_manager.definition().id].layout=id
						stage_manager.preview(stage)
			for argument in args:
				if argument.begins_with("--weapon="):
					var id: String=argument.trim_prefix("--weapon=")
					if catalog.has("weapons",id):
						weapon_manager.loadout.assign([id])
						weapon_manager.reset()
						player.rebuild_weapon_visual()
			if "--commercial" in args:
				stage_manager.preview(2)
			if "--arena" in args:
				stage_manager.preview(3)
			for argument in args:
				if argument.begins_with("--objective="):
					var modes := ["clear","survive","generator","nests"]
					var index: int=modes.find(argument.trim_prefix("--objective="))
					if index>=0:
						stage_manager.chapter_id="objective_trials"
						stage_manager.preview(index+1)
			director.active=false
			player.bot=true
			for i in 10:
				if stage_manager.is_boss_stage() and i==9:
					spawn_enemy(Vector3(2,.05,-5),false,true)
				else:
					spawn_enemy(Vector3(randf_range(-6,5),0,randf_range(-9,-2)),i==9)
			player.aim_point=Vector3(0,1.2,-5)
			if "--base" in args:
				state="base"
				if "--armory" in args:
					hud.base_page="armory"
				if "--crates" in args:
					hud.base_page="crates"
				if "--settings" in args:
					hud.base_page="settings"
					toggle_settings()
			if "--upgrades" in args:
				present_upgrades()
			if "--mutations" in args:
				perks.assign(["fire_rate","pierce","pellets"])
				kills=40
				state="upgrade"
				mutation_manager.offer_available("field")
			if "--action" in args:
				player.bot_fire=true
				player.invulnerability=10
			if "--screen-effects" in args:
				save_manager.profile.settings.reduced_effects="--reduced-effects" in args
				get_tree().create_timer(2.7).timeout.connect(preview_screen_effects)
			if "--build" in args:
				perks.assign(catalog.items("perks").map(func(item):return item.id))
				toggle_build()
			if "--hover-ui" in args:
				get_tree().create_timer(2.45,true,false,true).timeout.connect(preview_ui_hover)
			get_tree().create_timer(3).timeout.connect(capture)
	if "--smoke" in args:
		call_deferred("run_smoke")
	if "--benchmark" in args:
		call_deferred("run_benchmark")
	if "--architecture" in args:
		call_deferred("run_architecture_tests")
	if "--flow" in args:
		call_deferred("run_flow_tests")
	if "--objectives" in args:
		call_deferred("run_objective_tests")
	if "--perks" in args:
		call_deferred("run_perk_tests")
	if "--progression" in args:
		call_deferred("run_progression_tests")
	if "--crate-tests" in args:
		call_deferred("run_crate_tests")
	if "--lobby-tests" in args:
		call_deferred("run_lobby_tests")
	if "--save-tests" in args:
		call_deferred("run_save_tests")
	if "--enemy-tests" in args:
		call_deferred("run_enemy_tests")
	if "--crowd-tests" in args:
		call_deferred("run_crowd_tests")
	if "--director-tests" in args:
		call_deferred("run_director_tests")
	if "--weapon-tests" in args:
		call_deferred("run_weapon_tests")
	if "--mutation-tests" in args:
		call_deferred("run_mutation_tests")
	if "--feedback-tests" in args:
		call_deferred("run_feedback_tests")
	if "--screen-tests" in args:
		call_deferred("run_screen_tests")
	if "--environment-tests" in args:
		call_deferred("run_environment_tests")
	if "--library-tests" in args:
		call_deferred("run_library_tests")
	if "--chapter-tests" in args:
		call_deferred("run_chapter_tests")
	if "--rating-tests" in args:
		call_deferred("run_rating_tests")
	if "--boss-tests" in args:
		call_deferred("run_boss_tests")
	if "--hud-tests" in args:
		call_deferred("run_hud_tests")
	if "--audio-tests" in args:
		call_deferred("run_audio_tests")
	if "--performance-tests" in args:
		call_deferred("run_performance_tests")
	if "--horde-benchmark" in args:
		call_deferred("run_horde_benchmark")
	if "--settings-tests" in args:
		call_deferred("run_settings_tests")
	if "--ui-visual-tests" in args:
		call_deferred("run_ui_visual_tests")

func build_stage() -> void:
	stage_manager.build()

func deploy(instant: bool=false, chapter_id: String="") -> void:
	if not chapter_id.is_empty():
		var chapter: Dictionary=catalog.definition("chapters",chapter_id)
		if chapter.is_empty() or not chapter.playable:
			return
		stage_manager.chapter_id=chapter_id
	run_manager.deploy(instant)

func _process(delta: float) -> void:
	if closing:
		return
	var now := Time.get_ticks_msec()
	if paused or state=="upgrade":
		Engine.time_scale=1
	else:
		Engine.time_scale=.03 if now<frozen_until else (settings_manager.slow_scale() if now<cinematic_until else 1.0)
	if manage_pointer:
		var pointer_mode: int=Input.MOUSE_MODE_CAPTURED if state in ["combat","cleared"] and not paused else Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode!=pointer_mode: Input.mouse_mode=pointer_mode
	clock+=delta
	if autoplay and clock>next_audit_time:
		next_audit_time=clock+5
		var data := {"state":state,"stage":stage,"kills":kills,"health":player.hp,"position":str(player.position),"enemies":enemies.size(),"enemy_sample":enemies.slice(0,3).map(func(e):return {"position":str(e.position),"hp":e.hp}),"wave":director.wave,"spawned":director.spawned,"budget":director.budget,"ammo":player.magazines,"reserve":player.reserve,"objective":objective.kind,"objective_elapsed":objective.elapsed,"activated":objective.activated,"unit_health":objective.generator.hp if is_instance_valid(objective.generator) else 0}
		data.director=director.assessment.duplicate(true)
		data.special_spawns=director.mix_spawns
		data.objective_part=objective.mission_index+1
		data.loadout=weapon_manager.loadout.duplicate()
		data.perks=perks.duplicate()
		data.mutations=mutation_manager.active.duplicate(true)
		print("RUN_AUDIT "+JSON.stringify(data))
	announcement_time=maxf(0,announcement_time-delta)
	hit_marker=maxf(0,hit_marker-delta)
	hurt_overlay=maxf(0,hurt_overlay-delta*1.3)
	shake=move_toward(shake,0,delta*.9)
	if is_instance_valid(camera) and is_instance_valid(player):
		var target: Vector3=Vector3(player.position.x*.32,0,player.position.z*.28-1)
		camera_anchor=camera_anchor.lerp(target,1-exp(-delta*3))
		var intensity: float=float(save_manager.profile.settings.camera_shake)*(.25 if save_manager.profile.settings.get("reduced_effects",false) else 1)
		var noise_offset := Vector3(feedback_noise.get_noise_2d(now*.055,0),feedback_noise.get_noise_2d(0,now*.055),0)*shake*2.0
		camera.position=camera_anchor+Vector3(22,29,27)+(noise_offset+shot_kick)*intensity
		shot_kick=shot_kick.lerp(Vector3.ZERO,1-exp(-delta*20))
	if state=="cleared" and not paused and player.position.z < -12.9:
		next_stage()
	if autoplay and state=="upgrade":
		if not mutation_manager.choices.is_empty():
			mutation_manager.choose(mutation_manager.choices[0].id)
		elif not upgrade_choices.is_empty():
			choose_perk(upgrade_choices[0].id)
	if autoplay and state in ["victory","dead"]:
		print("FULL_RUN "+JSON.stringify({"result":state,"kills":kills,"stage":stage,"elapsed":clock,"wall_seconds":(Time.get_ticks_msec()-wall_started_ms)/1000.0,"transitions":transitions}))
		shutdown(0 if state=="victory" else 1)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and state in ["combat","cleared"] and not paused and is_instance_valid(player) and not player.bot:
		player.move_aim_cursor(event.relative)
	if settings_panel!=null and settings_panel.visible and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		toggle_settings()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if settings_panel!=null and settings_panel.visible: return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point: Vector2=player.aim_cursor if manage_pointer and state in ["combat","cleared"] and not paused else event.position
		if hud.click(point):
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_TAB and state in ["combat","cleared"]:
			toggle_build()
			return
		if event.keycode==KEY_ESCAPE and hud.build_open:
			toggle_build()
			return
		if event.keycode==KEY_ENTER and state in ["base","dead","victory"]:
			if state=="base":
				deploy(false,"chapter_01")
			else:
				run_manager.return_to_base()
		elif event.keycode==KEY_T and state=="base":
			deploy(false,"objective_trials")
		elif event.keycode==KEY_B and state=="base":
			hud.base_page="briefing" if hud.base_page=="armory" else "armory"
		elif event.keycode==KEY_ESCAPE and state=="base":
			hud.base_page="lobby"
		elif event.keycode==KEY_ESCAPE and state in ["combat","cleared"]:
			toggle_settings()
		elif state=="upgrade" and event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:
			var index: int=event.keycode-KEY_1
			if not mutation_manager.choices.is_empty() and index<mutation_manager.choices.size():
				mutation_manager.choose(mutation_manager.choices[index].id)
			elif index<upgrade_choices.size():
				choose_perk(upgrade_choices[index].id)
		elif state in ["combat","cleared"] and not paused:
			if event.keycode==KEY_Q:
				player.switch_weapon()
			elif event.keycode==KEY_R:
				player.reload()
			elif event.keycode==KEY_SPACE:
				player.dash()
			elif event.keycode==KEY_G:
				player.throw_grenade()
			elif event.keycode==KEY_F12:
				capture()

func toggle_build() -> bool:
	if settings_panel!=null and settings_panel.visible: return false
	if state not in ["combat","cleared"]:
		return false
	hud.build_open=not hud.build_open
	paused=hud.build_open
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_HIDDEN
	return true

func toggle_settings() -> bool:
	if state not in ["base","combat","cleared"] or hud.build_open: return false
	settings_panel.visible=not settings_panel.visible
	if settings_panel.visible: settings_panel.sync_values()
	if state in ["combat","cleared"]: paused=settings_panel.visible
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if settings_panel.visible else Input.MOUSE_MODE_HIDDEN
	return true

func ui_action(action: String) -> void:
	if action=="toggle_build":
		toggle_build()
		return
	if action.begins_with("build:") and hud.build_open:
		hud.selected_perk=action.trim_prefix("build:")
		return
	if action.begins_with("mutation:"):
		mutation_manager.choose(action.trim_prefix("mutation:"))
		return
	if action=="mutation_skip":
		mutation_manager.skip()
		return
	if action=="deploy":
		deploy(false,"chapter_01")
	elif action=="prototype":
		deploy(false,"prototype")
	elif action=="trials":
		deploy(false,"objective_trials")
	elif action=="threats":
		deploy(false,"threat_trials")
	elif action=="pressure":
		deploy(false,"director_trials")
	elif action=="armory" and state=="base":
		hud.base_page="armory"
	elif action=="briefing" and state=="base":
		hud.base_page="briefing"
	elif action=="crates" and state=="base":
		hud.base_page="crates"
	elif action=="open_crate" and state=="base":
		crate_manager.open_crate()
	elif action=="lobby" and state=="base":
		hud.base_page="lobby"
	elif action=="settings_open":
		toggle_settings()
	elif action.begins_with("station:"):
		lobby_manager.open_station(action.trim_prefix("station:"))
	elif action=="research_upgrade":
		lobby_manager.upgrade_research()
	elif action=="retry_reward":
		stage_manager.retry_reward()
	elif action.begins_with("setting:"):
		lobby_manager.toggle_setting(action.trim_prefix("setting:"))
	elif action.begins_with("armory:") and state=="base":
		var parts := action.split(":")
		var id: String=parts[2]
		match parts[1]:
			"select": hud.selected_weapon=id
			"unlock": progression_manager.unlock(id)
			"level": progression_manager.level_up(id)
			"star": progression_manager.star_up(id)
			"equip_a": progression_manager.equip_loadout(id,0)
			"equip_b": progression_manager.equip_loadout(id,1)
			"trait": progression_manager.equip_trait(hud.selected_weapon,id)
	elif action=="return_base":
		run_manager.return_to_base()
	elif action.begins_with("perk:"):
		choose_perk(action.trim_prefix("perk:"))

func spawn_enemy(pos: Vector3, elite: bool=false, boss: bool=false, definition_id: String="") -> CharacterBody3D:
	var id := definition_id if not definition_id.is_empty() else ("warden" if boss else ("heavy" if elite else "normal"))
	return enemy_manager.spawn(pos,id)

func nearest_enemy(pos: Vector3, excluding: Node=null, radius: float=100, visible_only: bool=false) -> Node3D:
	return enemy_manager.nearest(pos,excluding,radius,visible_only)

func has_perk(id: String) -> bool:
	return rogue_manager.has(id)

func enemy_killed(enemy: Node3D, headshot: bool, critical: bool) -> void:
	enemies.erase(enemy)
	kills+=1
	lifetime_kills+=1
	save_manager.profile.achievements.infected_100={"progress":mini(lifetime_kills,100),"target":100,"unlocked":lifetime_kills>=100}
	feedback_manager.killed(enemy)
	rogue_manager.on_kill(enemy,headshot)
	if kills%10==0:
		weapon_manager.grant_supply("kill_resupply")

func area_blast(pos: Vector3, radius: float, damage: float, force: float, excluded: Node=null) -> void:
	var profile_start: int=Time.get_ticks_usec() if combat_profiler.enabled else 0
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.dead or enemy==excluded:
			continue
		var delta: Vector3=enemy.position-pos
		if delta.length()<radius:
			enemy.take_damage(damage,delta.normalized(),false,false,force,"explosion")
	if is_instance_valid(world.environment_props):
		world.environment_props.damage_props(pos+Vector3.UP,radius,damage,force)
	if combat_profiler.enabled: combat_profiler.note("area_blast_inclusive",profile_start)

func ricochet(source: Node3D, damage: float) -> void:
	var other := nearest_enemy(source.position,source,rogue_manager.value("ricochet_radius"))
	if is_instance_valid(other):
		fx.tracer(source.position+Vector3.UP,other.position+Vector3.UP,Color("abd6b3"))
		other.take_damage(damage*rogue_manager.value("ricochet_damage"),(other.position-source.position).normalized())

func camera_shake(amount: float) -> void:
	shake=minf(.5,shake+amount)

func present_upgrades() -> void:
	rogue_manager.offer()

func choose_perk(id: String) -> void:
	rogue_manager.choose(id)

func clear_stage() -> void:
	stage_manager.clear_stage()

func next_stage() -> void:
	stage_manager.advance()

func fail_run(reason: String="death") -> void:
	run_manager.fail(reason)

func save_progress(path: String="user://progress.json") -> bool:
	if is_test_session() and path=="user://progress.json":
		return true
	return save_manager.save_profile(path)

func load_progress(path: String="user://progress.json") -> void:
	if is_test_session() and path=="user://progress.json":
		return
	save_manager.load_profile(path)

func is_test_session() -> bool:
	var args := OS.get_cmdline_user_args()
	if "--ui-visual-tests" in args: return true
	if "--weapon-lab" in args: return true
	if "--audio-tests" in args or "--performance-tests" in args or "--horde-benchmark" in args or "--settings-tests" in args: return true
	return "--smoke" in args or "--capture" in args or "--benchmark" in args or "--autoplay" in args or "--architecture" in args or "--flow" in args or "--objectives" in args or "--perks" in args or "--progression" in args or "--crate-tests" in args or "--lobby-tests" in args or "--save-tests" in args or "--enemy-tests" in args or "--crowd-tests" in args or "--director-tests" in args or "--weapon-tests" in args or "--mutation-tests" in args or "--feedback-tests" in args or "--screen-tests" in args or "--environment-tests" in args or "--library-tests" in args or "--chapter-tests" in args or "--rating-tests" in args or "--boss-tests" in args or "--hud-tests" in args

func preview_screen_effects() -> void:
	player.hp=20
	player.apply_status("poison",3)
	player.apply_status("burn",3)
	hurt_overlay=.8
	feedback_manager.route("boss_slam",player.position)

func capture() -> void:
	# Explicit visual fixture: freeze a shot for review, never used by normal play.
	if "--weapon-showcase" in OS.get_cmdline_user_args():
		var origin: Vector3=player.muzzle.global_position
		var endpoint: Vector3=origin+Vector3(0,0,-7)
		var data: Dictionary=weapon_manager.definition()
		fx.weapon_muzzle(origin,(endpoint-origin).normalized(),data)
		if data.behavior=="projectile":
			fx.plasma_explosion(endpoint,3.3,Color(data.tracer_color))
		else:
			fx.weapon_tracer(origin,endpoint,data)
			fx.weapon_impact(endpoint,Vector3.FORWARD,data)
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/prototype.png"
	if stage>1:
		path="res://artifacts/sector-%d.png" % stage
	if state=="base":
		path="res://artifacts/base.png"
		if hud.base_page in ["armory","crates"]:
			path="res://artifacts/"+hud.base_page+".png"
	if state=="upgrade":
		path="res://artifacts/upgrades.png"
		if not mutation_manager.choices.is_empty():
			path="res://artifacts/mutations.png"
	if "--action" in OS.get_cmdline_user_args():
		path="res://artifacts/action.png"
	if hud.build_open:
		path="res://artifacts/build-screen.png"
	if settings_panel.visible:
		path="res://artifacts/settings.png"
	if stage_manager.chapter_id=="objective_trials":
		path="res://artifacts/objective-"+objective.kind+".png"
	if stage_manager.chapter_id=="chapter_01":
		path="res://artifacts/chapter-01-sector-%d.png" % stage
	if "--screen-effects" in OS.get_cmdline_user_args():
		path="res://artifacts/screen-effects"+("-reduced" if "--reduced-effects" in OS.get_cmdline_user_args() else "")+".png"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--layout="):
			path="res://artifacts/"+argument.trim_prefix("--layout=").get_file()+".png"
	if not OS.has_feature("editor"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://captures"))
		path="user://captures/"+path.get_file()
	var capture_error: Error=get_viewport().get_texture().get_image().save_png(path)
	print(("CAPTURE_SAVED " if capture_error==OK else "CAPTURE_FAILED ")+ProjectSettings.globalize_path(path))
	if capture_mode:
		shutdown(0 if capture_error==OK else 1)

func preview_ui_hover() -> void:
	for item in hud.buttons:
		if str(item.action)=="station:armory":
			var event:=InputEventMouseMotion.new()
			event.position=item.rect.get_center()*hud.size/Vector2(1440,900)
			get_viewport().push_input(event,true)
			return

func run_ui_visual_tests() -> void:
	var suite=load("res://tests/visual_ui.gd").new()
	add_child(suite)
	suite.run(self)

func run_smoke() -> void:
	var suite = load("res://tests/smoke.gd").new()
	add_child(suite)
	suite.run(self)

func run_benchmark() -> void:
	var suite = load("res://tests/benchmark.gd").new()
	add_child(suite)
	suite.run(self)

func _exit_tree() -> void:
	GameLocale.clear()
	Engine.time_scale=1
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	ZVisuals.materials.clear()
	ZVisuals.crowd_materials.clear()

func run_architecture_tests() -> void:
	var suite = load("res://tests/architecture.gd").new()
	add_child(suite)
	suite.run(self)

func run_flow_tests() -> void:
	var suite = load("res://tests/stage_flow.gd").new()
	add_child(suite)
	suite.run(self)

func run_objective_tests() -> void:
	var suite = load("res://tests/objectives.gd").new()
	add_child(suite)
	suite.run(self)

func run_perk_tests() -> void:
	var suite = load("res://tests/perks.gd").new()
	add_child(suite)
	suite.run(self)

func run_progression_tests() -> void:
	var suite = load("res://tests/progression.gd").new()
	add_child(suite)
	suite.run(self)

func run_crate_tests() -> void:
	var suite = load("res://tests/crates.gd").new()
	add_child(suite)
	suite.run(self)

func run_lobby_tests() -> void:
	var suite = load("res://tests/lobby.gd").new()
	add_child(suite)
	suite.run(self)

func run_save_tests() -> void:
	var suite = load("res://tests/save_integrity.gd").new()
	add_child(suite)
	suite.run(self)

func run_enemy_tests() -> void:
	var suite = load("res://tests/enemy_roster.gd").new()
	add_child(suite)
	suite.run(self)

func run_crowd_tests() -> void:
	var suite = load("res://tests/crowd.gd").new()
	add_child(suite)
	suite.run(self)

func run_director_tests() -> void:
	var suite = load("res://tests/adaptive_director.gd").new()
	add_child(suite)
	suite.run(self)

func run_weapon_tests() -> void:
	var suite = load("res://tests/weapon_roster.gd").new()
	add_child(suite)
	suite.run(self)

func run_mutation_tests() -> void:
	var suite = load("res://tests/mutations.gd").new()
	add_child(suite)
	suite.run(self)

func run_feedback_tests() -> void:
	var suite = load("res://tests/damage_feedback.gd").new()
	add_child(suite)
	suite.run(self)

func run_screen_tests() -> void:
	var suite = load("res://tests/screen_effects.gd").new()
	add_child(suite)
	suite.run(self)

func run_environment_tests() -> void:
	var suite = load("res://tests/environment.gd").new()
	add_child(suite)
	suite.run(self)

func run_library_tests() -> void:
	var suite = load("res://tests/modular_library.gd").new()
	add_child(suite)
	suite.run(self)

func run_chapter_tests() -> void:
	var suite = load("res://tests/chapter_one.gd").new()
	add_child(suite)
	suite.run(self)

func run_rating_tests() -> void:
	var suite = load("res://tests/stage_rating.gd").new()
	add_child(suite)
	suite.run(self)

func run_boss_tests() -> void:
	var suite = load("res://tests/boss.gd").new()
	add_child(suite)
	suite.run(self)

func run_hud_tests() -> void:
	var suite = load("res://tests/hud_flow.gd").new()
	add_child(suite)
	suite.run(self)

func run_audio_tests() -> void:
	var suite = load("res://tests/audio.gd").new()
	add_child(suite)
	suite.run(self)

func run_performance_tests() -> void:
	var suite=load("res://tests/performance_bounds.gd").new()
	add_child(suite)
	suite.run(self)

func run_horde_benchmark() -> void:
	var suite=load("res://scripts/diagnostics/horde_benchmark.gd").new()
	add_child(suite)
	suite.run(self)

func run_settings_tests() -> void:
	var suite=load("res://tests/settings.gd").new()
	add_child(suite)
	suite.run(self)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()

func shutdown(code: int=0) -> void:
	if closing:
		return
	closing=true
	stage_manager.cancel_pending()
	state_manager.paused=true
	state_manager.transition_to("base")
	# Keep the main loop running so paused stream players can release playback.
	get_tree().paused=false
	Engine.time_scale=1
	sound.stop_all()
	save_progress()
	# The Dummy backend needs a longer drain after a synchronous burst of play/stop
	# requests (for example Boss ability tests). Keep real-device shutdown unchanged.
	await get_tree().create_timer(1.0 if AudioServer.get_driver_name()=="Dummy" else .25,true,false,true).timeout
	get_tree().quit(code)

func initialize_managers() -> bool:
	if not catalog.load_all():
		return false
	for manager in [weapon_manager,enemy_manager,stage_manager,run_manager,rogue_manager,progression_manager,crate_manager,mutation_manager,feedback_manager]:
		manager.game=self
	for manager in [state_manager,save_manager,pool_manager,weapon_manager,enemy_manager,stage_manager,run_manager,rogue_manager,progression_manager,crate_manager,mutation_manager,feedback_manager]:
		manager.process_mode=Node.PROCESS_MODE_PAUSABLE
		add_child(manager)
	weapon_manager.reset()
	return true
