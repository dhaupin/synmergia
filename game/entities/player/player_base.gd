## PlayerBase - the shared surface every playable body carries.
##
## WHY THIS EXISTS: the game has two player bodies -- the planar
## the player body and the spherical GlobeWorldPlayer -- that were
## SIBLINGS with no shared base. ~20 shared systems gate on
## `is the player body` (resurrection targeting, player_died,
## player_killed_player), so the globe body silently fell outside them
## and the two worlds drifted (see labs/archive/prd/prd-planar-retirement.md). This
## base owns the surface those systems gate on, so both bodies are
## `is PlayerBase` and the gates work on either.
##
## The base DECLARES the whole surface on purpose: GDScript resolves
## identifiers at parse time per script, so a method here cannot read a
## field that only a subclass declares (verified -- "Identifier X not
## declared in the current scope"). Both subclasses therefore DROP their
## duplicate declarations and inherit these.
##
## What lives here: identity + progression + health/mana + stats + the
## ONE-purse currency surface + the player death/level signals. What does
## NOT: movement (planar vs radial), interaction, targeting -- those stay
## in each body.
extends CharacterBody3D
class_name PlayerBase

const HealthComponent = preload("res://core/components/health_component.gd")

## THE PROGRESSION RATIO LAW: the cap and the curve live in ONE authority;
## the body consults it, never forks it.
const LevelCurveScript = preload("res://core/progression/level_curve.gd")

## Runtime autoload lookup (script-mode-safe; bare identifiers fail to
## compile when autoloads are absent).
func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

# --- Identity -------------------------------------------------------------
var entity_id: String = ""
## Entity.EntityType.PLAYER constant, mirrored so `entity.entity_type`
## reads work without an Entity cast.
var entity_type: int = 1
var display_name: String = "Player"
var level: int = 1
## The player's class id ("human_warrior", ...). Required by Skill.can_cast's
## required_class gate; boot paths without login use the default class so the
## starting skillbar is actually castable.
var character_class: String = "human_warrior"

# --- Allegiance -----------------------------------------------------------
## Read by EntityService.is_enemy / is_ally, the aura friendly/hostile
## checks, and FactionManager wars ("entity.faction == Entity.Relation.X").
## Both bodies carry the surface so the shared combat services resolve it
## on the globe exactly as they did on the planar controller.
var faction: int = 0
var relation: int = 0
## Services (FactionManager wars, RespawnService rez rules, ZoneData entry
## gates, PlacementAccess) read faction_id off any combatant. Empty string
## = unaligned. Entity parity: Entity declares the same field.
var faction_id: String = ""
var team_id: int = 0

## Standard stat block (Entity-compatible shape used by the get_* accessors).
var stats: Dictionary = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"vitality": 10,
	"endurance": 10,
	"wisdom": 10,
	"damage_multiplier": 1.0,
	"defense_multiplier": 1.0,
	"armor_multiplier": 1.0,
	"movement_speed_multiplier": 1.0,
	"attack_speed_multiplier": 1.0,
	"damage_reduction": 0.0,
	"damage_reflect": 0.0,
	"health_regen": 0.0,
	"mana_regen": 0.0,
	"cooldown_reduction": 0.0,
	"effect_duration_mult": 1.0,
	"effect_power_mult": 1.0,
}

# --- Health + mana --------------------------------------------------------
## The component owns the damage/heal path; the fields mirror it for the
## services (TickService regen, HUD) that read them directly -- the same
## dual-store both bodies kept (R37 audit).
var health_component: HealthComponent = null
var max_health: int = 100
var current_health: int = 100
var current_mana: int = 100
var max_mana: int = 100

signal health_changed(current: int, maximum: int, delta: int)
signal mana_changed(current: int, maximum: int)
signal player_died(killer)

# --- Progression ----------------------------------------------------------
var experience: int = 0
var experience_to_next_level: int = 1000

signal experience_changed(current: int, level: int)
signal gold_changed(current: int)
signal leveled_up(new_level: int)

## Respawn cycle state parked here by RespawnService between the death
## signal and the delayed respawn execution. Declared on the node because
## GDScript 4 cannot add undeclared properties via dot-assignment.
var _pending_respawn_mode_int = null      # int(RespawnMode) or null
var _pending_respawn_position = null      # Vector3 or null
var _pending_respawn_choice: Dictionary = {}

