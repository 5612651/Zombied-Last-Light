extends Node
var invalid_reasons: Array[String]=[]

func run(game: Node3D) -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Hardware benchmark requires a rendered window; headless FPS is not a GPU result.")
		game.shutdown(1)
		return
	game.deploy(true,"prototype")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--horde-chapter="):
			game.deploy(true,argument.trim_prefix("--horde-chapter="))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--horde-sector="):
			game.stage_manager.preview(argument.trim_prefix("--horde-sector=").to_int())
	# Measure this map without mission timers, transitions or defend-unit failure.
	# Normal gameplay objectives remain active; this diagnostic owns its own run.
	game.objective.active=false
	game.director.active=false
	game.player.bot=true
	if game.combat_profiler.enabled:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var samples: Array=[]
	for count in [50,100,150]:
		game.announcement="PERFORMANCE TEST / %d HOSTILES" % count
		game.announcement_time=30
		game.enemy_manager.clear()
		game.fx.clear_transients()
		game.player.position=Vector3(0,.05,7)
		game.player.invulnerability=100
		for i in count: game.spawn_enemy(game.director.spawn_position())
		await get_tree().create_timer(1).timeout
		var sample: Dictionary=await measure(game,5,false,count)
		samples.append(sample)
		print("HORDE_BENCHMARK "+JSON.stringify(sample))
	game.autoplay=true
	game.announcement="PERFORMANCE TEST / 150 HOSTILES / LIVE COMBAT"
	game.announcement_time=30
	game.player.bot_fire=true
	game.player.reserve=[10000,10000]
	var combat: Dictionary=await measure(game,10,true,150)
	combat["build"]="starter_weapons"
	samples.append(combat)
	# Also exercise a legal late-run content combination, rather than only fresh guns.
	game.fx.clear_transients()
	game.perks.assign(["pierce","fire_rate","head_blast","ricochet","kill_speed","deadeye","heavy_rounds","burn","fire_spread","fire_damage","lightning","conductor","overload","blast_radius","blast_damage","death_blast","crit_blast"])
	game.weapon_manager.loadout.assign(["ar"])
	game.weapon_manager.current=0
	game.weapon_manager.reset()
	game.mutation_manager.active["ar"]="vulcan_ar"
	game.player.rebuild_weapon_visual()
	game.player.reserve=[10000]
	game.announcement="PERFORMANCE TEST / LATE-RUN BUILD / 150 HOSTILES"
	game.announcement_time=30
	var build_combat: Dictionary=await measure(game,10,true,150)
	build_combat["build"]="17_perks_vulcan_ar"
	samples.append(build_combat)
	game.autoplay=false
	var pack_path: String=OS.get_executable_path().get_base_dir().path_join("Zombied.pck")
	var output: Dictionary={"engine":Engine.get_version_info().string,"os":OS.get_name(),"cpu":OS.get_processor_name(),"logical_processors":OS.get_processor_count(),"memory":OS.get_memory_info(),"device":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"viewport":str(get_viewport().get_visible_rect().size),"window_size":str(DisplayServer.window_get_size()),"vsync":DisplayServer.window_get_vsync_mode(),"fps_limit":Engine.max_fps,"pack_sha256":FileAccess.get_sha256(pack_path) if FileAccess.file_exists(pack_path) else "development","samples":samples,"valid":invalid_reasons.is_empty(),"invalid_reasons":invalid_reasons,"scope":"Hardware measurements only; test uses invulnerability and replenishment. Background workloads are not controlled. Report does not establish gameplay balance or player enjoyment."}
	var directory: String="res://artifacts" if OS.has_feature("editor") else "user://diagnostics"
	output["build_version"]=ProjectSettings.get_setting("application/config/version","development")
	output["layout"]=game.stage_manager.definition().layout
	output["physics_engine"]=ProjectSettings.get_setting("physics/3d/physics_engine","DEFAULT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var stem: String="horde-performance" if OS.has_feature("editor") else "horde-performance-"+str(int(Time.get_unix_time_from_system()))
	var report_path: String=directory.path_join(stem+".json")
	output["pool_stats"]=game.pool_manager.stats.duplicate()
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:
		push_error("Could not write hardware report: "+report_path)
		game.shutdown(1)
		return
	file.store_string(JSON.stringify(output,"  "))
	file.close()
	print("HORDE_BENCHMARK_COMPLETE "+JSON.stringify(combat))
	print("BUILD_BENCHMARK_COMPLETE "+JSON.stringify(build_combat))
	print("HARDWARE_REPORT "+ProjectSettings.globalize_path(report_path))
	await RenderingServer.frame_post_draw
	var image_error: Error=get_viewport().get_texture().get_image().save_png(directory.path_join(stem+".png"))
	game.shutdown(0 if image_error==OK and invalid_reasons.is_empty() else 1)

func measure(game: Node3D, seconds: float, combat: bool, count: int) -> Dictionary:
	game.combat_profiler.reset()
	var times: Array[float]=[]
	var cpu: Array[float]=[]
	var physics: Array[float]=[]
	var start: int=Time.get_ticks_msec()
	var previous: int=Time.get_ticks_usec()
	var min_active: int=count
	var peak_vfx := 0
	var peak_corpses := 0
	var start_kills: int=game.kills
	var start_samples: int=game.fx.sampled_deaths
	var spikes: Array=[]
	while Time.get_ticks_msec()-start<seconds*1000:
		if game.paused and not invalid_reasons.has("Paused during measurement"): invalid_reasons.append("Paused during measurement")
		if game.state!="combat" and not invalid_reasons.has("Left combat during measurement"): invalid_reasons.append("Left combat during measurement")
		game.player.invulnerability=100
		var frame_kills: int=game.kills
		var frame_physics: int=Engine.get_physics_frames()
		var frame_scopes: Dictionary=game.combat_profiler.scopes.duplicate(true) if game.combat_profiler.enabled else {}
		var spawn_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
		var replenished := 0
		if combat:
			while game.enemies.size()<count:
				game.spawn_enemy(game.director.spawn_position())
				replenished+=1
		var spawn_us: int=Time.get_ticks_usec()-spawn_start if game.combat_profiler.enabled else 0
		min_active=mini(min_active,game.enemies.size())
		peak_vfx=maxi(peak_vfx,game.fx.particles.size())
		peak_corpses=maxi(peak_corpses,game.fx.corpses.size())
		await get_tree().process_frame
		var now: int=Time.get_ticks_usec()
		var frame_ms: float=(now-previous)/1000.0
		times.append(frame_ms)
		if game.combat_profiler.enabled and (spikes.size()<20 or frame_ms>float(spikes[-1].frame_ms)):
			var timing_delta: Dictionary={}
			for id in game.combat_profiler.scopes:
				var latest: Dictionary=game.combat_profiler.scopes[id]
				var before: Dictionary=frame_scopes.get(id,{"calls":0,"total_us":0})
				if int(latest.calls)>int(before.calls):
					timing_delta[id]={"calls":int(latest.calls)-int(before.calls),"total_us":int(latest.total_us)-int(before.total_us)}
			var viewport_rid: RID=get_viewport().get_viewport_rid()
			spikes.append({"frame_ms":frame_ms,"at_ms":now/1000-start,"kills":game.kills-frame_kills,"replenished":replenished,"replenish_us":spawn_us,"physics_steps":Engine.get_physics_frames()-frame_physics,"render_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"last_render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),"last_render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"scopes":timing_delta})
			spikes.sort_custom(func(a,b):return float(a.frame_ms)>float(b.frame_ms))
			if spikes.size()>20: spikes.pop_back()
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		previous=now
	times.sort()
	return {"combat":combat,"requested_enemies":count,"min_active":min_active,"duration_ms":Time.get_ticks_msec()-start,"frames":times.size(),"mean_frame_ms":times.reduce(func(a,b):return a+b,0.0)/times.size(),"p95_frame_ms":times[int(times.size()*.95)],"p99_frame_ms":times[int(times.size()*.99)],"mean_process_ms":cpu.reduce(func(a,b):return a+b,0.0)/cpu.size(),"mean_physics_ms":physics.reduce(func(a,b):return a+b,0.0)/physics.size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"peak_vfx":peak_vfx,"peak_corpses":peak_corpses,"kills":game.kills-start_kills,"sampled_physical_deaths":game.fx.sampled_deaths-start_samples,"pool_created":game.pool_manager.stats.created,"pool_reused":game.pool_manager.stats.reused,"cpu_profile":game.combat_profiler.snapshot(),"profiled_spikes":spikes,"spike_scope":"Only --profile-combat records worst 20 process-frame intervals. Nested CPU scopes overlap. GPU/renderer counters describe their last completed frame and may lag; correlation is not exact attribution. Diagnostic overhead invalidates acceptance FPS."}
