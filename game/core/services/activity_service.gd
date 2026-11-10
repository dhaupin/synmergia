## ActivityService - the per-account idle clock (the AFK gate).
##
## The law this service holds (labs/prd-agent-play.md sec 17.3): AFK is a
## cross-cutting gate, not a lobby concern, so it gets its own clock. The
## clock tracks the last genuine activity per account and answers "is this
## account active for purpose X?" with a CONFIGURABLE, per-purpose timeout.
##
## The first purpose is "agent" (the human must be active for their agents
## to play; default 15 minutes). The same clock serves later needs without
## a new service (e.g. "store" -- a player store may idle ~4 hours before
## logout). Timeouts are process config, so they tune without touching the
## gate that reads them.
##
## Activity is any genuine play input. Because a macro or bot can FAKE
## activity, this service is also an anticheat INPUT: the raw activity
## timestamps + cadence are evidence a probe can read, not a verdict. This
## is an unwinnable arms race and worth the fight anyway -- the honest
## framing is that the clock CONTRIBUTES evidence, it does not prove intent.
##
## State is EPHEMERAL on purpose: idle state is about who is online NOW, so
## it is not persisted (a reboot means nobody is online). No KV door.
##
## Autoload: NO class_name (the autoload/class_name shadow rule). Extends
## Node; a single _process sweeps the clocks on a throttle.
extends Node

## The default timeout (seconds) for a purpose that has no override.
const DEFAULT_TIMEOUT: float = 900.0  # 15 minutes

## How long before a timeout the warning fires (the graceful alert, so the
## human and their agents see "you have been idle; your agents will be
## logged out" before the logout lands).
const WARN_LEAD: float = 60.0

## The sweep cadence (seconds between _process checks). Cheap on purpose:
## the clock is second-granular, so a 1 s tick is plenty.
const SWEEP_INTERVAL: float = 1.0

## Per-purpose timeout overrides (seconds). Seeded from the shipping law;
## an operator or a later feature may retune via set_timeout().
var _timeouts: Dictionary = {
	"default": DEFAULT_TIMEOUT,
	"agent": 900.0,    # 15 min -- the human must be active for agents to play
	"store": 14400.0,  # 4 h -- a later player-store AFK limit
}

## account_id -> last activity unix time (seconds).
var _last_activity: Dictionary = {}
## account_id -> { purpose: true } already-warned set (one warning per idle run).
var _warned: Dictionary = {}
## account_id -> { purpose: true } already-timed-out set (one emit per idle run).
var _idled: Dictionary = {}

var _sweep_accum: float = 0.0

signal activity_recorded(account_id: String)
signal idle_warning(account_id: String, purpose: String, seconds_remaining: float)
signal went_idle(account_id: String, purpose: String)
signal activity_resumed(account_id: String)


func _ready() -> void:
	GameLog.info("ActivityService: Ready (agent timeout %ds)" % int(get_timeout("agent")))


func _process(delta: float) -> void:
	_sweep_accum += delta
	if _sweep_accum < SWEEP_INTERVAL:
		return
	_sweep_accum = 0.0
	_sweep()


# == Public API =========================================================

## Record genuine activity for an account (any real play input). Idempotent
## and cheap; safe to call on every input event.
func touch(account_id: String) -> void:
	if account_id.strip_edges() == "":
		return
	var was_idle: bool = _idled.has(account_id) and not (_idled[account_id] as Dictionary).is_empty()
	_last_activity[account_id] = Time.get_unix_time_from_system()
	_warned.erase(account_id)
	_idled.erase(account_id)
	if was_idle:
		activity_resumed.emit(account_id)
		GameLog.info("ActivityService: %s resumed activity" % account_id)
	activity_recorded.emit(account_id)


## Drop an account's clock entirely (on logout). A later touch starts fresh.
func forget(account_id: String) -> void:
	_last_activity.erase(account_id)
	_warned.erase(account_id)
	_idled.erase(account_id)


## Seconds since the account's last activity, or -1 if it has no clock
## (never seen / forgotten). A never-seen account is treated as inactive
## by is_active() so a missing clock never opens a gate by accident.
func seconds_idle(account_id: String) -> float:
	if not _last_activity.has(account_id):
		return -1.0
	return Time.get_unix_time_from_system() - float(_last_activity[account_id])


## Is the account active for this purpose (idle time within the timeout)?
## A never-seen account is INACTIVE (fail closed).
func is_active(account_id: String, purpose: String = "default") -> bool:
	var idle: float = seconds_idle(account_id)
	if idle < 0.0:
		return false
	return idle <= get_timeout(purpose)


## The inverse, for callers that read it that way (agents log out when the
## human is AFK).
func is_afk(account_id: String, purpose: String = "agent") -> bool:
	return not is_active(account_id, purpose)


## The configured timeout (seconds) for a purpose.
func get_timeout(purpose: String) -> float:
	return float(_timeouts.get(purpose, DEFAULT_TIMEOUT))


## Retune a purpose's timeout (process config; no persistence).
func set_timeout(purpose: String, seconds: float) -> void:
	if seconds <= 0.0:
		return
	_timeouts[purpose] = seconds
	GameLog.info("ActivityService: timeout '%s' set to %ds" % [purpose, int(seconds)])


## The public board (a surface reads this; never invents a number).
func board(account_id: String) -> Dictionary:
	var idle: float = seconds_idle(account_id)
	return {
		"account_id": account_id,
		"known": idle >= 0.0,
		"seconds_idle": idle,
		"agent_active": is_active(account_id, "agent"),
		"agent_timeout": get_timeout("agent"),
	}


# == Internals ==========================================================

func _sweep() -> void:
	for account_id in _last_activity.keys():
		var idle: float = seconds_idle(account_id)
		for purpose in _timeouts.keys():
			var timeout: float = get_timeout(purpose)
			if idle > timeout:
				# Timed out: emit ONCE per idle run (the gate reads is_active,
				# so this is the alert side, not the gate itself).
				if not _has_flag(_idled, account_id, purpose):
					_set_flag(_idled, account_id, purpose)
					went_idle.emit(account_id, purpose)
					GameLog.info("ActivityService: %s idle past '%s' timeout (%ds)" % [account_id, purpose, int(timeout)])
			elif idle > timeout - WARN_LEAD:
				# In the warning window: alert ONCE per idle run.
				if not _has_flag(_warned, account_id, purpose):
					_set_flag(_warned, account_id, purpose)
					idle_warning.emit(account_id, purpose, timeout - idle)
					GameLog.info("ActivityService: %s nearing '%s' timeout (%ds left)" % [account_id, purpose, int(timeout - idle)])


func _has_flag(book: Dictionary, account_id: String, purpose: String) -> bool:
	var m = book.get(account_id, null)
	if not (m is Dictionary):
		return false
	return (m as Dictionary).has(purpose)


func _set_flag(book: Dictionary, account_id: String, purpose: String) -> void:
	var m: Dictionary = book.get(account_id, {})
	m[purpose] = true
	book[account_id] = m