# --- THE ONE PURSE --------------------------------------------------------
## The mounted InventoryComponent is the authoritative wallet for this
## player; `gold` is its synced mirror (persistence, HUD, and duck-typed
## payers read it). Direct writes to `gold` (restore, horde shares, housing
## spends) convert into REAL deltas in the component purse, so every payment
## speaks through the ONE wallet-voice lane instead of a silent field write.
var _wallet_swallow: bool = false

var gold: int = 0:
	set(value):
		var v := maxi(0, int(value))
		if _wallet_swallow:
			gold = v
			return
		var comp: Variant = null
		if "inventory_component" in self:
			comp = self.get("inventory_component")
		if comp != null and is_instance_valid(comp) and comp.has_method("add_gold"):
			var current := int(comp.get_gold())
			if v > current:
				comp.add_gold(v - current)
				_wallet_swallow = true
				gold = int(comp.get_gold())
				_wallet_swallow = false
				return
			if v < current and comp.has_method("remove_gold"):
				if comp.remove_gold(current - v):
					_wallet_swallow = true
					gold = int(comp.get_gold())
					_wallet_swallow = false
					return
				# The purse refused (fresh body adopted a richer bag, then a
				# stale restore wanted less). Keep the mirror in sync with the
				# truth the purse holds.
			_wallet_swallow = true
			gold = int(comp.get_gold()) if comp != null and is_instance_valid(comp) else v
			_wallet_swallow = false
			return
		gold = v
		gold_changed.emit(v)

# --- Hitbox surface (the ONE player hitbox) -------------------------------
## Hitbox Profile System: cached profile (resolved via the species-fairness
## path) + current stance ("standing" | "crouch"). Crouch/Slide states swap
## the stance; the capsule changes size, never scale -- players of every
## species/sex/body_type share ONE hitbox. Moved here from the planar
## controller (planar-retirement Step 5) so every playable body carries the
## fair hitbox, not just the scene-authored one.
var _hitbox_profile: HitboxProfile = null
var _hitbox_stance: String = "standing"

## Resolve + apply the player collision shape. FAIRNESS RULE (species PvP):
## resolution goes through the species-fair path
## (_ds().resolve_player_hitbox_profile) so every playable species lands on
## the SAME profile. Species, sex, and body_type never scale or swap the
## player hitbox; hitbox_player.tres clamps scale to 1.0 hard.
func _apply_hitbox_profile() -> void:
	if _ds() == null:
		return
	var species_id := "human"
	var char_data = _gm().selected_character_data if is_instance_valid(_gm()) else null
	if char_data != null and "species_id" in char_data and not str(char_data.species_id).is_empty():
		species_id = str(char_data.species_id)
	_hitbox_profile = _ds().resolve_player_hitbox_profile(species_id)
	if _hitbox_profile == null:
		var gl := _glog()
		if gl:
			gl.warn("PlayerBase: hitbox profile missing -- keeping scene capsule")
		return
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		# Deferred: _ready-time tree setup can reject sync adds.
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		add_child.call_deferred(shape_node)
	shape_node.shape = _hitbox_profile.build_shape(1.0, _hitbox_stance)
	var dims: Dictionary = _hitbox_profile.get_dims(1.0, _hitbox_stance)
	shape_node.position = Vector3(0.0, float(dims["offset"]), 0.0)
	var gl2 := _glog()
	if gl2:
		gl2.info("PlayerBase: applied hitbox profile '%s' (species-fair: %s)" % [_hitbox_profile.id, str(_hitbox_profile.pvp_fair)])

## Stance swap for Crouch/Slide states: same profile, same species, SAME
## scale -- only the crouch variant's smaller capsule applies. Falls back to
## standing when the profile has no crouch variant.
func set_hitbox_stance(stance: String) -> void:
	if _hitbox_profile == null:
		_hitbox_stance = stance
		return
	if stance == _hitbox_stance:
		return
	if stance != "standing" and stance != "crouch":
		return
	_hitbox_stance = stance
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	shape_node.shape = _hitbox_profile.build_shape(1.0, _hitbox_stance)
	var dims: Dictionary = _hitbox_profile.get_dims(1.0, _hitbox_stance)
	shape_node.position = Vector3(0.0, float(dims["offset"]), 0.0)

