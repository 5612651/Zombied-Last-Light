class_name StageRating
extends RefCounted

static func evaluate(definition: Dictionary, metrics: Dictionary) -> Dictionary:
	var result := metrics.duplicate(true)
	var rule: Dictionary=definition.get("optional",{})
	var progress := 0.0
	var complete := false
	var threshold: float=float(rule.get("threshold",1))
	match str(rule.get("type","")):
		"low_damage":
			progress=float(metrics.damage_taken)
			complete=progress<=threshold
		"destroy_props":
			progress=float(metrics.get("props_destroyed",0))
			complete=progress>=threshold
		"generator_health":
			progress=float(metrics.get("generator_health_ratio",0))
			complete=progress>=threshold
		"boss_weak_hits":
			progress=float(metrics.get("boss_weak_hits",0))
			complete=progress>=threshold
	var par: float=float(definition.get("target_seconds",180))
	var kill_target: float=float(definition.get("rating_kills",maxi(1,int(metrics.kills))))
	var time_score: float=20*clampf(par/maxf(1,float(metrics.time)),0,1)
	var kill_score: float=15*clampf(float(metrics.kills)/maxf(1,kill_target),0,1)
	var damage_score: float=20*clampf(1-float(metrics.damage_taken)/150,0,1)
	var score: float=40+time_score+kill_score+damage_score+(5 if complete else 0)
	result.optional_objective=complete
	result.optional_progress=progress
	result.score=snappedf(score,.1)
	result.rating="S" if score>=90 else ("A" if score>=80 else ("B" if score>=65 else "C"))
	return result
