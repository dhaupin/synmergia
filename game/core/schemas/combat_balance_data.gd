## CombatBalanceData - the tunable hit table, armor mitigation and baseline
## regeneration. CombatMath owns the roll/order and the mitigation curve;
## TickService owns the regen application. This record owns the bases, curves,
## caps and rates a designer can tune without editing the combat services.
extends Resource
class_name CombatBalanceData

@export var id: String = "combat_balance"

## Hit chance: base, level penalty, floor, and the rating scaling.
@export var hit_base: float = 0.95
@export var hit_level_penalty_per_level: float = 0.01
@export var hit_level_penalty_cap: float = 0.30
@export var hit_floor: float = 0.05
@export var hit_rating_level_factor: float = 10.0

## Dodge: base, agility curve, level bonus, rating divisor and cap.
@export var dodge_base: float = 0.03
@export var dodge_per_agility: float = 0.0015
@export var dodge_level_bonus: float = 0.0005
@export var dodge_rating_divisor: float = 40.0
@export var dodge_cap: float = 0.35

## Parry: base, strength curve, level bonus, rating divisor, shield
## multiplier and cap.
@export var parry_base: float = 0.02
@export var parry_per_strength: float = 0.001
@export var parry_level_bonus: float = 0.0005
@export var parry_rating_divisor: float = 40.0
@export var parry_no_shield_multiplier: float = 0.5
@export var parry_cap: float = 0.25

## Block: base, vitality curve, rating divisor, cap and block value.
@export var block_base: float = 0.05
@export var block_per_vitality: float = 0.002
@export var block_rating_divisor: float = 45.0
@export var block_cap: float = 0.40
@export var block_value_base: float = 30.0
@export var block_value_per_strength: float = 0.5
@export var block_value_rating_divisor: float = 25.0

## Armor/resistance mitigation curve. Flat armor values come from items
## (players) or EnemyData (enemies); the attacker's level sets the curve's
## scaling, and a higher-level defender gets a small effective-armor bonus.
@export var armor_curve_base: float = 100.0
@export var armor_curve_per_attacker_level: float = 2.0
@export var armor_defender_level_bonus: float = 0.02
@export var armor_mitigation_cap: float = 0.90

## Baseline regeneration as a fraction of max resource per second. Rest and
## combat are separate rates so a class/skill can change the in-combat pace;
## they are the same value for now. Flat StatId regen stacks on top.
@export var health_regen_pct_per_sec: float = 0.01
@export var health_regen_combat_pct_per_sec: float = 0.01
@export var mana_regen_pct_per_sec: float = 0.02
@export var mana_regen_combat_pct_per_sec: float = 0.02
@export var stamina_regen_pct_per_sec: float = 0.02
@export var stamina_regen_combat_pct_per_sec: float = 0.01


## Structural gate: a malformed record must not reach the hit table.
func is_valid() -> bool:
	if id.is_empty():
		return false
	if hit_base < 0.0 or hit_base > 1.0:
		return false
	if hit_floor < 0.0 or hit_floor > hit_base:
		return false
	if hit_level_penalty_cap < 0.0 or hit_level_penalty_cap > 1.0:
		return false
	if hit_rating_level_factor <= 0.0:
		return false
	if dodge_cap <= 0.0 or dodge_cap > 1.0:
		return false
	if dodge_rating_divisor <= 0.0:
		return false
	if parry_cap <= 0.0 or parry_cap > 1.0:
		return false
	if parry_rating_divisor <= 0.0:
		return false
	if parry_no_shield_multiplier < 0.0 or parry_no_shield_multiplier > 1.0:
		return false
	if block_cap <= 0.0 or block_cap > 1.0:
		return false
	if block_rating_divisor <= 0.0:
		return false
	if block_value_rating_divisor <= 0.0:
		return false
	if armor_curve_base < 0.0 or armor_curve_per_attacker_level < 0.0:
		return false
	if armor_defender_level_bonus < 0.0:
		return false
	if armor_mitigation_cap <= 0.0 or armor_mitigation_cap > 1.0:
		return false
	var non_negative := [
		hit_level_penalty_per_level,
		dodge_base, dodge_per_agility, dodge_level_bonus,
		parry_base, parry_per_strength, parry_level_bonus,
		block_base, block_per_vitality,
		block_value_base, block_value_per_strength,
		health_regen_pct_per_sec, health_regen_combat_pct_per_sec,
		mana_regen_pct_per_sec, mana_regen_combat_pct_per_sec,
		stamina_regen_pct_per_sec, stamina_regen_combat_pct_per_sec,
	]
	for value in non_negative:
		if float(value) < 0.0:
			return false
	return true
