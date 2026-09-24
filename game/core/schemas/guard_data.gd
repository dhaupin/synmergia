## GuardData - Town/entrance/house guard definition.
##
## Guards are an NPC/ENEMY hybrid: FRIENDLY NPCs to everyone by default,
## per-player HOSTILE to offenders. Perception of the guard is relative
## to the viewer, not a global relation flip -- the criminal sees the
## guard as an enemy, everyone else still sees an NPC.
##
## Trigger pipeline:
##   1. watch_triggers are evaluated by the guard's brain (GuardAI) or a
##      service caller against a player.
##   2. On trigger, mark_criminal(player_id) flips that player's view of
##      this guard to hostile with an instant permanent grudge.
##   3. mark_criminal_broadcast(...) shares the offense across every
##      guard in the same watch_group ("the town watch"), so all guards
##      see the same aggro. This is what makes the town guard scenario
##      work: one player's crime turns the whole watch against them and
##      only them.
##
## Future scenarios this schema is built for (not yet implemented):
##   - house guards purchased by players (owner_id / allowed_player_ids)
##   - faction-only hostility (hostile_factions)
##   - quest-triggered aggression (hostile_quest_ids / quest flags)
##   - entrance checkpoint rules (watch_triggers with distance checks)
extends Resource
class_name GuardData

## What a guard watches for.
enum WatchTrigger {
	NONE,             # Never triggers on its own (escort/admin-driven)
	ATTACKED,         # Someone attacked the guard (always watched)
	ATTACKED_FACTION, # Someone attacked a member of protected_faction
	ATTACKED_PLAYER,  # Someone attacked a protected player in range
	STEALING,         # Reported theft (service calls report_offense)
	KILLING,          # Reported player kill inside jurisdiction
	TRESPASS,         # Entered a restricted area (watch_area radius)
	WANTED,           # Player is on the watchlist from another source
}

## Who the guard answers to (affects who can command/dismiss it later).
enum GuardDuty {
	TOWN_WATCH,   # Shared watch_group jurisdiction
	PERSONAL,     # Owned by owner_id (the 250k house guard, someday)
	FACTION,      # Answers to a faction
	QUEST,        # Spawned by a quest, hostility driven by quest flags
	ARENA,        # Arena marshal rules
}

@export var id: String = ""
@export var display_name: String = "Guard"

## Combat stats (mirror EnemyData fields so GuardAI can reuse the same
## duck-typed combat surface).
@export var level: int = 10
@export var health: int = 200
@export var attack_power: int = 15
@export var defense: int = 10
@export var move_speed: float = 4.5

## Perception ranges (mirror EnemyData).
@export var aggro_range: float = 12.0
@export var chase_range: float = 25.0
@export var attack_range: float = 2.0

## Behavior when no offender is engaged.
@export var patrol_points: Array = []          # Array[Vector3] (untyped so .tres serializes)
@export var post_position: Vector3 = Vector3.ZERO  # Guard post to return to

## Watch configuration.
@export var watch_triggers: Array = []         # Array[int] (WatchTrigger values)
@export var watch_group: String = ""           # Guards sharing a group share watchlists
@export var watch_area_radius: float = 30.0    # TRESPASS jurisdiction radius
@export var protected_faction: String = ""     # ATTACKED_FACTION: protect this faction_id
@export var hostile_factions: Array = []       # Always hostile to these faction_ids
## Who the guard answers to. GuardAI._beyond_leash reads this every
## physics frame while chasing: only PERSONAL-duty guards leash hard to
## their post; TOWN_WATCH (the default) roam their whole jurisdiction.
@export var guard_duty: GuardDuty = GuardDuty.TOWN_WATCH

## Law settings.
@export var bounty_per_offense: int = 0        # Future: bounty/bail system
@export var forgive_after_seconds: float = 0.0 # 0 = permanent grudge (never forget)
@export var attack_on_sight_karma_below: int = -100  # Karma-based wanted level

## Durability. Lawful guards (town watch, house guards) are NOT loot/XP
## pinatas and never truly die: at 0 HP they are DOWNED, then respawn
## at their post after respawn_delay seconds. Non-lawful guards (arena
## foes, event guards) use the normal enemy death path.
@export var is_lawful: bool = true
@export var respawn_delay: float = 30.0

## NPC face: dialog/offering ref ids so the guard still talks like an NPC.
@export var npc_data_id: String = ""           # NPCData id for the friendly face
@export var greeting_text: String = "Move along, citizen."

## Ownership scope (PlacementAccess -- the shared vocabulary with
## ankhs and dwellings). PERSONAL guards stamp this with the owner;
## GuardAI uses it for allowed-entry checks around the guarded spot.
@export var access: Resource

## Future hooks (data present, consumers later).
@export var owner_id: String = ""              # PERSONAL guards
@export var allowed_player_ids: Array = []     # PERSONAL: always friendly to these
@export var hostile_quest_ids: Array = []      # QUEST: hostile to players holding these quest ids


## Convenience: does this guard watch for a trigger?
func watches(trigger: int) -> bool:
	return watch_triggers.has(trigger)


## Default town-watch configuration. Guards the zone, responds to
## attacks on itself and on the protected faction, shared watchlist.
static func town_guard(guard_id: String, guard_name: String, zone_id: String) -> GuardData:
	var g: GuardData = GuardData.new()
	g.id = guard_id
	g.display_name = guard_name
	g.watch_triggers = [
		WatchTrigger.ATTACKED,
		WatchTrigger.ATTACKED_FACTION,
		WatchTrigger.KILLING,
		WatchTrigger.WANTED,
	]
	g.watch_group = "watch_%s" % zone_id
	g.level = 10
	g.health = 250
	g.attack_power = 18
	g.defense = 12
	return g


## Personal house-guard configuration (the 250k-gold dream).
static func house_guard(guard_id: String, guard_name: String, owner: String, allowed_ids: Array) -> GuardData:
	var g: GuardData = GuardData.new()
	g.id = guard_id
	g.display_name = guard_name
	g.watch_triggers = [
		WatchTrigger.TRESPASS,
		WatchTrigger.ATTACKED,
		WatchTrigger.ATTACKED_PLAYER,
	]
	g.owner_id = owner
	g.guard_duty = GuardDuty.PERSONAL  # answers to the owner; GuardAI leashes it to the post
	g.allowed_player_ids = allowed_ids.duplicate()
	g.watch_group = ""  # Personal guards keep their own watchlist
	g.level = 15
	g.health = 400
	g.attack_power = 25
	g.defense = 18
	return g
