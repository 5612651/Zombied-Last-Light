extends Node

var results: Array=[]
func check(condition: bool, title: String) -> void:
	results.append({"test":title,"passed":condition})
	print(("PASS " if condition else "FAIL ")+title)

func run(game: Node3D) -> void:
	game.save_manager.profile=SaveManager.fresh_profile()
	var sound=game.sound
	check(sound.clips.size()==30,"Manifest loads all 30 original audio assets")
	check(sound.clips.values().all(func(clip):return clip is AudioStreamOggVorbis and clip.get_length()>0),"Runtime clips decode as non-empty Ogg streams")
	check(sound.music_voices.size()==3 and sound.music_voices.all(func(voice):return voice.stream.loop and voice.stream.get_length()>=30),"Safehouse, horde and Boss music are authored as looping tracks")
	check(["Master","SFX","Music","Ambience","UI"].all(func(bus):return AudioServer.get_bus_index(bus)>=0),"Independent mixing buses are available")
	check(AudioServer.get_bus_effect_count(0)>0 and AudioServer.get_bus_effect(0,0) is AudioEffectLimiter,"Master limiter bounds layered output")
	var settings: Dictionary=game.save_manager.profile.settings
	settings.master=.5
	settings.music=.3
	settings.sfx=.6
	sound.apply_settings()
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)),.5) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))),.3),"Master and music gains use their independent saved controls")
	settings.sfx=0
	sound.apply_settings()
	check(["SFX","Ambience","UI"].all(func(bus):return AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))),"Zero effects gain mutes effects, environment and UI")
	settings.sfx=1
	sound.apply_settings()
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),"Raising effects gain restores the bus")
	sound._process(4)
	check(sound.previous_mode=="safe" and sound.music_voices[0].playing and not sound.music_voices[1].playing and not sound.music_voices[2].playing,"Safehouse starts its own track without decoding inactive combat music")
	game.deploy(true,"prototype")
	game.director.active=false
	game.player.bot=true
	sound._process(4)
	check(sound.previous_mode=="combat" and sound.music_voices[1].playing and not sound.music_voices[0].playing,"Deployment crossfades from safehouse into horde music")
	check(sound.environment_voices.rain.playing and not sound.environment_voices.indoor_room.playing,"Outdoor battle uses rain without the indoor layer")
	game.world.indoor=true
	sound._process(4)
	check(not sound.environment_voices.rain.playing and sound.environment_voices.indoor_room.playing,"Indoor transition fades out rain and starts room tone")
	var elite=game.spawn_enemy(game.player.position+Vector3.RIGHT*4,true,false,"elite_runner")
	check(int(sound.played.get("elite_warning",0))>0,"Real elite spawn issues an audible proximity warning")
	elite.set_physics_process(false)
	var boss=game.spawn_enemy(game.player.position+Vector3.FORWARD*8,false,false,"chapter_warden")
	boss.set_physics_process(false)
	sound._process(4)
	check(sound.previous_mode=="boss" and sound.music_voices[2].playing and int(sound.played.get("boss_warning",0))>0,"Real Boss presence selects Boss music and its entry warning")
	var before: int=sound.index
	sound.play_at("infected_1",game.player.position+Vector3.RIGHT*100)
	check(sound.index==before,"Distant infected voices are culled")
	sound.crowd_timer=0
	sound._process(.01)
	check(sound.index>before and sound.index<=before+2,"Crowd voice scheduler emits a bounded nearby group")
	sound.play("ar_crack")
	var voice: AudioStreamPlayer=sound.voices[(sound.index-1)%sound.voices.size()]
	var pitch: float=sound.base_pitches[voice.get_instance_id()]
	Engine.time_scale=.5
	sound._process(.01)
	check(int(sound.played.get("slow_motion",0))>0 and is_equal_approx(voice.pitch_scale,pitch*.72),"Slow motion cues audio and lowers active weapon pitch")
	Engine.time_scale=1
	sound._process(.01)
	check(is_equal_approx(voice.pitch_scale,pitch),"Weapon pitch restores after slow motion")
	game.feedback_manager.route("elite_kill",elite.position)
	check(int(sound.played.get("kill_stinger",0))>0,"Actual elite feedback triggers a kill stinger")
	for i in 100: sound.play("impact")
	check(sound.voices.size()==32 and sound.get_child_count()==38,"Repeated impacts reuse bounded voices and music/environment players")
	sound.stop_all()
	check(sound.get_children().all(func(child):return not child.playing and child.stream==null),"Shutdown explicitly detaches all active playback streams")
	before=sound.index
	sound.play("ar_crack")
	check(sound.index==before,"Stopped manager cannot enqueue late playback")
	var failed: Array=results.filter(func(item):return not item.passed)
	var report := {"checks":results,"passed":results.size()-failed.size(),"failed":failed.size(),"audio_driver":AudioServer.get_driver_name(),"scope":"Runtime routing, transitions, assets and pool bounds; timbre and perceived mix require human listening."}
	var file:=FileAccess.open("res://artifacts/audio-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("AUDIO_COMPLETE %d/%d driver=%s" % [report.passed,results.size(),report.audio_driver])
	game.shutdown(0 if failed.is_empty() else 1)
