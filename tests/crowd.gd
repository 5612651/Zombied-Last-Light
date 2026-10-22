extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func reference_slot(game: Node3D, crowd: RefCounted, actor: Node3D) -> int:
	var owners: Dictionary=crowd.targets.get(game.player.get_instance_id(),{}).get("owners",{})
	var best := -1
	var cost := INF
	for index in 224:
		var ring_cost: float=crowd.ring_number(index)*10000.0
		if ring_cost>cost: break
		if owners.has(index): continue
		var point: Vector3=crowd.slot_point(index,game.player.position)
		if not game.world.walkable(point): continue
		var candidate: float=ring_cost+actor.position.distance_squared_to(point)
		if candidate<cost:
			cost=candidate
			best=index
	return best

func run(game: Node3D) -> void:
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	game.player.position=Vector3.ZERO
	var crowd=game.enemy_manager.crowd
	var same_geometry := true
	for center in [Vector3.ZERO,Vector3(3.5,.05,-2.2)]:
		for slot in range(225):
			var remaining: int=slot
			var ring := 0
			var count := 8
			while remaining>=count:
				remaining-=count
				ring+=1
				count=8*(ring+1)
			var angle: float=TAU*float(remaining)/float(count)+float(ring%2)*.13
			var expected: Vector3=center+Vector3(sin(angle),0,cos(angle))*(1.05+ring*1.35)
			same_geometry=same_geometry and crowd.slot_point(slot,center).is_equal_approx(expected) and crowd.ring_number(slot)==ring
	check(same_geometry,"Precomputed approach geometry preserves every ring, translated center and uncached boundary")
	var reference_actors: Array=[]
	var same_allocations := true
	for i in 150:
		var angle: float=float(i)*TAU/150
		var actor=game.spawn_enemy(Vector3(sin(angle)*9,.05,cos(angle)*9))
		actor.set_physics_process(false)
		var expected: int=reference_slot(game,crowd,actor)
		crowd.approach(actor,game.player)
		same_allocations=same_allocations and int(crowd.allocations.get(actor.get_instance_id(),{}).get("slot",-1))==expected
		reference_actors.append(actor)
	check(same_allocations,"A 150-enemy batch chooses exactly the same reservations as the original occupied-slot search")
	for i in range(0,150,7): crowd.release(reference_actors[i])
	var same_released := true
	for i in range(0,150,7):
		var actor: Node3D=reference_actors[i]
		var expected: int=reference_slot(game,crowd,actor)
		crowd.approach(actor,game.player)
		same_released=same_released and int(crowd.allocations.get(actor.get_instance_id(),{}).get("slot",-1))==expected
	check(same_released,"Released reservations restore original row priorities and deterministic tie breaks")
	var target_entry: Dictionary=crowd.targets[game.player.get_instance_id()]
	var free_count := 0
	var partitioned := true
	for ring in target_entry.free_rings:
		free_count+=ring.size()
		for slot in ring: partitioned=partitioned and not target_entry.owners.has(slot)
	check(partitioned and free_count+target_entry.owners.size()==224,"Free and reserved slots remain disjoint and cover the complete approach geometry")
	game.enemy_manager.clear()
	var actors: Array=[]
	for i in 48:
		var angle: float=i*TAU/48
		var actor=game.spawn_enemy(Vector3(sin(angle)*7,.05,cos(angle)*7))
		actor.set_physics_process(false)
		actors.append(actor)
		crowd.approach(actor,game.player)
	check(crowd.allocations.size()==48,"Every melee infected receives its own approach reservation")
	var occupied := {}
	var inner: Array=[]
	var waiting: Array=[]
	var all_walkable := true
	for actor in actors:
		var point: Vector3=crowd.approach(actor,game.player)
		var index: int=crowd.allocations[actor.get_instance_id()].slot
		occupied[index]=true
		all_walkable=all_walkable and game.world.walkable(point)
		if crowd.can_melee(actor,game.player):
			inner.append(actor)
		else:
			waiting.append(actor)
	check(occupied.size()==48 and all_walkable,"Crowd reservations remain unique and on navigable cells")
	check(inner.size()==8 and waiting.size()==40,"Only eight inner positions may perform ordinary melee attacks")
	var victim: Node3D=inner[0]
	game.enemy_manager.release(victim)
	crowd.approach(waiting[0],game.player)
	check(crowd.can_melee(waiting[0],game.player),"A waiting infected fills a released attack position")
	game.player.position=Vector3(3.5,0,0)
	var point: Vector3=crowd.approach(actors[1],game.player)
	check(crowd.allocations.size()==1 and point.distance_to(game.player.position)<1.1,"Large player movement reallocates approach directions around the new position")
	var spitter=game.spawn_enemy(Vector3(3.5,.05,-6),false,false,"spitter")
	spitter.set_physics_process(false)
	var ranged: Vector3=crowd.approach(spitter,game.player)
	check(ranged.distance_to(game.player.position)>=5 and not crowd.allocations.has(spitter.get_instance_id()),"Ranged infected hold a rear line without consuming melee positions")
	crowd.refresh(game.enemies)
	crowd.pair_checks=0
	for actor in actors:
		if actor!=victim:
			crowd.neighbors(actor)
	check(crowd.pair_checks<48*47/2,"Spatial neighborhood queries avoid scanning the full population for separation")
	actors[1].position=Vector3.ZERO
	actors[2].position=Vector3.ZERO
	crowd.refresh(game.enemies)
	check(crowd.separation(actors[1]).length()>0 and crowd.separation(actors[1]).length()<=1.4,"Exact overlaps receive a bounded separating force")
	game.enemy_manager.clear()
	check(crowd.allocations.is_empty() and crowd.targets.is_empty() and crowd.bins.is_empty(),"Stage cleanup releases slots and neighborhood state")
	game.player.position=Vector3.ZERO
	await get_tree().process_frame
	await get_tree().process_frame
	var positions: Array=[]
	var rebuilds_before: int=game.director.screen_cache_rebuilds
	for i in 40:
		var spawn: Vector3=game.director.spawn_position()
		if spawn!=Vector3.INF:
			positions.append(spawn)
	check(positions.size()==40,"Current combat camera exposes usable offscreen entry points")
	var safe := true
	for spawn in positions:
		safe=safe and game.director.offscreen(spawn) and game.world.walkable(spawn) and spawn.distance_to(game.player.position)>8
	check(safe,"All sampled spawn points are offscreen, navigable and away from the player")
	check(game.director.screen_cache_rebuilds-rebuilds_before<=1,"A same-view spawn batch shares its offscreen projection work")
	var camera_size: float=game.camera.size
	var previous_rebuilds: int=game.director.screen_cache_rebuilds
	game.camera.size=camera_size*.9
	var zoom_spawn: Vector3=game.director.spawn_position()
	check(game.director.screen_cache_rebuilds==previous_rebuilds+1 and (zoom_spawn==Vector3.INF or game.director.offscreen(zoom_spawn)),"Projection changes invalidate visibility before the next spawn in the same frame")
	game.camera.size=camera_size
	game.director.spawn_position()
	previous_rebuilds=game.director.screen_cache_rebuilds
	var offset_before: float=game.camera.h_offset
	game.camera.h_offset=offset_before+2
	var shifted_spawn: Vector3=game.director.spawn_position()
	check(game.director.screen_cache_rebuilds==previous_rebuilds+1 and (shifted_spawn==Vector3.INF or game.director.offscreen(shifted_spawn)),"Camera offset changes invalidate visibility within the same frame")
	game.camera.h_offset=offset_before
	var blocked_point: Vector3=positions[0]
	var blocked_cell: Vector2i=game.world.cell(blocked_point)
	game.world.grid.set_point_solid(blocked_cell,true)
	var avoids_blocked := true
	for i in 20:
		var candidate: Vector3=game.director.spawn_position()
		avoids_blocked=avoids_blocked and (candidate==Vector3.INF or game.world.walkable(candidate))
	game.world.grid.set_point_solid(blocked_cell,false)
	check(avoids_blocked,"Visibility memoization still checks live navigation changes for every spawn")
	check(not game.director.offscreen(game.player.position),"Visible player position cannot pass the offscreen predicate")
	for i in 18:
		var angle: float=i*TAU/18
		var enemy=game.spawn_enemy(Vector3(sin(angle)*5,.05,cos(angle)*5))
		enemy.path_timer=0
	game.player.hp=10000
	await get_tree().create_timer(4.5).timeout
	var attackers := 0
	var overlaps := 0
	for actor in game.enemies:
		if actor.attack_count>0:
			attackers+=1
		for other in game.enemies:
			if actor.get_instance_id()<other.get_instance_id() and actor.position.distance_to(other.position)<.25:
				overlaps+=1
	print("CROWD_OBSERVATION "+JSON.stringify({"attackers":attackers,"population":game.enemies.size(),"severe_overlap_pairs":overlaps,"pair_checks":crowd.pair_checks}))
	check(attackers>0 and attackers<=8,"Real physics crowd reaches the player while respecting attack-slot capacity")
	check(overlaps<=4,"Real moving crowd limits severe body overlap at the melee front")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"observed":{"attackers":attackers,"severe_overlap_pairs":overlaps}}
	var file:=FileAccess.open("res://artifacts/crowd-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("CROWD_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
