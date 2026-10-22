extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	game.player.position=Vector3(10,.05,7)
	game.player.invulnerability=100
	var near_enemy=game.spawn_enemy(Vector3(8,.05,7))
	var far_enemy=game.spawn_enemy(Vector3(-13,.05,7))
	await get_tree().create_timer(1.1).timeout
	check(near_enemy.decision_steps>40 and far_enemy.decision_steps<near_enemy.decision_steps*.4,"Distant enemy decisions run at a lower real-time frequency than nearby combat")
	check(far_enemy.animation_steps<near_enemy.animation_steps*.3,"Distant animation transforms update at 5 Hz rather than every physics tick")
	check(far_enemy.lod_tier==2 and far_enemy.distant_model.visible and not far_enemy.model.visible,"Distant actor renders the material-batched pose LOD")
	var low_mesh: MeshInstance3D=far_enemy.distant_model.get_child(0)
	check(low_mesh.mesh.get_surface_count()<far_enemy.model.get_child_count() and low_mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Batched LOD reduces render submissions while preserving authored body geometry")
	var tagged_vertices := 0
	for surface in low_mesh.mesh.get_surface_count():
		for color in low_mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]:
			if color.r>.25: tagged_vertices+=1
	check(tagged_vertices>0 and float(low_mesh.get_instance_shader_parameter("walk_phase"))>0,"Batched walking receives leg tags and a live per-instance animation phase")
	far_enemy.flash_timer=.1
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(float(low_mesh.get_instance_shader_parameter("hit_flash"))==1,"Real far-enemy hit flash reaches the batched shader")
	check(near_enemy.model.visible and not near_enemy.distant_model.visible,"Nearby combat retains the detailed character model")
	check(far_enemy.path_queries<=2,"Distant navigation requests are staggered and throttled")
	var id: int=far_enemy.get_instance_id()
	var hierarchy_events: Dictionary={"enter":0,"exit":0}
	far_enemy.tree_entered.connect(func():hierarchy_events.enter+=1)
	far_enemy.tree_exiting.connect(func():hierarchy_events.exit+=1)
	game.enemy_manager.release(far_enemy)
	var reused=game.spawn_enemy(Vector3(9,.05,7))
	check(reused.get_instance_id()==id and reused.lod_tier==0 and reused.model.visible and not reused.distant_model.visible,"Reused enemies reset distant visual and decision state")
	check(hierarchy_events.enter==0 and hierarchy_events.exit==0 and reused.get_parent()==game,"Persistent enemy reuse avoids exiting and re-entering the scene hierarchy")
	var transient_host:=Node3D.new()
	game.add_child(transient_host)
	var temporary=game.pool_manager.acquire("transient_fixture",func():return Node3D.new(),transient_host)
	game.pool_manager.release(temporary)
	check(temporary.get_parent()==game.pool_manager,"Unregistered temporary parents still transfer idle objects into pool ownership")
	transient_host.queue_free()
	game.enemy_manager.clear()
	for i in 150: game.spawn_enemy(game.director.spawn_position())
	check(game.enemies.size()==150,"Actor pool supports 150 simultaneous live enemies")
	game.enemy_manager.clear()
	var created: int=game.pool_manager.stats.created
	for i in 150: game.spawn_enemy(game.director.spawn_position())
	check(game.enemies.size()==150 and game.pool_manager.stats.created==created,"Second 150-enemy wave reuses the pool without allocating more actors")
	game.enemy_manager.clear()
	for i in 600: game.fx.debris(Vector3(0,1,0),Vector3.ZERO,Color.RED,Vector3.ONE*.02,1)
	check(game.fx.particles.size()==300,"Background debris leaves 150 foreground slots available")
	for i in 150: game.fx.energy_ring(Vector3(0,1,0),Vector3.UP,Color.CYAN,.1,1,.2)
	check(game.fx.particles.size()==450,"Foreground pulses remain visible after the background budget is full")
	check(game.fx.particles.size()<=450,"Burst effects enforce their 450-instance ceiling")
	for i in 160: game.fx.number(Vector3.ZERO,1,false)
	check(game.fx.damage_numbers.size()<=128,"Damage numbers enforce their 128-entry ceiling")
	game.fx.clear_transients()
	check(game.fx.particles.is_empty() and game.fx.damage_numbers.is_empty(),"Stage cleanup returns transient effects and clears their tracking lists")
	check(game.pool_manager.idle_count("vfx")==450,"Effects pool retains the full supported burst capacity")
	var created_after_burst: int=game.pool_manager.stats.created
	for i in 300: game.fx.debris(Vector3(0,1,0),Vector3.ZERO,Color.RED,Vector3.ONE*.02,1)
	for i in 150: game.fx.energy_ring(Vector3(0,1,0),Vector3.UP,Color.CYAN,.1,1,.2)
	check(game.pool_manager.stats.created==created_after_burst,"A repeated maximum effects burst reuses all nodes without allocation churn")
	game.fx.clear_transients()
	var kills_before: int=game.kills
	for i in 16:
		var victim=game.spawn_enemy(Vector3(0,.05,5))
		victim.take_damage(10000,Vector3.RIGHT)
	check(game.kills==kills_before+16 and game.enemies.is_empty(),"A simultaneous kill burst retains every authoritative kill")
	check(game.fx.corpses.size()==4 and game.fx.sampled_deaths>=12,"Mass-death physics sampling bounds creation without dropping kill results")
	for wave in 3:
		await get_tree().physics_frame
		await get_tree().physics_frame
		for i in 4:
			var victim=game.spawn_enemy(Vector3(0,.05,5))
			victim.take_damage(10000,Vector3.RIGHT)
	var moving_bodies := 0
	for corpse in game.fx.corpses:
		for body in corpse.get_children():
			if body is RigidBody3D and not body.freeze: moving_bodies+=1
	check(moving_bodies<=48 and game.fx.corpses.size()<=24,"New articulated deaths freeze older bodies within the eight-moving-corpse budget")
	game.fx.clear_transients()
	var failed: Array=results.filter(func(item):return not item.passed)
	var report: Dictionary={"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"scope":"Scheduling and resource bounds; hardware frame time is measured by --horde-benchmark."}
	var file:=FileAccess.open("res://artifacts/performance-bounds-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("PERFORMANCE_BOUNDS_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
