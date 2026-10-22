extends Node

var game: Node3D
var results: Array = []

func check(condition: bool, label_: String) -> void:
	results.append({"test":label_,"passed":condition})
	print(("PASS " if condition else "FAIL ")+label_)

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func reset(ids: Array=[]) -> void:
	game.enemy_manager.clear()
	game.fx.clear_transients()
	game.rogue_manager.reset()
	game.perks.assign(ids)
	game.weapon_manager.reset()
	game.director.active=false
	game.player.position=Vector3(0,.05,5)
	game.player.bot=true
	game.player.bot_fire=false
	game.player.test_motion=Vector3.ZERO
	game.player.hp=100
	game.player.armor=0
	game.player.invulnerability=0
	game.player.shot_timer=0
	game.player.reload_timer=0
	game.player.dash_timer=0
	game.player.dash_cooldown=0
	game.player.boost=0
	await frames(2)

func tank(pos: Vector3=Vector3.ZERO) -> CharacterBody3D:
	var actor: CharacterBody3D=game.spawn_enemy(pos)
	actor.max_hp=1000
	actor.hp=1000
	return actor

func body_ray(actor: Node3D, damage: float=10, distance: float=5) -> void:
	var origin := Vector3(actor.position.x,1.1,actor.position.z+distance)
	game.player.fire_ray(origin,Vector3.FORWARD,damage,0)

