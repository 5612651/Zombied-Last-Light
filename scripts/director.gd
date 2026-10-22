class_name SpawnDirector
extends Node

var game: Node3D
var wave := 0
var spawned := 0
var budget := 0
var timer := 0.0
var active := false
var total_spawned := 0
var waves: Array = []
var current_wave: Dictionary = {}
var tuning: Dictionary={}
var tension := TensionModel.new()
var assessment: Dictionary={}
var sample_timer := 0.0
var kill_rate := 0.0
var previous_kills := 0
var last_wave_ended := -1000.0
var last_spawn_direction := ""
var mix_spawns := 0
var edge_candidates: Array[Vector3]=[]
var screen_candidates: Array[Vector3]=[]
var screen_cache_frame := -1
var screen_cache_transform := Transform3D.IDENTITY
var screen_cache_projection := Projection.IDENTITY
var screen_cache_rect := Rect2()
var screen_cache_rebuilds := 0

func _init() -> void:
	for edge in range(-12,13):
		for side in [-1,1]:
			edge_candidates.append(Vector3(edge,0,side*12.5))
			edge_candidates.append(Vector3(side*12.5,0,edge))

func _ready() -> void:
	tuning=JSON.parse_string(FileAccess.get_file_as_string("res://data/director.json"))

func start_stage() -> void:
	kill_rate=0
	previous_kills=game.kills
	last_wave_ended=-1000
	last_spawn_direction=""
	sample_timer=0
	mix_spawns=0
	waves=game.objective.waves()
	wave=0
	assess(0)
	start_wave()

func start_wave() -> void:
	spawned=0
	current_wave=waves[wave]
	budget=int(current_wave.count)
	timer=float(current_wave.delay)
	if wave>0:
		timer=maxf(timer,float(assessment.get("gap",1.5)))
	active=true
	game.announcement = "尸潮正在逼近" if wave==0 else "守住阵地"
	game.announcement_time=3

func _process(delta: float) -> void:
	if game.state!="combat" or not active:
		return
	sample_timer-=delta
	if sample_timer<=0:
		sample_timer=float(tuning.sample_interval)
		assess(float(tuning.sample_interval))
	timer-=delta
	var continuous: bool=game.objective.kind!="clear"
	if continuous:
		if game.objective.finished:
			active=false
			return
	var authored_cap: int=int(game.objective.config.get("max_active",100))
	if game.enemies.size()>=mini(authored_cap,int(assessment.get("active_cap",32))):
		return
	if (spawned<budget or continuous) and timer<=0:
		timer=float(game.objective.config.get("spawn_interval",.75)) if continuous else float(current_wave.interval)
		timer*=float(assessment.get("interval_multiplier",1))
		var boss: bool = not str(current_wave.boss).is_empty()
		var pos := Vector3(0,.05,-7) if boss else spawn_position()
		if pos != Vector3.INF:
			var id: String=current_wave.normal
			if boss:
				id=current_wave.boss
			elif spawned==budget-1 and not str(current_wave.elite).is_empty() and int(assessment.get("elite_limit",2))>0:
				id=current_wave.elite
			elif game.stage_manager.definition().get("adaptive_mix",false):
				id=choose_enemy()
			game.spawn_enemy(pos,false,false,id)
			spawned+=1
			total_spawned+=1
	if not continuous and spawned>=budget and game.enemies.is_empty():
		active=false
		last_wave_ended=game.run_manager.elapsed
		assess(0)
		if wave<int(waves.size())-1:
			next_wave()
		else:
			game.objective.assault_cleared()

func next_wave() -> void:
	if wave+1>=waves.size():
		return
	wave+=1
	start_wave()

