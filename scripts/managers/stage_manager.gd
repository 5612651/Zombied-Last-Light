class_name StageManager
extends Node

const WorldScript = preload("res://scripts/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ObjectiveScript = preload("res://scripts/managers/objective_manager.gd")
signal entered(id: String)
signal cleared(id: String)
var game: Node3D
var chapter_id := "prototype"
var number := 1
var transitions := 0
signal phase_changed(phase: String, stage_id: String)
var phase := "base"
var history: Array = []
var fade := 0.0
var generation := 0
var last_reward: Dictionary = {}
var elapsed := 0.0
var damage_taken := 0.0
var starting_kills := 0
var completion_record: Dictionary = {}
var reward_failed := false
var reward_save_callback: Callable
var props_destroyed := 0
var generator_health_ratio := 1.0
var boss_weak_hits := 0
const PHASE_STATE := {"base":"base","start":"stage_start","combat":"combat","objective":"combat","boss_combat":"combat","area_clear":"area_clear","reward":"reward","upgrade":"upgrade","exit":"cleared","transition":"transition","chapter_clear":"victory","death":"dead"}

func _process(delta: float) -> void:
	fade=move_toward(fade,1.0 if phase=="transition" else 0.0,delta*4)
	if game.state=="combat" and game.run_manager.active:
		elapsed+=delta

func cancel_pending() -> void:
	generation+=1

func set_phase(next: String) -> bool:
	if not PHASE_STATE.has(next) or not game.state_manager.transition_to(PHASE_STATE[next]):
		return false
	phase=next
	history.append({"phase":next,"stage":definition().id,"run":game.run_manager.run_id})
	if history.size()>128:
		history.pop_front()
	phase_changed.emit(next,definition().id)
	return true

func start(instant: bool=false) -> void:
	cancel_pending()
	elapsed=0
	damage_taken=0
	starting_kills=game.kills
	completion_record.clear()
	reward_failed=false
	props_destroyed=0
	generator_health_ratio=1
	boss_weak_hits=0
	var token := generation
	game.director.active=false
	set_phase("start")
	game.announcement="区域0%d / %s" % [number,definition().title]
	game.announcement_time=3
	entered.emit(definition().id)
	if not instant:
		await get_tree().create_timer(1.1,false,false,true).timeout
	if token!=generation or not game.run_manager.active or game.closing:
		return
	set_phase("combat")
	set_phase("boss_combat" if is_boss_stage() else "objective")
	game.objective.activate()
	game.director.start_stage()

func chapter() -> Dictionary:
	return game.catalog.definition("chapters",chapter_id)

func stage_count() -> int:
	return chapter().get("stages",[]).size()

func is_boss_stage() -> bool:
	return definition().waves.any(func(w):return not str(w.get("boss","")).is_empty())

func definition() -> Dictionary:
	var ids: Array=chapter().get("stages",[])
	return game.catalog.definition("stages",ids[clampi(number-1,0,ids.size()-1)])

func build() -> void:
	game.world=WorldScript.new()
	game.world.process_mode=Node.PROCESS_MODE_PAUSABLE
	game.world.game=game
	game.add_child(game.world)
	game.player=PlayerScript.new()
	game.player.process_mode=Node.PROCESS_MODE_PAUSABLE
	game.player.game=game
	game.player.position=Vector3(0,.1,7)
	game.add_child(game.player)
	game.objective=ObjectiveScript.new()
	game.objective.game=game
	game.world.add_child(game.objective)

func clear_stage() -> void:
	if game.state!="combat" or not game.run_manager.active or phase not in ["combat","objective","boss_combat"]:
		return
	cancel_pending()
	var token := generation
	game.director.active=false
	game.objective.active=false
	completion_record={"time":elapsed,"kills":maxi(0,game.kills-starting_kills),"damage_taken":damage_taken,"optional_objective":false,"objective":game.objective.kind}
	completion_record.props_destroyed=props_destroyed
	completion_record.generator_health_ratio=generator_health_ratio
	completion_record.boss_weak_hits=boss_weak_hits
	completion_record=StageRating.evaluate(definition(),completion_record)
	game.enemy_manager.clear()
	set_phase("area_clear")
	game.announcement="区域已肃清 / 评级 "+str(completion_record.rating)
	game.announcement_time=4
	cleared.emit(definition().id)
	settle_reward(token)

func optional_description() -> String:
	var rule: Dictionary=definition().get("optional",{})
	if rule.is_empty(): return ""
	var progress: float=damage_taken
	match str(rule.get("type","")):
		"destroy_props": progress=props_destroyed
		"generator_health": progress=generator_health_ratio*100
		"boss_weak_hits": progress=boss_weak_hits
	return str(rule.title)+" / "+("%d%%" % int(progress) if rule.type=="generator_health" else str(int(progress)))

func settle_reward(token: int) -> void:
	await get_tree().create_timer(.65,false,false,true).timeout
	if token!=generation or not game.run_manager.active or game.closing:
		return
	set_phase("reward")
	commit_reward(token)

func commit_reward(token: int) -> void:
	if token!=generation or phase!="reward" or not game.run_manager.active or game.closing:
		return
	reward_failed=false
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	game.highest_stage=maxi(game.highest_stage,number)
	var current := definition()
	last_reward=current.reward.duplicate(true)
	last_reward.supply=roundi(float(last_reward.get("supply",0))*(1+.1*game.lobby_manager.research_level()))
	game.save_manager.award_stage(game.run_manager.run_id,current.id,last_reward,completion_record)
	var saved: bool=reward_save_callback.call() if reward_save_callback.is_valid() else game.save_progress()
	if not saved:
		game.save_manager.profile=before
		reward_failed=true
		game.announcement="保存失败 / 请重试以结算物资"
		game.announcement_time=5
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		return
	game.sound.play("upgrade",-7)
	game.announcement="物资+%d / 研究+%d" % [int(last_reward.get("supply",0)),int(last_reward.get("research",0))]
	await get_tree().create_timer(.45,false,false,true).timeout
	if token!=generation or not game.run_manager.active or game.closing:
		return
	if number==stage_count():
		open_exit()
	else:
		set_phase("upgrade")
		game.rogue_manager.offer("stage_reward")

func retry_reward() -> bool:
	if not reward_failed or phase!="reward" or not game.run_manager.active:
		return false
	commit_reward(generation)
	return true

func open_exit() -> void:
	if phase not in ["reward","upgrade"] or not game.run_manager.active:
		return
	set_phase("exit")
	game.world.open_gate()
	game.announcement="出口已开放 / 只能前进"
	game.announcement_time=4
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN

func advance() -> bool:
	if phase!="exit" or game.state!="cleared" or not game.run_manager.active:
		return false
	if number>=stage_count():
		game.run_manager.complete()
		return true
	cancel_pending()
	set_phase("transition")
	transition_to_next(generation)
	return true

func transition_to_next(token: int) -> void:
	var health: float=game.player.hp
	var armor: float=game.player.armor
	var grenades: int=game.player.grenades
	var old_bot: bool=game.player.bot
	var old_bot_fire: bool=game.player.bot_fire
	await get_tree().create_timer(.35,false,false,true).timeout
	if token!=generation or not game.run_manager.active or game.closing:
		return
	game.enemy_manager.clear()
	game.fx.clear_transients()
	game.world.queue_free()
	game.player.queue_free()
	number+=1
	transitions+=1
	build()
	var supply: Dictionary=definition().resupply
	game.player.hp=minf(game.player.max_hp,health+float(supply.get("health",20)))
	game.player.armor=armor
	game.player.grenades=mini(game.player.max_grenades,grenades+int(supply.get("grenades",1)))
	game.player.bot=old_bot
	game.player.bot_fire=old_bot_fire
	game.weapon_manager.resupply(supply,true)
	game.highest_stage=maxi(game.highest_stage,number)
	game.save_progress()
	fade=1
	start()

func preview(target: int) -> void:
	if not game.is_test_session():
		return
	cancel_pending()
	game.enemy_manager.clear()
	game.fx.clear_transients()
	game.world.queue_free()
	game.player.queue_free()
	number=clampi(target,1,stage_count())
	build()
	# Preview navigation is explicit and never grants progression or rewards.
	game.state_manager.current="base"
	start(true)
