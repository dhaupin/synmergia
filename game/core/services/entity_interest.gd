## EntityInterest - the ONE "nearby" law (round 10).
## Every system that asks "who is around me" for combat went through
## get_entities_in_radius with DIFFERENT type filters -- and the
## default filter is NPC, so the 4 projectile scans (traps, chain,
## ricochet, explosions) silently saw ONLY NPCs: player fireballs
## could not hit wolves or other players. Interest for combat is one
## concept; it lives in exactly one place now.
##
## OWNERSHIP (labs/prd-world-layers.md): physics answers "what can I
## touch", EntityService answers "who exists and where". Interest
## queries are the second one -- never replace this with a physics
## shape query for gameplay targeting.
##
## Autoload-free helper (const-preloaded like CombatMath): resolves
## EntityService through the scene tree so deep script-mode probes
## and parse-time contexts keep working.
extends RefCounted
class_name EntityInterest


## Combat interest: players + enemies (the hostile-to-someone
## population). This is what explosions, chains, traps, and ricochets
## mean. NPCs are deliberately excluded -- guards target through
## GuardAI's own law, not proximity.
static func query_interest(origin: Vector3, radius: float, exclude: Array = []) -> Array:
	var es = _service()
	if es == null:
		return []
	var found: Array = []
	for entity in es.get_entities_in_radius(origin, radius, Entity.EntityType.PLAYER):
		if _keep(entity, exclude):
			found.append(entity)
	for entity in es.get_entities_in_radius(origin, radius, Entity.EntityType.ENEMY):
		if _keep(entity, exclude):
			found.append(entity)
	return found


## Everything alive in range (players, enemies, AND NPCs). For chat
## proximity loops and revive-finder scans that genuinely mean
## "any entity" -- the old default-type call sites that relied on the
## NPC default but filtered by controller_type themselves.
static func query_all(origin: Vector3, radius: float, exclude: Array = []) -> Array:
	var es = _service()
	if es == null:
		return []
	var found: Array = []
	for entity in es.get_entities_in_radius(origin, radius, Entity.EntityType.PLAYER):
		if _keep(entity, exclude):
			found.append(entity)
	for entity in es.get_entities_in_radius(origin, radius, Entity.EntityType.ENEMY):
		if _keep(entity, exclude):
			found.append(entity)
	for entity in es.get_entities_in_radius(origin, radius, Entity.EntityType.NPC):
		if _keep(entity, exclude):
			found.append(entity)
	return found


## Players only (chat channels, guards' sight law, aggro scans).
static func query_players(origin: Vector3, radius: float, exclude: Array = []) -> Array:
	var es = _service()
	if es == null:
		return []
	var found: Array = []
	for entity in es.get_entities_in_radius(origin, radius, Entity.EntityType.PLAYER):
		if _keep(entity, exclude):
			found.append(entity)
	return found


static func _keep(entity, exclude: Array) -> bool:
	if not is_instance_valid(entity):
		return false
	return not exclude.has(entity)


static func _service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("EntityService")
