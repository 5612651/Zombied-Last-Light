class_name DamageFeedbackManager
extends Node

signal event_received(kind: String, position: Vector3, priority: int)
var game: Node3D
var profiles: Dictionary={}
var ready_at: Dictionary={}
var counts: Dictionary={}
var applied: Dictionary={}
var history: Array=[]
var kill_times: Array[int]=[]
var hitstop_ready := 0
var cinematic_ready := 0
var priority_until := 0
var current_priority := 0

func _ready() -> void:
	profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/feedback.json"))

func reset() -> void:
	ready_at.clear()
	counts.clear()
	applied.clear()
	history.clear()
	kill_times.clear()
	hitstop_ready=0
	cinematic_ready=0
	priority_until=0
	current_priority=0
	game.frozen_until=0
	game.cinematic_until=0
	game.shake=0
	game.shot_kick=Vector3.ZERO
	game.hit_marker=0
	game.hit_critical=false
	game.hurt_overlay=0
	if is_instance_valid(game.screen_effects) and game.screen_effects.is_inside_tree():
		game.screen_effects.reset()

func route(kind: String, position: Vector3, direction: Vector3=Vector3.ZERO) -> bool:
	var profile_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	if not profiles.has(kind):
		return false
	var data: Dictionary=profiles[kind]
	var now := Time.get_ticks_msec()
	counts[kind]=int(counts.get(kind,0))+1
	history.append({"kind":kind,"position":position,"priority":int(data.priority)})
	if history.size()>64:
		history.pop_front()
	event_received.emit(kind,position,int(data.priority))
	if now<int(ready_at.get(kind,0)):
		if game.combat_profiler.enabled: game.combat_profiler.note("feedback_culled",profile_start)
		return false
	ready_at[kind]=now+int(data.cooldown_ms)
	applied[kind]=int(applied.get(kind,0))+1
	if now>=priority_until or int(data.priority)>=current_priority:
		current_priority=int(data.priority)
		priority_until=now+70
		game.camera_shake(float(data.shake))
		if int(data.hold_ms)>0 and (now>=hitstop_ready or int(data.priority)>=7):
			game.frozen_until=maxi(game.frozen_until,now+mini(40,int(data.hold_ms)))
			hitstop_ready=now+90
		if int(data.slow_ms)>0 and now>=cinematic_ready and game.save_manager.profile.settings.slow_motion:
			game.cinematic_until=now+mini(250,int(data.slow_ms))
			cinematic_ready=now+400
	game.sound.play(data.sound,float(data.volume))
	if kind in ["elite_kill","multi_kill"]: game.sound.play("kill_stinger",-13)
	match str(data.vfx):
		"blood", "blood_heavy": game.fx.blood(position,direction,data.vfx=="blood_heavy")
		"shockwave": game.fx.shockwave(position,Color(data.color))
		"sparks":
			for i in 3:
				game.fx.debris(position,Vector3.UP*2+direction,Color(data.color),Vector3.ONE*.07,.25,4,2)
	if game.combat_profiler.enabled: game.combat_profiler.note("feedback_applied",profile_start)
	return true

func hit(enemy: Node3D, amount: float, direction: Vector3, headshot: bool, critical: bool, source: String="bullet") -> void:
	var kind := "normal_hit"
	if source in ["fire","electric"]:
		kind="elemental"
	elif source=="explosion":
		kind="explosion"
	elif enemy.boss and headshot:
		kind="boss_weak"
		game.stage_manager.boss_weak_hits+=1
	elif headshot:
		kind="headshot"
	elif critical:
		kind="critical"
	enemy.flash_timer=.09 if critical or headshot else .065
	game.fx.number(enemy.position,amount,critical)
	game.hit_marker=.14
	game.hit_critical=critical
	route(kind,enemy.position+Vector3.UP*(1.5 if headshot else 1),direction)

func killed(enemy: Node3D) -> void:
	var profile_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	var now := Time.get_ticks_msec()
	var multi: bool=record_kill(now)
	route("elite_kill" if enemy.elite or enemy.boss else ("multi_kill" if multi else "kill"),enemy.position)
	if game.combat_profiler.enabled: game.combat_profiler.note("kill_feedback",profile_start)

func record_kill(now: int) -> bool:
	# Only the three newest timestamps can decide the >=3-within-1200ms rule.
	kill_times.append(now)
	while kill_times.size()>3 or (not kill_times.is_empty() and now-kill_times[0]>=1200):
		kill_times.pop_front()
	return kill_times.size()>=3

func weapon_fired(data: Dictionary) -> void:
	game.camera_shake(float(data.shake))
	game.shot_kick=-game.player.facing*minf(.15,float(data.recoil)*.42)
	game.sound.play(data.sound,float(data.volume))
	game.sound.play("weapon_mechanism",-20)

func player_hurt() -> void:
	game.hurt_overlay=.8
	route("player_hurt",game.player.position)