func run(target: Node3D) -> void:
	game=target
	game.deploy(true,"prototype")
	game.director.active=false
	game.catalog.tables.weapons.ar.crit_chance=0
	game.catalog.tables.weapons.shotgun.crit_chance=0
	check(game.PERKS.size()==30,"Thirty Perk definitions are available")
	# Compare the event snapshot with the original scalar calculation across every
	# authored effect, including duplicated entries and live definition changes.
	game.perks.assign(game.catalog.tables.perks.keys())
	game.perks.append("burn")
	game.perks.append("unknown_fixture")
	var effects: Dictionary=game.rogue_manager.effect_totals()
	var all_equal := true
	for effect in effects:
		all_equal=all_equal and is_equal_approx(float(effects[effect]),game.rogue_manager.value(effect))
	check(all_equal,"Event effect snapshot matches scalar totals for all authored effects, stacks and unknown IDs")
	var authored: Dictionary=game.catalog.tables.perks.burn.effects
	var original: float=authored.burn_duration
	authored.burn_duration=original+1
	var changed: Dictionary=game.rogue_manager.effect_totals()
	check(is_equal_approx(float(changed.burn_duration),game.rogue_manager.value("burn_duration")) and not is_equal_approx(float(changed.burn_duration),float(effects.burn_duration)),"Next event observes live definition changes without stale cached totals")
	authored.burn_duration=original
	game.perks.clear()
	check(game.rogue_manager.effect_totals().is_empty(),"Cleared build has no residual event modifiers")
	for family in ["ballistic","shotgun","fire","electric","explosion","survival"]:
		check(game.PERKS.filter(func(p):return p.family==family).size()==5,"Five distinct Perks in "+family)
	check(not game.rogue_manager.eligible(game.catalog.definition("perks","fire_damage")),"Dependent fire upgrades are withheld without ignition")
	game.perks.append("burn")
	check(game.rogue_manager.eligible(game.catalog.definition("perks","fire_damage")),"Ignition unlocks fire build progression")
	check(not game.rogue_manager.eligible(game.catalog.definition("perks","burn")),"Already owned nonstacking Perks are withheld")
	await reset(["ricochet"])
	var arc_source=tank(Vector3(0,.05,0))
	var arc_neighbor=tank(Vector3(1.5,.05,0))
	await frames(2)
	game.player.fire_ray(arc_source.position+Vector3(0,1.65,3),Vector3.FORWARD,10,0)
	check(is_equal_approx(arc_neighbor.hp,993.5),"Critical ricochet applies its authored sixty-five-percent secondary damage")
	await reset(["heavy_rounds","deadeye"])
	var p=game.player
	var target_body=tank()
	await frames(2)
	p.aim_point=target_body.position+Vector3(0,1.1,0)
	# Remove critical chance only for this damage multiplier sample.
	game.perks.erase("deadeye")
	p.shoot()
	check(is_equal_approx(1000-target_body.hp,28.8),"Heavy rounds alter actual AR damage by twenty percent")
	game.perks.append("deadeye")
	check(is_equal_approx(game.rogue_manager.value("crit_chance"),.15),"Deadeye supplies critical chance modifier")
	await reset(["impact_sg","close_sg"])
	p.weapon=1
	var close=tank()
	await frames(2)
	body_ray(close)
	check(is_equal_approx(1000-close.hp,14),"Point-blank Shotgun multiplier changes close hit damage")
	check(close.knockback.length()>13.9,"Breacher changes actual Shotgun impact force")
	close.hp=1000
	body_ray(close,10,9)
	check(is_equal_approx(1000-close.hp,10),"Point-blank modifier does not apply at long range")
	await reset(["reload_sg","speed_sg"])
	p.weapon=1
	p.magazines[1]=0
	p.reload()
	check(is_equal_approx(p.reload_duration,1.26),"Quick Rack reduces actual reload duration")
	p.reload_timer=0
	p.magazines[1]=8
	p.aim_point=Vector3(0,1,-3)
	p.shoot()
	check(is_equal_approx(p.shot_timer,.78/1.25),"Rapid Pump changes the Shotgun firing interval")
	await reset(["burn","fire_damage","fire_linger"])
	var burning=tank()
	await frames(2)
	body_ray(burning)
	check(is_equal_approx(burning.burn_time,5),"Slow Burn extends ignition to five seconds")
	var after_hit: float=burning.hp
	burning.burn_tick=0
	burning._physics_process(.01)
	check(is_equal_approx(after_hit-burning.hp,12),"Thermite increases a burning tick to twelve damage")
	await reset(["burn","fire_spread"])
	var source=tank(Vector3(0,.05,0))
	var neighbor=tank(Vector3(2,.05,0))
	source.burn_time=2
	source.take_damage(2000,Vector3.ZERO)
	check(neighbor.burn_time>=3,"Burning kill spreads ignition to a nearby infected")
	await reset(["burn","fire_reload"])
	var heated=tank(Vector3(1,.05,3))
	p.magazines[0]=0
	p.reload()
	check(heated.burn_time>=3,"Vent Heat ignites nearby infected on reload")
	await reset(["lightning","conductor","overload"])
	var chain: Array=[]
	for x in [0,1.5,3,4.5,6]:
		chain.append(tank(Vector3(x,.05,2)))
	await frames(2)
	game.catalog.tables.perks.lightning.effects.electric_chance=1
	body_ray(chain[0],1,2)
	game.catalog.tables.perks.lightning.effects.electric_chance=.25
	check(chain.slice(1).all(func(e):return is_equal_approx(e.hp,968)),"Chain Arc, Conductor and Overload hit four secondary targets")
	check(chain.slice(1).all(func(e):return e.stun_time>0),"Electric arcs stun affected infected")
	var held: Vector3=chain[1].position
	await frames(8)
	check(Vector2(chain[1].position.x-held.x,chain[1].position.z-held.z).length()<.05,"Stunned infected stop advancing")
	await reset(["static_dash"])
	var shocked=tank(Vector3(0,.05,3))
	await frames(2)
	p.dash()
	check(shocked.hp==976 and shocked.stun_time>1,"Static Step applies actual arc damage and stun")
	await reset(["head_blast","blast_radius","blast_damage"])
	var blast=tank(Vector3(2.7,.05,0))
	game.rogue_manager.explosion(Vector3.ZERO,2,10)
	check(is_equal_approx(blast.hp,986),"Explosion upgrades increase both radius and damage")
	await reset(["death_blast"])
	game.catalog.tables.perks.death_blast.effects.death_blast_chance=1
	var doomed=tank(Vector3(0,.05,0))
	var nearby=tank(Vector3(1.5,.05,0))
	doomed.take_damage(2000,Vector3.ZERO)
	game.catalog.tables.perks.death_blast.effects.death_blast_chance=.25
	check(nearby.hp==965,"Deadman Switch produces kill-triggered blast damage")
	await reset(["crit_blast"])
	game.catalog.tables.perks.crit_blast.effects.crit_blast_chance=1
	var critical_target=tank(Vector3(0,.05,0))
	var collateral=tank(Vector3(1.5,.05,0))
	await frames(2)
	p.fire_ray(critical_target.position+Vector3(0,1.65,3),Vector3.FORWARD,1,0)
	game.catalog.tables.perks.crit_blast.effects.crit_blast_chance=.3
	check(collateral.hp==975,"Volatile Shot produces critical-triggered blast damage")
	await reset()
	game.rogue_manager.offer()
	game.rogue_manager.choices=[game.catalog.definition("perks","armor")]
	game.rogue_manager.choose("armor")
	game.director.active=false
	check(p.armor==30,"Picking Field Armor grants its protective pool")
	p.take_damage(20)
	check(p.armor==10 and p.hp==100,"Armor absorbs damage before health")
	p.invulnerability=0
	p.take_damage(20)
	check(p.armor==0 and p.hp==90,"Excess incoming damage passes through depleted armor")
	await reset(["dash_cd"])
	p.dash()
	check(is_equal_approx(p.dash_cooldown,1.2),"Light Feet reduces actual Dash cooldown")
	game.catalog.tables.weapons.ar.crit_chance=.1
	game.catalog.tables.weapons.shotgun.crit_chance=.1
	var failed: Array=results.filter(func(c):return not c.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size()}
	var file := FileAccess.open("res://artifacts/perks-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("PERKS_COMPLETE "+str(report.passed)+"/"+str(results.size()))
	game.shutdown(0 if failed.is_empty() else 1)
