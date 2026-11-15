## AcademyBalanceData - the Skill Academy's price tables.
## The service owns the purchase and respec flow; this record owns the
## gold costs a designer tunes.
extends Resource
class_name AcademyBalanceData

@export var id: String = "academy_balance"
@export var common_book_price: int = 100
@export var skill_respec_base_cost: int = 500
@export var skill_respec_gold_per_point: int = 20
@export var stat_respec_base_cost: int = 500
@export var stat_respec_gold_per_point: int = 20


func is_valid() -> bool:
	if id.is_empty():
		return false
	if common_book_price <= 0:
		return false
	if skill_respec_base_cost < 0 or skill_respec_gold_per_point < 0:
		return false
	if stat_respec_base_cost < 0 or stat_respec_gold_per_point < 0:
		return false
	return true
