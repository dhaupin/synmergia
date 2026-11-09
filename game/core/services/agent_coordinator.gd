## AgentCoordinator - the roster + work-item scheduler for MANY agents.
##
## AgentDriver (agent_driver.gd) is the control channel for ONE agent playing
## the local seat. AgentCoordinator sits above it and answers the owner's
## "maybe a few later": several agents registered by handle, each given work,
## each reporting back, with a sign-off gate for consequential actions.
##
## The vocabulary is deliberately Vant's (lib/agents.js + lib/agents/work.js):
## a roster (spawn/list/get/pause/resume/terminate) plus a work-item lifecycle
## (delegate -> poll -> complete, with approve/reject sign-off). Vant is the
## brain; this is the WORLD side it drives. See labs/prd-agent-play.md sec 8.
##
## THE TURN LAW (why this is not free-running parallelism on one client):
## the local seat's movement rides Input.action_press -- GLOBAL input state --
## so exactly ONE local agent may drive it at a time. The coordinator holds a
## single turn token and steps the roster round-robin: each step, the next
## agent with pending work performs ONE act, then the token passes. Agents on
## their OWN process/door (remote endpoints) are not serialized by this -- they
## run in their own input space; the coordinator still tracks them uniformly.
##
## ENDPOINTS: an agent's endpoint is where its verbs execute.
##   local   -> the AgentDriver autoload (the shared local seat; serialized)
##   callable-> any injected transport (a remote door client, a scripted
##              brain, a test double) with observe()/act() methods
## The endpoint interface is just observe()/act(id, args) -- the same two
## verbs AgentDriver exposes, so any door (HTTP, in-page, in-proc) qualifies.
##
## Enable: rides AgentDriver. Off unless the driver is enabled (SYN_AGENT=1).
extends Node

const STATE_IDLE := "idle"
const STATE_WORKING := "working"
const STATE_PAUSED := "paused"
const STATE_DONE := "done"

# Verbs that MUST be signed off before they run (consequence > trivial).
# The gate is honest by default: an unlisted verb runs, a listed one parks.
const APPROVAL_GATED := ["trade", "drop", "destroy", "spend", "purchase", "sell"]

var _agents: Dictionary = {}     # handle -> record
var _work: Dictionary = {}       # handle -> Array of work items (queue)
var _next_work_id: int = 1
var _turn_order: Array = []      # handles, round-robin cursor
var _turn_cursor: int = 0

func _ready() -> void:
	var d := _driver()
	if d == null or not d.is_enabled():
		GameLog.info("AgentCoordinator: idle (agent driver disabled; no roster).")

# -- Roster -----------------------------------------------------------------

## Register an agent by handle. opts: {name, role, endpoint, permissions}.
## endpoint defaults to the local seat (the AgentDriver autoload).
func register(handle: String, opts: Dictionary = {}) -> Dictionary:
	if handle.strip_edges() == "":
		return {"ok": false, "reason": "handle required"}
	if _agents.has(handle):
		return {"ok": false, "reason": "handle '%s' already registered" % handle}
	var endpoint = opts.get("endpoint", null)
	if endpoint == null:
		endpoint = _local_endpoint()
	if endpoint == null:
		return {"ok": false, "reason": "no local seat available"}
	_agents[handle] = {
		"handle": handle,
		"name": String(opts.get("name", handle)),
		"role": String(opts.get("role", "assistant")),
		"state": STATE_IDLE,
		"endpoint": endpoint,
		"permissions": opts.get("permissions", {}),
		"registered_frame": _frame(),
	}
	_work[handle] = []
	_turn_order.append(handle)
	return {"ok": true, "handle": handle}

func unregister(handle: String) -> bool:
	if not _agents.has(handle):
		return false
	_agents.erase(handle)
	_work.erase(handle)
	_turn_order.erase(handle)
	if _turn_cursor >= _turn_order.size():
		_turn_cursor = 0
	return true

func list_agents() -> Array:
	var out: Array = []
	for h in _turn_order:
		out.append(_public_record(_agents[h]))
	return out

