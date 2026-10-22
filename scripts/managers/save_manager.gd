class_name SaveManager
extends Node

const VERSION := 4
const DEFAULT_PATH := "user://progress.json"
var profile: Dictionary = fresh_profile()
var last_error := ""
var last_load_status := "new"
var loaded_path := ""
var write_blocked := false

static func fresh_profile() -> Dictionary:
	return {
		"schema_version":VERSION,
		"records":{"highest_chapter":1,"highest_stage":1,"stages":{},"chapters":{}},
		"totals":{"kills":0,"runs":0,"deaths":0,"chapters_cleared":0},
		"wallet":{"supply":0,"research":0},
		"weapons":{
			"ar":{"unlocked":true,"level":1,"stars":1,"blueprints":0,"trait":""},
			"shotgun":{"unlocked":false,"level":1,"stars":1,"blueprints":0,"trait":""},
			"smg":{"unlocked":false,"level":1,"stars":1,"blueprints":0,"trait":""},
			"magnum":{"unlocked":false,"level":1,"stars":1,"blueprints":0,"trait":""},
			"lmg":{"unlocked":false,"level":1,"stars":1,"blueprints":0,"trait":""},
			"grenade_launcher":{"unlocked":false,"level":1,"stars":1,"blueprints":0,"trait":""}
		},
		"trait_inventory":{},"loadout":["ar"],
		"crates":{"opened":0,"since_rare":0,"last_reward":{}},
		"research":{},"achievements":{},"claimed_rewards":{},
		"settings":{"resolution":[1280,800],"fullscreen":false,"vsync":true,"fps_limit":120,"master":1.0,"music":.7,"sfx":1.0,"camera_shake":1.0,"screen_blood":1.0,"slow_motion":true,"slow_motion_strength":1.0,"aim_sensitivity":1.0,"reduced_effects":false}
	}

func merge_defaults(defaults: Dictionary, values: Dictionary) -> Dictionary:
	var result := defaults.duplicate(true)
	for key in values:
		if result.get(key) is Dictionary and values[key] is Dictionary:
			result[key]=merge_defaults(result[key],values[key])
		else:
			result[key]=values[key]
	return result

func migrate(raw: Variant) -> Dictionary:
	last_error=""
	if not raw is Dictionary:
		last_error="Save root must be an object"
		return {}
	var raw_version: Variant=raw.get("schema_version",0)
	if not is_number(raw_version) or float(raw_version)!=floor(float(raw_version)):
		last_error="Invalid save version"
		return {}
	var version := int(raw_version)
	if version>VERSION or version<0:
		last_error="Unsupported save version "+str(version)
		return {}
	var data: Dictionary=raw.duplicate(true)
	if version==0:
		# Prototype 0.1 held only highest_stage and kills.
		if not data.has("highest_stage") or not data.has("kills"):
			last_error="Unrecognized legacy save"
			return {}
		if not is_number(data.highest_stage) or not is_number(data.kills):
			last_error="Legacy counters must be numeric"
			return {}
		data={"schema_version":1,"records":{"highest_chapter":1,"highest_stage":maxi(1,int(data.highest_stage)),"stages":{}},"totals":{"kills":maxi(0,int(data.kills))},"weapons":{"shotgun":{"unlocked":true,"level":1,"stars":1,"blueprints":0,"trait":""}},"loadout":["ar","shotgun"]}
		version=1
	if version==1:
		if not data.has("loadout"):
			data.loadout=["ar","shotgun"] if data.get("weapons",{}).get("shotgun",{}).get("unlocked",false) else ["ar"]
		data=merge_defaults(fresh_profile(),data)
		data.schema_version=2
		version=2
	if version==2:
		if not data.has("loadout"):
			data.loadout=["ar","shotgun"] if data.get("weapons",{}).get("shotgun",{}).get("unlocked",false) else ["ar"]
		data=merge_defaults(fresh_profile(),data)
		data.schema_version=3
		version=3
	if version==3:
		data=merge_defaults(fresh_profile(),data)
		data.schema_version=VERSION
	if not validate(data):
		return {}
	return merge_defaults(fresh_profile(),data)

