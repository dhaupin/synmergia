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
## The design ceiling ("up to 5 agents can play at once" -- a full
## 6-seat party: 1 human + 5 agents). The agent CHARACTERS live on the
## human's subaccount (up to 10, the normal character cap); this ladder
## caps how many may PLAY concurrently.
const MAX_SLOTS: int = 5

## The slot ladder, slot index (1-based) -> one-time sigil price,
## steeply progressive (labs/prd-monetization.md sec 43): unlocking all
## four paid slots is a month or more of ordinary play, or a purchase.
const SLOT_PRICES := {
	2: 250,
	3: 900,
	4: 2500,
	5: 6000,
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
	# The presence gate's close leg (labs/prd-agent-play.md sec 17.2): when
	# the human goes idle past the agent timeout, their agents leave play.
	# Deferred so the AFK clock (a sibling autoload) is ready first.
	_bind_presence_gate.call_deferred()


## Wire the AFK clock's idle signal into the unseat leg. Deferred + guarded
## (script-mode probes mount no clock; a re-enter must not double-connect).
func _bind_presence_gate() -> void:
	var act := _node("ActivityService")
	if act == null or not act.has_signal("went_idle"):
		return
	if not act.went_idle.is_connected(_on_human_idle):
		act.went_idle.connect(_on_human_idle)


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
	# The attached agent needs a home account (sec 17.1): the human's ONE
	# managed subaccount. Ensure it exists so the agent's characters link
	# somewhere real. Idempotent; a missing AccountService is not fatal
	# (script-mode probes), the attach still stands.
	_ensure_home_account(account_id)
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


# == Party bridge (AgentRoster -> PartyService) =========================
##
## The law (labs/prd-agent-play.md sec 12, 17): an attached agent is a
## SEPARATE player body that parties WITH its human (never the human's
## character). This section is the one seam that seats an attached agent
## into its human's party, and it is gated by presence: an agent may only
## be seated while the human is online and not AFK (can_play). Seating
## rides PartyService.add_member (the programmatic join) with the human as
## the leader, so every party consumer sees ordinary membership.

signal agent_seated(account_id: String, handle: String, party_id: String)
signal agent_unseated(account_id: String, handle: String)


## The presence gate (labs/prd-agent-play.md sec 17.2): an agent lane is
## closed unless the parent human is online AND active. Reads the AFK clock
## (ActivityService); a missing clock fails CLOSED (no accidental play).
func can_play(account_id: String) -> Dictionary:
	if account_id.strip_edges() == "":
		return {"ok": false, "reason": "an account is required"}
	var act := _node("ActivityService")
	if act == null or not act.has_method("is_active"):
		return {"ok": false, "reason": "no activity clock is mounted (the presence gate is closed)"}
	if not act.is_active(account_id, "agent"):
		return {"ok": false, "reason": "the human is offline or AFK - agents may not play"}
	return {"ok": true}


## Seat an attached agent's character into its human's party. Best-effort
## and honest: refuses by name when the gate is closed, when the human's
## live body is not resolvable, or when the agent has no character yet.
func seat_agent(account_id: String, handle: String) -> Dictionary:
	if owner_of(handle) != account_id:
		return {"ok": false, "reason": "agent '%s' is not attached to %s" % [handle, account_id]}
	var gate: Dictionary = can_play(account_id)
	if not gate.get("ok", false):
		return gate
	var human: String = _human_entity(account_id)
	if human == "":
		return {"ok": false, "reason": "the human's live body is not resolvable for this account"}
	var agent: String = _agent_entity(handle)
	if agent == "":
		return {"ok": false, "reason": "agent '%s' has no character to seat" % handle}
	var ps := _party_service()
	if ps == null:
		return {"ok": false, "reason": "no PartyService is mounted"}
	var party: Dictionary = ps.get_player_party(human)
	var party_id: String = String(party.get("id", ""))
	if party_id == "":
		party_id = String(ps.create_party(human))
		if party_id == "":
			return {"ok": false, "reason": "could not open a party for the human"}
	var res: Dictionary = ps.add_member(party_id, agent, human)
	if bool(res.get("ok", false)):
		agent_seated.emit(account_id, handle, party_id)
		GameLog.info("AgentRoster: seated agent %s in party %s (human %s)" % [handle, party_id, human])
	return res


## Unseat an agent (it left the party). Honest: false when the agent has no
## live body or was not in a party.
func unseat_agent(handle: String) -> bool:
	var agent: String = _agent_entity(handle)
	if agent == "":
		return false
	var ps := _party_service()
	if ps == null:
		return false
	if ps.get_player_party(agent).is_empty():
		return false
	var ok: bool = bool(ps.leave_party(agent))
	if ok:
		agent_unseated.emit(owner_of(handle), handle)
		GameLog.info("AgentRoster: unseated agent %s" % handle)
	return ok


## Seat every attached agent of an account (best-effort; returns the rows).
func seat_all(account_id: String) -> Array:
	var out: Array = []
	for handle in agents_of(account_id):
		out.append(seat_agent(account_id, String(handle)))
	return out


## Unseat every attached agent of an account. Returns how many left.
func unseat_all(account_id: String) -> int:
	var n := 0
	for handle in agents_of(account_id):
		if unseat_agent(String(handle)):
			n += 1
	return n


# == Internals ==========================================================

func _node(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(name))


func _party_service() -> Node:
	return _node("PartyService")


## The human's LIVE character id, resolved only for the local/session human
## (the account whose login owns this process). A remote human is not
## resolvable here yet, and we say so rather than guess an identity.
func _human_entity(account_id: String) -> String:
	var ls := _node("LoginService")
	if ls == null or not ls.has_method("get_current_account_id"):
		return ""
	if str(ls.get_current_account_id()) != account_id:
		return ""
	var pm := _node("PlayerManager")
	if pm == null or not ("local_player" in pm):
		return ""
	var lp = pm.local_player
	if lp != null and is_instance_valid(lp) and "entity_id" in lp:
		return str(lp.entity_id)
	return ""


## The agent's character id, read from the coordinator record (the honest
## handle -> character link; "" until the door assigns one).
func _agent_entity(handle: String) -> String:
	var coord := _coordinator()
	if coord == null or not coord.has_method("get_agent"):
		return ""
	var rec: Dictionary = coord.get_agent(handle)
	return String(rec.get("entity_id", ""))


## The human went idle (or logged out): their agents leave play, starting
## with the party (the body save/despawn is the door's later leg).
func _on_human_idle(account_id: String, purpose: String) -> void:
	if purpose != "agent":
		return
	var left: int = unseat_all(account_id)
	GameLog.info("AgentRoster: human %s idle - %d agent(s) left play" % [account_id, left])


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

## Ensure the human's managed subaccount exists (the agent's home account).
## Returns the subaccount id, or "" when AccountService is absent / refuses.
func _ensure_home_account(account_id: String) -> String:
	var acct := _node("AccountService")
	if acct == null or not acct.has_method("ensure_subaccount"):
		return ""
	return String(acct.ensure_subaccount(account_id))


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
