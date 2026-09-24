## Test stub: an Entity with the duck-typed progression surface the
## real PlayerController exposes. Used by test_kill_rewards.gd so
## kill_rewards.gd's grant routing can be exercised without the full
## PlayerController scene.
extends "res://core/entities/entity.gd"

var experience: int = 0
var gold: int = 0
# Declared so tests can assign a HealthComponent node (Entity base has
# no such property; the undeclared assignment was a silent runtime
# error that skipped the ankh dead-player asserts).
var health_component = null


func add_experience(amount: int) -> void:
	if amount > 0:
		experience += amount


func add_gold(amount: int) -> void:
	if amount > 0:
		gold += amount
