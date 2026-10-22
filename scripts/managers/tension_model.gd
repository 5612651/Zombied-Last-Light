class_name TensionModel
extends RefCounted

func evaluate(input: Dictionary, config: Dictionary) -> Dictionary:
	var health := clampf(float(input.health),0,1)
	var ammo := clampf(float(input.ammo),0,1)
	var build := clampf(float(input.build),0,1)
	var pace := clampf(float(input.kill_rate)/3,0,1)
	var time := clampf(float(input.elapsed)/900,0,1)
	var recovery: bool=health<float(config.recovery_health) or ammo<float(config.recovery_ammo)
	var recent_clear: bool=float(input.since_wave)<float(config.recovery_gap)
	var pressure := clampf(.35+.45*health+.15*ammo+.12*build+.2*pace+.15*time-(.18 if recent_clear else 0),.25,1.3)
	if recovery:
		pressure=minf(pressure,.42)
	var cap: int=int(config.recovery_active) if recovery else clampi(roundi(float(input.get("base_active",config.base_active))*pressure),8,int(config.max_active))
	return {"mode":"recovery" if recovery else ("surge" if pressure>1.05 else "combat"),"pressure":pressure,"active_cap":cap,"interval_multiplier":2.2 if recovery else clampf(1.35/pressure,.7,2),"elite_limit":0 if recovery else int(config.elite_limit),"gap":float(config.recovery_gap) if recovery or recent_clear else 1.5,"specials":not recovery and pressure>.65,"health":health,"ammo":ammo,"build":build,"kill_rate":float(input.kill_rate),"elapsed":float(input.elapsed),"since_wave":float(input.since_wave)}
