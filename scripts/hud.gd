extends Control

var game: Node3D
var font: Font = GameLocale.font()
var buttons: Array = []
var ivory := Color("e0e3ce")
var dim := Color("889f92")
var mint := Color("b1d5af")
var amber := Color("e4ae66")
var base_page := "lobby"
var selected_weapon := "ar"
var build_open := false
var selected_perk := ""
var weapon_previews: Dictionary={}
var ui_images: Dictionary={}
var hovered_action := ""
var hover_elapsed := 0.0
var pointer := Vector2(-1000,-1000)
var family_colors := {"ballistic":Color("57d8eb"),"shotgun":Color("f1ae5b"),"fire":Color("f1794b"),"electric":Color("be8ef0"),"explosion":Color("ebc06e"),"survival":Color("8cd4a4")}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	var point := mouse_point()
	var action := ""
	for item in buttons:
		if item.rect.has_point(point): action=item.action
	if action==hovered_action: hover_elapsed+=delta
	else:
		hovered_action=action
		hover_elapsed=0
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer=event.position/size*Vector2(1440,900)

func mouse_point() -> Vector2:
	return pointer if pointer.x>=0 else get_viewport().get_mouse_position()/size*Vector2(1440,900)

func label_at(text: String, pos: Vector2, size_: int=16, color: Color=Color("e0e3ce")) -> void:
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_,color)

func panel(rect: Rect2, opacity: float=.88) -> void:
	draw_style_box(panel_style(opacity),rect)

func panel_style(opacity: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color=Color(.035,.065,.061,opacity)
	s.border_color=Color(.44,.56,.47,.4)
	s.set_border_width_all(1)
	s.corner_radius_top_left=3
	s.corner_radius_bottom_right=3
	return s

func button(rect: Rect2, title: String, subtitle: String, action: String, accent: Color=Color("b1d5af")) -> void:
	var hover: bool=rect.has_point(mouse_point())
	panel(rect,.98 if hover else .9)
	if hover: draw_rect(rect,Color(accent,.7),false,1.5)
	var icon: String=action_icon(action)
	var icon_size: float=minf(42,rect.size.y-12)
	if not icon.is_empty(): icon_at(icon,Rect2(rect.position+Vector2(10,(rect.size.y-icon_size)*.5),Vector2.ONE*icon_size))
	var left: float=58 if not icon.is_empty() else 18
	var caption: bool=rect.size.y>=62 and (action.begins_with("armory:level:") or action.begins_with("armory:star:") or action.begins_with("armory:unlock:") or action in ["open_crate","research_upgrade"])
	var title_size := 18 if rect.size.y>=60 else 14
	while title_size>11 and font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,title_size).x>rect.size.x-left-14: title_size-=1
	label_at(title,rect.position+Vector2(left,rect.size.y*.5+(0 if caption else 6)),title_size,accent if hover else ivory)
	if caption: label_at(subtitle,rect.position+Vector2(left,rect.size.y-13),12,amber)
	buttons.append({"rect":rect,"action":action,"title":title,"description":subtitle,"icon":icon})

func click(pos: Vector2) -> bool:
	var p := pos/size*Vector2(1440,900)
	for b in buttons:
		if b.rect.has_point(p):
			if b.action=="objective_info": return false
			game.ui_action(b.action)
			return true
	return false

func _draw() -> void:
	_draw_content()
	if is_instance_valid(game) and is_instance_valid(game.player): draw_hover_popup()

