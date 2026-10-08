## WebIdBridge - guest identity that survives a page reload (R48).
##
## The gap this closes: `login_as_guest()` mints a fresh account id
## (`guest_<ticks>`) EVERY call, so a browser reload re-enters the
## world as a brand-new guest -- the stable's RideService ownership
## ledger is keyed by player_id, so every purchase and every wallet
## is stranded behind the reload.
##
## Medium: user:// -- on web builds Godot mounts user:// to IndexedDB
## (the same mount the DurableStore snapshots live on, the SAME
## reload-durability tier), and on desktop it is a plain file, so one
## implementation serves both. This is deliberately NOT
## window.localStorage: the JS-eval path crosses Godot's worker
## boundary and failed silently in the first R48 probe run.
##
## Law: the remembered guest id is a small, non-secret, account-
## shaped convenience token -- the same tier as a remembered device
## login. It is NOT the password tier and must never hold one. When
## user:// is unavailable (--script tests run in an export sandbox
## without it), the bridge is invisible: get_last_guest_id answers ""
## and the login screen mints a fresh guest exactly as before. The
## product's credential tier stays username+password, untouched.
##
## Autoload: NO class_name (AGENTS rule). Mounted as WebIdBridge in
## project.godot, before the UI boots.
extends Node

const _PATH := "user://guest_identity.cfg"

## The last guest id this machine/browser played, or "" when none is
## remembered (and "" wherever FileAccess cannot open user:// -- the
## invisible contract).
func get_last_guest_id() -> String:
	var f := FileAccess.open(_PATH, FileAccess.READ)
	if f == null:
		return ""
	var id := f.get_line().strip_edges()
	if id.begins_with("guest_"):
		GameLog.info("WebIdBridge: read %s" % id)
		return id
	return ""

func remember_guest(account_id: String) -> void:
	if account_id == "" or not account_id.begins_with("guest_"):
		return
	var f := FileAccess.open(_PATH, FileAccess.WRITE)
	if f == null:
		GameLog.info("WebIdBridge: WRITE FAILED for %s" % account_id)
		return
	f.store_line(account_id)
	f.flush()
	GameLog.info("WebIdBridge: remembered %s" % account_id)

func forget_guest() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_PATH))

func has_last_guest() -> bool:
	return get_last_guest_id() != ""
