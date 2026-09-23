## ShardParameterDefinition - Declares a shard parameter's contract
##
## A shard parameter is a named, typed value stored in a shard's
## state tree (e.g. boss_defeated, respawn_rate_modifier).
##
## Criticality is CONFIG-TIME: it is set in this Resource and read
## by ShardParameters at write time. There is no runtime setter for
## `critical` -- a player cannot escalate a non-critical parameter
## to critical (see labs/prd-critical-params.md US-005).
##
## Usage:
##   var def = load("res://data/roots/world/parameters/boss_defeated.tres")
##   if def.critical:
##       ShardParameters.set(shard_id, def.name, value, actor_id)

extends Resource
class_name ShardParameterDefinition

## Human-readable identifier (matches the .tres filename without extension)
@export var name: String = ""

## One of: int, float, bool, string, enum, other
@export_enum("int", "float", "bool", "string", "enum", "other") var type: String = "string"

## Default value when the parameter has not been written yet
@export var default_value: Variant = null

## If true, writes apply immediately (no 5-min coalesce window).
## If false, writes queue and apply after the coalesce window.
@export var critical: bool = false

## Optional human-readable description for tooling/docs
@export var description: String = ""

## Schema version; bumped when the parameter's contract changes
@export var version: int = 1
