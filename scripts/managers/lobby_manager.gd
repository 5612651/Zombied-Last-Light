class_name LobbyManager
extends Node3D

var game: Node3D
var stations: Array=[]
var last_message := ""
var save_callback: Callable

func _ready() -> void:
	position=Vector3(80,0,0)
	stations=JSON.parse_string(FileAccess.get_file_as_string("res://assets/safehouse_stations.json"))
	var scene: PackedScene=load("res://assets/models/safehouse.glb")
	add_child(scene.instantiate())
	var key:=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-65,-20,0)
	key.light_color=Color("d6d6b5")
	key.light_energy=1.2
	key.shadow_enabled=true
	add_child(key)
	for x in [-7,0,7]:
		var lamp:=OmniLight3D.new()
		lamp.position=Vector3(x,3,-5)
		lamp.light_color=Color("ffbd76")
		lamp.light_energy=2.5
		lamp.omni_range=12
		add_child(lamp)
	var survivor:=Node3D.new()
	survivor.position=Vector3(0,.1,-1)
	add_child(survivor)
	ZVisuals.humanoid(survivor)
	visible=false

func _process(_delta: float) -> void:
	visible=game.state=="base"
	if is_instance_valid(game.world):
		game.world.visible=not visible
	if is_instance_valid(game.player):
		game.player.visible=not visible
	if visible and is_instance_valid(game.camera):
		game.camera.position=position+Vector3(22,29,27)
		game.camera.size=27
	elif is_instance_valid(game.camera):
		game.camera.size=19.5

func open_station(id: String) -> bool:
	if game.state!="base" or not stations.any(func(station):return station.id==id):
		return false
	game.hud.base_page=id
	if id=="settings": game.toggle_settings()
	return true

func research_level() -> int:
	return clampi(int(game.save_manager.profile.research.get("salvage",0)),0,3)

func research_cost() -> int:
	return 5*(research_level()+1)

func commit(before: Dictionary) -> bool:
	var saved: bool=save_callback.call() if save_callback.is_valid() else game.save_progress()
	if not saved:
		game.save_manager.profile=before
		last_message="保存失败，资源已还原。"
	return saved

func upgrade_research() -> bool:
	if game.state!="base" or research_level()>=3:
		last_message="回收研究已满级。"
		return false
	if game.save_manager.profile.wallet.research<research_cost():
		last_message="研究点不足，完成任务可获取更多。"
		return false
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	game.save_manager.profile.wallet.research-=research_cost()
	game.save_manager.profile.research.salvage=research_level()+1
	if not commit(before):
		return false
	last_message="回收效率提升，后续区域物资+%d%%。" % (research_level()*10)
	return true

func toggle_setting(id: String) -> bool:
	if game.state!="base" or id not in ["master","camera_shake","screen_blood","slow_motion","reduced_effects"]:
		return false
	var before: Dictionary=game.save_manager.profile.duplicate(true)
	var settings: Dictionary=game.save_manager.profile.settings
	if id in ["slow_motion","reduced_effects"]:
		settings[id]=not settings[id]
	else:
		settings[id]=0.0 if float(settings[id])>0 else 1.0
	if not commit(before):
		return false
	apply_settings()
	return true

func apply_settings() -> void:
	game.settings_manager.apply_settings()
