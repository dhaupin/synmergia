extends Resource
class_name WardGateData

## The hard gate registry (labs/prd-ward-gate.md): the admin keys in
## one tres, and the breach embargo in the same place. Defense in
## depth means a gate opens only when EVERY key signal matches -- the
## role truth (server-side character class, never a client claim), the
## token mounts (the RideService ownership ledger), and the token
## items. The absence of any one signal is enough to keep it closed.
## An unknown rider is a closed gate: fail-closed is the default
## posture of every layer here.

@export var id: String = ""
@export var display_name: String = "Ward Gate"
@export var description: String = ""

## Role truth required to open (CharacterClass.Role). 0 = GM -- the
## role reserved in character_class.gd ("Never via .tres. Admin-only,
## guarded at login"). Resolved from server-side character data.
@export var key_role: int = 0

## Token mounts that must sit in the rider's ownership ledger
## (RideService.owns_mount). The Skywarden is the warden's key: it is
## fail-closed to grant for non-GM riders, so its presence in the
## ledger is itself a second, independently-verified signal.
@export var key_mounts: Array[String] = []

## Token items that must sit in the holder's inventory. Checked
## through the defensive lookup (InventoryService grows the method,
## the gate picks it up); until then this leg is fail-closed.
@export var key_items: Array[String] = []

## Labels of what this gate opens when every key matches ("opens gates
## and stuff" -- admin shell tiers, warden tools, future multiworld
## gates). Callers ask WardGateService.can_open and act on the label.
@export var opens: Array[String] = []

## The breach embargo: items listed here do not DROP. Drop a duped or
## exploited item id in here to kill its spawns while the breach is
## handled. The runtime ledger (WardGateService.embargo_item) carries
## the TEMPORARY ones -- same check, one lift_embargo call to clear.
@export var embargoed_items: Array[String] = []

## Why the standing embargo exists (admin logs only, never to players).
@export var embargo_reason: String = ""
