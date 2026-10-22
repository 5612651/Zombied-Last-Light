extends Node

var game: Node3D
var results: Array = []

func check(condition: bool, label_: String) -> void:
	results.append({"test":label_,"passed":condition})
	print(("PASS " if condition else "FAIL ")+label_)

func dps(definition: Dictionary) -> float:
	return float(definition.damage)*float(definition.pellets)*float(definition.magazine)*(1+float(definition.crit_chance)*(float(definition.crit_multiplier)-1))/(float(definition.magazine)*float(definition.interval)+float(definition.reload))

func run(target: Node3D) -> void:
	game=target
	var progress=game.progression_manager
	game.save_manager.profile=SaveManager.fresh_profile()
	check(progress.owned("ar") and not progress.owned("shotgun"),"New profile starts with AR and a locked Shotgun")
	check(not progress.level_up("shotgun"),"Locked weapons cannot be leveled")
	check(not progress.level_up("ar") and game.save_manager.profile.weapons.ar.level==1,"Insufficient supplies cannot change weapon progression")
	game.save_manager.profile.wallet.supply=1000
	check(not progress.unlock("shotgun"),"Unlock requires both blueprints and supplies")
	game.save_manager.profile.weapons.shotgun.blueprints=20
	check(progress.unlock("shotgun") and progress.owned("shotgun") and game.save_manager.profile.wallet.supply==850 and progress.record("shotgun").blueprints==0,"Unlock consumes exact authored costs")
	var balance: int=game.save_manager.profile.wallet.supply
	check(not progress.unlock("shotgun") and game.save_manager.profile.wallet.supply==balance,"Repeated unlock cannot consume resources")
	check(progress.level_up("ar") and progress.record("ar").level==2 and game.save_manager.profile.wallet.supply==balance-40,"Level increase consumes its current-level cost")
	check(not progress.star_up("ar"),"Star increase rejects missing fragments")
	game.save_manager.profile.weapons.ar.blueprints=20
	balance=game.save_manager.profile.wallet.supply
	check(progress.star_up("ar") and progress.record("ar").stars==2 and progress.record("ar").blueprints==0 and game.save_manager.profile.wallet.supply==balance-80,"Star increase consumes fragments and supplies together")
	check(not progress.equip_trait("ar","precision"),"Unowned rare trait cannot be equipped")
	game.save_manager.profile.trait_inventory={"precision":1,"forged":1}
	check(progress.equip_trait("ar","precision") and progress.record("ar").trait=="precision" and game.save_manager.profile.trait_inventory.precision==0,"Equipping rare trait consumes its inventory copy")
	check(progress.equip_trait("ar","forged") and game.save_manager.profile.trait_inventory.precision==1 and progress.record("ar").trait=="forged","Replacing a trait returns the previous trait to storage")
	check(not progress.equip_trait("ar","forged"),"Repeated trait assignment cannot duplicate inventory")
	check(progress.equip_loadout("shotgun",1) and game.save_manager.profile.loadout==["ar","shotgun"],"Unlocked weapon can be placed in secondary slot")
	check(progress.equip_loadout("shotgun",0) and game.save_manager.profile.loadout==["shotgun","ar"],"Moving an equipped weapon swaps slots without duplicates")
	game.weapon_manager.configure_owned_loadout()
	game.weapon_manager.reset()
	check(game.weapon_manager.loadout==["shotgun","ar"],"Deployment loadout reads permanent profile order")
	game.save_manager.profile.wallet.supply=100000
	game.save_manager.profile.weapons.ar.level=10
	game.save_manager.profile.weapons.ar.stars=5
	game.save_manager.profile.weapons.ar.blueprints=1000
	balance=game.save_manager.profile.wallet.supply
	check(not progress.level_up("ar") and not progress.star_up("ar") and game.save_manager.profile.wallet.supply==balance,"Level and star limits reject further spending")
	for id in ["ar","shotgun"]:
		game.save_manager.profile.weapons[id].level=10
		game.save_manager.profile.weapons[id].stars=5
		for trait_id in progress.config.traits:
			game.save_manager.profile.weapons[id].trait=trait_id
			var base: Dictionary=game.catalog.definition("weapons",id)
			var upgraded: Dictionary=progress.apply_definition(base)
			check(dps(upgraded)/dps(base)<=1.30001,"Permanent DPS cap holds for "+id+" / "+trait_id)
	var previous_level_gain: float=progress.config.damage_per_level
	progress.config.damage_per_level=1.0
	var exaggerated: Dictionary=progress.apply_definition(game.catalog.definition("weapons","ar"))
	check(dps(exaggerated)/dps(game.catalog.definition("weapons","ar"))<=1.30001,"Hard cap still holds when tuning exceeds its budget")
	progress.config.damage_per_level=previous_level_gain
	game.save_manager.profile.weapons.ar.level=1
	game.save_manager.profile.weapons.ar.stars=1
	game.save_manager.profile.weapons.ar.trait=""
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	progress.save_callback=func() -> bool:return false
	check(not progress.level_up("ar") and game.save_manager.profile==before,"Persistence failure rolls back the entire upgrade transaction")
	progress.save_callback=Callable()
	var legacy: Dictionary=game.save_manager.migrate({"highest_stage":3,"kills":99})
	check(legacy.schema_version==SaveManager.VERSION and legacy.weapons.shotgun.unlocked and legacy.loadout==["ar","shotgun"],"Legacy players keep their previously available Shotgun")
	game.save_manager.profile=SaveManager.fresh_profile()
	game.save_manager.profile.weapons.ar.level=2
	game.weapon_manager.loadout.assign(["ar","shotgun"])
	game.catalog.tables.weapons.ar.crit_chance=0
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	game.player.aim_point=Vector3(0,1.1,0)
	var enemy=game.spawn_enemy(Vector3.ZERO)
	enemy.hp=1000
	for i in 3:
		await get_tree().physics_frame
	game.player.shoot()
	check(is_equal_approx(1000-enemy.hp,24.36),"Weapon level changes actual in-run bullet damage")
	game.catalog.tables.weapons.ar.crit_chance=.1
	var failed: Array=results.filter(func(c):return not c.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size()}
	var file := FileAccess.open("res://artifacts/progression-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("PROGRESSION_COMPLETE "+str(report.passed)+"/"+str(results.size()))
	game.shutdown(0 if failed.is_empty() else 1)
