class_name MutationManager
extends Node

signal evolved(weapon: String, mutation: String)
var game: Node3D
var active: Dictionary={}
var choices: Array=[]
var context := "field"
var offered_stage := ""

func reset() -> void:
	active.clear()
	choices.clear()
	offered_stage=""

func eligible(data: Dictionary) -> bool:
	return data.weapon in game.weapon_manager.loadout and not active.has(data.weapon) and game.kills>=int(data.min_kills) and game.perks.size()>=int(data.min_perks) and data.requires_any.any(func(id):return game.has_perk(id))

func available() -> Array:
	return game.catalog.items("mutations").filter(eligible)

func offer_available(reason: String) -> bool:
	if game.state!="upgrade" or not game.run_manager.active:
		return false
	var stage: String=game.run_manager.run_id+":"+game.stage_manager.definition().id
	if stage==offered_stage:
		return false
	choices=available()
	if choices.is_empty():
		return false
	context=reason
	offered_stage=stage
	game.sound.play("upgrade",-7,.8)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	return true

func choose(id: String) -> bool:
	if game.state!="upgrade" or not game.run_manager.active:
		return false
	var matches: Array=choices.filter(func(item):return item.id==id and eligible(item))
	if matches.is_empty():
		return false
	var data: Dictionary=matches[0]
	active[data.weapon]=id
	game.player.rebuild_weapon_visual()
	game.announcement=data.title+" / 已进化"
	game.announcement_time=4
	evolved.emit(data.weapon,id)
	resume()
	return true

func skip() -> bool:
	if game.state!="upgrade" or choices.is_empty() or not game.run_manager.active:
		return false
	resume()
	return true

func resume() -> void:
	choices.clear()
	if context=="stage_reward":
		game.stage_manager.open_exit()
	elif context=="objective_checkpoint":
		game.objective.advance_mission()
	else:
		game.state="combat"
		Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
		game.director.next_wave()

func apply_definition(base: Dictionary) -> Dictionary:
	if not active.has(base.id):
		return base
	var data: Dictionary=game.catalog.definition("mutations",active[base.id])
	var result := base.duplicate(true)
	for field in data.multipliers:
		result[field]=float(result.get(field,0))*float(data.multipliers[field])
	for field in data.additions:
		result[field]=float(result.get(field,0))+float(data.additions[field])
	result.title=data.title
	result.mutation_id=data.id
	result.tracer_color=data.tracer_color
	for part in result.get("model_parts",[]):
		part.color=data.visual_color
	return result
