## Faction - Grouping/organization definition
## Factions can be species-based, political, or PvP rule modifiers
class_name Faction
extends Resource

enum FactionType {
	SPECIES,      # Race-based allegiance (Human Faction, Akkan Faction)
	POLITICAL,    # Server-wide politics (Order Guild, Chaos Pact)
	PVP_RULE,     # PvP override rules (Peaceful until 20, Hunters always PvP)
	REPUTATION    # Reputation-based, not species-based (Guards, Merchants, Bandits)
}

enum PvPRule {
	DEFAULT,      # Follow zone rules
	PEACEFUL,     # No PvP until level X
	HUNTED        # PvP everywhere, always
}

enum Relation {
	ALLIED,       # Can party, trade, buff each other
	NEUTRAL,      # No special treatment
	HOSTILE       # Can attack in PvP zones
}

@export var id: String = ""
@export var display_name: String = "Unknown Faction"
@export var description: String = ""

@export var faction_type: FactionType = FactionType.SPECIES
@export var icon_path: String = ""

# PvP override rules (only for PVP_RULE type)
@export var pvp_rule: PvPRule = PvPRule.DEFAULT
@export var peaceful_until_level: int = 0  # Only relevant if PEACEFUL

# If this faction is tied to a species
@export var species_id: String = ""

# Faction relations (overrides species defaults)
@export var relations: Dictionary = {
	# faction_id: Relation
}

# Benefits from this faction
@export var shop_discount: float = 0.0  # 0.1 = 10% off
@export var quest_rewards_bonus: float = 0.0  # 0.1 = 10% more XP/rewards

# Can other factions join?
@export var is_joinable: bool = true
@export var is_default: bool = false  # Player starts in this faction

# Territory (zone IDs this faction controls)
@export var controlled_zones: Array[String] = []

# War/cooldown timers
var _war_timers: Dictionary = {}  # faction_id: timestamp when war can end

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Get relation with another faction
func get_relation(other_faction_id: String) -> Relation:
	# Check explicit relations first
	if relations.has(other_faction_id):
		return relations[other_faction_id]
	
	# Check species-based auto-alliance
	if faction_type == FactionType.SPECIES and species_id != "":
		var data_service = DataService
		if data_service:
			var other_faction: Faction = data_service.get_faction(other_faction_id)
			if other_faction and other_faction.species_id == species_id:
				return Relation.ALLIED
	
	return Relation.NEUTRAL

## Check if at war with another faction
func is_at_war_with(other_faction_id: String) -> bool:
	return get_relation(other_faction_id) == Relation.HOSTILE

## Set relation with another faction
func set_relation(other_faction_id: String, relation: Relation) -> void:
	relations[other_faction_id] = relation
	var other_faction: Faction = null
	if other_faction_id != "":
		var data_service = DataService
		if data_service:
			other_faction = data_service.get_faction(other_faction_id)
	EventBus.faction_hostility_changed.emit(self, other_faction)

## Can members of this faction PvP with members of another?
func can_pvp_with(other_faction_id: String, player_level: int = 1) -> bool:
	# Check PvP rule override
	match pvp_rule:
		PvPRule.PEACEFUL:
			if player_level < peaceful_until_level:
				return false
		PvPRule.HUNTED:
			return true
	
	# Check other faction's rule
	var data_service = DataService
	if data_service:
		var other_faction: Faction = data_service.get_faction(other_faction_id)
		if other_faction:
			match other_faction.pvp_rule:
				PvPRule.PEACEFUL:
					if player_level < other_faction.peaceful_until_level:
						return false
				PvPRule.HUNTED:
					return true
	
	# Default: check relation
	return is_at_war_with(other_faction_id)

## Check if player in this faction can attack target in another
func can_attack_target(target_faction: Faction, attacker_level: int = 1, target_level: int = 1) -> bool:
	# Both must be able to PvP
	if not can_pvp_with(target_faction.id, attacker_level):
		return false
	if not target_faction.can_pvp_with(id, target_level):
		return false
	
	return true

## Get display info for UI
func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"description": description,
		"type": FactionType.keys()[faction_type],
		"pvp_rule": PvPRule.keys()[pvp_rule],
		"peaceful_until_level": peaceful_until_level,
		"relations_count": relations.size(),
		"controlled_zones": controlled_zones
	}