func assess(sample_delta: float) -> Dictionary:
	if sample_delta>0:
		var instant: float=maxi(0,game.kills-previous_kills)/sample_delta
		kill_rate=lerpf(kill_rate,instant,.2)
	previous_kills=game.kills
	var ammo := 0.0
	var capacity := 0.0
	for index in game.weapon_manager.loadout.size():
		var weapon: Dictionary=game.catalog.definition("weapons",game.weapon_manager.loadout[index])
		ammo+=maxf(0,float(game.weapon_manager.magazines[index])+float(game.weapon_manager.reserve[index]))
		capacity+=float(weapon.magazine)+float(weapon.reserve)
	var build: float=minf(1,game.perks.size()*.06+game.rogue_manager.value("damage_mult")+game.rogue_manager.value("fire_rate"))
	var input := {"health":game.player.hp/game.player.max_hp,"ammo":ammo/maxf(1,capacity),"build":build,"kill_rate":kill_rate,"elapsed":game.run_manager.elapsed,"since_wave":game.run_manager.elapsed-last_wave_ended,"base_active":game.stage_manager.definition().get("director_active",tuning.base_active)}
	var previous: String=assessment.get("mode","")
	assessment=tension.evaluate(input,tuning)
	if previous!=str(assessment.mode):
		print("DIRECTOR_STATE "+JSON.stringify(assessment))
	return assessment

func choose_enemy() -> String:
	var weights: Dictionary=game.stage_manager.definition().get("enemy_weights",tuning.enemy_weights)
	var eligible: Dictionary={}
	var elites := 0
	for enemy in game.enemies:
		if is_instance_valid(enemy) and enemy.elite and not enemy.dead:
			elites+=1
	var total := 0
	for id in weights:
		if not game.catalog.has("enemies",id):
			continue
		var definition: Dictionary=game.catalog.definition("enemies",id)
		if definition.tier=="boss":
			continue
		if definition.tier=="elite" and elites>=int(assessment.get("elite_limit",2)):
			continue
		if not assessment.get("specials",true) and id!="normal":
			continue
		eligible[id]=maxi(0,int(weights[id]))
		total+=int(eligible[id])
	if total<=0:
		return "normal"
	var roll := randi_range(1,total)
	for id in eligible:
		roll-=int(eligible[id])
		if roll<=0:
			mix_spawns+=int(id!="normal")
			return id
	return "normal"

func direction_of(point: Vector3) -> String:
	var difference: Vector3=point-game.player.position
	if absf(difference.x)>absf(difference.z):
		return "east" if difference.x>0 else "west"
	return "south" if difference.z>0 else "north"

func spawn_position() -> Vector3:
	# A spawn batch shares one camera view. Cache only visibility; distance,
	# navigation, direction bias and random scores are evaluated for every spawn.
	var frame: int=Engine.get_process_frames()
	var camera_transform: Transform3D=game.camera.get_camera_transform()
	var projection: Projection=game.camera.get_camera_projection()
	var view_rect: Rect2=game.get_viewport().get_visible_rect()
	if frame!=screen_cache_frame or camera_transform!=screen_cache_transform or projection!=screen_cache_projection or view_rect!=screen_cache_rect:
		screen_candidates.clear()
		for point in edge_candidates:
			if offscreen(point): screen_candidates.append(point)
		screen_cache_frame=frame
		screen_cache_transform=camera_transform
		screen_cache_projection=projection
		screen_cache_rect=view_rect
		screen_cache_rebuilds+=1
	var candidates: Array[Vector3]=screen_candidates.duplicate()
	candidates.shuffle()
	var best := Vector3.INF
	var score := -INF
	for p in candidates:
		if p.distance_to(game.player.position)>8 and game.world.walkable(p):
			var heading: Vector3=game.player.velocity
			heading.y=0
			var front: float=heading.normalized().dot((p-game.player.position).normalized()) if heading.length()>.5 else 0
			var candidate: float=randf()+(.45 if direction_of(p)!=last_spawn_direction else 0)-front*(1.2 if assessment.get("mode","")=="recovery" else .25)
			if candidate>score:
				score=candidate
				best=p
	if best!=Vector3.INF:
		last_spawn_direction=direction_of(best)
	return best

func offscreen(point: Vector3) -> bool:
	if game.camera.is_position_behind(point):
		return true
	var visible: Rect2=game.get_viewport().get_visible_rect().grow(48)
	return not visible.has_point(game.camera.unproject_position(point)) and not visible.has_point(game.camera.unproject_position(point+Vector3.UP*2.2))
