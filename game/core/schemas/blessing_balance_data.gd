## BlessingBalanceData - the Daily Class Blessing tuning record.
## SignService owns the sky wheel and earn gate; this record owns the
## multipliers and effective-level bonus the wheel pays out. Keeping it
## separate means a damage/heal/XP pass never edits combat_balance.tres.
extends Resource
class_name BlessingBalanceData

@export var id: String = "blessing_balance"
@export var damage_multiplier: float = 1.2
@export var heal_multiplier: float = 1.2
@export var xp_multiplier: float = 1.2
@export var level_bonus: int = 5


## Structural gate: a malformed blessing record must not reach the payoff.
func is_valid() -> bool:
	if id.is_empty():
		return false
	if damage_multiplier <= 0.0 or heal_multiplier <= 0.0 or xp_multiplier <= 0.0:
		return false
	if level_bonus < 0:
		return false
	return true
