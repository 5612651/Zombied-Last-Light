extends Node

func run(game: Node3D) -> void:
	game.deploy(true)
	game.director.active=false
	game.player.bot=true
	var report: Array=[]
	for count in [10,30,50]:
		for enemy in game.enemies:
			enemy.queue_free()
		game.enemies.clear()
		game.player.position=Vector3(0,.05,7)
		for i in count:
			var p: Vector3=game.director.spawn_position()
			game.spawn_enemy(p,i==count-1)
		for i in 90:
			game.player.invulnerability=10
			await get_tree().process_frame
		var times: Array[float]=[]
		var cpu: Array[float]=[]
		var previous := Time.get_ticks_usec()
		for i in 300:
			game.player.invulnerability=10
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append((now-previous)/1000.0)
			cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
			previous=now
		var sum_ := 0.0
		var sum_cpu := 0.0
		for value in times:sum_+=value
		for value in cpu:sum_cpu+=value
		times.sort()
		var data := {"enemies":count,"rendered_frames":times.size(),"mean_frame_ms":sum_/times.size(),"p95_frame_ms":times[int(times.size()*.95)],"mean_process_ms":sum_cpu/cpu.size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"physics_objects":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),"renderer":"Forward+"}
		report.append(data)
		print("BENCHMARK "+JSON.stringify(data))
	var file := FileAccess.open("res://artifacts/performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"device":RenderingServer.get_video_adapter_name(),"samples":report},"  "))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/horde-50.png")
	# Sustained combat includes rays, flashes, transient particles and jointed corpses.
	game.autoplay=true
	game.player.bot_fire=true
	game.player.reserve=[2000,500]
	var combat_start := Time.get_ticks_msec()
	var peak_corpses := 0
	var combat_times: Array[float]=[]
	var previous := Time.get_ticks_usec()
	var min_active := 50
	while Time.get_ticks_msec()-combat_start<10000:
		game.player.invulnerability=10
		while game.enemies.size()<50:
			game.spawn_enemy(game.director.spawn_position())
		min_active=mini(min_active,game.enemies.size())
		peak_corpses=maxi(peak_corpses,game.fx.corpses.size())
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		combat_times.append((now-previous)/1000.0)
		previous=now
	combat_times.sort()
	var combat := {"duration_ms":Time.get_ticks_msec()-combat_start,"min_active":min_active,"peak_corpses":peak_corpses,"shots":game.player.shots_fired,"kills":game.kills,"p95_frame_ms":combat_times[int(combat_times.size()*.95)]}
	report.append({"combat":combat})
	file.store_string("")
	file.close()
	var output := FileAccess.open("res://artifacts/performance.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"device":RenderingServer.get_video_adapter_name(),"samples":report},"  "))
	print("COMBAT_BENCHMARK "+JSON.stringify(combat))
	game.autoplay=false
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/combat-50.png")
	game.shutdown()
