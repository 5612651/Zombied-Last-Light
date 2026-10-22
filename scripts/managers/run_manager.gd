class_name RunManager
extends Node

signal finished(outcome: String)
var game: Node3D
var run_id := ""
var kills := 0
var elapsed := 0.0
var active := false
var outcome := ""

func deploy(instant: bool=false) -> void:
	game.stage_manager.cancel_pending()
	if game.state!="base":
		game.stage_manager.set_phase("base")
	game.enemy_manager.clear()
	game.fx.clear_transients()
	game.feedback_manager.reset()
	game.rogue_manager.reset()
	if not game.is_test_session():
		game.weapon_manager.configure_owned_loadout()
	game.weapon_manager.reset()
	kills=0
	elapsed=0
	active=true
	outcome=""
	run_id=str(Time.get_unix_time_from_system())+"-"+str(randi())
	game.stage_manager.number=1
	game.stage_manager.transitions=0
	game.save_manager.profile.totals.runs+=1
	if is_instance_valid(game.world):
		game.world.queue_free()
	if is_instance_valid(game.player):
		game.player.queue_free()
	game.stage_manager.build()
	game.hud.build_open=false
	if game.settings_panel!=null: game.settings_panel.visible=false
	game.paused=false
	Engine.time_scale=1
	game.stage_manager.start(instant)
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN

func _process(delta: float) -> void:
	if active and game.state=="combat" and not game.paused:
		elapsed+=delta

func fail(reason: String="death") -> void:
	if not active:
		return
	active=false
	outcome=reason
	game.stage_manager.cancel_pending()
	game.stage_manager.set_phase("death")
	game.rogue_manager.reset()
	game.director.active=false
	game.save_manager.profile.totals.deaths+=1
	game.save_progress()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	Engine.time_scale=1
	finished.emit("death")
	return_later(run_id,"dead")

func complete() -> void:
	if not active:
		return
	active=false
	outcome="chapter_clear"
	game.stage_manager.cancel_pending()
	game.stage_manager.set_phase("chapter_clear")
	game.rogue_manager.reset()
	game.director.active=false
	game.save_manager.profile.totals.chapters_cleared+=1
	var chapters: Dictionary=game.save_manager.profile.records.get("chapters",{})
	var id: String=game.stage_manager.chapter_id
	var previous: Dictionary=chapters.get(id,{})
	chapters[id]={"clears":int(previous.get("clears",0))+1,"best_time":minf(float(previous.get("best_time",elapsed)),elapsed),"last_time":elapsed}
	game.save_manager.profile.records.chapters=chapters
	game.save_manager.profile.achievements.first_extraction={"progress":1,"target":1,"unlocked":true}
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.save_progress()
	finished.emit("chapter_clear")
	return_later(run_id,"victory")

func return_later(id: String, expected: String) -> void:
	await get_tree().create_timer(1.8,true,false,true).timeout
	if not game.closing and id==run_id and not active and game.state==expected:
		return_to_base()

func return_to_base() -> bool:
	if active or game.state not in ["dead","victory"]:
		return false
	game.stage_manager.cancel_pending()
	game.stage_manager.set_phase("base")
	game.enemy_manager.clear()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.hud.base_page="lobby"
	return true
