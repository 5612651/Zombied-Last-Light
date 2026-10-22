extends RefCounted

var enabled: bool="--profile-combat" in OS.get_cmdline_user_args()
var scopes: Dictionary={}

func reset() -> void:
	scopes.clear()

func note(id: String, started_us: int) -> void:
	var duration: int=Time.get_ticks_usec()-started_us
	if not scopes.has(id): scopes[id]={"calls":0,"total_us":0,"max_us":0}
	var sample: Dictionary=scopes[id]
	sample.calls+=1
	sample.total_us+=duration
	sample.max_us=maxi(sample.max_us,duration)

func snapshot() -> Dictionary:
	return {"enabled":enabled,"scope":"Inclusive CPU scopes, nested times overlap. Instrumentation adds overhead; do not use profiled FPS for hardware acceptance.","timings":scopes.duplicate(true)}