# --- Shared ready surface -------------------------------------------------
## THE SHARED PLAYER-READY LAW (planar-retirement Step 5): the surface
## every playable body wires on entering the tree -- the health component,
## the "players" group membership (ActionBar + PlayerProgress resolve their
## caster through get_first_node_in_group("players")), the class skillbar,
## and the combat effect stack. Both bodies wired these themselves (the same
## four lines in each); they now call super._ready() so the shared setup has
## ONE home, and a bare PlayerBase (probes, fixture tests) gets the same
## surface without a scene.
func _ready() -> void:
	_ensure_health_component()
	add_to_group("players")
	_setup_starting_skills()
	# The default basic attack (the fallback the Attack state and the globe
	# body's combat entry point both read). Owned here so a bare PlayerBase
	# (probes, fixture tests) and the globe body carry it, not just the
	# planar controller.
	if basic_attack == null:
		basic_attack = _create_basic_attack()
	_ensure_effect_stack(true)
	_setup_gm_indicator()

# --- GM star (the GMIndicator feature, wired 2026-11-13) ------------------
## A GM body wears a floating gold star above it -- the 3D twin of the
## "[GM]" chat tag / gold nameplate. Attached ONLY when the body's class
## is a GM class (role 0), so ordinary players never see it. The class
## check is duck-typed through CharacterData.is_gm_class, so it works for
## any class id and never crashes when the schema/DataService is absent
## (bare PlayerBase probes).
func _setup_gm_indicator() -> void:
	if get_node_or_null("GMIndicator") != null:
		return
	var cd_script = load("res://core/schemas/character_data.gd")
	if cd_script == null:
		return
	if not cd_script.is_gm_class(character_class):
		return
	var ind := Node3D.new()
	ind.name = "GMIndicator"
	ind.set_script(load("res://entities/player/components/gm_indicator.gd"))
	add_child(ind)

# --- Health surface -------------------------------------------------------
## Receive damage from any combatant (enemies route here through
## EnemyAI._perform_attack and skill.gd's untyped take_damage).
func take_damage(amount: int, source = null, damage_type: String = "physical", is_crit: bool = false) -> int:
	if health_component == null:
		return 0
	var dealt: int = health_component.take_damage(amount, source, damage_type, is_crit)
	if dealt > 0:
		# Emit the health_component truth, not the stale local field -- the
		# component owns the damage path (the R37 dual-store lesson).
		health_changed.emit(health_component.current_health, health_component.max_health, -dealt)
		var gl := _glog()
		if gl:
			gl.info("Player hit: %d %s damage (HP %d/%d)" % [
				dealt, damage_type, health_component.current_health, health_component.max_health])
	return dealt

## Heal (skill.gd target.heal / self-heal path).
func heal(amount: int, source = null) -> int:
	if health_component == null:
		return 0
	return health_component.heal(amount, source)

func is_dead() -> bool:
	return health_component != null and health_component.is_dead()

## Create the health component if a body's _ready did not (idempotent, so a
## subclass may call it and so standalone probes still get one). Wires the
## component's health_changed into the field mirror.
func _ensure_health_component() -> void:
	if health_component != null:
		return
	health_component = HealthComponent.new()
	health_component.max_health = max_health
	health_component.current_health = current_health
	add_child(health_component)
	health_component.health_changed.connect(_on_component_health_changed)

## Mirror the component back into the fields the live HUD and the regen step
## read (the intentional double-store).
func _on_component_health_changed(current: int, maximum: int, _delta: int) -> void:
	current_health = current
	max_health = maximum

# --- Stat surface ---------------------------------------------------------
func get_stat(stat_name: String) -> int:
	return int(stats.get(stat_name, 0))

## Entity-parity stat surface. A CharacterBody3D player is not an Entity, so
## it lacks the get_stat/set_stat pair InventoryComponent._apply_equipment_stats
## drives. set_stat is deliberately silent -- the player has no stat_changed
## listener (a zero-listener emit would be void under the no-void law).
func set_stat(stat_name: String, value: int) -> void:
	stats[stat_name] = value

