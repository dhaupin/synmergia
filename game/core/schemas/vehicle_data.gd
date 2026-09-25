class_name VehicleData
extends Resource

## Data-driven multi-passenger transport. The engine ban shapes the
## roster: everything is creature-drawn, wind-driven, or buoyant -- no
## combustion, no factory parts. Vehicles differ from mounts by seat
## count and (later) station roles: a ferry moves groups between
## harbors, a caravan hauls trade goods, a siege drake is an event
## platform. Ownership is per-character or per-guild.

enum VehicleKind {
	CARAVAN,     # Ground wagon, trade goods + passengers
	FERRY,       # Water transport between harbors
	SLEDGE,      # Snow/ice ground transport
	SIEGE,       # Event/instance siege platform
	CUSTOM
}

enum VehicleSource {
	PURCHASE,
	GUILD,
	QUEST,
	EVENT
}

@export var id: String = ""
@export var display_name: String = "Vehicle"
@export var description: String = ""
@export var icon_path: String = ""
@export var model_path: String = ""

@export var kind: VehicleKind = VehicleKind.CARAVAN

## Movement multiplier over base speed while driven.
@export var speed_multiplier: float = 1.2

## Movement Design System profile override. Empty = movement_mechanical
## via DataService.get_mount_movement_profile() -- the single
## resolution path for mounts AND vehicles.
@export var movement_profile_id: String = ""

## Seats including the driver. 1 = solo transport.
@export var seat_count: int = 1

## Trade-goods capacity in stack units (0 = cannot haul).
@export var cargo_capacity: int = 0

## Character level required to drive.
@export var required_level: int = 10

## Guild-owned when true (purchase/claim flows through the guild).
@export var guild_owned: bool = false

## Acquisition
@export var source: VehicleSource = VehicleSource.PURCHASE
## Cost in CurrencyData units (gold per_unit when currency_id is "").
@export var currency_id: String = ""
@export var cost: int = 0

## Route definition for FERRY kind (gateway/waypoint ids it docks at).
@export var route_gateways: Array[String] = []

## Soulbound vehicles cannot transfer ownership.
@export var soulbound: bool = true
