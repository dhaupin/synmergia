## PlayerBase - the shared surface every playable body carries.
##
## WHY THIS EXISTS: the game has two player bodies -- the planar
## PlayerController and the spherical GlobeWorldPlayer -- that were
## SIBLINGS with no shared base. ~20 shared systems gate on
## `is PlayerController` (resurrection targeting, player_died,
## player_killed_player), so the globe body silently fell outside them
## and the two worlds drifted (see labs/prd-planar-retirement.md). This
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

## Standard stat block (Entity-compatible shape used by the get_* accessors).
var stats: Dictionary = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"vitality": 10,
	"wisdom": 10,
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
## payers read it). Direct writes to `gold` (restore, horde shares, dwelling
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

# --- Health surface -------------------------------------------------------
## Receive damage from any combatant (enemies route here through
## EnemyAI._perform_attack and skill.gd's untyped take_damage).
func take_damage(amount: int, source = null, damage_type: String = "physical") -> int:
	if health_component == null:
		return 0
	var dealt: int = health_component.take_damage(amount, source, damage_type)
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

# --- Combat surface (cast + effect stack) ---------------------------------
## WHY THIS LIVES HERE: the ActionBar casts through `player.use_skill(slot)`
## and the hitbox sweep calls `target.apply_status_effect(...)` on whatever it
## hits. The planar controller carried both; the globe body did not, so on the
## planet the ActionBar no-oped and live DoTs/CCs could not land -- the same
## two-worlds drift PlayerBase exists to close (labs/prd-planar-retirement.md
## Step 2). Both bodies now inherit the surface; the skillbar is the only
## per-body state (each body loads its own from class data).
const Skill = preload("res://core/combat/skill.gd")
const Entity = preload("res://core/entities/entity.gd")
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

func _get_ground_target_position(max_range: float) -> Vector3:
	var direction: Vector2 = _im().last_direction if _im() else Vector2(0, -1)
	if direction == Vector2.ZERO:
		direction = Vector2(0, -1)
	return _cs().get_ground_target_position(self, direction, max_range)
