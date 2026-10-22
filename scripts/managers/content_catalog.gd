class_name ContentCatalog
extends RefCounted

const TABLES := ["weapons","enemies","perks","stages","chapters","mutations"]
const REQUIRED := {
	"mutations":["id","weapon","title","description","min_kills","min_perks","requires_any","multipliers","additions","tracer_color","visual_color"],
	"weapons":["id","title","family","behavior","magazine","reserve","damage","interval","reload","pellets","spread","knockback","recoil","shake","flash","range","gun_scale","sound","volume","crit_chance","crit_multiplier","vertical_spread"],
	"enemies":["id","title","behavior","tier","health","speed_min","speed_max","scale","damage","attack_range","attack_interval","knockback_resistance","knockback_cap"],
	"perks":["id","title","description","category","family","effects","max_stacks"],
	"stages":["id","title","layout","objective","waves","reward","resupply","upgrade_after_wave"],
	"chapters":["id","title","playable","stages","target_seconds"]
}
var tables: Dictionary = {}
var errors: Array[String] = []

func load_all(directory: String="res://data") -> bool:
	errors.clear()
	var loaded := {}
	for table in TABLES:
		var path: String = directory+"/"+table+".json"
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path))!=OK:
			errors.append(path+": "+parser.get_error_message())
			continue
		var document: Variant=parser.data
		if not validate_document(table,document):
			continue
		loaded[table]=index_items(document.items)
	if not errors.is_empty():
		return false
	var previous := tables
	tables=loaded
	if not validate_references():
		tables=previous
		return false
	return true

func index_items(items_: Array) -> Dictionary:
	var index := {}
	for item in items_:
		index[item.id]=item.duplicate(true)
	return index

func validate_document(table: String, document: Variant) -> bool:
	var before := errors.size()
	if not document is Dictionary or document.get("schema_version",0)!=1 or not document.get("items") is Array:
		errors.append(table+": expected schema_version 1 and items array")
		return false
	var ids := {}
	for row in document.items:
		if not row is Dictionary:
			errors.append(table+": item must be an object")
			continue
		for field in REQUIRED[table]:
			if not row.has(field):
				errors.append(table+"/"+str(row.get("id","?"))+": missing "+field)
		var id: Variant=row.get("id")
		if not id is String or id.is_empty() or ids.has(id):
			errors.append(table+": empty, invalid or duplicate id "+str(id))
		ids[id]=true
		if table=="weapons":
			positive_fields(table,row,["magazine","damage","interval","reload","pellets","range","gun_scale"])
			if row.get("behavior") not in ["hitscan","projectile"]:
				errors.append(table+"/"+str(id)+": unsupported firing behavior")
			if row.get("behavior")=="projectile":
				positive_fields(table,row,["projectile_speed","projectile_gravity","blast_radius"])
		elif table=="mutations":
			if not row.get("requires_any") is Array or not row.get("multipliers") is Dictionary or not row.get("additions") is Dictionary:
				errors.append(table+"/"+str(id)+": invalid prerequisites or effects")
			else:
				positive_fields(table,row,["min_kills","min_perks"])
				for field in row.multipliers:
					var factor: Variant=row.multipliers[field]
					if not (factor is int or factor is float) or float(factor)<=0:
						errors.append(table+"/"+str(id)+": invalid multiplier")
		elif table=="enemies":
			positive_fields(table,row,["health","scale","attack_interval","knockback_cap"])
			if row.get("behavior") not in ["melee","runner","spitter","screamer","charger","boss_slam"]:
				errors.append(table+"/"+str(id)+": unsupported enemy behavior")
		elif table=="perks":
			if not row.get("effects") is Dictionary:
				errors.append(table+"/"+str(id)+": effects must be an object")
			else:
				for key in row.effects:
					if not (row.effects[key] is float or row.effects[key] is int):
						errors.append(table+"/"+str(id)+": effect "+str(key)+" must be numeric")
			positive_fields(table,row,["max_stacks"])
		elif table=="stages":
			if not row.get("waves") is Array or row.waves.is_empty():
				errors.append(table+"/"+str(id)+": waves must be a nonempty array")
			if not row.get("objective") is Dictionary or not row.get("resupply") is Dictionary or not row.get("reward") is Dictionary:
				errors.append(table+"/"+str(id)+": objective / reward / resupply must be objects")
			elif row.objective.get("type","") not in ["clear","survive","generator","nests","sequence"]:
				errors.append(table+"/"+str(id)+": unsupported objective type")
			elif row.objective.type in ["survive","generator"] and (not (row.objective.get("duration") is float or row.objective.get("duration") is int) or float(row.objective.duration)<60 or float(row.objective.duration)>120):
				errors.append(table+"/"+str(id)+": survival / defense duration must be 60-120 seconds")
			if row.get("objective") is Dictionary and row.objective.get("type")=="sequence":
				if not row.objective.get("missions") is Array or row.objective.missions.size()<2:
					errors.append(table+"/"+str(id)+": sequence requires multiple missions")
				else:
					for mission in row.objective.missions:
						if not mission is Dictionary or mission.get("type") not in ["clear","survive","generator","nests"]:
							errors.append(table+"/"+str(id)+": invalid mission template")
						elif mission.type in ["survive","generator"] and (not (mission.get("duration") is int or mission.get("duration") is float) or float(mission.duration)<60 or float(mission.duration)>120):
							errors.append(table+"/"+str(id)+": mission duration must be 60-120 seconds")
		elif table=="chapters":
			if not row.get("stages") is Array or row.stages.is_empty() or not row.get("playable") is bool:
				errors.append(table+"/"+str(id)+": invalid stage list or playable flag")
	return before==errors.size()

