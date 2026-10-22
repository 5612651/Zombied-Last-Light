class_name StageObjectiveManager
extends Node3D

const TargetScript = preload("res://scripts/mission_target.gd")
signal completed
signal failed(reason: String)
var game: Node3D
var config: Dictionary = {}
var kind := "clear"
var active := false
var finished := false
var elapsed := 0.0
var activation := 0.0
var activated := false
var targets: Array = []
var destroyed_count := 0
var generator: StaticBody3D
var missions: Array=[]
var mission_index := 0
var mission_history: Array=[]

func _ready() -> void:
	config=game.stage_manager.definition().objective.duplicate(true)
	if config.get("type")=="sequence":
		missions=config.missions.duplicate(true)
		config=missions[0].duplicate(true)
	configure_targets()

func configure_targets() -> void:
	kind=config.get("type","clear")
	destroyed_count=0
	activation=0
	activated=false
	elapsed=0
	if kind=="generator":
		var point: Array=config.get("position",[0,.8,-3])
		generator=create_target("generator",Vector3(point[0],point[1],point[2]),float(config.get("health",240)))
	elif kind=="nests":
		for a in config.get("positions",[[-6,.8,-3],[6,.8,-3],[0,.8,-8]]):
			create_target("nest",Vector3(a[0],a[1],a[2]),float(config.get("health",160)))
	if not targets.is_empty():
		game.world.setup_navigation()

func waves() -> Array:
	return config.get("waves",game.stage_manager.definition().waves)

func create_target(type_: String, pos: Vector3, health: float) -> StaticBody3D:
	var node: StaticBody3D=TargetScript.new()
	node.game=game
	node.objective=self
	node.kind=type_
	node.target_id="Mission target "+str(targets.size())
	node.position=pos
	node.hp=health
	node.max_hp=health
	add_child(node)
	targets.append(node)
	game.world.obstacles.append({"name":node.target_id,"position":[pos.x,pos.y,pos.z],"size":[1.7,1.6,1.7]})
	return node

func activate() -> void:
	active=true
	finished=false
	elapsed=0

func _physics_process(delta: float) -> void:
	if not active or finished or game.state!="combat":
		return
	if kind=="survive":
		elapsed+=delta
		if elapsed>=float(config.duration):
			finish()
	elif kind=="generator":
		if not activated:
			var held: bool=Input.is_physical_key_pressed(KEY_E) or (game.autoplay and game.player.bot)
			interact(delta,held)
		else:
			elapsed+=delta
			if elapsed>=float(config.duration):
				finish()

func interact(delta: float, held: bool) -> void:
	if kind!="generator" or activated or not active or game.state!="combat":
		return
	if held and game.player.global_position.distance_to(generator.global_position)<2.8:
		activation=minf(float(config.get("activation_seconds",2)),activation+delta)
	else:
		activation=maxf(0,activation-delta*.5)
	if activation>=float(config.get("activation_seconds",2)):
		activated=true
		generator.lamp.light_color=Color("99d6ae")
		game.sound.play("upgrade",-8,.8)
		game.announcement="电力已恢复 / 守住发电机"
		game.announcement_time=3

func assault_cleared() -> void:
	if kind=="clear" and active and game.enemies.is_empty() and game.director.spawned>=game.director.budget and game.director.wave>=waves().size()-1:
		finish()

func target_destroyed(target: StaticBody3D) -> void:
	if kind!="nests" or finished:
		return
	destroyed_count+=1
	var id: String=target.target_id
	game.world.obstacles=game.world.obstacles.filter(func(o):return o.name!=id)
	game.world.setup_navigation()
	if destroyed_count>=targets.size():
		finish()

func generator_failed() -> void:
	if finished:
		return
	finished=true
	active=false
	failed.emit("generator_destroyed")
	game.fail_run("generator_destroyed")

func finish() -> void:
	if finished or not active:
		return
	finished=true
	active=false
	if kind=="generator" and is_instance_valid(generator):
		game.stage_manager.generator_health_ratio=minf(game.stage_manager.generator_health_ratio,generator.hp/generator.max_hp)
	mission_history.append({"part":mission_index+1,"type":kind,"elapsed":game.stage_manager.elapsed,"kills":game.kills})
	print("MISSION_COMPLETED "+JSON.stringify(mission_history[-1]))
	if not missions.is_empty() and mission_index<missions.size()-1:
		game.director.active=false
		game.enemy_manager.clear()
		game.weapon_manager.clear_projectiles()
		game.announcement="目标已完成 / 选择战地强化"
		game.announcement_time=3
		game.rogue_manager.offer("objective_checkpoint")
		return
	completed.emit()
	game.stage_manager.clear_stage()

func advance_mission() -> bool:
	if missions.is_empty() or not finished or mission_index>=missions.size()-1 or not game.run_manager.active:
		return false
	var ids: Array=targets.map(func(target):return target.target_id)
	game.world.obstacles=game.world.obstacles.filter(func(obstacle):return obstacle.name not in ids)
	for target in targets:
		if is_instance_valid(target):
			target.collision_layer=0
			target.queue_free()
	targets.clear()
	generator=null
	mission_index+=1
	config=missions[mission_index].duplicate(true)
	configure_targets()
	game.world.setup_navigation()
	game.state="combat"
	game.stage_manager.set_phase("boss_combat" if waves().any(func(wave):return not str(wave.get("boss","")).is_empty()) else "objective")
	activate()
	game.director.start_stage()
	game.announcement="目标 %d / %d" % [mission_index+1,missions.size()]
	game.announcement_time=3
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
	return true

func target_for(enemy: Node3D) -> Node3D:
	if kind=="generator" and activated and not finished and is_instance_valid(generator) and not generator.destroyed:
		if enemy.position.distance_to(generator.global_position)<enemy.position.distance_to(game.player.position)+2:
			return generator
	return game.player

func combat_target() -> Node3D:
	if kind!="nests" or finished:
		return null
	var best: Node3D
	var distance := INF
	for target in targets:
		if target.destroyed:
			continue
		var ray := PhysicsRayQueryParameters3D.create(game.player.muzzle.global_position,target.global_position,1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var d: float=target.global_position.distance_to(game.player.position)
		if d<distance:
			distance=d
			best=target
	return best

func steering_goal() -> Vector3:
	if kind=="generator" and not activated:
		return generator.global_position+Vector3(0,-.8,2.1)
	if kind=="generator" and activated:
		return generator.global_position+Vector3(0,-.8,3)
	if kind=="nests":
		for target in targets:
			if not target.destroyed:
				return target.global_position+Vector3(0,-.8,3)
	return Vector3.INF

func description() -> String:
	return ("%d/%d / " % [mission_index+1,missions.size()] if not missions.is_empty() else "")+task_description()

func task_description() -> String:
	match kind:
		"clear": return "肃清区域 / 第%d波，共%d波" % [game.director.wave+1,waves().size()]
		"survive": return "坚持生存 / 剩余%03d秒" % ceili(maxf(0,float(config.duration)-elapsed))
		"generator":
			if not activated:
				return "靠近发电机并长按E（%d%%）" % int(activation/float(config.get("activation_seconds",2))*100)
			return "守护电力 / %03d秒 / 设备生命%d%%" % [ceili(maxf(0,float(config.duration)-elapsed)),int(generator.hp/generator.max_hp*100)]
		"nests": return "摧毁感染巢 / 已完成%d，共%d个" % [destroyed_count,targets.size()]
	return ""
