class_name SupplyCrateManager
extends Node

signal opened(reward: Dictionary)
var game: Node3D
var config: Dictionary = {}
var rng := RandomNumberGenerator.new()
var save_callback: Callable
var last_reward: Dictionary = {}
var last_message := ""
var busy := false

func _ready() -> void:
	config=JSON.parse_string(FileAccess.get_file_as_string("res://data/crates.json"))
	rng.randomize()

func rare_due() -> bool:
	return int(game.save_manager.profile.crates.since_rare)>=int(config.rare_pity)-1

func choose_kind() -> String:
	if rare_due():
		for weapon in game.catalog.items("weapons"):
			if not game.progression_manager.owned(weapon.id):
				return "weapon"
		return "trait"
	var total := 0
	for weight in config.weights.values():
		total+=int(weight)
	var roll := rng.randi_range(1,total)
	for kind in config.weights:
		roll-=int(config.weights[kind])
		if roll<=0:
			return kind
	return "supply"

func roll_reward() -> Dictionary:
	var kind := choose_kind()
	var result := {"kind":kind,"rare":kind in ["weapon","trait"],"pity":rare_due()}
	if kind in ["weapon","blueprints"]:
		var candidates: Array=game.catalog.items("weapons")
		if result.pity and kind=="weapon":
			candidates=candidates.filter(func(item):return not game.progression_manager.owned(item.id))
		var weapon: Dictionary=candidates[rng.randi_range(0,candidates.size()-1)]
		result.id=weapon.id
		result.title=weapon.title
		result.amount=int(config.blueprints)
	elif kind=="trait":
		var ids: Array=game.progression_manager.config.traits.keys()
		result.id=ids[rng.randi_range(0,ids.size()-1)]
		result.title=game.progression_manager.config.traits[result.id].title
	else:
		result.title="Supplies"
		result.amount=int(config.supply_reward)
	return result

func apply_reward(reward: Dictionary) -> void:
	var profile: Dictionary=game.save_manager.profile
	match reward.kind:
		"weapon", "blueprints":
			if not profile.weapons.has(reward.id):
				profile.weapons[reward.id]=game.progression_manager.record(reward.id)
			var weapon: Dictionary=profile.weapons[reward.id]
			if reward.kind=="weapon" and not weapon.unlocked:
				weapon.unlocked=true
				reward.message=reward.title+"已解锁，可在武器库装备。"
			else:
				var amount: int=int(config.duplicate_weapon_blueprints) if reward.kind=="weapon" else int(reward.amount)
				weapon.blueprints+=amount
				reward.amount=amount
				reward.duplicate=reward.kind=="weapon"
				reward.message="%s / 获得%d张蓝图" % [reward.title,amount]
		"trait":
			var duplicate: bool=int(profile.trait_inventory.get(reward.id,0))>0
			for weapon in profile.weapons.values():
				duplicate=duplicate or str(weapon.get("trait",""))==str(reward.id)
			reward.duplicate=duplicate
			if duplicate:
				profile.wallet.supply+=int(config.duplicate_trait_supply)
				reward.message="重复%s / 转为%d物资" % [reward.title,int(config.duplicate_trait_supply)]
			else:
				profile.trait_inventory[reward.id]=1
				reward.message=reward.title+"特性已获得，可在武器库装备。"
		"supply":
			profile.wallet.supply+=int(reward.amount)
			reward.message="回收%d物资。" % int(reward.amount)

func open_crate() -> bool:
	if busy or game.state!="base":
		last_message="请在安全屋开启军械箱。"
		return false
	if game.save_manager.profile.wallet.supply<int(config.cost):
		last_message="需要%d物资，可通过完成区域获取。" % int(config.cost)
		return false
	busy=true
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	var reward := roll_reward()
	game.save_manager.profile.wallet.supply-=int(config.cost)
	apply_reward(reward)
	game.save_manager.profile.crates.opened+=1
	game.save_manager.profile.crates.since_rare=0 if reward.rare else int(game.save_manager.profile.crates.since_rare)+1
	game.save_manager.profile.crates.last_reward=reward.duplicate(true)
	var saved: bool=save_callback.call() if save_callback.is_valid() else game.save_progress()
	busy=false
	if not saved:
		game.save_manager.profile=before
		last_message="保存失败，军械箱、物资和保底进度已还原。"
		return false
	last_reward=reward
	last_message=reward.message
	opened.emit(reward)
	return true
