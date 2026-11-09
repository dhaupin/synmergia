## AgentRoster - the human<->agent pairing law (agent slots).
##
## The law this service holds (labs/prd-agent-play.md sec 12-13): every
## agent belongs to EXACTLY ONE human account, and every human account may
## run a bounded number of agents. An agent is a PLAYER-shaped body of its
## own -- agents never play a human's character. This service owns the
## pairing + the slot ledger; it does not own the agent's loop (that is
## AgentCoordinator) and it does not own the character (that is
## AccountService).
##
## The slot ladder (labs/prd-monetization.md sec 43, "The Agent Ledger"):
##   - the FIRST agent is free (production floor: DEFAULT_FREE_SLOTS).
##   - agents 2..10 cost Concord Sigils, progressively more expensive, in
##     ONE-TIME unlock purchases (an agent slot is owned forever, not
##     rented). The design ceiling is MAX_SLOTS = 10.
##   - the DEVELOPMENT/TESTING floor is generous: SYN_AGENT_DEV_SLOTS=5
##     grants the full 6-seat party (1 human + 5 agents) for free, so
##     devs and testers never pay to build. Production trims to 1 free.
##
## Email binding is the account floor (guest play is retired); the hosted
## auth provider is a later lane. Here we only enforce the pairing: no
## account, no agent.
##
## Autoload: NO class_name (AGENTS rule). Read-only access to AccountService
## and the ONE purse (InventoryComponent via InventoryService); spend rides
## the same add_currency/remove_currency ledger every other sink uses.
extends Node

const CURRENCY_ID := "currency_concord_sigil"
const DictStore = preload("res://adapters/persistence/dict_store.gd")

## The production free floor: the first agent is free.
const DEFAULT_FREE_SLOTS: int = 1
## The development/testing floor: the full 6-seat party (1 human + 5
## agents) rides free when SYN_AGENT_DEV_SLOTS names it.
const DEV_FREE_SLOTS: int = 5
## The design ceiling ("up to 10 agents can connect under your account").
const MAX_SLOTS: int = 10

## The slot ladder, slot index (1-based) -> one-time sigil price,
## progressively more expensive. Slots at or below the free floor are free
## (not rows here); a slot above MAX_SLOTS has no price.
const SLOT_PRICES := {
	2: 25,
	3: 60,
	4: 120,
	5: 200,
	6: 320,
	7: 480,
	8: 700,
	9: 980,
	10: 1400,
}

## The coordinator is the source of truth for live agent handles.
const _COORDINATOR := "AgentCoordinator"
const _KV_PREFIX := "agent_roster:"
const _KV_UNLOCKS := "agent_roster:unlocks"

signal agent_slot_unlocked(account_id: String, slot_index: int, price: int)
signal agent_attached(account_id: String, handle: String, slot_index: int)
signal agent_detached(account_id: String, handle: String)

# account_id -> { slot_index: handle }
var _attachments: Dictionary = {}
# account_id -> [int] owned slot indices (>= 1)
var _unlocks: Dictionary = {}


func _ready() -> void:
	_load_state()
	GameLog.info("AgentRoster: Ready (%d accounts with unlocked slots)" % _unlocks.size())


# == Public API =========================================================

## The number of agent slots this account may use: the free floor, plus
## every slot it has paid for, capped at the design ceiling.
func effective_slots(account_id: String) -> int:
	var owned: Array = _unlocks.get(account_id, [])
	var n: int = free_floor() + owned.size()
	return min(n, MAX_SLOTS)


## The free floor for THIS process: the production default, or the
## development/testing floor when SYN_AGENT_DEV_SLOTS names one.
func free_floor() -> int:
	var raw := OS.get_environment("SYN_AGENT_DEV_SLOTS")
	if raw.strip_edges() != "":
		var n := int(raw)
		if n > 0:
			return min(n, MAX_SLOTS)
	return DEFAULT_FREE_SLOTS

## The live agents (coordinator handles) attached to this account.
func agents_of(account_id: String) -> Array:
	var map: Dictionary = _attachments.get(account_id, {})
	var out: Array = map.values()
	out.sort()
	return out

## How many agent slots this account has free right now.
func available_slots(account_id: String) -> int:
	return effective_slots(account_id) - agents_of(account_id).size()

## Is this account allowed to attach one more agent?
func can_attach(account_id: String) -> Dictionary:
	if account_id.strip_edges() == "":
		return {"ok": false, "reason": "an account is required (guest play is retired)"}
	if available_slots(account_id) <= 0:
		return {"ok": false, "reason": "no free agent slots - unlock one with sigils (you have %d of %d)" % [agents_of(account_id).size(), effective_slots(account_id)]}
	return {"ok": true}

## Attach a live coordinator agent to this account. 1:1 -- a handle belongs
## to exactly one account.
func attach(account_id: String, handle: String) -> Dictionary:
	if account_id.strip_edges() == "":
		return {"ok": false, "reason": "an account is required (guest play is retired)"}
	if handle.strip_edges() == "":
		return {"ok": false, "reason": "an agent handle is required"}
	if not _coordinator_has(handle):
		return {"ok": false, "reason": "no agent '%s' is registered with the coordinator" % handle}
	if owner_of(handle) != "":
		return {"ok": false, "reason": "agent '%s' is already attached to %s" % [handle, owner_of(handle)]}
	var gate: Dictionary = can_attach(account_id)
	if not gate.get("ok", false):
		return gate
	var map: Dictionary = _attachments.get(account_id, {})
	var slot: int = _next_slot(account_id)
	map[slot] = handle
	_attachments[account_id] = map
	_persist_account(account_id)
	agent_attached.emit(account_id, handle, slot)
	GameLog.info("AgentRoster: %s attached agent %s (slot %d)" % [account_id, handle, slot])
	return {"ok": true, "slot_index": slot, "handle": handle}

