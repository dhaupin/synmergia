## TitleData - Player title definition
## Titles can be equipped as prefix and/or suffix, displayed on player name
extends Resource
class_name TitleData

const GameTier = preload("res://core/schemas/game_tier.gd")

## Title categories
enum Category {
	COMBAT,       # Combat-related titles
	SOCIAL,       # Party, guild, friends
	ECONOMY,      # Trading, crafting, collecting
	EXPLORATION,  # Discovering zones, locations
	ACHIEVEMENT,  # Achievement-unlocked titles
	QUEST,        # Quest-unlocked titles
	ACCOUNT,      # Account-wide titles (across all characters)
	SPECIAL,      # GM, events, special occasions
}

## Title rarity (affects display color intensity)
## The one game-wide five-rung scale (GameTier).
enum Rarity {
	COMMON,
	RARE,
	EPIC,
	LEGENDARY,
	MYTHIC,
}

## How the title is unlocked
enum UnlockMethod {
	ACHIEVEMENT,  # Unlocked via achievement completion
	QUEST,        # Unlocked via quest completion
	PVP,          # Unlocked via PvP ranking
	CRAFTING,     # Unlocked via crafting milestones
	EVENT,        # Unlocked via time-limited event
	GM_GRANT,     # Manually granted by GM
	PURCHASE,     # Purchased from a shop
	ACCOUNT,      # Account-level achievement
}

## Core identification
@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

## Prefix/Suffix forms (optional - a title may only have one form)
@export var prefix_form: String = ""  # "The Slayer" -> "[The Slayer] PlayerName"
@export var suffix_form: String = ""  # "the slayer" -> "PlayerName, the slayer"

## Display settings
@export var category: Category = Category.ACHIEVEMENT
@export var rarity: Rarity = Rarity.COMMON

## Unlock requirements
@export var unlock_method: UnlockMethod = UnlockMethod.ACHIEVEMENT
@export var unlock_source: String = ""  # achievement_id, quest_id, etc.

## Title scope (character vs account)
@export var is_account_title: bool = false

## Visual
@export var icon_path: String = ""

## Ordering
@export var sort_order: int = 0

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Check if title has a usable prefix form
func has_prefix() -> bool:
	return prefix_form != ""

## Check if title has a usable suffix form
func has_suffix() -> bool:
	return suffix_form != ""

## Check if title has at least one usable form
func is_usable() -> bool:
	return has_prefix() or has_suffix()

## Get rarity color (the canonical GameTier palette).
func get_rarity_color() -> Color:
	return GameTier.color_of(rarity)
