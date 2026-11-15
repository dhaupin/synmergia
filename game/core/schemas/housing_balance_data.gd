## HousingBalanceData - the housing economy's price tables.
## HousingService owns plot registration, purchases and placement gates;
## this record owns the gold costs and the default plot/house choices.
extends Resource
class_name HousingBalanceData

@export var id: String = "housing_balance"
@export var default_plot_price: int = 50000
@export var house_guard_cost: int = 250000
@export var personal_ankh_cost: int = 100000
@export var default_house_id: String = "house_cottage"


func is_valid() -> bool:
	if id.is_empty():
		return false
	if default_plot_price <= 0 or house_guard_cost <= 0 or personal_ankh_cost <= 0:
		return false
	if default_house_id.is_empty():
		return false
	return true
