## GuardAI - Brain for NPC/enemy hybrid guards.
##
## The key idea: hostility is PER-PLAYER, not a global relation flip.
## The guard keeps two views of the world:
##   - everyone else: it is an NPC (FRIENDLY, interactable)
##   - offenders in _hostile_players: an enemy that attacks on sight
##
## Two aggression sources are merged by _check_for_targets():
##   1. The guard's own watchlist (_hostile_players) -- crimes it saw or
##      heard about through its watch_group. Offenses here carry an
##      instant, permanent grudge (no leash forgiveness, no decay).
##   2. The threat table (AggroComponent) -- combat being done TO the
##      guard right now, standard MMO semantics.
##
## Watchlist sharing: report_offense() forwards to every other guard in
## the same watch_group via the static _watch_registry, so "other guards
## see the same aggro and attack too" works even when they are out of
## shout range.
##
## GuardData (core/schemas/guard_data.gd) defines what triggers an
## offense. Future triggers (house guards, faction quests, checkpoints)
## only need new call sites of report_offense().
extends "res://core/ai/enemy_ai.gd"

const GuardData = preload("res://core/schemas/guard_data.gd")

## Static watch-group registry: watch_group -> { guard_id -> GuardAI }.
## Guards broadcast offenses here so the whole watch responds.
static var _watch_registry: Dictionary = {}

var guard_data = null                 # GuardData, optional (dumb-guard fallback)
var _hostile_players: Dictionary = {} # player_id -> true (the town-watch list)
var _group_shared := false


func _ready() -> void:
	super._ready()
	# Register with the watch group AFTER parent _ready so entity_id exists.
	_join_watch_group()


func _exit_tree() -> void:
	_leave_watch_group()


## Attach the guard's data definition.
func setup(data) -> void:
	guard_data = data
	if data != null:
		aggro_range = float(data.aggro_range)
		chase_range = float(data.chase_range)
		attack_range = float(data.attack_range)
	_join_watch_group()


func _join_watch_group() -> void:
	if _group_shared or guard_data == null:
		return
	var group := str(guard_data.watch_group)
	if group == "":
		return
	if not _watch_registry.has(group):
		_watch_registry[group] = {}
	var entity = get_parent()
	if entity != null and "entity_id" in entity:
		_watch_registry[group][str(entity.entity_id)] = self
	_group_shared = true


func _leave_watch_group() -> void:
	if not _group_shared or guard_data == null:
		return
	var group := str(guard_data.watch_group)
	if _watch_registry.has(group):
		var entity = get_parent()
		var my_id := str(entity.entity_id) if entity != null and "entity_id" in entity else ""
		_watch_registry[group].erase(my_id)
	_group_shared = false


## ---------------------------------------------------------------------------
## OFFENSES (the town-watch pipeline)
## ---------------------------------------------------------------------------

## Report a crime by player_id against this guard's jurisdiction.
## Source is for logging/toasts only. The offense is instant, permanent,
## and shared across the whole watch group.
func report_offense(player_id: String, trigger: int, source_desc: String = "") -> void:
	if player_id == "":
		return
	if not _is_watching(trigger):
		return
	mark_criminal(player_id)

	# Share across the watch group so other guards attack too.
	if guard_data != null and str(guard_data.watch_group) != "":
		var group: Dictionary = _watch_registry.get(str(guard_data.watch_group), {})
		for guard_id in group:
			var other = group[guard_id]
			if other != null and other != self and is_instance_valid(other):
				other.receive_offense_broadcast(player_id, trigger, source_desc)

	GameLog.info("GuardAI: %s marked player %s hostile (%s) %s" % [
		_entity_name(), player_id, GuardData.WatchTrigger.keys()[trigger] if trigger >= 0 and trigger < GuardData.WatchTrigger.size() else str(trigger), source_desc])


## Receive a shared offense from another guard in the same watch group.
## Does NOT re-broadcast (the originator already did).
func receive_offense_broadcast(player_id: String, trigger: int, source_desc: String = "") -> void:
	if player_id == "" or _hostile_players.has(player_id):
		return
	mark_criminal(player_id)
	GameLog.info("GuardAI: %s shares watchlist aggro on %s (%s)" % [
		_entity_name(), player_id, source_desc])


