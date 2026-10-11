## ForgeBalanceData - the blacksmith's balance tables (prd-blacksmith
## sec 2.3/2.4). Data truth, NOT code constants: the service reads the
## table, designers tune the gamble. One row per ORE GRADE (the
## attempt's ore decides the column set: its base chance and its
## bonus-vs-tier behavior). Tiers index 0..4 = weapon scale
## (COMMON..MYTHIC]; the ore ladder assimilates to the same scale.
##
## The chance law (prd sec 2.3):
##   chance = clampf(base_chance + ore_bonus_delta, 0.0, MYTHIC_CAP)
##   ore_bonus_delta: negative below target tier, 0 equal,
##     +per_grade_above per grade above (halving past the soft cap).
## The endurance law (addendum): a failure strips a UniformRandomInt
## in [endurance_damage_min, endurance_damage_max] off the TARGET's
## max endurance (the RYL2 scar) and (soft_cap_downgrade) may drop
## one upgrade level.
extends Resource
class_name ForgeBalanceData

@export var id: String = "forge_balance"

## Base success chance per TARGET tier (fractions, index 0..4).
@export var base_chance: Array[float] = [0.90, 0.80, 0.70, 0.60, 0.50]
## Ore-grade effect vs the target tier: delta added to base chance.
## Index == ore grade (0..4). Below-tier entries are negative.
@export var ore_bonus_delta: Array[float] = [-0.15, 0.0, 0.10, 0.20, 0.40]
## The MYTHIC wall: no roll at any ore ever exceeds this.
@export var my_thic_cap: float = 0.90
## Grade steps above the target tier: each adds its own delta, but
## past the SOFT CAP each further grade halts: bonus x 0.5 per grade.
@export var soft_cap_grade: int = 2
## Failure may strip 1..endurance span off the target's max
## endurance (the scar) with this chance; and downgrade one level.
@export var endurance_damage_min: int = 1
@export var endurance_damage_max: int = 10
@export var downgrade_on_failure: bool = true
## Hard upgrade ceiling (the RYL2 wackiness guard: beyond +8 the
## attempt REFUSES -- not a chance penalty, a wall).
@export var upgrade_hard_cap: int = 8
## The cost curve multiplier for gold repair-stage entry (free in v1
## -- survival costs ores, the coin law comes with the vendor).
@export var gold_cost_per_grade: int = 0
