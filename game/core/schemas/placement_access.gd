## PlacementAccess - ownership scope shared by guards, ankhs, furnishings.
##
## ONE vocabulary for "who may use/enter/interact with a placed thing"
## across every placement-ish system: house guards (HousingService),
## guild-hall ankhs, faction-hall doors, plot entry rules. Systems embed
## an instance and call evaluate() / can_access() instead of each
## re-implementing owner/guild/faction/allow-list logic.
##
## Resolution order (first match wins):
##   1. deny_ids          -> explicitly denied (beats everything)
##   2. owner             -> owner always
##   3. allowed_ids       -> explicitly allowed
##   4. WORLD scope       -> everyone else
##   5. guild scope       -> same guild_id
##   6. faction scope     -> same faction_id
##   7. otherwise denied
extends Resource
class_name PlacementAccess

## NOTE: named AccessScope, not Scope -- the frame's scope.gd already
## claims the global class name Scope (core/frame/srv/scope.gd).
enum AccessScope {
	WORLD,      # Everyone (the haven plaza ankh)
	PERSONAL,   # owner + allowed_ids only
	GUILD,      # owner + allowed_ids + same-guild members
	FACTION,    # owner + allowed_ids + same-faction members
}

@export var scope: AccessScope = AccessScope.WORLD
@export var owner_id: String = ""
@export var guild_id: String = ""
@export var faction_id: String = ""
@export var allowed_ids: Array = []   # Array[String] (untyped so .tres serializes)
@export var deny_ids: Array = []      # Array[String] -- explicit bans, beat guild/faction

## Resolve access for a player-shaped object (duck-typed like everywhere
## else in this codebase: works on the player body and test stubs).
func evaluate(player) -> bool:
	if player == null:
		return false

	var pid := ""
	if "entity_id" in player:
		pid = str(player.entity_id)

	# Deny beats everything -- even WORLD scope (a ban list on a public
	# ankh must still ban).
	if deny_ids.has(pid):
		return false
	if pid != "" and pid == owner_id:
		return true
	if allowed_ids.has(pid):
		return true
	if scope == AccessScope.WORLD:
		return true

	match scope:
		AccessScope.GUILD:
			if guild_id == "":
				return pid != "" and pid == owner_id
			var p_guild := ""
			if "guild_id" in player:
				p_guild = str(player.guild_id)
			elif player.has_method("get_guild_id"):
				p_guild = str(player.get_guild_id())
			return p_guild != "" and p_guild == guild_id
		AccessScope.FACTION:
			if faction_id == "":
				return false
			var p_faction := ""
			if "faction_id" in player:
				p_faction = str(player.faction_id)
			return p_faction != "" and p_faction == faction_id
		_:
			return false


## Convenience wrapper used by scripts that don't care about WHY access
## was denied.
func can_access(player) -> bool:
	return evaluate(player)


## Builders. Typed -> Resource and self-load via runtime load() on
## purpose: a brand-new class_name is not in Godot's global class cache
## until an editor import pass runs, and self-references through the
## global name would fail to compile until then (same trap as GuardData).

## Builder for a personal (house) placement.
static func personal(owner: String, extra_allowed: Array = []) -> Resource:
	var pa: Resource = load("res://core/schemas/placement_access.gd").new()
	pa.scope = AccessScope.PERSONAL
	pa.owner_id = owner
	pa.allowed_ids = extra_allowed.duplicate()
	return pa


## Builder for a guild placement.
static func guild(guild_id: String) -> Resource:
	var pa: Resource = load("res://core/schemas/placement_access.gd").new()
	pa.scope = AccessScope.GUILD
	pa.guild_id = guild_id
	return pa


## Builder for a faction placement.
static func faction(faction_id: String) -> Resource:
	var pa: Resource = load("res://core/schemas/placement_access.gd").new()
	pa.scope = AccessScope.FACTION
	pa.faction_id = faction_id
	return pa


## Builder for a world placement (no restrictions).
static func world() -> Resource:
	var pa: Resource = load("res://core/schemas/placement_access.gd").new()
	pa.scope = AccessScope.WORLD
	return pa
