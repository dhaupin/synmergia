## Test stub: an Entity with the Enemy-shaped slots the kill-reward
## path reads (enemy_data, aggro_component). Used by
## test_kill_rewards.gd so threat-table and EnemyData-driven reward
## paths can be exercised without the full Enemy scene graph.
## NOTE: enemy_data is NOT redeclared here -- the base Entity class now
## carries it (bosses/elites are bare Entities that must project and
## pay rewards), so redeclaring breaks the stub's parse.
extends "res://core/entities/entity.gd"

var aggro_component = null
## Declared so duck-typed reads like "health_component" in target
## (GuardAI._is_valid_target) resolve instead of erroring on stubs.
var health_component = null
var status_handler = null
