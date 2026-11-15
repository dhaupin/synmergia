## BoutRewardsData - the XP and gold payouts for bouts, trials and royales.
## BoutHostService owns the win/loss gates and the payout ledger; this record
## owns the amounts those gates pay.
extends Resource
class_name BoutRewardsData

@export var id: String = "bout_rewards"
@export var win_xp: int = 120
@export var win_gold: int = 25
@export var consolation_xp: int = 40
@export var trial_win_xp: int = 40
@export var trial_win_gold: int = 10
@export var trial_loss_xp: int = 15
@export var royale_win_xp: int = 250
@export var royale_win_gold: int = 60
@export var royale_survival_xp_per_min: int = 12
@export var royale_kill_xp: int = 25
@export var royale_consolation_xp: int = 30
@export var royale_first_win_xp: int = 400


func is_valid() -> bool:
	if id.is_empty():
		return false
	if win_xp < 0 or win_gold < 0 or consolation_xp < 0:
		return false
	if trial_win_xp < 0 or trial_win_gold < 0 or trial_loss_xp < 0:
		return false
	if royale_win_xp < 0 or royale_win_gold < 0 or royale_survival_xp_per_min < 0:
		return false
	if royale_kill_xp < 0 or royale_consolation_xp < 0 or royale_first_win_xp < 0:
		return false
	return true
