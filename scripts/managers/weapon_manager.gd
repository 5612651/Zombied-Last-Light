class_name WeaponManager
extends Node

signal switched(id: String)
var game: Node3D
var loadout: Array[String] = ["ar","shotgun"]
var current := 0
var magazines: Array = []
var capacity: Array = []
var reserve: Array = []
var projectiles: Array=[]
const GrenadeScript=preload("res://scripts/grenade_projectile.gd")

func launch_grenade(origin: Vector3, direction: Vector3, data: Dictionary) -> Node3D:
	var factory := func() -> Node3D:
		var projectile=GrenadeScript.new()
		projectile.game=game
		return projectile
	var projectile: Node3D=game.pool_manager.acquire("weapon_grenade",factory,game)
	projectile.launch(origin,direction,data)
	projectiles.append(projectile)
	return projectile

func clear_projectiles() -> void:
	for projectile in projectiles.duplicate():
		if is_instance_valid(projectile):
			projectile.recycle()

func reset() -> void:
	clear_projectiles()
	current=0
	magazines.clear()
	capacity.clear()
	reserve.clear()
	for id in loadout:
		var def: Dictionary=game.catalog.definition("weapons",id)
		capacity.append(int(def.magazine))
		magazines.append(int(def.magazine))
		reserve.append(int(def.reserve))

func definition(index: int=-1) -> Dictionary:
	return game.mutation_manager.apply_definition(game.progression_manager.apply_definition(game.catalog.definition("weapons",loadout[current if index<0 else index])))

func configure_owned_loadout() -> void:
	var owned: Array=game.save_manager.profile.loadout.filter(func(id):return game.progression_manager.owned(id))
	if owned.is_empty():
		owned=game.catalog.items("weapons").filter(func(d):return game.progression_manager.owned(d.id)).map(func(d):return d.id).slice(0,2)
	loadout.assign(owned)

func equip(index: int) -> bool:
	if index<0 or index>=loadout.size():
		return false
	current=index
	switched.emit(loadout[current])
	return true

func cycle() -> void:
	equip((current+1)%loadout.size())

func complete_reload() -> int:
	var needed := mini(int(capacity[current])-int(magazines[current]),int(reserve[current]))
	magazines[current]+=needed
	reserve[current]-=needed
	return needed

func resupply(amounts: Dictionary, stage_fallback: bool=false) -> void:
	for i in loadout.size():
		var data: Dictionary=game.catalog.definition("weapons",loadout[i])
		reserve[i]+=int(amounts.get(loadout[i],data.get("stage_resupply",0) if stage_fallback else 0))

func grant_supply(kind: String) -> void:
	for i in loadout.size():
		reserve[i]+=int(game.catalog.definition("weapons",loadout[i]).get(kind,0))