func is_number(value: Variant) -> bool:
	return value is float or value is int

func validate(data: Dictionary) -> bool:
	for section in ["records","totals","wallet","weapons","research","settings","achievements","claimed_rewards","trait_inventory","crates"]:
		if not data.get(section) is Dictionary:
			last_error="Invalid save section: "+section
			return false
	if not data.get("loadout") is Array or data.loadout.is_empty() or data.loadout.size()>2:
		last_error="Invalid weapon loadout"
		return false
	var seen := {}
	for id in data.loadout:
		if not id is String or seen.has(id) or not data.weapons.get(id) is Dictionary or not data.weapons[id].get("unlocked",false):
			last_error="Invalid or locked loadout weapon"
			return false
		seen[id]=true
	for counter in ["opened","since_rare"]:
		if not is_number(data.crates.get(counter)) or data.crates[counter]<0 or float(data.crates[counter])!=floor(float(data.crates[counter])):
			last_error="Invalid crate counter"
			return false
	if not data.crates.get("last_reward") is Dictionary:
		last_error="Invalid crate reward"
		return false
	for amount in data.trait_inventory.values():
		if not is_number(amount) or amount<0 or float(amount)!=floor(float(amount)):
			last_error="Invalid trait inventory"
			return false
	for field in ["highest_chapter","highest_stage"]:
		if not is_number(data.records.get(field)) or data.records[field]<1:
			last_error="Invalid record: "+field
			return false
	if not data.records.get("stages") is Dictionary:
		last_error="Invalid stage records"
		return false
	for record in data.records.stages.values():
		if not record is Dictionary:
			last_error="Invalid individual stage record"
			return false
		for metric in ["time","kills","damage_taken","clears"]:
			if record.has(metric) and (not is_number(record[metric]) or not is_finite(float(record[metric])) or float(record[metric])<0):
				last_error="Invalid stage metric"
				return false
		if record.has("optional_objective") and not record.optional_objective is bool:
			last_error="Invalid optional objective record"
			return false
		if record.has("rating") and str(record.rating) not in ["C","B","A","S"]:
			last_error="Invalid stage grade"
			return false
	if not data.records.get("chapters",{}) is Dictionary:
		last_error="Invalid chapter records"
		return false
	for section in ["totals","wallet"]:
		for key in data[section]:
			if not is_number(data[section][key]) or data[section][key]<0:
				last_error="Invalid nonnegative counter: "+section+"/"+str(key)
				return false
	for id in data.weapons:
		var weapon: Variant=data.weapons[id]
		if not weapon is Dictionary or not weapon.get("unlocked") is bool:
			last_error="Invalid weapon record: "+str(id)
			return false
		for field in ["level","stars","blueprints"]:
			if not is_number(weapon.get(field)) or weapon[field]<(0 if field=="blueprints" else 1):
				last_error="Invalid weapon progression: "+str(id)+"/"+field
				return false
		if not weapon.get("trait","") is String:
			last_error="Invalid weapon trait"
			return false
	for setting in ["master","music","sfx","camera_shake","screen_blood","slow_motion_strength","aim_sensitivity"]:
		if not is_number(data.settings.get(setting)) or not is_finite(float(data.settings[setting])) or float(data.settings[setting])<0:
			last_error="Invalid numeric setting: "+setting
			return false
	for setting in ["fullscreen","vsync","slow_motion"]:
		if not data.settings.get(setting) is bool:
			last_error="Invalid boolean setting: "+setting
			return false
	if data.settings.has("reduced_effects") and not data.settings.reduced_effects is bool:
		last_error="Invalid reduced effects setting"
		return false
	if not data.settings.get("resolution") is Array or data.settings.resolution.size()!=2:
		last_error="Invalid resolution"
		return false
	for dimension in data.settings.resolution:
		if not is_number(dimension) or dimension<1:
			last_error="Invalid resolution dimension"
			return false
	if not is_number(data.settings.get("fps_limit")) or data.settings.fps_limit<0:
		last_error="Invalid FPS limit"
		return false
	return true

