## InstanceTypeDefinition - Declares an instance type's configuration
##
## Configures TTL (Time To Live) semantics for open instance environments
## (dungeons, arenas, raids). The TTL window starts at the last character logout.
## Reconnecting within the window restores the same instance_seed and state.
## After TTL expiry, the instance state is finalized and GC'd.
##
## Spec: labs/prd-open-seed-ttl.md US-004
extends Resource
class_name InstanceTypeDefinition

## Identifier for this instance type (e.g. "dungeon", "arena", "raid")
@export var name: String = ""

## Reconnect window in milliseconds from last character logout.
## Default is 5 minutes (300,000 ms).
@export var default_ttl_ms: int = 300000

## Optional category classification (e.g. "dungeon", "arena", "raid", "battleground")
@export var category: String = "dungeon"

## Optional description
@export var description: String = ""