func add_stat(stat_name: String, amount: int) -> void:
	set_stat(stat_name, get_stat(stat_name) + amount)

func get_attack_power() -> int:
	return get_stat("strength") * 2

func get_spell_power() -> int:
	return get_stat("intelligence") * 2

func get_healing_power() -> int:
	return get_stat("wisdom") * 2

func get_defense() -> int:
	return get_stat("vitality") * 2

func get_crit_chance() -> float:
	return 0.05 + (get_stat("agility") * 0.003)

func get_crit_multiplier() -> float:
	return 1.5

# --- Progression surface (duck-typed Entity API) --------------------------
func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	experience += amount
	# THE CAP LAW: the body never encodes the cap -- LevelCurve is the ONE
	# authority. Overflow XP past the cap banks (the experience field keeps
	# its value; no level, no stat, no heal), so a seasonal cap raise pays
	# out from what the body already banked.
	while experience >= experience_to_next_level \
			and level < LevelCurveScript.max_level():
		experience -= experience_to_next_level
		level += 1
		experience_to_next_level = LevelCurveScript.level_cost(level)
		# Full restore on level up.
		if health_component != null:
			max_health += 10
			# Sync into the component: it owns the damage/heal path, so the
			# bump must land where take_damage actually reads.
			health_component.max_health = max_health
			current_health = max_health
			health_component.current_health = current_health
		leveled_up.emit(level)
		var gl := _glog()
		if gl:
			gl.info("Player level up: now level %d" % level)
	experience_changed.emit(experience, level)

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	# THE ONE PURSE: when the component wallet is mounted, it is the
	# authoritative purse and its gold_changed is the ONE speak lane -- the
	# mirror just follows (no duplicate node emit). Standalone bodies (probes,
	# unmounted stubs) keep their own voice.
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp != null and is_instance_valid(comp) and comp.has_method("add_gold"):
		comp.add_gold(amount)
		return
	gold += amount
	gold_changed.emit(gold)

## Mirror-sync leg: the component purse was paid/spent through a path that
## does not touch the node (vendors, restores into the adopted bag, vault
## transfers). Keep `gold` equal to the truth the purse holds -- silently;
## the PURSE emits the roster rows.
func _on_component_gold_changed_mirror(_delta: int) -> void:
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp == null or not is_instance_valid(comp):
		return
	_wallet_swallow = true
	gold = int(comp.get_gold())
	_wallet_swallow = false

## Bind the ONE PURSE mirror to the mounted bag: resync the node `gold`
## from the purse (a boot-restored wallet may already be loaded) and keep it
## following every purse emit. Both bodies call this after their bag exists;
## without it the globe node's `gold` never moved on a kill payout.
func _bind_purse_mirror() -> void:
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp == null or not is_instance_valid(comp):
		return
	if comp.has_signal("gold_changed") and not comp.gold_changed.is_connected(_on_component_gold_changed_mirror):
		comp.gold_changed.connect(_on_component_gold_changed_mirror)
	_wallet_swallow = true
	gold = int(comp.get_gold())
	_wallet_swallow = false

# --- Duck-typed currency surface (the ONE purse for every currency) --------
## Prefer the component when mounted; standalone bodies keep an honest zero
## (never invent balance).
func get_currency_amount(currency_id: String) -> int:
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp != null and is_instance_valid(comp) and comp.has_method("get_currency_amount"):
		return int(comp.get_currency_amount(currency_id))
	return 0

func add_currency(currency_id: String, amount: int) -> bool:
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp != null and is_instance_valid(comp) and comp.has_method("add_currency"):
		return bool(comp.add_currency(currency_id, amount))
	return false

func remove_currency(currency_id: String, amount: int) -> bool:
	var comp: Variant = null
	if "inventory_component" in self:
		comp = self.get("inventory_component")
	if comp != null and is_instance_valid(comp) and comp.has_method("remove_currency"):
		return bool(comp.remove_currency(currency_id, amount))
	return false