## Detach a handle from whatever account owns it.
func detach(handle: String) -> bool:
	var owner_id: String = owner_of(handle)
	if owner_id == "":
		return false
	var map: Dictionary = _attachments.get(owner_id, {})
	for slot in map.keys():
		if map[slot] == handle:
			map.erase(slot)
			break
	_attachments[owner_id] = map
	_persist_account(owner_id)
	agent_detached.emit(owner_id, handle)
	GameLog.info("AgentRoster: %s detached agent %s" % [owner_id, handle])
	return true

## The account that owns a handle, or "" if unattached.
func owner_of(handle: String) -> String:
	for account_id in _attachments.keys():
		var map: Dictionary = _attachments[account_id]
		if map.values().has(handle):
			return account_id
	return ""

## The one-time sigil price of the next slot this account could buy, or -1
## when the ladder is exhausted (the spare is not for sale).
func next_slot_price(account_id: String) -> int:
	var slot: int = free_floor() + _unlocks.get(account_id, []).size() + 1
	if slot > MAX_SLOTS:
		return -1
	return int(SLOT_PRICES.get(slot, -1))

## Unlock the next priced agent slot, debiting Concord Sigils from the ONE
## purse. Refuses honestly when there is no priced slot left or the purse is
## short (naming the exact need). A failed debit never grants the slot.
func unlock_next_slot(account_id: String) -> Dictionary:
	if account_id.strip_edges() == "":
		return {"ok": false, "reason": "an account is required (guest play is retired)"}
	var slot: int = free_floor() + _unlocks.get(account_id, []).size() + 1
	if slot > MAX_SLOTS:
		return {"ok": false, "reason": "the agent ladder is full (%d slots)" % MAX_SLOTS}
	var price: int = int(SLOT_PRICES.get(slot, -1))
	if price < 0:
		return {"ok": false, "reason": "slot %d is not for sale" % slot}
	var inv = _inventory_of(account_id)
	if inv == null:
		return {"ok": false, "reason": "no purse found for this account"}
	if int(inv.get_currency_amount(CURRENCY_ID)) < price:
		return {"ok": false, "reason": "not enough Concord Sigils for slot %d (need %d, have %d)" % [slot, price, int(inv.get_currency_amount(CURRENCY_ID))]}
	if not inv.remove_currency(CURRENCY_ID, price):
		# The books never take sigils without granting the slot; a refused
		# debit is a hard stop, not a silent loss.
		GameLog.error("AgentRoster: sigil debit failed for %s slot %d - no slot granted" % [account_id, slot])
		return {"ok": false, "reason": "the sigil debit was refused - no slot granted"}
	var owned: Array = _unlocks.get(account_id, [])
	owned.append(slot)
	_unlocks[account_id] = owned
	_persist_account(account_id)
	agent_slot_unlocked.emit(account_id, slot, price)
	GameLog.info("AgentRoster: %s unlocked slot %d for %d sigils" % [account_id, slot, price])
	return {"ok": true, "slot_index": slot, "price": price, "slots": effective_slots(account_id)}

## The public board (a surface reads this; never invents a number).
func board(account_id: String) -> Dictionary:
	return {
		"account_id": account_id,
		"effective_slots": effective_slots(account_id),
		"used_slots": agents_of(account_id).size(),
		"available_slots": available_slots(account_id),
		"agents": agents_of(account_id),
		"next_slot_price": next_slot_price(account_id),
		"sigils": _sigils_of(account_id),
	}


# == Internals ==========================================================

func _next_slot(account_id: String) -> int:
	var used: Dictionary = _attachments.get(account_id, {})
	var slot: int = 1
	while used.has(slot):
		slot += 1
	return slot

func _sigils_of(account_id: String) -> int:
	var inv = _inventory_of(account_id)
	if inv == null:
		return 0
	return int(inv.get_currency_amount(CURRENCY_ID))

func _coordinator() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(_COORDINATOR))

func _coordinator_has(handle: String) -> bool:
	var coord := _coordinator()
	if coord == null or not coord.has_method("get_agent"):
		return false
	return not (coord.get_agent(handle) as Dictionary).is_empty()

func _inventory_of(account_id: String) -> InventoryComponent:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var svc := tree.root.get_node_or_null(NodePath("InventoryService"))
	if svc == null or not svc.has_method("get_inventory"):
		return null
	var inv = svc.get_inventory(account_id)
	if inv == null or not is_instance_valid(inv):
		return null
	return inv

func _kv() -> DictStore:
	return DictStore.new()

func _persist_account(account_id: String) -> void:
	var store := _kv()
	var blob := {
		"attachments": _attachments.get(account_id, {}),
		"unlocks": _unlocks.get(account_id, []),
	}
	store.set_value(_KV_PREFIX + account_id, blob)

func _load_state() -> void:
	var store := _kv()
	var keys: Array = store.all_keys()
	for key in keys:
		var k := String(key)
		if not k.begins_with(_KV_PREFIX):
			continue
		var account_id := k.substr(_KV_PREFIX.length())
		var blob = store.get_value(k)
		if not (blob is Dictionary):
			continue
		var att = blob.get("attachments", {})
		if att is Dictionary and not att.is_empty():
			# JSON stringifies int keys -- normalize back to int.
			var norm: Dictionary = {}
			for slot in att.keys():
				norm[int(slot)] = String(att[slot])
			_attachments[account_id] = norm
		var unlocks = blob.get("unlocks", [])
		if unlocks is Array and not unlocks.is_empty():
			var ul: Array = []
			for s in unlocks:
				ul.append(int(s))
			_unlocks[account_id] = ul
