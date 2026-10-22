extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	var save:=SaveManager.new()
	add_child(save)
	for version in [1,2,3,4]:
		var old: Dictionary=SaveManager.fresh_profile()
		old.schema_version=version
		old.weapons.shotgun.unlocked=true
		old.wallet.supply=173
		old.weapons.ar.level=4
		old.research.salvage=2
		old.achievements.custom={"progress":7,"target":10,"unlocked":false}
		old["extension_from_mod"]={"value":"preserve"}
		if version<3:
			old.erase("loadout")
			old.erase("trait_inventory")
		if version<4:
			old.erase("crates")
		var migrated: Dictionary=save.migrate(old)
		check(not migrated.is_empty() and migrated.schema_version==SaveManager.VERSION and migrated.wallet.supply==173 and migrated.weapons.ar.level==4 and migrated.research.salvage==2 and migrated.achievements.custom.progress==7 and migrated.extension_from_mod.value=="preserve","Version %d migration preserves progression and unknown extensions" % version)
		if version<3:
			check(migrated.loadout==["ar","shotgun"],"Version %d keeps the formerly available Shotgun in loadout" % version)
		check(save.migrate(migrated)==migrated,"Version %d migration is idempotent" % version)
	var malformed: Dictionary=SaveManager.fresh_profile()
	malformed.loadout=["ar","ar"]
	check(not save.validate(malformed),"Duplicated loadout weapons are rejected")
	malformed=SaveManager.fresh_profile()
	malformed.loadout=["shotgun"]
	check(not save.validate(malformed),"Locked loadout weapons are rejected")
	malformed=SaveManager.fresh_profile()
	malformed.settings.master="broken"
	check(not save.validate(malformed),"Nonnumeric audio setting is rejected")
	malformed=SaveManager.fresh_profile()
	malformed.settings.slow_motion=1
	check(not save.validate(malformed),"Nonboolean gameplay setting is rejected")
	malformed=SaveManager.fresh_profile()
	malformed.settings.resolution=[1280,-2]
	check(not save.validate(malformed),"Invalid screen dimension is rejected")
	malformed=SaveManager.fresh_profile()
	malformed.records.stages.street={"time":-1}
	check(not save.validate(malformed),"Invalid stage metric is rejected")
	malformed=SaveManager.fresh_profile()
	malformed.schema_version="4"
	check(save.migrate(malformed).is_empty(),"Text schema version is rejected")
	save.profile=SaveManager.fresh_profile()
	var first := {"time":100.0,"kills":10,"damage_taken":20.0,"optional_objective":false}
	var second := {"time":120.0,"kills":15,"damage_taken":10.0,"optional_objective":true}
	save.award_stage("first","street",{"supply":40},first)
	save.award_stage("second","street",{"supply":40},second)
	var record: Dictionary=save.profile.records.stages.street
	check(record.clears==2 and record.time==100 and record.kills==15 and record.damage_taken==10 and record.optional_objective and record.last.time==120,"Stage history preserves independent best metrics and the last result")
	check(not save.award_stage("second","street",{"supply":40},second) and record.clears==2,"Reward deduplication also prevents duplicate clear records")
	game.save_manager.profile=SaveManager.fresh_profile()
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	game.player.invulnerability=0
	game.player.armor=8
	game.player.take_damage(12)
	check(game.stage_manager.damage_taken==12 and game.player.hp==96,"Live stage tracks health and armor damage once")
	game.player.take_damage(12)
	check(game.stage_manager.damage_taken==12,"Invulnerable duplicate hit does not increase damage records")
	var enemy=game.spawn_enemy(Vector3.ZERO)
	enemy.take_damage(1000,Vector3.FORWARD)
	check(game.save_manager.profile.achievements.infected_100.progress==1,"Live enemy kill advances permanent achievement progress")
	await get_tree().process_frame
	await get_tree().process_frame
	var before_reward: Dictionary=game.save_manager.profile.duplicate(true)
	game.stage_manager.reward_save_callback=func():return false
	game.clear_stage()
	var until: int=Time.get_ticks_msec()+2500
	while not game.stage_manager.reward_failed and Time.get_ticks_msec()<until:
		await get_tree().process_frame
	check(game.stage_manager.reward_failed and game.state=="reward" and game.save_manager.profile==before_reward and not game.world.gate.collision_layer==0,"Failed stage save rolls back rewards and records and holds the exit closed")
	game.stage_manager.reward_save_callback=Callable()
	check(game.stage_manager.retry_reward(),"Failed settlement exposes a recoverable retry")
	check(not game.stage_manager.retry_reward(),"Repeated retry cannot duplicate an accepted settlement")
	until=Time.get_ticks_msec()+2000
	while game.state!="upgrade" and Time.get_ticks_msec()<until:
		await get_tree().process_frame
	var actual: Dictionary=game.save_manager.profile.records.stages.get("street",{})
	check(not actual.is_empty() and actual.kills==1 and actual.damage_taken==12 and actual.time>0 and game.save_manager.profile.achievements.first_stage.unlocked,"Actual stage settlement saves elapsed time, kills, damage and first-clear achievement")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size()}
	var file:=FileAccess.open("res://artifacts/save-integrity-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("SAVE_INTEGRITY_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