# --- World seams (duck-typed data lookups) --------------------------------
## The vessel a dock pin fronts: the ferry whose ROUTE names the pin
## (moor/seaward -> the Sundered Barque; village/capitol pier -> the Haven
## Ferry; village/island dock -> the Island Ferry). One truth door: the pin
## id only resolves through a vehicle's data-truth route gateways -- no
## pin-to-boat lookup table to drift. Moved here from the planar controller
## (planar-retirement Step 5) so every playable body carries the walk-up
## dock seam.
func _dock_vehicle_for_pin(gateway_pin_id: String) -> String:
	var ds := _ds()
	if ds == null:
		return ""
	for v in ds.get_all_vehicles():
		if v == null or int(v.ferries_per_day) <= 0:
			continue
		for port in v.route_gateways:
			if str(port) == gateway_pin_id:
				return str(v.id)
	return ""

# --- Combat surface (cast + effect stack) ---------------------------------
## WHY THIS LIVES HERE: the ActionBar casts through `player.use_skill(slot)`
## and the hitbox sweep calls `target.apply_status_effect(...)` on whatever it
## hits. The planar controller carried both; the globe body did not, so on the
## planet the ActionBar no-oped and live DoTs/CCs could not land -- the same
## two-worlds drift PlayerBase exists to close (labs/archive/prd/prd-planar-retirement.md
## Step 2). Both bodies now inherit the surface; the skillbar is the only
## per-body state (each body loads its own from class data).
const Skill = preload("res://core/combat/skill.gd")
const Entity = preload("res://core/entities/entity.gd")
const CcImmunity = preload("res://core/combat/cc_immunity.gd")
const AuraComponentScript = preload("res://core/components/aura_component.gd")
const CombatComponentScript = preload("res://core/components/combat_component.gd")

@export var basic_attack: Skill = null
@export var skillbar: Array = []
@export var attack_range: float = 2.5

var status_effects: Array = []
var aura_component = null
var combat_component = null

## Runtime autoload lookups (script-mode-safe; bare identifiers fail to
## compile when autoloads are absent).
func _tm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("TargetingManager")) if tree and tree.root else null

func _cs() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("CombatSystem")) if tree and tree.root else null

func _ds() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DataService")) if tree and tree.root else null

func _gm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameManager")) if tree and tree.root else null

func _im() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InputManager")) if tree and tree.root else null

## Populate the skillbar from the character's class data (idempotent). The
## class's starting_skills resolve to runtime Skill resources; boot paths
## without login run the default class so keys 1-8 are actually castable.
func _setup_starting_skills() -> void:
	if not skillbar.is_empty():
		return
	var class_data = null
	var char_data = _gm().selected_character_data if is_instance_valid(_gm()) else null
	if char_data != null and "class_data" in char_data and char_data.class_data != null:
		class_data = char_data.class_data
	else:
		var class_id: String = "human_warrior"
		if char_data != null and "class_id" in char_data and str(char_data.class_id) != "":
			class_id = str(char_data.class_id)
		if is_instance_valid(_ds()) and _ds().has_method("get_character_class"):
			class_data = _ds().get_character_class(class_id)
	# Keep can_cast's class gate consistent with the skillbar source.
	if class_data != null and "id" in class_data and str(class_data.id) != "":
		character_class = str(class_data.id)
	# General skills first: the class-agnostic verbs (Bind, Recover) every
	# walker of the Concord owns, ahead of the class kit. They load even when
	# a class has no starting_skills of its own.
	if is_instance_valid(_ds()) and _ds().has_method("get_general_skills"):
		for gschema in _ds().get_general_skills():
			skillbar.append(Skill.from_schema(gschema))
	if class_data == null or not ("starting_skills" in class_data) \
			or class_data.starting_skills.is_empty():
		return
	for skill_id: String in class_data.starting_skills:
		if is_instance_valid(_ds()) and _ds().has_method("get_skill"):
			var schema = _ds().get_skill(skill_id)
			if schema != null:
				skillbar.append(Skill.from_schema(schema))
	if not skillbar.is_empty():
		var gl := _glog()
		if gl:
			gl.info("Player skillbar loaded: %d starting skill(s)" % skillbar.size())

## Attach the effect stack (aura tracker + optional GCD/casting component).
## The hitbox sweep calls apply_status_effect on whatever family it hits, so
## every player body needs this to receive live DoTs/CCs.
func _ensure_effect_stack(with_combat: bool = false) -> void:
	if aura_component == null:
		aura_component = AuraComponentScript.new()
		add_child(aura_component)
	if with_combat and combat_component == null:
		combat_component = CombatComponentScript.new()
		add_child(combat_component)