func get_agent(handle: String) -> Dictionary:
	if not _agents.has(handle):
		return {}
	return _public_record(_agents[handle])

func pause(handle: String) -> bool:
	if not _agents.has(handle):
		return false
	_agents[handle]["state"] = STATE_PAUSED
	return true

func resume(handle: String) -> bool:
	if not _agents.has(handle):
		return false
	if _agents[handle]["state"] == STATE_PAUSED:
		_agents[handle]["state"] = STATE_IDLE
	return true

## Terminate = unregister (Vant's kill alias). A terminated handle is gone.
func terminate(handle: String) -> bool:
	return unregister(handle)

# -- Work items -------------------------------------------------------------

## Delegate a task to an agent. task: {verb, args} (a world verb) OR
## {id, args} (a stable handle). Returns a work id; the result lands via
## poll_work() after the agent's next turn. A gated verb parks for approval.
func delegate(handle: String, task: Dictionary) -> Dictionary:
	if not _agents.has(handle):
		return {"ok": false, "reason": "unknown handle '%s'" % handle}
	var verb: String = String(task.get("verb", task.get("id", "")))
	if verb == "":
		return {"ok": false, "reason": "task needs a verb or id"}
	var wid: int = _next_work_id
	_next_work_id += 1
	var gated: bool = _is_gated(verb) or bool(task.get("requires_approval", false))
	var item: Dictionary = {
		"work_id": wid,
		"verb": verb,
		"args": task.get("args", {}),
		"state": "pending_approval" if gated else "queued",
		"result": {},
		"gated": gated,
	}
	(_work[handle] as Array).append(item)
	if _agents[handle]["state"] == STATE_IDLE and not gated:
		_agents[handle]["state"] = STATE_WORKING
	return {"ok": true, "work_id": wid, "gated": gated}

## The result of the agent's most recent finished work item (or the queue head).
func poll_work(handle: String) -> Dictionary:
	if not _work.has(handle):
		return {"ok": false, "reason": "unknown handle '%s'" % handle}
	var queue: Array = _work[handle]
	for i in range(queue.size() - 1, -1, -1):
		var it: Dictionary = queue[i]
		if it["state"] == "done":
			return {"ok": true, "work_id": it["work_id"], "result": it["result"]}
	return {"ok": false, "reason": "no completed work"}

func queue_of(handle: String) -> Array:
	if not _work.has(handle):
		return []
	var out: Array = []
	for it in _work[handle]:
		out.append({"work_id": it["work_id"], "verb": it["verb"], "state": it["state"], "gated": it["gated"]})
	return out

## Sign off a gated work item: it becomes queued and will run on the next turn.
func approve(handle: String, work_id: int) -> Dictionary:
	var it := _find_work(handle, work_id)
	if it.is_empty():
		return {"ok": false, "reason": "no work %d for '%s'" % [work_id, handle]}
	if it["state"] != "pending_approval":
		return {"ok": false, "reason": "work %d is '%s', not awaiting approval" % [work_id, it["state"]]}
	it["state"] = "queued"
	if _agents[handle]["state"] == STATE_IDLE:
		_agents[handle]["state"] = STATE_WORKING
	return {"ok": true, "work_id": work_id}

func reject(handle: String, work_id: int, reason: String = "") -> Dictionary:
	var it := _find_work(handle, work_id)
	if it.is_empty():
		return {"ok": false, "reason": "no work %d for '%s'" % [work_id, handle]}
	if it["state"] != "pending_approval":
		return {"ok": false, "reason": "work %d is '%s', not awaiting approval" % [work_id, it["state"]]}
	it["state"] = "rejected"
	it["result"] = {"ok": false, "reason": reason if reason != "" else "rejected by sign-off"}
	_retire_if_idle(handle)
	return {"ok": true, "work_id": work_id}

# -- The turn scheduler -----------------------------------------------------