func _draw_content() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player):
		return
	var profile_start: int=Time.get_ticks_usec() if game.combat_profiler.enabled else 0
	buttons.clear()
	draw_set_transform(Vector2.ZERO,0,size/Vector2(1440,900))
	# Fine cinematic letterbox and corner framing.
	draw_rect(Rect2(0,0,1440,20),Color("071210"))
	draw_rect(Rect2(0,880,1440,20),Color("071210"))
	label_at("Z / 17     终光",Vector2(44,59),15,mint)
	label_at("雨城封锁区  /  最后防线",Vector2(44,82),11,dim)
	label_at("版本 "+str(ProjectSettings.get_setting("application/config/version","development")).to_upper(),Vector2(1168,54),11,dim)
	if game.state=="base" and base_page in ["crates","research","records","settings"]:
		draw_rect(Rect2(0,20,1440,860),Color(.012,.022,.032,.88))
		panel(Rect2(58,220,550,620),.97)
		var titles := {"crates":"军械补给","research":"研究台","records":"行动档案","settings":"设置"}
		var descriptions := {"crates":"任务物资换取装备。重复武器转为25蓝图，重复特性转为35物资。无现金购买。","research":"提升任务回收效率，为下一次行动做好准备。","records":"每一次突破，都留在这里。","settings":"调整属于你的战场体验。"}
		label_at(titles[base_page],Vector2(90,284),29,ivory)
		icon_at(base_page,Rect2(150,328,360,360))
		paragraph(descriptions[base_page],Vector2(90,743),470,17,mint)
		draw_base_management()
		button(Rect2(650,113,745,62),"安全屋 [ESC]","返回功能区。","lobby")
		return
	if game.state=="base" and base_page=="armory":
		draw_rect(Rect2(0,20,1440,860),Color(.01,.025,.023,.75))
		draw_weapon_preview()
		draw_base_management()
		button(Rect2(650,113,745,62),"安全屋 [ESC]","返回六个功能区","lobby")
		return
	if game.state=="base" or game.state=="dead" or game.state=="victory":
		if game.state=="base" and base_page=="lobby":
			draw_lobby()
			return
		draw_rect(Rect2(0,20,1440,860),Color(.01,.025,.023,.32))
		panel(Rect2(58,235,525,575),.94)
		label_at("安全屋 / 行动简报",Vector2(90,278),12,amber)
		label_at("终",Vector2(85,365),78,ivory)
		label_at("光",Vector2(85,446),78,mint)
		var heading := "守住最后的光，打出一条生路。"
		if game.state=="dead" or (game.state=="base" and game.run_manager.outcome in ["death","generator_destroyed"]):
			heading="已返回安全屋 / 已结算进度保留"
		if game.state=="victory":
			heading="撤离成功 / 你活下来了"
		label_at(heading,Vector2(90,490),17,ivory)
		label_at("第一章 / 六个连续区域 / 约25–35分钟",Vector2(90,522),14,dim)
		label_at("最远区域 0%d / 累计击杀 %d" % [game.highest_stage,game.lifetime_kills],Vector2(90,554),12,amber)
		if game.state=="base":
			button(Rect2(90,590,460,70),"第一章：封锁之城 [回车]","连续穿越六个区域，抵达撤离终点","deploy")
			button(Rect2(90,670,460,65),"目标训练 [T]","清场 / 生存 / 守护发电机 / 摧毁感染巢","trials",amber)
			button(Rect2(90,745,460,55),"感染者威胁试炼","疾奔者 / 喷吐者 / 尖啸者 / 冲锋者 / 撕裂者","threats",amber)
		else:
			button(Rect2(90,590,460,79),"返回安全屋 [回车]","已结算的物资、解锁与历史记录会保留。","return_base")
		controls(825)
		if game.state=="base":
			draw_base_management()
			button(Rect2(650,113,745,62),"安全屋 [ESC]","返回六个功能区","lobby")
		return
	if game.state=="upgrade":
		if not game.mutation_manager.choices.is_empty():
			draw_mutations()
			return
		draw_rect(Rect2(0,20,1440,860),Color(.01,.025,.023,.65))
		label_at("战地强化",Vector2(110,270),13,amber)
		label_at("让火力继续进化。",Vector2(110,325),36,ivory)
		label_at("选择一项强化，效果持续至本局结束。",Vector2(110,357),16,dim)
		for i in game.upgrade_choices.size():
			var perk: Dictionary=game.upgrade_choices[i]
			var rect:=Rect2(110+i*412,405,390,260)
			image_card(rect,perk.title,str(perk.family),perk.description,"perk:"+perk.id,family_colors.get(perk.family,mint))
			label_at("[%d]" % (i+1),rect.position+Vector2(24,34),17,dim)

		return
	var stage_definition: Dictionary=game.stage_manager.definition()
	label_at("区域 %02d / %02d" % [game.stage,game.stage_manager.stage_count()],Vector2(44,132),12,amber)
	label_at(stage_definition.title,Vector2(42,164),28,ivory)
	var objective: String=game.objective.description()
	if game.state=="stage_start":
		objective="正在进入区域 / 准备战斗"
	elif game.state=="area_clear":
		objective="区域已肃清 / 正在结算物资"
	elif game.state=="reward":
		objective="存档失败 / 物资尚未结算" if game.stage_manager.reward_failed else "奖励已结算 / 选择战地强化"
		if game.stage_manager.reward_failed:
			button(Rect2(450,370,540,90),"重试保存","请检查磁盘访问权限和剩余空间，然后重试结算。","retry_reward",amber)
	elif game.state=="transition":
		objective="正在前往下一区域"
	if game.state=="cleared":
		objective="区域已肃清 / 前往北侧出口"
	label_at(objective,Vector2(44,190),14,mint)
	var optional: String=game.stage_manager.optional_description()
	if not optional.is_empty():
		icon_at("briefing",Rect2(42,202,36,36))
		buttons.append({"rect":Rect2(42,202,240,36),"action":"objective_info","title":"支线目标","description":optional,"icon":"briefing"})
	if game.state in ["area_clear","reward","cleared"] and game.stage_manager.completion_record.has("rating"):
		panel(Rect2(460,660,520,72))
		label_at("区域评级 / "+str(game.stage_manager.completion_record.rating),Vector2(482,690),20,amber)
		label_at("%.1f秒 / 击杀%d / 承伤%.0f / 支线%s" % [float(game.stage_manager.completion_record.time),int(game.stage_manager.completion_record.kills),float(game.stage_manager.completion_record.damage_taken),"完成" if game.stage_manager.completion_record.optional_objective else "未完成"],Vector2(482,715),13,dim)
	panel(Rect2(1190,98,205,106))
	label_at("现存敌人",Vector2(1210,126),11,dim)
	label_at("%02d" % game.enemies.size(),Vector2(1210,167),34,ivory)
	label_at("击杀 %03d" % game.kills,Vector2(1280,167),12,amber)
	var p=game.player
	var buffs: Array[String]=[]
	if p.poison_time>0: buffs.append("中毒 %.1f秒" % p.poison_time)
	if p.burn_time>0: buffs.append("燃烧 %.1f秒" % p.burn_time)
	if p.boost>0: buffs.append("杀戮加速 %.1f秒" % p.boost)
	if not buffs.is_empty(): label_at(" / ".join(buffs),Vector2(44,294),12,amber)
	if not game.mutation_manager.active.is_empty():
		label_at("武器进化 / "+str(game.mutation_manager.active.size()),Vector2(44,245),11,amber)
	draw_combat_strip()

	if not game.perks.is_empty():
		label_at("战地强化 %02d" % game.perks.size(),Vector2(44,222),11,amber)
	if game.announcement_time>0:
		label_at(game.announcement,Vector2(485,125),24,Color(mint,clampf(game.announcement_time,0,1)))
	if game.state=="cleared":
		var screen: Vector2=game.camera.unproject_position(Vector3(0,2.8,-14))/size*Vector2(1440,900)
		label_at("出口  ↑",screen+Vector2(-30,-15),18,amber)
	if game.paused and not build_open:
		draw_rect(Rect2(0,20,1440,860),Color(0,.02,.015,.72))
		label_at("已暂停",Vector2(615,425),42,ivory)
		label_at("按ESC继续",Vector2(636,465),14,dim)
	var mouse := get_viewport().get_mouse_position()/size*Vector2(1440,900)
	if game.manage_pointer and not game.paused: mouse=p.aim_cursor/size*Vector2(1440,900)
	if p.bot:
		mouse=game.camera.unproject_position(p.aim_point)/size*Vector2(1440,900)
	var cross_color := amber if game.hit_marker>0 else ivory
	var gap: float = 7+p.recoil*25
	for v in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		draw_line(mouse+v*gap,mouse+v*(gap+7),cross_color,1.4,true)
	if game.hit_marker>0:
		for v in [Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
			draw_line(mouse+v*4,mouse+v*8,Color("f6c16e") if game.hit_critical else ivory,2,true)
	for num in game.fx.damage_numbers:
		var point: Vector2=game.camera.unproject_position(num.position)/size*Vector2(1440,900)
		label_at(str(num.amount),point,18 if num.critical else 14,Color(amber if num.critical else ivory,minf(1,num.life*3)))
	for target in game.objective.targets:
		if not is_instance_valid(target) or target.destroyed:
			continue
		var point: Vector2=game.camera.unproject_position(target.global_position+Vector3.UP*1.25)/size*Vector2(1440,900)
		var text: String="发电机 / 长按E启动" if target.kind=="generator" and not game.objective.activated else ("发电机" if target.kind=="generator" else "感染巢")
		label_at(text,point+Vector2(-48,-9),11,amber)
		draw_rect(Rect2(point+Vector2(-45,0),Vector2(90,3)),Color("343c2d"))
		draw_rect(Rect2(point+Vector2(-45,0),Vector2(90*target.hp/target.max_hp,3)),amber)
	# Boss health is drawn only while present.
	for enemy in game.enemies:
		if is_instance_valid(enemy) and enemy.boss:
			panel(Rect2(440,210,560,50))
			label_at(str(enemy.definition.title).to_upper()+(" / 狂暴" if enemy.boss_brain.enraged else ""),Vector2(460,232),13,amber)
			draw_rect(Rect2(460,243,520,4),Color("4b3a2c"))
			draw_rect(Rect2(460,243,520*maxf(0,enemy.hp/enemy.max_hp),4),amber)
	if build_open:
		draw_build()
	if game.stage_manager.fade>0:
		draw_rect(Rect2(0,20,1440,860),Color(0,.015,.01,game.stage_manager.fade))
	if game.combat_profiler.enabled: game.combat_profiler.note("combat_hud_draw",profile_start)

func controls(y: float) -> void:
	label_at("WASD 移动",Vector2(90,y),13,ivory)
	label_at("鼠标瞄准 / 左键开火",Vector2(285,y),13,ivory)
	label_at("R换弹 / Q切枪 / 空格冲刺 / G手雷",Vector2(90,y+28),12,dim)

func draw_build() -> void:
	buttons.clear()
	draw_rect(Rect2(0,20,1440,860),Color(.01,.018,.028,.94))
	label_at("战地构筑",Vector2(90,148),34,ivory)
	label_at("点击查看 / 悬停说明",Vector2(90,181),15,dim)
	if selected_perk.is_empty() and not game.perks.is_empty(): selected_perk=game.perks[0]
	for i in game.perks.size():
		var item: Dictionary=game.catalog.definition("perks",game.perks[i])
		var rect:=Rect2(90+(i%6)*119,220+(i/6)*102,108,92)
		panel(rect,.98 if selected_perk==item.id else .7)
		icon_at(str(item.family),Rect2(rect.position+Vector2(27,6),Vector2(54,54)))
		label_at(item.title,rect.position+Vector2(8,79),12,family_colors.get(item.family,mint))
		buttons.append({"rect":rect,"action":"build:"+str(item.id),"title":item.title,"description":item.description,"icon":item.family})
	if game.perks.is_empty(): label_at("完成任务后，选择属于你的战斗风格。",Vector2(90,280),18,dim)
	panel(Rect2(860,220,490,510),.92)
	if selected_perk in game.perks:
		var item: Dictionary=game.catalog.definition("perks",selected_perk)
		icon_at(str(item.family),Rect2(1018,244,170,170))
		label_at(item.title,Vector2(890,458),27,ivory)
		label_at(GameLocale.family_name(str(item.family)),Vector2(890,492),15,family_colors.get(item.family,mint))
		paragraph(item.description,Vector2(890,542),420,18,ivory)
	button(Rect2(860,760,490,68),"继续战斗 [TAB]","死亡或章节结束后，局内强化清空。","toggle_build",amber)
	var optional: String=game.stage_manager.optional_description()
	if not optional.is_empty():
		icon_at("briefing",Rect2(90,755,48,48))
		paragraph(optional,Vector2(150,784),620,15,mint)

func draw_mutations() -> void:
	draw_rect(Rect2(0,20,1440,860),Color(.01,.025,.023,.8))
	label_at("战地工程 / 武器进化",Vector2(110,240),14,amber)
	label_at("突破火力极限。",Vector2(110,295),36,ivory)
	label_at("选择本局武器进化；局外武器养成仍会保留。",Vector2(110,328),16,dim)
	for i in game.mutation_manager.choices.size():
		var item: Dictionary=game.mutation_manager.choices[i]
		var rect:=Rect2(110+(i%2)*620,365+(i/2)*180,600,160)
		button(rect,"%d / %s" % [i+1,item.title],item.description,"mutation:"+item.id,amber)
		label_at("武器 / "+str(game.catalog.definition("weapons",str(item.weapon)).title),rect.position+Vector2(22,70),13,mint)
	button(Rect2(110,770,1220,65),"保持当前武器","暂不进化，后续满足条件时仍可再次选择。","mutation_skip")

func draw_base_management() -> void:
	if base_page in ["research","records","settings"]:
		draw_base_service()
		return
	if base_page=="crates":
		draw_crates()
		return
	if base_page!="armory":
		panel(Rect2(760,352,560,162),.9)
		label_at("实弹训练 / 动态遭遇战",Vector2(784,387),16,amber)
		button(Rect2(784,407,512,76),"动态尸潮试炼","生存90秒 / 全感染者阵容","pressure",amber)
		panel(Rect2(760,540,560,245),.9)
		label_at("物资 %d" % int(game.save_manager.profile.wallet.supply),Vector2(784,574),18,amber)
		button(Rect2(784,594,512,72),"武器库 [B]","等级 / 升星 / 特性 / 出战配置","armory")
		button(Rect2(784,682,512,72),"军械箱","武器 / 蓝图 / 稀有特性","crates",amber)
		return
	panel(Rect2(650,220,745,535),.97)
	label_at("武器库",Vector2(674,255),25,ivory)
	var definitions: Array=game.catalog.items("weapons")
	for i in mini(6,definitions.size()):
		var weapon: Dictionary=definitions[i]
		var record: Dictionary=game.progression_manager.record(weapon.id)
		var rect:=Rect2(674+(i%3)*233,278+(i/3)*108,221,98)
		panel(rect,.98 if selected_weapon==weapon.id else .6)
		if selected_weapon==weapon.id: draw_rect(rect,mint,false,2)
		icon_at("weapon:"+str(weapon.id),Rect2(rect.position+Vector2(28,-8),Vector2(165,103)),Color.WHITE if record.unlocked else Color(.5,.58,.6,1))
		var short_title: String=str(weapon.title).split(" · ")[0]
		label_at(short_title,rect.position+Vector2(14,85),14,mint if record.unlocked else dim)
		buttons.append({"rect":rect,"action":"armory:select:"+str(weapon.id),"title":weapon.title,"description":"伤害 %.0f / 弹匣 %d / 换弹 %.1f秒" % [weapon.damage,weapon.magazine,weapon.reload],"icon":"weapon:"+str(weapon.id)})
	var base: Dictionary=game.catalog.definition("weapons",selected_weapon)
	var record: Dictionary=game.progression_manager.record(selected_weapon)
	label_at("武器等级",Vector2(674,524),14,dim)
	for i in 10: draw_rect(Rect2(774+i*18,512,14,12),mint if i<int(record.level) else Color("25333a"))
	for i in 5: icon_at("records",Rect2(1024+i*36,501,32,32),Color.WHITE if i<int(record.stars) else Color(.23,.28,.3,1))
	icon_at("blueprint",Rect2(1240,501,32,32));label_at(str(record.blueprints),Vector2(1280,524),17,amber)
	var ids: Array=game.progression_manager.config.traits.keys()
	for i in ids.size():
		var trait_id: String=ids[i]
		var trait_data: Dictionary=game.progression_manager.config.traits[trait_id]
		var amount: int=game.save_manager.profile.trait_inventory.get(trait_id,0)
		button(Rect2(674+i*175,550,163,48),trait_data.title,"持有%d / 点击装备 / %s" % [amount,trait_data.description],"armory:trait:"+trait_id,amber if record.trait==trait_id else dim)
	if not record.unlocked:
		button(Rect2(674,618,687,62),"解锁这把武器","20蓝图 + 150物资","armory:unlock:"+selected_weapon,amber)
	else:
		var cost: Dictionary=game.progression_manager.star_cost(selected_weapon)
		button(Rect2(674,618,337,62),"提升等级" if record.level<10 else "已满级","%d物资" % game.progression_manager.level_cost(selected_weapon),"armory:level:"+selected_weapon,mint)
		button(Rect2(1024,618,337,62),"武器升星" if record.stars<5 else "已满星","%d蓝图 + %d物资" % [cost.blueprints,cost.supply],"armory:star:"+selected_weapon,amber)
		button(Rect2(674,690,337,48),"装备至主武器位","主武器配置在下次部署时生效。","armory:equip_a:"+selected_weapon)
		button(Rect2(1024,690,337,48),"装备至副武器位","副武器配置在下次部署时生效。","armory:equip_b:"+selected_weapon)
	label_at(game.progression_manager.last_message,Vector2(674,778),13,amber)
	button(Rect2(650,798,745,54),"返回安全屋","保留当前武器配置。","lobby")

func draw_weapon_preview() -> void:
	var data: Dictionary=game.catalog.definition("weapons",selected_weapon)
	var accent := Color(data.get("tracer_color","36cfff"))
	panel(Rect2(58,220,550,620),.98)
	label_at("尖端武装 / 科技军械",Vector2(86,258),15,accent)
	label_at(data.title,Vector2(86,305),23,ivory)
	if not weapon_previews.has(selected_weapon):
		var path: String="res://assets/textures/weapons/"+selected_weapon+".png"
		if ResourceLoader.exists(path): weapon_previews[selected_weapon]=load(path)
	if weapon_previews.has(selected_weapon):
		draw_texture_rect(weapon_previews[selected_weapon],Rect2(70,332,525,328),false)
	draw_line(Vector2(86,665),Vector2(578,665),Color(accent,.6),2)
	label_at("精密金属 / 陶瓷装甲 / 独立能量核心",Vector2(86,703),17,ivory)
	var descriptions := {"ar":"电磁双层弹道 / 稳定连续输出","shotgun":"等离子扇形爆发 / 近距离冲击","smg":"紫色离子双轨 / 高速压制","magnum":"磁轨贯穿光束 / 重型脉冲环","lmg":"炽热机炮弹道 / 持续火力覆盖","grenade_launcher":"聚能核心抛射 / 立体能量爆破"}
	label_at(descriptions.get(selected_weapon,""),Vector2(86,741),17,accent)
	label_at("右侧选择武器，查看养成与出战配置。",Vector2(86,801),14,dim)

func draw_crates() -> void:
	var crates=game.crate_manager
	var history: Dictionary=game.save_manager.profile.crates
	panel(Rect2(650,220,745,535),.97)
	label_at("军械补给",Vector2(674,265),26,ivory)
	icon_at("supply",Rect2(1225,232,36,36));label_at(str(game.save_manager.profile.wallet.supply),Vector2(1275,262),19,amber)
	var names := ["武器","稀有特性","蓝图","物资"]
	var images := ["armory","research","blueprint","supply"]
	var weight_ids := ["weapon","trait","blueprints","supply"]
	var total: float=0
	for weight in crates.config.weights.values(): total+=float(weight)
	for i in 4:
		var point:=Vector2(685+i*169,300)
		icon_at(images[i],Rect2(point,Vector2(130,130)))
		label_at(names[i],point+Vector2(10,158),17,ivory)
		label_at("%d%%" % roundi(100*float(crates.config.weights[weight_ids[i]])/total),point+Vector2(10,184),14,dim)
	var remaining: int=maxi(1,int(crates.config.rare_pity)-int(history.since_rare))
	for i in int(crates.config.rare_pity): draw_rect(Rect2(685+i*60,525,45,5),amber if i<int(history.since_rare) else Color("2b3538"))
	label_at("稀有保底 / 还差%d箱" % remaining,Vector2(685,568),16,amber)
	button(Rect2(674,600,687,72),"开启军械箱","消耗%d物资" % crates.config.cost,"open_crate",amber)
	var reward: Dictionary=crates.last_reward if not crates.last_reward.is_empty() else history.last_reward
	if not reward.is_empty(): label_at("最近回收 / "+str(reward.title),Vector2(685,715),17,mint)
	else: label_at("完成任务，带回你的下一件武装。",Vector2(685,715),16,dim)
	label_at(crates.last_message,Vector2(674,778),13,amber)
	button(Rect2(650,798,360,54),"武器库","查看并配置回收的武器。","armory")
	button(Rect2(1024,798,371,54),"返回安全屋","奖励与保底进度已保存。","lobby")

func draw_lobby() -> void:
	var backdrop: Texture2D=ui_image("res://assets/ui/city_backdrop.png")
	if backdrop: draw_texture_rect(backdrop,Rect2(0,20,1440,860),false)
	draw_rect(Rect2(0,20,1440,860),Color(.015,.025,.035,.58))
	label_at("终 光",Vector2(76,210),68,ivory)
	label_at("封锁之城",Vector2(80,256),26,amber)
	label_at("穿过雨城，抵达最后的撤离点。",Vector2(80,300),18,mint)
	var weapon: Dictionary=game.weapon_manager.definition()
	var art: Texture2D=ui_image("res://assets/textures/weapons/"+str(weapon.id)+".png")
	if art: draw_texture_rect(art,Rect2(28,330,570,355),false)
	button(Rect2(80,704,470,82),"部署第一章  →","六个连续区域 / 约25–35分钟","deploy",amber)
	icon_at("supply",Rect2(78,808,32,32));label_at(str(game.save_manager.profile.wallet.supply),Vector2(120,832),18,ivory)
	icon_at("research",Rect2(225,808,32,32));label_at(str(game.save_manager.profile.wallet.research),Vector2(267,832),18,ivory)
	var labels := {"briefing":"行动简报","armory":"武器库","crates":"军械补给","research":"研究台","records":"行动档案","settings":"设置"}
	var details := {"briefing":"选择第一章任务、目标训练或感染者试炼。","armory":"查看武器模型，解锁、强化并配置出战武器。","crates":"消耗任务物资开启军械箱，查看奖励与保底。","research":"提升回收效率，为下一次行动准备资源。","records":"查看各区域评级和历史最佳表现。","settings":"调整画面、音频、瞄准与屏幕反馈。"}
	for i in game.lobby_manager.stations.size():
		var station: Dictionary=game.lobby_manager.stations[i]
		var rect:=Rect2(650+(i%3)*242,240+(i/3)*244,222,224)
		image_card(rect,labels.get(station.id,station.title),station.id,details.get(station.id,""),"station:"+station.id,amber if station.id=="briefing" else mint)
	label_at("鼠标悬停查看详情",Vector2(650,796),14,dim)

func draw_base_service() -> void:
	panel(Rect2(650,220,745,535),.97)
	label_at({"research":"研究台","records":"行动档案","settings":"设置"}.get(base_page,base_page),Vector2(674,255),24,amber)
	var profile: Dictionary=game.save_manager.profile
	if base_page=="research":
		var level: int=game.lobby_manager.research_level()
		label_at("物资回收 / 等级%d（最高3级）" % level,Vector2(674,322),20,ivory)
		label_at("后续区域物资+%d%% / 不增加战斗属性" % (level*10),Vector2(674,362),16,dim)
		label_at("可用研究点 %d" % int(profile.wallet.research),Vector2(674,408),17,amber)
		button(Rect2(674,454,687,80),"已满级" if level>=3 else "提升回收效率","消耗%d研究点" % game.lobby_manager.research_cost(),"research_upgrade",dim if level>=3 else mint)
		label_at(game.lobby_manager.last_message,Vector2(674,582),14,amber)
	elif base_page=="records":
		label_at("出战%d / 阵亡%d / 成功撤离%d" % [int(profile.totals.runs),int(profile.totals.deaths),int(profile.totals.chapters_cleared)],Vector2(674,322),17,ivory)
		label_at("累计击杀%d / 最远区域%d" % [game.lifetime_kills,game.highest_stage],Vector2(674,365),17,dim)
		label_at("区域 / 评级 / 最快用时 / 击杀 / 最低承伤",Vector2(674,417),13,amber)
		var ids: Array=profile.records.stages.keys()
		for i in mini(6,ids.size()):
			var record: Dictionary=profile.records.stages[ids[i]]
			var stage_name: String=str(game.catalog.definition("stages",str(ids[i])).get("title",ids[i]))
			label_at("%s / %s / %.1f秒 / %d / %.0f" % [stage_name,str(record.get("rating","-")),float(record.get("time",0)),int(record.get("kills",0)),float(record.get("damage_taken",0))],Vector2(674,454+i*32),15,ivory)
		label_at("已记录%d项成就，各项最佳成绩独立保留。" % profile.achievements.size(),Vector2(674,697),14,dim)
	else:
		button(Rect2(674,278,687,55),"画面 / 音频 / 瞄准","打开完整设置","settings_open")
		var ids := ["master","camera_shake","screen_blood","slow_motion","reduced_effects"]
		for i in ids.size():
			var id: String=ids[i]
			var enabled: bool=bool(profile.settings[id])
			button(Rect2(674,342+i*70,687,60),GameLocale.setting_name(id)+" / "+("开启" if enabled else "关闭"),"点击切换 / 即时保存","setting:"+id)
	button(Rect2(650,778,745,62),"返回安全屋","所有修改都会保存。","lobby")

func ui_image(path: String) -> Texture2D:
	if not ui_images.has(path):
		ui_images[path]=load(path) if ResourceLoader.exists(path) else null
	return ui_images[path]

func icon_at(id: String, rect: Rect2, tint: Color=Color.WHITE) -> void:
	var path: String="res://assets/textures/weapons/"+id.trim_prefix("weapon:")+".png" if id.begins_with("weapon:") else "res://assets/ui/icons/"+id+".png"
	var tex: Texture2D=ui_image(path)
	if tex: draw_texture_rect(tex,rect,false,tint)

func action_icon(action: String) -> String:
	if action.begins_with("station:"): return action.trim_prefix("station:")
	if action.begins_with("armory:"): return "armory"
	if action.begins_with("perk:") or action.begins_with("build:"):
		var item: Dictionary=game.catalog.definition("perks",action.get_slice(":",1))
		return str(item.get("family","research"))
	return {"deploy":"briefing","trials":"briefing","threats":"armor","pressure":"explosion","armory":"armory","crates":"crates","open_crate":"crates","research_upgrade":"research","toggle_build":"research","settings_open":"settings","lobby":"briefing"}.get(action,"")

func image_card(rect: Rect2,title: String,icon: String,description: String,action: String,accent: Color) -> void:
	var hover: bool=rect.has_point(mouse_point())
	panel(rect,.98 if hover else .9)
	if hover: draw_rect(rect,Color(accent,.8),false,2)
	draw_line(rect.position+Vector2(16,rect.size.y-52),rect.end-Vector2(16,52),Color(accent,.4),1)
	var size_: float=minf(rect.size.x-48,rect.size.y-76)
	icon_at(icon,Rect2(rect.position+Vector2((rect.size.x-size_)*.5,12),Vector2.ONE*size_))
	label_at(title,rect.position+Vector2(22,rect.size.y-22),20,accent if hover else ivory)
	buttons.append({"rect":rect,"action":action,"title":title,"description":description,"icon":icon})

func paragraph(text: String,point: Vector2,width: float,size_: int,color: Color) -> void:
	var line := ""
	for character in text:
		if character=="\n" or font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,size_).x>width:
			label_at(line,point,size_,color);point.y+=size_+8;line=""
		if character!="\n": line+=character
	label_at(line,point,size_,color)

