## test_activity_service.gd - receipt for the AFK/activity clock
## (labs/prd-agent-play.md sec 17.3; the presence gate's foundation).
##
##   cd game && godot --headless --path . --script res://tests/test_activity_service.gd
##
## Legs:
##   1. a never-seen account is INACTIVE (fail closed).
##   2. touch() opens the gate; the account is active for the agent purpose.
##   3. a short timeout makes an idle account AFK (the gate closes).
##   4. the warning fires once inside the lead window, then the idle emit
##      fires once past the timeout; a fresh touch clears both.
##   5. per-purpose timeouts are independent (a long 'store' purpose stays
##      active while the short 'agent' purpose has gone idle).
##   6. forget() drops the clock (a later read is unknown again).
extends SceneTree

const ACTIVITY := "res://core/services/activity_service.gd"

var _pass := 0
var _fail := 0
var _svc: Node = null


func _initialize() -> void:
	print("=== ACTIVITY SERVICE TEST ===")
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + msg)
	else:
		_fail += 1
		print("  [FAIL] " + msg)


func _run() -> void:
	# Boot the real autoload if present; else make a fresh instance (the
	# receipt must work in --script mode too, where autoloads are absent).
	_svc = root.get_node_or_null("ActivityService")
	if _svc == null:
		_svc = load(ACTIVITY).new()
		root.add_child(_svc)
	await process_frame
	_assert(_svc != null, "ActivityService present")

	var acct := "acct_afk_%d" % Time.get_ticks_msec()

	# 1. Fail closed on an unknown account.
	_assert(not _svc.is_active(acct, "agent"), "a never-seen account is inactive (fail closed)")
	_assert(_svc.seconds_idle(acct) < 0.0, "an unknown account reports no idle clock")

	# 2. Touch opens the gate.
	_svc.touch(acct)
	_assert(_svc.is_active(acct, "agent"), "a touched account is active for the agent purpose")
	_assert(_svc.seconds_idle(acct) >= 0.0, "the clock is live after touch")

	# 3. A short timeout closes the gate when idle.
	_svc.set_timeout("agent", 1.0)
	_svc.touch(acct)
	await create_timer(1.2).timeout
	_assert(not _svc.is_active(acct, "agent"), "an account idle past the timeout is AFK")
	_assert(_svc.is_afk(acct, "agent"), "is_afk mirrors is_active")

	# 4. The warn + idle emits fire once each, then a touch clears them.
	_svc.set_timeout("agent", 3.0)
	_svc.touch(acct)
	var warns := [0]
	var idles := [0]
	var _w = func(_a, _p, _r): warns[0] += 1
	var _i = func(_a, _p): idles[0] += 1
	_svc.idle_warning.connect(_w)
	_svc.went_idle.connect(_i)
	# Sit inside the warn window (> 3.0 - 1.0 = 2.0 s), then past it.
	await create_timer(2.4).timeout
	_svc._sweep()
	_assert(warns[0] == 1, "the idle warning fired once inside the lead window")
	await create_timer(1.0).timeout
	_svc._sweep()
	_svc._sweep()
	_assert(idles[0] == 1, "the went_idle emit fired once past the timeout")
	_svc.touch(acct)
	_svc._sweep()
	_assert(_svc.is_active(acct, "agent"), "a fresh touch resumes the gate")

	# 5. Per-purpose independence.
	_svc.set_timeout("agent", 1.0)
	_svc.set_timeout("store", 100.0)
	_svc.touch(acct)
	await create_timer(1.2).timeout
	_assert(not _svc.is_active(acct, "agent"), "the short 'agent' purpose has gone idle")
	_assert(_svc.is_active(acct, "store"), "the long 'store' purpose is still active")

	# 6. forget() drops the clock.
	_svc.forget(acct)
	_assert(_svc.seconds_idle(acct) < 0.0, "forget() drops the clock (unknown again)")
	_assert(not _svc.is_active(acct, "agent"), "a forgotten account is inactive")

	_finish()


func _finish() -> void:
	print("--- ACTIVITY SERVICE TEST: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
