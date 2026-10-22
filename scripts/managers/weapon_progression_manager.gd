class_name WeaponProgressionManager
extends Node

signal changed
var game: Node3D
var config: Dictionary = {}
var last_message := ""
var save_callback: Callable

func _ready() -> void:
	config=JSON.parse_string(FileAccess.get_file_as_string("res://data/progression.json"))

func record(id: String) -> Dictionary:
	return game.save_manager.profile.weapons.get(id,{"unlocked":false,"level":1,"stars":1,"blueprints":0,"trait":""}).duplicate(true)

func owned(id: String) -> bool:
	return bool(record(id).unlocked) and game.catalog.has("weapons",id)

func level_cost(id: String) -> int:
	return int(record(id).level)*int(config.level_cost_factor)

func star_cost(id: String) -> Dictionary:
	return {"supply":int(record(id).stars)*int(config.star_supply_factor),"blueprints":int(record(id).stars)*int(config.star_blueprint_factor)}

func reject(message: String) -> bool:
	last_message=message
	return false

func commit(before: Dictionary, message: String) -> bool:
	var saved: bool=save_callback.call() if save_callback.is_valid() else game.save_progress()
	if not saved:
		game.save_manager.profile=before
		return reject("保存失败，未消耗物资。")
	last_message=message
	changed.emit()
	return true

func unlock(id: String) -> bool:
	if not game.catalog.has("weapons",id) or owned(id):
		return reject("武器不可用或已经解锁。")
	var data := record(id)
	if data.blueprints<int(config.unlock_blueprints) or game.save_manager.profile.wallet.supply<int(config.unlock_supply):
		return reject("需要%d张蓝图和%d物资。" % [config.unlock_blueprints,config.unlock_supply])
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	data.unlocked=true
	data.blueprints-=int(config.unlock_blueprints)
	game.save_manager.profile.wallet.supply-=int(config.unlock_supply)
	game.save_manager.profile.weapons[id]=data
	return commit(before,"武器已解锁，可加入出战配置。")

func level_up(id: String) -> bool:
	if not owned(id):
		return reject("请先解锁该武器。")
	var data := record(id)
	if int(data.level)>=int(config.max_level):
		return reject("武器已达到最高等级。")
	var cost := level_cost(id)
	if game.save_manager.profile.wallet.supply<cost:
		return reject("需要%d物资。" % cost)
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	game.save_manager.profile.wallet.supply-=cost
	game.save_manager.profile.weapons[id].level+=1
	return commit(before,"武器等级已提升。")

func star_up(id: String) -> bool:
	if not owned(id):
		return reject("请先解锁该武器。")
	var data := record(id)
	if int(data.stars)>=int(config.max_stars):
		return reject("武器已达到最高星级。")
	var cost := star_cost(id)
	if data.blueprints<cost.blueprints or game.save_manager.profile.wallet.supply<cost.supply:
		return reject("需要%d张蓝图和%d物资。" % [cost.blueprints,cost.supply])
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	game.save_manager.profile.wallet.supply-=cost.supply
	game.save_manager.profile.weapons[id].blueprints-=cost.blueprints
	game.save_manager.profile.weapons[id].stars+=1
	return commit(before,"武器星级已提升。")

func equip_trait(id: String, trait_id: String) -> bool:
	if not owned(id) or not config.traits.has(trait_id):
		return reject("武器或特性不可用。")
	var data := record(id)
	if data.trait==trait_id:
		return reject("该特性已装备。")
	var inventory: Dictionary=game.save_manager.profile.trait_inventory
	if int(inventory.get(trait_id,0))<1:
		return reject("武器库中没有该特性。")
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	if not str(data.trait).is_empty():
		inventory[data.trait]=int(inventory.get(data.trait,0))+1
	inventory[trait_id]-=1
	game.save_manager.profile.weapons[id].trait=trait_id
	return commit(before,"特性已装备，原特性已归还仓库。")

func equip_loadout(id: String, slot: int) -> bool:
	if not owned(id) or slot not in [0,1]:
		return reject("请先解锁该武器。")
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	var loadout: Array=game.save_manager.profile.loadout
	if id in loadout:
		var previous := loadout.find(id)
		if previous==slot:
			return reject("该武器已在此位置装备。")
		if slot<loadout.size():
			var swap: String=loadout[slot]
			loadout[slot]=id
			loadout[previous]=swap
		else:
			return reject("同一把武器不能占用两个位置。")
	elif slot<loadout.size():
		loadout[slot]=id
	else:
		loadout.append(id)
	return commit(before,"配置已更新，下次部署时生效。")

func apply_definition(base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	var data := record(base.id)
	var trait_definition: Dictionary=config.get("traits",{}).get(data.trait,{})
	var level := clampi(int(data.level),1,int(config.get("max_level",10)))
	var stars := clampi(int(data.stars),1,int(config.get("max_stars",5)))
	var raw_bonus := (level-1)*float(config.get("damage_per_level",.015))+(stars-1)*float(config.get("damage_per_star",.025))+float(trait_definition.get("damage_bonus",0))
	var reload_multiplier := float(trait_definition.get("reload_multiplier",1))
	var crit_chance := float(trait_definition.get("crit_chance",0))
	var cycle: float=float(base.magazine)*float(base.interval)+float(base.reload)
	var modified_cycle: float=float(base.magazine)*float(base.interval)+float(base.reload)*reload_multiplier
	var critical_factor: float=(1+(float(base.crit_chance)+crit_chance)*(float(base.crit_multiplier)-1))/(1+float(base.crit_chance)*(float(base.crit_multiplier)-1))
	var secondary_factor: float=cycle/modified_cycle*critical_factor
	var damage_factor: float=minf(1+raw_bonus,float(config.get("max_power_ratio",1.3))/secondary_factor)
	result.damage=float(base.damage)*damage_factor
	result.reload=float(base.reload)*reload_multiplier
	result.crit_chance=float(base.crit_chance)+crit_chance
	result.recoil=float(base.recoil)*float(trait_definition.get("recoil_multiplier",1))
	result.permanent_power_ratio=damage_factor*secondary_factor
	return result
