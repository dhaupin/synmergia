## Test stub: the reward-player progression surface plus the guild
## identity fields. Extracted from test_placement_system.gd's inner
## GuildPlayer class: an inner-class `extends` of reward_player_stub.gd
## is a parse-time load of entity.gd (which references the EventHub
## autoload) and poisons --script-mode compilation. Applied at runtime
## with set_script() instead, after autoloads exist.
extends "res://tests/support/reward_player_stub.gd"

var guild_id: String = ""
var guild_rank: int = 0