func _is_watching(trigger: int) -> bool:
	if guard_data == null:
		return trigger == GuardData.WatchTrigger.ATTACKED  # dumb guard still self-defends
	return guard_data.watches(trigger)


## ---------------------------------------------------------------------------
## PER-PLAYER HOSTILITY (the NPC/enemy hybrid core)
## ---------------------------------------------------------------------------

## Flag a player as a criminal of this guard. Instant full grudge:
## the offense memory is written at permanent weight and the player is
## added to the personal watchlist. Never decays, never forgiven.
func mark_criminal(player_id: String) -> void:
	if player_id == "" or _hostile_players.has(player_id):
		return
	_hostile_players[player_id] = true
	# Permanent memory: written at weight 10.0 and re-pinned after every
	# decay pass by the _decay_grudges override (criminals never fade).
	remember("criminal_%s" % player_id, {
		"player_id": player_id,
		"type": "criminal",
		"time": Time.get_unix_time_from_system(),
	}, 10.0)

	# Immediate engagement if the criminal is within perception.
	_engage_criminal(player_id)


## Immediate engagement if the criminal is within perception.
func _engage_criminal(player_id: String) -> void:
	var entity = get_parent()
	if entity == null or not ("global_position" in entity):
		return
	var es = _resolve_entity_service()
	if es == null or not es.has_method("get_entity"):
		return
	var criminal = es.get_entity(player_id)
	if criminal != null and entity.global_position.distance_to(criminal.global_position) <= chase_range:
		# Instant full aggro: jump straight into combat.
		engage_target(criminal)


## Is this player on the criminal list (from any guard in the group)?
func is_hostile_to_player(player_id: String) -> bool:
	return _hostile_players.has(player_id)


## Admin/future-bail-system hook: clear one player (none of the standard
## gameplay paths call this -- grudges are permanent).
func pardon_player(player_id: String) -> void:
	_hostile_players.erase(player_id)
	var tree = _get_memory_tree()
	if tree != null and _memory_agent_path != "":
		tree.delete_memory(_memory_agent_path + "/events/criminal_" + player_id)
	_update_known_threats(tree)


## ---------------------------------------------------------------------------
## TARGETING OVERRIDES (per-player view of the world)
## ---------------------------------------------------------------------------

## _check_for_targets override: merge criminal watchlist + threat table +
## faction hostility. Everyone NOT on those lists is invisible to
## targeting -- the guard stays an NPC to them.
func _check_for_targets():
	var entity = get_parent()
	if not entity:
		return null

	var nearby: Array = _resolve_entity_service().get_entities_in_radius(
		entity.global_position,
		aggro_range,
		Entity.EntityType.PLAYER
	) if _resolve_entity_service() != null else []

	# Priority 1: criminals -- instant full aggro on sight.
	for target in nearby:
		if _is_valid_target(target) and is_criminal(target):
			return target

	# Priority 2: highest current threat (someone attacking the guard now).
	if "aggro_component" in entity and entity.aggro_component != null:
		var threat_target = entity.aggro_component.get_highest_threat_target()
		if threat_target != null and _is_valid_target(threat_target):
			return threat_target

	# Priority 3: faction-hostile players (future faction-guard setups).
	var faction_target = _find_faction_hostile(nearby)
	if faction_target != null:
		return faction_target

	return null