func apply_status_effect(effect) -> void:
	if effect == null or effect.is_expired():
		return
	# Immunity gate -- same choke point and same law as Entity: a ward that
	# refuses this control keeps the effect out of the stack entirely.
	if CcImmunity.body_is_immune_to(self, str(effect.get("cc_tag"))):
		return
	status_effects.append(effect)
	effect.apply(self)
	# effect_expired is a no-arg signal; bind the effect so the handler
	# receives it (same reasoning as Entity). Ticks apply through
	# StatusEffect._apply_tick_effect (duck-typed take_damage/heal) -- no
	# local tick_occurred connect, which would DOUBLE-apply damage.
	effect.effect_expired.connect(_on_status_effect_expired.bind(effect))

func _on_status_effect_expired(effect) -> void:
	status_effects.erase(effect)
	if aura_component:
		aura_component.untrack_effect(effect)

func remove_status_effect(effect) -> void:
	if status_effects.has(effect):
		effect.remove(self)
		status_effects.erase(effect)
		if aura_component:
			aura_component.untrack_effect(effect)

func clear_all_status_effects() -> void:
	for effect in status_effects:
		effect.remove(self)
		if aura_component:
			aura_component.untrack_effect(effect)
	status_effects.clear()

## Cast the skill bound to a skillbar slot (ActionBar keys 1-8 / touch). The
## target resolves from the shared TargetingManager; the component path owns
## the GCD/casting/anticheat surface when mounted.
func use_skill(slot: int) -> void:
	if slot < 0 or slot >= skillbar.size():
		return
	var skill: Skill = skillbar[slot]
	if skill and skill.can_cast(self):
		var target: Node = null
		var target_info: Variant = _tm().get_current_target() if _tm() else null
		if target_info:
			target = target_info.node
		if combat_component:
			if skill.is_ground_targeted:
				combat_component.execute_skill(skill, null, _get_ground_target_position(skill.ground_target_range))
			else:
				combat_component.execute_skill(skill, target)
			return
		# Legacy fallback (no component attached).
		if skill.is_ground_targeted:
			_cs().execute_skill(self, skill, null, _get_ground_target_position(skill.ground_target_range))
		else:
			_cs().execute_skill(self, skill, target as Entity)

## Swing the body's basic attack at `target` through the same combat entry
## point a keypress takes (CombatComponent when attached, else the hitbox
## path). Callers that mean "attack" use this instead of assuming skillbar
## slot 0 is an attack -- the skillbar order is not an attack contract.
func basic_attack_target(target = null) -> bool:
	if basic_attack == null or not basic_attack.can_cast(self):
		return false
	if combat_component:
		return combat_component.execute_skill(basic_attack, target)
	create_hitbox(basic_attack, target)
	return true

func _get_ground_target_position(max_range: float) -> Vector3:
	var direction: Vector2 = _im().last_direction if _im() else Vector2(0, -1)
	if direction == Vector2.ZERO:
		direction = Vector2(0, -1)
	return _cs().get_ground_target_position(self, direction, max_range)

## The default melee basic attack (the fallback both bodies use). Moved here
## from the planar controller so the globe body's combat entry point works.
func _create_basic_attack() -> Skill:
	var skill: Skill = Skill.new()
	skill.skill_name = "Strike"
	skill.skill_id = "strike"
	skill.skill_type = Skill.SkillType.MELEE
	skill.damage = 20
	skill.mana_cost = 0
	skill.cast_time = 0.0
	skill.cooldown = 1.0
	skill.animation_duration = 0.4
	skill.range = 2.5
	skill.hitbox_size = 1.5
	skill.allow_movement = true
	skill.allow_jumping = true
	skill.combo_chain = ["heavy_strike"]
	return skill

## Swing a skill's hitbox through CombatSystem (the Attack state and the
## globe body's combat entry point both call this). Moved here from the
## planar controller so the shared body carries the combat entry point.
func create_hitbox(skill: Skill, target = null, ground_pos: Vector3 = Vector3.ZERO) -> void:
	_cs().create_hitbox(self, skill, target, ground_pos)