## Run ONE turn: the next agent (round-robin) with a queued item acts once.
## Returns a small record of what happened (or that nothing was runnable).
func step() -> Dictionary:
	var d := _driver()
	if d == null or not d.is_enabled():
		return {"ok": false, "reason": "agent driver disabled"}
	if _turn_order.is_empty():
		return {"ok": false, "reason": "empty roster"}
	var n: int = _turn_order.size()
	for _i in range(n):
		if _turn_cursor >= _turn_order.size():
			_turn_cursor = 0
		var handle: String = _turn_order[_turn_cursor]
		_turn_cursor = (_turn_cursor + 1) % maxi(1, _turn_order.size())
		var rec: Dictionary = _agents[handle]
		if rec["state"] == STATE_PAUSED:
			continue
		var item := _next_runnable(handle)
		if item.is_empty():
			continue
		var result: Dictionary = _run_item(rec, item)
		item["result"] = result
		item["state"] = "done"
		_retire_if_idle(handle)
		return {"ok": true, "handle": handle, "work_id": item["work_id"], "verb": item["verb"], "result": result}
	return {"ok": false, "reason": "no runnable work"}

## Run every turnnable item once, round-robin, until the roster drains (or a
## bound is hit). A convenience for a brain that wants a batch, not a step.
func run_until_idle(max_steps: int = 256) -> Dictionary:
	var ran: int = 0
	for _i in range(max_steps):
		var r: Dictionary = step()
		if not bool(r.get("ok", false)):
			break
		ran += 1
	return {"ok": true, "steps": ran}

# -- Status -----------------------------------------------------------------

func status() -> Dictionary:
	var d := _driver()
	var out: Dictionary = {
		"ok": true,
		"enabled": d != null and d.is_enabled(),
		"agents": list_agents(),
		"turn_cursor": _turn_cursor,
	}
	return out

# -- Internals --------------------------------------------------------------

func _driver() -> Node:
	return get_node_or_null("/root/AgentDriver")

func _local_endpoint() -> Variant:
	var d := _driver()
	if d == null:
		return null
	return d

func _frame() -> int:
	return int(Engine.get_process_frames())

func _is_gated(verb: String) -> bool:
	var v: String = verb.to_lower()
	for g in APPROVAL_GATED:
		if v == g or v.begins_with(g + ":"):
			return true
	return false

func _find_work(handle: String, work_id: int) -> Dictionary:
	if not _work.has(handle):
		return {}
	for it in _work[handle]:
		if int(it["work_id"]) == work_id:
			return it
	return {}

func _next_runnable(handle: String) -> Dictionary:
	if not _work.has(handle):
		return {}
	for it in _work[handle]:
		if it["state"] == "queued":
			return it
	return {}

func _run_item(rec: Dictionary, item: Dictionary) -> Dictionary:
	var endpoint = rec["endpoint"]
	var verb: String = String(item["verb"])
	var args: Dictionary = item["args"]
	if endpoint == null:
		return {"ok": false, "reason": "no endpoint"}
	# The endpoint contract is exactly AgentDriver's: act(id, args).
	if endpoint is Node:
		if endpoint.has_method("act"):
			return endpoint.act(verb, args)
		return {"ok": false, "reason": "endpoint has no act()"}
	if endpoint is Callable:
		return endpoint.call(verb, args)
	if endpoint.has_method("act"):
		return endpoint.act(verb, args)
	return {"ok": false, "reason": "endpoint has no act()"}

func _retire_if_idle(handle: String) -> void:
	if _next_runnable(handle).is_empty() and _count_pending(handle) == 0:
		_agents[handle]["state"] = STATE_IDLE

func _count_pending(handle: String) -> int:
	var c: int = 0
	for it in _work.get(handle, []):
		if it["state"] in ["queued", "pending_approval"]:
			c += 1
	return c

func _public_record(rec: Dictionary) -> Dictionary:
	return {
		"handle": rec["handle"],
		"name": rec["name"],
		"role": rec["role"],
		"state": rec["state"],
		"queued": _count_pending(rec["handle"]),
	}
