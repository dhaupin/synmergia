## stub_buff_bar.gd - duck-typed BuffBar stand-in for headless tests.
## Records add_buff/remove_buff calls; hud_integrator handlers only
## require these two methods (has_method-gated). Extends Node because
## HudIntegrator._buff_bar is a typed Node property.
extends Node

var added: Array = []
var removed: Array = []

func add_buff(buff_id: String, _icon = null, duration: float = 0.0, _stacks: int = 1, is_debuff: bool = false, _is_player_cast: bool = false, _category: int = 0) -> void:
	added.append({
		"id": buff_id,
		"duration": duration,
		"debuff": is_debuff,
	})

func remove_buff(buff_id: String) -> void:
	removed.append(buff_id)
