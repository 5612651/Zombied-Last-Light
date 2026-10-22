class_name GameLocale
extends RefCounted

static var ui_font: Font
const SETTINGS: Dictionary={"resolution":"分辨率","fullscreen":"全屏","vsync":"垂直同步","fps_limit":"帧率上限","master":"主音量","music":"音乐","sfx":"音效","camera_shake":"镜头震动","screen_blood":"屏幕血污","slow_motion":"慢动作","slow_motion_strength":"慢动作强度","aim_sensitivity":"瞄准灵敏度","reduced_effects":"降低屏幕效果"}
const FAMILIES: Dictionary={"ballistic":"弹道流派","shotgun":"霰弹流派","fire":"燃烧流派","electric":"电能流派","explosion":"爆破流派","survival":"生存流派"}

static func font() -> Font:
	if ui_font==null:
		if ResourceLoader.exists("res://assets/fonts/ZombiedSansSC.otf"):
			ui_font=load("res://assets/fonts/ZombiedSansSC.otf")
		else:
			var system:=SystemFont.new()
			system.font_names=PackedStringArray(["Microsoft YaHei","Microsoft YaHei UI","Noto Sans CJK SC","SimHei"])
			ui_font=system
	return ui_font

static func setting_name(id: String) -> String:
	return str(SETTINGS.get(id,id))

static func family_name(id: String) -> String:
	return str(FAMILIES.get(id,id))

static func clear() -> void:
	ui_font=null
