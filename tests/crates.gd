extends Node

var game: Node3D
var results: Array=[]

func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(target: Node3D) -> void:
	game=target
	var crates=game.crate_manager
	game.save_manager.profile=SaveManager.fresh_profile()
	var profile: Dictionary=game.save_manager.profile
	var before: Dictionary=profile.duplicate(true)
	check(not crates.open_crate() and profile==before,"Insufficient supplies leave profile unchanged")
	profile.wallet.supply=1000
	game.state="stage_start"
	check(not crates.open_crate() and profile.wallet.supply==1000,"Crates cannot be opened during a run")
	game.state="base"
	crates.busy=true
	check(not crates.open_crate(),"Reentrant crate opening is rejected")
	crates.busy=false
	var weights: Dictionary=crates.config.weights.duplicate()
	crates.config.weights={"blueprints":1}
	var total := 0
	for weapon in profile.weapons.values(): total+=int(weapon.blueprints)
	check(crates.open_crate() and profile.wallet.supply==940 and profile.crates.opened==1 and profile.crates.since_rare==1,"One crate deducts exact cost and advances pity")
	var updated := 0
	for weapon in profile.weapons.values(): updated+=int(weapon.blueprints)
	check(updated==total+12,"Blueprint reward increases exactly one weapon fragment balance")
	profile.crates.since_rare=9
	check(crates.open_crate() and crates.last_reward.kind=="weapon" and profile.weapons[crates.last_reward.id].unlocked and crates.last_reward.pity and profile.crates.since_rare==0,"Tenth crate guarantees a rare and prioritizes a locked weapon")
	for weapon in profile.weapons.values(): weapon.unlocked=true
	profile.crates.since_rare=9
	check(crates.open_crate() and crates.last_reward.kind=="trait" and profile.crates.since_rare==0,"Pity grants a rare trait when all weapons are owned")
	var id: String=crates.last_reward.id
	var money: int=profile.wallet.supply
	crates.apply_reward({"kind":"trait","id":id,"title":"Test trait"})
	check(profile.trait_inventory[id]==1 and profile.wallet.supply==money+35,"Stored duplicate trait converts to supplies without duplication")
	profile.trait_inventory[id]=0
	profile.weapons.ar.trait=id
	money=profile.wallet.supply
	crates.apply_reward({"kind":"trait","id":id,"title":"Test trait"})
	check(profile.trait_inventory[id]==0 and profile.wallet.supply==money+35,"Equipped duplicate trait also converts to supplies")
	total=profile.weapons.ar.blueprints
	crates.apply_reward({"kind":"weapon","id":"ar","title":"AR"})
	check(profile.weapons.ar.blueprints==total+25,"Owned weapon converts to 25 matching blueprints")
	crates.config.weights={"supply":1}
	profile.crates.since_rare=0
	money=profile.wallet.supply
	check(crates.open_crate() and profile.wallet.supply==money-60+25,"Supply reward is netted against the crate cost")
	before=profile.duplicate(true)
	var previous_reward: Dictionary=crates.last_reward.duplicate(true)
	crates.save_callback=func():return false
	check(not crates.open_crate() and game.save_manager.profile==before and crates.last_reward==previous_reward,"Failed persistence restores wallet, reward, ownership and pity")
	crates.save_callback=Callable()
	profile=game.save_manager.profile
	crates.config.weights=weights
	crates.rng.seed=77117
	var observed: Dictionary={}
	for i in 1000:
		observed[crates.choose_kind()]=true
	check(observed.size()==4,"Seeded base distribution reaches all four reward categories")
	var saver:=SaveManager.new()
	add_child(saver)
	var old: Dictionary=SaveManager.fresh_profile()
	old.schema_version=3
	old.erase("crates")
	old.wallet.supply=173
	var migrated: Dictionary=saver.migrate(old)
	check(not migrated.is_empty() and migrated.schema_version==4 and migrated.wallet.supply==173 and migrated.crates.opened==0,"Version 3 migrates without changing wallet or progression")
	var invalid: Dictionary=profile.duplicate(true)
	invalid.crates.since_rare=-1
	check(not saver.validate(invalid),"Invalid negative pity counter is rejected")
	invalid=profile.duplicate(true)
	invalid.trait_inventory={"precision":-1}
	check(not saver.validate(invalid),"Invalid trait inventory is rejected")
	saver.profile=profile.duplicate(true)
	var path: String="user://crate-test-"+str(Time.get_ticks_usec())+".json"
	check(saver.save_profile(path),"Reward and pity persist together to disk")
	var restored:=SaveManager.new()
	add_child(restored)
	var loaded: bool=restored.load_profile(path)
	# JSON numbers are decoded as floats; compare against a JSON-normalized copy.
	var normalized: Dictionary=JSON.parse_string(JSON.stringify(profile))
	check(loaded and restored.profile==normalized,"Reload retains exact crate history, wallet, traits and fragments")
	DirAccess.remove_absolute(path)
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size()}
	var file:=FileAccess.open("res://artifacts/crates-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("CRATES_COMPLETE %d/%d" % [report.passed,results.size()])
	game.shutdown(0 if failed.is_empty() else 1)
