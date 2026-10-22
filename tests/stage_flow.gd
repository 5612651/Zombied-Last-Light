extends Node

var game: Node3D
var results: Array = []

func check(condition: bool, label_: String) -> void:
	results.append({"test":label_,"passed":condition})
	print(("PASS " if condition else "FAIL ")+label_)

func wait_state(expected: String, timeout: float=4) -> bool:
	var until := Time.get_ticks_msec()+int(timeout*1000)
	while game.state!=expected and Time.get_ticks_msec()<until:
		await get_tree().physics_frame
	return game.state==expected

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func run(target: Node3D) -> void:
	game=target
	game.deploy()
	game.player.bot=true
	check(game.state=="stage_start" and not game.director.active,"Stage entry precedes enemy spawning")
	check(not game.stage_manager.advance(),"Exit cannot skip an incomplete objective")
	check(await wait_state("combat"),"Stage entry reaches combat after intro")
	game.director.active=false
	check(game.stage_manager.phase=="objective","Ordinary stage enters objective phase")
	var currency: int=game.save_manager.profile.wallet.supply
	game.clear_stage()
	check(game.state=="area_clear" and game.world.gate.collision_layer==1,"Area Clear keeps physical exit closed")
	check(not game.stage_manager.advance(),"Area Clear cannot bypass rewards")
	check(await wait_state("reward"),"Reward phase follows Area Clear")
	var reward: int=game.stage_manager.definition().reward.supply
	check(game.save_manager.profile.wallet.supply==currency+reward,"Stage reward is granted once")
	game.clear_stage()
	check(game.save_manager.profile.wallet.supply==currency+reward,"Repeated completion cannot duplicate reward")
	check(await wait_state("upgrade"),"Three-choice upgrade follows reward settlement")
	check(game.upgrade_choices.size()==3 and game.world.gate.collision_layer==1,"Exit remains closed while choosing upgrade")
	check(not game.rogue_manager.choose("unknown"),"Invalid choice cannot open exit")
	var id: String=game.upgrade_choices[0].id
	game.choose_perk(id)
	check(game.state=="cleared" and game.world.gate.collision_layer==0 and id in game.perks,"Valid choice opens gate and retains build")
	var phases: Array=game.stage_manager.history.map(func(e):return e.phase)
	check(phases.slice(-7)==["start","combat","objective","area_clear","reward","upgrade","exit"],"Stage lifecycle records the required phase order")
	await frames(85)
	game.player.hp=70
	game.player.weapon=1
	game.player.magazines[1]=5
	game.player.reserve[1]=50
	game.player.position=Vector3(0,.05,-12)
	game.player.test_motion=Vector3.FORWARD
	var old_world: WeakRef=weakref(game.world)
	check(await wait_state("transition"),"Walking through the open gate starts transition")
	check(not game.stage_manager.advance(),"Repeated exit triggers cannot skip a sector")
	check(await wait_state("stage_start"),"Transition builds and introduces next sector")
	await frames(2)
	check(old_world.get_ref()==null and game.stage==2,"Previous sector is unloaded and cannot be revisited")
	check(id in game.perks and game.player.weapon==1 and game.player.magazines[1]==5,"Weapon, loaded ammunition and build carry forward")
	check(game.player.hp==90 and game.player.reserve[1]==66,"Only authored resupply is applied between sectors")
	game.player.test_motion=Vector3.ZERO
	check(await wait_state("combat"),"Next sector resumes combat without a menu")
	game.director.active=false
	var resources: int=game.save_manager.profile.wallet.supply
	game.clear_stage()
	game.fail_run()
	check(game.state=="dead" and game.perks.is_empty(),"Death ends run and clears temporary upgrades")
	check(await wait_state("base"),"Death returns to the base preparation state")
	check(game.save_manager.profile.wallet.supply==resources and game.stage_manager.phase=="base","Cancelled reward coroutine cannot grant resources after death")
	game.deploy(true)
	game.director.active=false
	game.player.bot=true
	game.stage_manager.preview(game.stage_manager.stage_count())
	game.director.active=false
	check(game.stage_manager.phase=="boss_combat","Final sector enters explicit Boss phase")
	game.perks.append("pierce")
	game.clear_stage()
	check(await wait_state("cleared"),"Final stage settles rewards and opens extraction without a redundant upgrade")
	game.next_stage()
	check(game.state=="victory" and game.perks.is_empty() and not game.run_manager.active,"Extraction completes chapter and clears build")
	check(await wait_state("base"),"Chapter Clear returns to base")
	game.deploy(true)
	game.director.active=false
	var old_run: String=game.run_manager.run_id
	game.fail_run()
	game.deploy(true)
	game.director.active=false
	await frames(125)
	check(game.run_manager.run_id!=old_run and game.state=="combat" and game.run_manager.active,"Old death callback cannot interrupt a newly deployed run")
	var failed: Array=results.filter(func(e):return not e.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"history":game.stage_manager.history}
	var file := FileAccess.open("res://artifacts/stage-flow-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("FLOW_COMPLETE "+str(report.passed)+"/"+str(results.size()))
	game.shutdown(0 if failed.is_empty() else 1)
