## Test stub: an Entity with the Enemy-shaped slots the kill-reward
## path reads (enemy_data, aggro_component). Used by
## test_kill_rewards.gd so threat-table and EnemyData-driven reward
## paths can be exercised without the full Enemy scene graph.
extends "res://core/entities/entity.gd"

var enemy_data: Resource = null
var aggro_component = null
