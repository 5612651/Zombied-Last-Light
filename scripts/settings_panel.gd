extends PanelContainer
const Settings = preload("res://scripts/managers/settings_manager.gd")

var game: Node3D
var widgets: Dictionary={}
var status: Label
var syncing := false

func _ready() -> void:
	z_index=5
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left=-440
	offset_right=440
	offset_top=-350
	offset_bottom=350
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("10231f")
	style.border_color=Color("8daa93")
	style.set_border_width_all(1)
	style.set_content_margin_all(28)
	add_theme_stylebox_override("panel",style)
	add_theme_font_size_override("font_size",18)
	add_theme_font_override("font",GameLocale.font())
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	add_child(column)
	var title:=Label.new()
	title.text="设置 / 战地装备"
	title.add_theme_font_size_override("font_size",26)
	column.add_child(title)
	var grid:=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",20)
	grid.add_theme_constant_override("v_separation",9)
	column.add_child(grid)
	for id in ["resolution","fullscreen","vsync","fps_limit","master","music","sfx","camera_shake","screen_blood","slow_motion","slow_motion_strength","aim_sensitivity","reduced_effects"]:
		var label:=Label.new()
		label.text=GameLocale.setting_name(id)
		label.custom_minimum_size.x=260
		grid.add_child(label)
		var control: Control
		if id in ["fullscreen","vsync","slow_motion","reduced_effects"]:
			var toggle:=CheckButton.new()
			toggle.text="关闭"
			toggle.toggled.connect(func(value):
				toggle.text="开启" if value else "关闭"
				change(id,value))
			control=toggle
		elif id in ["resolution","fps_limit"]:
			var option:=OptionButton.new()
			if id=="resolution":
				for res in Settings.RESOLUTIONS: option.add_item("%d × %d" % [res.x,res.y])
			else:
				for limit in Settings.FPS_LIMITS: option.add_item("不限帧率" if limit==0 else str(limit)+" 帧/秒")
			option.item_selected.connect(func(index):
				var value: Variant=Settings.FPS_LIMITS[index] if id=="fps_limit" else [Settings.RESOLUTIONS[index].x,Settings.RESOLUTIONS[index].y]
				change(id,value))
			control=option
		else:
			var row:=HBoxContainer.new()
			var slider:=HSlider.new()
			slider.min_value=.25 if id=="aim_sensitivity" else 0
			slider.max_value=3 if id=="aim_sensitivity" else 1
			slider.step=.05
			slider.custom_minimum_size.x=335
			slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			var value_label:=Label.new()
			value_label.custom_minimum_size.x=60
			slider.value_changed.connect(func(value):
				value_label.text="%.2f×" % value if id=="aim_sensitivity" else "%d%%" % roundi(value*100)
				change(id,value))
			row.add_child(slider)
			row.add_child(value_label)
			control=row
			widgets[id]=slider
		control.custom_minimum_size.y=31
		control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_child(control)
		if not widgets.has(id): widgets[id]=control
	status=Label.new()
	status.text="修改即时生效并保存。"
	status.add_theme_font_size_override("font_size",14)
	column.add_child(status)
	var close:=Button.new()
	close.text="返回 / ESC"
	close.custom_minimum_size.y=40
	close.pressed.connect(game.toggle_settings)
	column.add_child(close)
	visible=false

func change(id: String, value: Variant) -> void:
	if syncing: return
	if game.settings_manager.set_value(id,value):
		status.text="已保存。"
	else:
		status.text=game.settings_manager.last_error
		sync_values()

func sync_values() -> void:
	syncing=true
	var settings: Dictionary=game.save_manager.profile.settings
	for id in widgets:
		var widget: Control=widgets[id]
		if widget is CheckButton:
			widget.button_pressed=settings[id]
			widget.text="开启" if settings[id] else "关闭"
		elif widget is HSlider: widget.value=settings[id]
		elif id=="resolution": widget.select(maxi(0,Settings.RESOLUTIONS.find(Vector2i(int(settings.resolution[0]),int(settings.resolution[1])))))
		else: widget.select(maxi(0,Settings.FPS_LIMITS.find(int(settings[id]))))
	syncing=false