## Is this live target a known criminal of this guard's watch?
func is_criminal(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not ("entity_id" in target):
		return false
	var pid := str(target.entity_id)
	if _hostile_players.has(pid):
		return true
	# Group-shared list: ask other guards (cheap dict lookups).
	if guard_data != null and str(guard_data.watch_group) != "":
		var group: Dictionary = _watch_registry.get(str(guard_data.watch_group), {})
		for guard_id in group:
			var other = group[guard_id]
			if other != null and other != self and is_instance_valid(other):
				if other.is_hostile_to_player(pid):
					return true
	return false


## Valid target = alive + criminal/faction-hostile. NOT the base class's
## "any player" rule: guards do not attack innocent players.
func _is_valid_target(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.health_component and target.health_component.is_dead():
		return false
	# Stealth rule inherited from base via explicit check.
	if "status_handler" in target and target.status_handler != null:
		var stealth_effect = target.status_handler.get_effect_by_type(StatusEffectData.EffectType.STEALTH, "stealth")
		if stealth_effect and stealth_effect.is_active():
			var see_stealth := false
			var parent_entity = get_parent()
			if parent_entity and guard_data != null:
				see_stealth = true  # guards are trained watchers
			if not see_stealth:
				return false
	if is_criminal(target):
		return true
	if _is_faction_hostile(target):
		return true
	return false


func _is_faction_hostile(target) -> bool:
	if guard_data == null:
		return false
	var hostile_list: Array = guard_data.hostile_factions
	if hostile_list.is_empty():
		return false
	if not "faction_id" in target:
		return false
	return hostile_list.has(str(target.faction_id))


func _find_faction_hostile(nearby: Array):
	for target in nearby:
		if _is_valid_target(target) and _is_faction_hostile(target):
			return target
	return null


## ---------------------------------------------------------------------------
## GRUDGE PERSISTENCE OVERRIDE
## ---------------------------------------------------------------------------

## Criminal grudges are permanent: after the base class decays event
## memories, re-pin every criminal entry at full weight so forgiveness
## never reaches the watchlist. (Base decay only touches memory weights;
## _hostile_players itself is already immune -- this keeps the memory
## tree consistent with it.)
func _decay_grudges() -> void:
	super._decay_grudges()
	var tree = _get_memory_tree()
	if tree == null or _memory_agent_path == "":
		return
	for player_id in _hostile_players:
		var path := _memory_agent_path + "/events/criminal_" + str(player_id)
		var mem: Dictionary = tree.get_memory(path)
		if mem.is_empty():
			tree.insert_memory(path, "event", {
				"player_id": str(player_id),
				"type": "criminal",
				"time": Time.get_unix_time_from_system(),
			}, 10.0)
		else:
			var content: Dictionary = mem.get("content", {})
			content["type"] = "criminal"
			tree.update_memory(path, "event", content, 10.0)
	_update_known_threats(tree)


## Guards never leash-forget (no RETURN forgiveness). Their patrol
## behavior is "return to post", not "return to spawn and forget".
func _update_return(_delta: float) -> void:
	var entity = get_parent()
	if entity == null:
		return
	var post := _guard_post()
	var dist: float = entity.global_position.distance_to(post)
	if dist <= 1.5:
		set_state(AIState.IDLE)
		return
	var dir: Vector3 = (post - entity.global_position).normalized()
	entity.move_direction = dir


func _guard_post() -> Vector3:
	if guard_data != null:
		return guard_data.post_position
	var entity = get_parent()
	return entity._spawn_position if entity != null and "_spawn_position" in entity else Vector3.ZERO


## Handle being damaged: the ATTACKED trigger. Attacking a guard is
## itself a crime -- report it (marks the attacker AND shares the
## offense with the whole watch) before the base engagement logic.
## Note: the base signature is (source: Entity), so a bare Node attacker
## cannot reach here -- the report_offense passthrough on Guard covers
## service-side callers that only hold a duck-typed source.
func on_damaged(source: Entity) -> void:
	if source != null and "entity_id" in source and not ("loot_table_id" in source):
		report_offense(str(source.entity_id), GuardData.WatchTrigger.ATTACKED,
			"attacked the guard")
	super.on_damaged(source)


func _entity_name() -> String:
	var entity = get_parent()
	return str(entity.display_name) if entity != null and "display_name" in entity else "Guard"


# --- service resolution (script-mode safe, same convention as tests) -------

func _resolve_entity_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return EntityService  # full boot: autoload identifier resolves
	var tree := ml as SceneTree
	if tree.root == null:
		return null
	var svc = tree.root.get_node_or_null(NodePath("EntityService"))
	return svc if svc != null else EntityService
