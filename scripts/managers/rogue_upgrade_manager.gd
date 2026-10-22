class_name RogueUpgradeManager
extends Node

signal selected(id: String)
var game: Node3D
var active: Array[String] = []
var choices: Array = []
var context := "field"
var proc_ready_at := 0

func has(id: String) -> bool:
	return id in active

func value(effect: String, base: float=0.0) -> float:
	var profile_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	var total := base
	for id in active:
		var definition: Dictionary=game.catalog.tables.perks.get(id,{})
		total+=float(definition.get("effects",{}).get(effect,0))
	if game.combat_profiler.enabled: game.combat_profiler.note("perk_values",profile_start)
	return total

func effect_totals() -> Dictionary:
	# A local snapshot for a single event, not a persistent cache: changes to the
	# active array or authored definitions take effect on the very next event.
	var profile_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	var totals: Dictionary={}
	for id in active:
		var effects: Dictionary=game.catalog.tables.perks.get(id,{}).get("effects",{})
		for effect in effects:
			totals[effect]=float(totals.get(effect,0))+float(effects[effect])
	if game.combat_profiler.enabled: game.combat_profiler.note("perk_batch_values",profile_start)
	return totals

func reset() -> void:
	game.mutation_manager.reset()
	active.clear()
	choices.clear()
	proc_ready_at=0

func eligible(perk: Dictionary) -> bool:
	if active.count(perk.id)>=int(perk.max_stacks):
		return false
	var required: Array=perk.get("requires_any",[])
	return required.is_empty() or required.any(func(id):return id in active)

func offer(reason: String="field") -> void:
	context=reason
	game.state="upgrade"
	var available: Array=game.catalog.items("perks").filter(eligible)
	available.shuffle()
	choices=available.slice(0,3)
	game.sound.play("upgrade",-10)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if choices.is_empty():
		resume()

func choose(id: String) -> bool:
	if game.state!="upgrade" or not choices.any(func(p):return p.id==id):
		return false
	active.append(id)
	var definition: Dictionary=game.catalog.definition("perks",id)
	game.player.armor=minf(value("armor_max"),game.player.armor+float(definition.effects.get("grant_armor",0)))
	game.player.hp=minf(game.player.max_hp,game.player.hp+20)
	game.weapon_manager.grant_supply("perk_resupply")
	selected.emit(id)
	resume()
	return true

func resume() -> void:
	choices.clear()
	if game.mutation_manager.offer_available(context):
		return
	if context=="stage_reward":
		game.stage_manager.open_exit()
	elif context=="objective_checkpoint":
		game.objective.advance_mission()
	else:
		game.state="combat"
		Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
		game.director.next_wave()

func explosion(pos: Vector3, radius: float, damage: float, excluded: Node=null, force: float=5) -> void:
	game.area_blast(pos,radius*(1+value("blast_radius_mult")),damage*(1+value("blast_damage_mult")),force,excluded)
	game.feedback_manager.route("detonation",pos)

func on_kill(enemy: Node3D, headshot: bool) -> void:
	var profile_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	var effects: Dictionary=effect_totals()
	game.player.hp=minf(game.player.max_hp,game.player.hp+float(effects.get("heal_on_kill",0)))
	if float(effects.get("kill_speed_duration",0))>0:
		game.player.boost=float(effects.kill_speed_duration)
	if headshot and float(effects.get("head_blast_damage",0))>0:
		explosion(enemy.position,float(effects.get("head_blast_radius",0)),float(effects.head_blast_damage),enemy,float(effects.get("head_blast_force",0)))
	if float(effects.get("death_blast_chance",0))>0 and randf()<float(effects.death_blast_chance):
		explosion(enemy.position,float(effects.get("death_blast_radius",0)),float(effects.get("death_blast_damage",0)),enemy)
	if enemy.burn_time>0 and float(effects.get("fire_spread_radius",0))>0:
		var spread_radius: float=float(effects.fire_spread_radius)
		var duration: float=float(effects.get("burn_duration",0))
		for other in game.enemies:
			if is_instance_valid(other) and not other.dead and other.position.distance_to(enemy.position)<spread_radius:
				other.burn_time=maxf(other.burn_time,duration)
				game.fx.tracer(enemy.position+Vector3.UP,other.position+Vector3.UP,Color("ef9e59"))
	if game.combat_profiler.enabled: game.combat_profiler.note("kill_effects_inclusive",profile_start)

func on_reload() -> void:
	if value("reload_wave_damage")>0:
		game.area_blast(game.player.position,value("reload_wave_radius"),value("reload_wave_damage"),value("reload_wave_force"))
		game.fx.shockwave(game.player.position)
	if value("fire_reload_radius")>0:
		var radius: float=value("fire_reload_radius")
		var duration: float=value("burn_duration")
		for enemy in game.enemies:
			if enemy.position.distance_to(game.player.position)<radius:
				enemy.burn_time=maxf(enemy.burn_time,duration)
				game.fx.debris(enemy.position+Vector3.UP,Vector3.UP,Color("ef9e59"),Vector3.ONE*.2,.4,0,3)

func on_dash() -> void:
	if value("dash_wave_damage")>0:
		game.area_blast(game.player.position,value("dash_wave_radius"),value("dash_wave_damage"),value("dash_wave_force"))
		game.fx.shockwave(game.player.position)
	if value("static_dash_damage")>0:
		electric_arc(game.player,value("static_dash_damage"),int(value("static_dash_targets")),value("static_dash_radius"),value("static_dash_stun"))

func on_weapon_hit(source: Node3D, critical: bool) -> void:
	if Time.get_ticks_msec()<proc_ready_at:
		return
	var triggered := false
	if value("electric_chance")>0 and randf()<value("electric_chance"):
		electric_arc(source,value("electric_damage"),int(value("electric_targets")),value("electric_radius"),value("electric_stun"))
		triggered=true
	if critical and value("crit_blast_chance")>0 and randf()<value("crit_blast_chance"):
		explosion(source.position,value("crit_blast_radius"),value("crit_blast_damage"),source)
		triggered=true
	if triggered:
		proc_ready_at=Time.get_ticks_msec()+60

func electric_arc(source: Node3D, damage: float, count: int, radius: float, stun: float) -> void:
	var visited: Array=[source]
	var origin: Vector3=source.global_position
	for i in mini(count,8):
		var chosen: Node3D
		var closest := radius
		for enemy in game.enemies:
			if not is_instance_valid(enemy) or enemy.dead or enemy in visited:
				continue
			var distance: float=origin.distance_to(enemy.position)
			if distance>=closest:
				continue
			var ray := PhysicsRayQueryParameters3D.create(origin+Vector3.UP,enemy.position+Vector3.UP,1|16)
			if not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			chosen=enemy
			closest=distance
		if chosen==null:
			break
		visited.append(chosen)
		game.fx.tracer(origin+Vector3.UP,chosen.position+Vector3.UP,Color("91d8ff"))
		chosen.stun_time=maxf(chosen.stun_time,minf(.3,stun) if chosen.boss else stun)
		origin=chosen.position
		chosen.take_damage(damage,Vector3.ZERO,false,false,0,"electric")
