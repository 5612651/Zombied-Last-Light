class_name SettingsManager
extends Node

const RESOLUTIONS := [Vector2i(1280,720),Vector2i(1280,800),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1440)]
const FPS_LIMITS := [0,30,60,90,120,144,165,240]
var game: Node3D
var save_callback: Callable
var last_error := ""

func set_value(id: String, value: Variant) -> bool:
	if not game.save_manager.profile.settings.has(id): return false
	var checked: Variant=value
	match id:
		"fullscreen","vsync","slow_motion","reduced_effects":
			if not value is bool: return false
		"resolution":
			if not value is Array or value.size()!=2: return false
			if not RESOLUTIONS.has(Vector2i(int(value[0]),int(value[1]))): return false
		"fps_limit":
			if not (value is int or value is float) or not FPS_LIMITS.has(int(value)): return false
			checked=int(value)
		_:
			if not (value is int or value is float) or not is_finite(float(value)): return false
			checked=clampf(float(value),.25 if id=="aim_sensitivity" else 0,3 if id=="aim_sensitivity" else 1)
	var before: Dictionary=game.save_manager.profile.settings.duplicate(true)
	game.save_manager.profile.settings[id]=checked
	var saved: bool=save_callback.call() if save_callback.is_valid() else game.save_progress()
	if not saved:
		game.save_manager.profile.settings=before
		last_error="设置保存失败，修改已还原。"
		return false
	last_error=""
	apply_settings()
	return true

func apply_settings() -> void:
	var settings: Dictionary=game.save_manager.profile.settings
	if DisplayServer.get_name()!="headless":
		var wanted: int=DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode()!=wanted: DisplayServer.window_set_mode(wanted)
		if not settings.fullscreen:
			var resolution:=Vector2i(int(settings.resolution[0]),int(settings.resolution[1]))
			if DisplayServer.window_get_size()!=resolution: DisplayServer.window_set_size(resolution)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=clampi(int(settings.fps_limit),0,240)
	if is_instance_valid(game.sound): game.sound.apply_settings()

func slow_scale() -> float:
	var settings: Dictionary=game.save_manager.profile.settings
	return lerpf(1,.25,clampf(float(settings.slow_motion_strength),0,1)) if settings.slow_motion else 1.0
