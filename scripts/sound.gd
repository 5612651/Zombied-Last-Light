class_name AudioManager
extends Node

var game: Node3D
var clips: Dictionary={}
var voices: Array[AudioStreamPlayer]=[]
var environment_voices: Dictionary={}
var music_voices: Array[AudioStreamPlayer]=[]
var music_targets: Array[float]=[0,0,0]
var base_pitches: Dictionary={}
var index := 0
var stopping := false
var crowd_timer := 1.5
var previous_mode := ""
var slow_active := false
var rng:=RandomNumberGenerator.new()
var played: Dictionary={}

func _ready() -> void:
	rng.randomize()
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio_manifest.json"))
	for item in manifest.items: clips[item.id]=load(item.path)
	for bus in ["SFX","Music","Ambience","UI"]:
		if AudioServer.get_bus_index(bus)<0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count-1,bus)
			AudioServer.set_bus_send(AudioServer.bus_count-1,"Master")
	if AudioServer.get_bus_effect_count(0)==0: AudioServer.add_bus_effect(0,AudioEffectLimiter.new())
	for i in 32:
		var voice:=AudioStreamPlayer.new()
		voice.bus="SFX"
		add_child(voice)
		voices.append(voice)
	for id in ["rain","ambience","indoor_room"]:
		var voice:=loop_player(id,"Ambience")
		voice.volume_db=-80
		environment_voices[id]=voice
	for id in ["music_safe","music_combat","music_boss"]:
		var voice:=loop_player(id,"Music")
		voice.volume_db=-80
		music_voices.append(voice)
	apply_settings()

func loop_player(id: String, bus: String) -> AudioStreamPlayer:
	var voice:=AudioStreamPlayer.new()
	voice.bus=bus
	var clip: AudioStreamOggVorbis=clips[id]
	clip.loop=true
	voice.stream=clip
	add_child(voice)
	return voice

func fade_loop(voice: AudioStreamPlayer, target: float, delta: float, rate: float) -> void:
	if target>-75 and not voice.playing: voice.play()
	voice.volume_db=move_toward(voice.volume_db,target,delta*rate)
	if target<=-75 and voice.volume_db<=-75 and voice.playing: voice.stop()

func play(id: String, volume: float=-8, pitch: float=1.0) -> void:
	if stopping or not clips.has(id): return
	var voice: AudioStreamPlayer=voices[index%voices.size()]
	index+=1
	voice.stop()
	voice.stream=clips[id]
	voice.bus="UI" if id=="upgrade" else "SFX"
	voice.volume_db=clampf(volume,-60,0)
	var varied: float=pitch*rng.randf_range(.96,1.04)
	base_pitches[voice.get_instance_id()]=varied
	voice.pitch_scale=varied
	voice.play()
	played[id]=int(played.get(id,0))+1

func play_at(id: String, point: Vector3, volume: float=-14, pitch: float=1) -> void:
	if not is_instance_valid(game.player): return
	var distance: float=game.player.global_position.distance_to(point)
	if distance>24: return
	play(id,volume-minf(18,distance*.55),pitch)

func apply_settings() -> void:
	if not is_instance_valid(game): return
	var settings: Dictionary=game.save_manager.profile.settings
	for bus in ["Master","Music","SFX","Ambience","UI"]:
		var value: float=float(settings.master if bus=="Master" else (settings.music if bus=="Music" else settings.sfx))
		var bus_index: int=AudioServer.get_bus_index(bus)
		AudioServer.set_bus_mute(bus_index,value<=0)
		AudioServer.set_bus_volume_db(bus_index,linear_to_db(maxf(.0001,clampf(value,0,1))))

func _process(delta: float) -> void:
	if stopping or not is_instance_valid(game) or not is_instance_valid(game.player): return
	var mode := "safe" if game.state in ["base","dead","victory"] else "combat"
	if game.enemies.any(func(enemy):return is_instance_valid(enemy) and enemy.boss and not enemy.dead): mode="boss"
	if mode!=previous_mode:
		music_targets=[.8 if mode=="safe" else 0,.8 if mode=="combat" else 0,.85 if mode=="boss" else 0]
		if mode=="boss": play("boss_warning",-8)
		previous_mode=mode
	for i in music_voices.size():
		var target: float=linear_to_db(maxf(.0001,float(music_targets[i])))-15
		fade_loop(music_voices[i],target,delta,24)
	var combat: bool=game.state not in ["base","dead","victory"]
	var indoor: bool=is_instance_valid(game.world) and game.world.indoor
	for id in environment_voices:
		var target := -80.0
		if id=="rain" and combat and not indoor: target=-15
		if id=="ambience": target=-14 if combat else -23
		if id=="indoor_room" and combat and indoor: target=-10
		fade_loop(environment_voices[id],target,delta,30)
	var slow: bool=Engine.time_scale<.9 and combat
	if slow and not slow_active: play("slow_motion",-18)
	slow_active=slow
	for voice in voices:
		if voice.playing:
			voice.pitch_scale=float(base_pitches.get(voice.get_instance_id(),1))*(.72 if slow and voice.bus=="SFX" else 1)
		elif voice.stream!=null:
			voice.stream=null
	crowd_timer-=delta
	if crowd_timer<=0 and game.state=="combat" and not game.paused and not game.enemies.is_empty():
		crowd_timer=rng.randf_range(1.3,2.5)
		for i in mini(2,game.enemies.size()):
			var enemy: Node3D=game.enemies[rng.randi_range(0,game.enemies.size()-1)]
			var id: String="heavy_growl" if enemy.elite or enemy.boss else ("runner_yelp" if enemy.definition.behavior=="runner" else "infected_"+str(rng.randi_range(1,3)))
			play_at(id,enemy.position,-16)

func stop_all() -> void:
	stopping=true
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream=null

func _exit_tree() -> void:
	stop_all()
	clips.clear()
