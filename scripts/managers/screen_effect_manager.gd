class_name ScreenEffectManager
extends CanvasLayer

var game: Node3D
var material: ShaderMaterial
var overlay: ColorRect
var dust := 0.0
var shock_time := 0.0
var shock_origin := Vector2(.5,.5)
var boss_impact := 0.0

func _ready() -> void:
	layer=-1
	overlay=ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var shader:=Shader.new()
	shader.code=FileAccess.get_file_as_string("res://shaders/combat_screen.gdshader")
	material=ShaderMaterial.new()
	material.shader=shader
	overlay.material=material
	add_child(overlay)
	game.feedback_manager.event_received.connect(on_feedback)

func strength() -> float:
	return .2 if game.save_manager.profile.settings.get("reduced_effects",false) else 1.0

func reset() -> void:
	dust=0
	shock_time=0
	boss_impact=0

func on_feedback(kind: String, point: Vector3, _priority: int) -> void:
	if kind in ["detonation","boss_slam"]:
		dust=maxf(dust,.8 if kind=="boss_slam" else .5)
		shock_time=.5
		var viewport_size: Vector2=game.get_viewport().get_visible_rect().size
		shock_origin=game.camera.unproject_position(point)/viewport_size
	if kind=="boss_slam":
		boss_impact=1

func _process(delta: float) -> void:
	if not is_instance_valid(game.player):
		return
	dust=move_toward(dust,0,delta*1.1)
	shock_time=maxf(0,shock_time-delta)
	boss_impact=move_toward(boss_impact,0,delta*3)
	var combat: bool=game.state not in ["base","victory","dead"]
	var scale: float=strength() if combat else 0
	material.set_shader_parameter("strength",scale)
	material.set_shader_parameter("blood",game.hurt_overlay*float(game.save_manager.profile.settings.screen_blood))
	material.set_shader_parameter("low_health",clampf(1-game.player.hp/30,0,1))
	material.set_shader_parameter("dust",dust)
	material.set_shader_parameter("poison",minf(1,game.player.poison_time))
	material.set_shader_parameter("heat",minf(1,game.player.burn_time))
	material.set_shader_parameter("shock_progress",1-shock_time/.5)
	material.set_shader_parameter("shock_active",1.0 if shock_time>0 else 0.0)
	material.set_shader_parameter("shock_origin",shock_origin)
	material.set_shader_parameter("boss_impact",boss_impact)
	var size: Vector2=game.get_viewport().get_visible_rect().size
	material.set_shader_parameter("aspect",size.x/maxf(1,size.y))