func positive_fields(table: String, row: Dictionary, names: Array) -> void:
	for field in names:
		var value: Variant=row.get(field)
		if not (value is float or value is int) or float(value)<=0:
			errors.append(table+"/"+str(row.get("id","?"))+": "+field+" must be positive")

func validate_references() -> bool:
	for mutation in items("mutations"):
		if not has("weapons",mutation.weapon) or not mutation.requires_any is Array or not mutation.multipliers is Dictionary or not mutation.additions is Dictionary:
			errors.append("mutations/"+mutation.id+": invalid weapon or effects")
			continue
		for id in mutation.requires_any:
			if not has("perks",id):
				errors.append("mutations/"+mutation.id+": unknown prerequisite "+str(id))
	for stage in items("stages"):
		if not ResourceLoader.exists("res://assets/models/"+stage.layout+".glb") or not FileAccess.file_exists("res://assets/"+stage.layout+"_layout.json"):
			errors.append("stages/"+stage.id+": missing layout")
		for wave in stage.waves:
			if not wave is Dictionary or int(wave.get("count",0))<1 or float(wave.get("interval",0))<=0:
				errors.append("stages/"+stage.id+": invalid wave")
				continue
			for role in ["normal","elite","boss"]:
				var id: String=wave.get(role,"")
				if not id.is_empty() and not has("enemies",id):
					errors.append("stages/"+stage.id+": unknown enemy "+id)
	for chapter in items("chapters"):
		if chapter.playable:
			for id in chapter.stages:
				if not has("stages",id):
					errors.append("chapters/"+chapter.id+": unknown stage "+id)
	for perk in items("perks"):
		for id in perk.get("requires_any",[]):
			if not has("perks",id):
				errors.append("perks/"+perk.id+": unknown prerequisite "+str(id))
	return errors.is_empty()

func has(table: String, id: String) -> bool:
	return tables.has(table) and tables[table].has(id)

func definition(table: String, id: String) -> Dictionary:
	return tables.get(table,{}).get(id,{}).duplicate(true)

func items(table: String) -> Array:
	return tables.get(table,{}).values().duplicate(true)
