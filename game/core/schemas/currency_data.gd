extends Resource
class_name CurrencyData

## Data-driven currency. Makes gold renameable, adds faction currencies,
## elite tokens, and black-market scrip without new code paths. Wallets
## and vendors reference CurrencyData.id (or "" for the default wallet),
## so an exchange-rate or replacement economy is a data edit.

enum CurrencyKind {
	REGULAR,      # Standard wallet money (gold)
	TOKEN,        # Elite/seasonal token, usually soulbound, capped
	FAVOR,        # Faction reputation currency (vendor unlocks)
	EVENT,        # Limited-time event currency
	BLACK_MARKET  # Undocumented scrip; vendors that accept it are rare
}

@export var id: String = ""
@export var display_name: String = "Gold"
@export var description: String = ""
@export var icon_path: String = ""

## REGULAR for the default wallet currency; one REGULAR currency expected.
@export var kind: CurrencyKind = CurrencyKind.REGULAR

## Exchange rate against the default wallet currency: how many units of
## this currency one unit of the default buys (gold_per_unit). A rate of
## 10.0 means 1 special token = 10 gold. BLACK_MARKET currencies often
## trade below 1. Vendors/exchange UIs read this; nothing hardcodes gold.
@export var gold_per_unit: float = 1.0

## Conversion back from gold into this currency is only allowed when true
## (tokens usually one-way: earned, spent, never re-minted from gold).
@export var convertible_to_gold: bool = false
@export var convertible_from_gold: bool = false

## Per-character wallet cap (0 = uncapped). Seasonal tokens cap hard so
## hoarding cannot stockpile past a season.
@export var wallet_cap: int = 0

## Whether wallet balance drops on death (harshcore rules; gold only).
@export var dropped_on_death: bool = false

## Faction gate: empty = everyone. Non-empty = only that faction holds it.
@export var faction_id: String = ""

## Soulbound wallets cannot be traded between players at all.
@export var soulbound: bool = false

## Sort weight for wallet UI ordering.
@export var sort_order: int = 100