func read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null:
		last_error="Cannot read "+path
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text())!=OK:
		last_error="Invalid JSON in "+path
		return {}
	return migrate(parser.data)

func load_profile(path: String=DEFAULT_PATH) -> bool:
	last_error=""
	write_blocked=false
	loaded_path=path
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".bak"):
		profile=fresh_profile()
		last_load_status="new"
		return true
	var document := read_document(path) if FileAccess.file_exists(path) else {}
	if not document.is_empty():
		profile=document
		last_load_status="loaded"
		return true
	# A future-version primary file must not be replaced by an older backup.
	if last_error.begins_with("Unsupported save version"):
		write_blocked=true
		last_load_status="unsupported"
		return false
	if FileAccess.file_exists(path+".bak"):
		document=read_document(path+".bak")
		if not document.is_empty():
			profile=document
			last_load_status="backup"
			last_error=""
			return true
	write_blocked=true
	last_load_status="invalid"
	return false

func save_profile(path: String=DEFAULT_PATH) -> bool:
	if write_blocked and path==loaded_path:
		return false
	var data := profile.duplicate(true)
	data.schema_version=VERSION
	if not validate(data):
		return false
	var temporary := path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:
		last_error="Cannot write "+temporary
		return false
	file.store_string(JSON.stringify(data,"  "))
	file.flush()
	file.close()
	if read_document(temporary).is_empty():
		return false
	if path==loaded_path and last_load_status=="backup" and FileAccess.file_exists(path):
		var quarantine := path+".corrupt."+str(Time.get_ticks_usec())
		if DirAccess.rename_absolute(path,quarantine)!=OK:
			last_error="Cannot preserve damaged primary save"
			return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path+".bak") and DirAccess.remove_absolute(path+".bak")!=OK:
			last_error="Cannot rotate save backup"
			return false
		if DirAccess.rename_absolute(path,path+".bak")!=OK:
			last_error="Cannot preserve previous save"
			return false
	if DirAccess.rename_absolute(temporary,path)!=OK:
		last_error="Cannot commit temporary save"
		if FileAccess.file_exists(path+".bak"):
			DirAccess.rename_absolute(path+".bak",path)
		return false
	last_load_status="saved"
	last_error=""
	return true

func award_stage(run_id: String, stage_id: String, reward: Dictionary, record: Dictionary={}) -> bool:
	var key := run_id+":"+stage_id
	if profile.claimed_rewards.has(key):
		return false
	for currency in ["supply","research"]:
		profile.wallet[currency]+=maxi(0,int(reward.get(currency,0)))
	profile.claimed_rewards[key]=true
	if not record.is_empty():
		var previous: Dictionary=profile.records.stages.get(stage_id,{})
		var merged: Dictionary=previous.duplicate(true)
		merged.clear=true
		merged.clears=int(previous.get("clears",0))+1
		merged.time=minf(float(previous.get("time",record.time)),float(record.time))
		merged.kills=maxi(int(previous.get("kills",0)),int(record.kills))
		merged.damage_taken=minf(float(previous.get("damage_taken",record.damage_taken)),float(record.damage_taken))
		merged.optional_objective=bool(previous.get("optional_objective",false)) or bool(record.get("optional_objective",false))
		merged.last=record.duplicate(true)
		if record.has("rating"):
			var ranks := ["C","B","A","S"]
			var previous_rank: int=ranks.find(str(previous.get("rating","C")))
			merged.rating=ranks[maxi(previous_rank,ranks.find(str(record.rating)))]
			merged.score=maxf(float(previous.get("score",0)),float(record.get("score",0)))
		profile.records.stages[stage_id]=merged
	profile.achievements.first_stage={"progress":1,"target":1,"unlocked":true}
	return true
