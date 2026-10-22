class_name GameStateManager
extends Node

signal changed(previous: String, current: String)
const TRANSITIONS := {
	"base":["stage_start"],
	"stage_start":["combat","dead","base"],
	"combat":["area_clear","upgrade","dead","base"],
	"area_clear":["reward","dead","base"],
	"reward":["upgrade","cleared","dead","base"],
	"upgrade":["combat","cleared","dead","base"],
	"cleared":["transition","victory","dead","base"],
	"transition":["stage_start","dead","base"],
	"dead":["stage_start","base"],
	"victory":["stage_start","base"]
}
var current := "base"
var paused := false

func transition_to(next: String) -> bool:
	if next==current:
		return true
	if not TRANSITIONS.has(next) or next not in TRANSITIONS.get(current,[]):
		push_warning("Rejected state transition "+current+" -> "+next)
		return false
	var previous := current
	current=next
	changed.emit(previous,current)
	return true

func set_paused(value: bool) -> void:
	paused=value
	if is_inside_tree():
		get_tree().paused=value