func draw_hover_popup() -> void:
	if game.settings_panel!=null and game.settings_panel.visible: return
	if game.state in ["combat","cleared"] and not game.paused: return
	if hover_elapsed<.22 or hovered_action.is_empty(): return
	for item in buttons:
		if item.action!=hovered_action: continue
		var point := mouse_point()+Vector2(22,22)
		point=point.clamp(Vector2(20,40),Vector2(1030,650))
		panel(Rect2(point,Vector2(390,205)),1)
		draw_rect(Rect2(point,Vector2(3,205)),amber)
		icon_at(str(item.get("icon","research")),Rect2(point+Vector2(15,13),Vector2(58,58)))
		label_at(str(item.get("title","详情")),point+Vector2(85,48),20,ivory)
		paragraph(str(item.get("description","")),point+Vector2(22,104),344,16,mint)
		return

func draw_combat_strip() -> void:
	var player=game.player
	panel(Rect2(36,756,360,100),.86)
	icon_at("health",Rect2(44,774,64,64))
	draw_rect(Rect2(119,788,245,11),Color("25343a"))
	draw_rect(Rect2(119,788,245*player.hp/player.max_hp,11),mint if player.hp>30 else Color("ed785d"))
	draw_rect(Rect2(119,810,245,5),Color("25343a"))
	draw_rect(Rect2(119,810,245*clampf(player.armor/maxf(1,game.rogue_manager.value("armor_max")),0,1),5),Color("5fc8ea"))
	label_at(str(ceili(player.hp)),Vector2(120,842),22,ivory)
	var ids := ["dash","grenade","research"]
	var keys := ["空格","G","TAB"]
	for i in 3:
		var rect:=Rect2(470+i*92,774,78,78)
		panel(rect,.78)
		icon_at(ids[i],Rect2(rect.position+Vector2(6,-6),Vector2(66,66)))
		label_at(keys[i],rect.position+Vector2(21,70),11,dim)
		if i==0 and player.dash_cooldown>0: draw_arc(rect.get_center()-Vector2(0,8),28,-PI*.5,TAU*(1-clampf(player.dash_cooldown/1.6,0,1))-PI*.5,32,amber,3,true)
		if i==1: label_at(str(player.grenades),rect.position+Vector2(58,26),14,amber)
		if i==2: buttons.append({"rect":rect,"action":"toggle_build","title":"战地构筑","description":"查看强化与武器进化。","icon":"research"})
	panel(Rect2(1008,748,390,108),.88)
	var data: Dictionary=game.weapon_manager.definition()
	var art: Texture2D=ui_image("res://assets/textures/weapons/"+str(data.id)+".png")
	if art: draw_texture_rect(art,Rect2(1008,740,150,94),false)
	label_at("%02d" % player.magazines[player.weapon],Vector2(1160,800),36,ivory)
	label_at("/ %d" % player.reserve[player.weapon],Vector2(1222,800),17,dim)
	var segments: int=mini(24,int(data.magazine))
	for i in segments:
		var filled: bool=float(i)/segments<float(player.magazines[player.weapon])/int(data.magazine)
		draw_rect(Rect2(1160+i*8,815,5,12),amber if filled else Color("263238"))
	if player.reload_timer>0: draw_rect(Rect2(1160,838,190*(1-player.reload_timer/player.reload_duration),3),amber)
	label_at("R 换弹    Q 切换",Vector2(1160,850),11,dim)
