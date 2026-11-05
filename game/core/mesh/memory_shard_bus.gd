## MemoryShardBus - the default, process-local transport.
##
## Backed by a MemoryCacheStore, so its mailboxes live and die with the
## process. This is the dev/CI default and the honest fallback: two
## ShardBus instances inside ONE process (a receipt, or a future
## multi-shard test) can exchange events through a shared store, but
## nothing crosses a process boundary. Cross-process is RedisShardBus.
extends "res://core/mesh/shard_bus.gd"

const MemoryCacheStore = preload("res://adapters/cache/memory_cache_store.gd")

## One process-wide store, so every MemoryShardBus instance shares the
## same mailboxes -- two in-process shards can exchange events. A static
## var is the correct scope: the mailboxes are process-local by design.
static var _shared = null

func get_id() -> String:
	return "memory"

func get_display_name() -> String:
	return "In-process memory bus"

func open(_config: Dictionary) -> int:
	if _shared == null:
		_shared = MemoryCacheStore.new()
		_shared.open({})
	return 0

func _store():
	# Lazily open: the registry seeds this bus via new() without open(),
	# so the first store access must self-initialize.
	if _shared == null:
		open({})
	return _shared
