## test_subaccount_law.gd - receipt for the managed subaccount
## (labs/prd-agent-play.md sec 17.1).
##
##   cd game && godot --headless --path . --script res://tests/test_subaccount_law.gd
##
## Legs:
##   1. ensure_subaccount is idempotent and stamps a real account record
##      (managed=true, parent_account set).
##   2. is_subaccount / subaccount_of / parent_of_subaccount read honestly.
##   3. a subaccount is never loggable (LoginService refuses it by name).
##   4. a human may not register an id in the reserved subaccount space.
##   5. the subaccount holds characters like any account (the agent lane is
##      first-class, sec 17.4).
##   6. the pairing survives a reload (rebuilt from the account's own stamp).
extends SceneTree

var _pass := 0
var _fail := 0
var _acct: Node = null
var _login: Node = null


func _initialize() -> void:
	print("=== SUBACCOUNT LAW TEST ===")
	call_deferred("_run")


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + msg)
	else:
		_fail += 1
		print("  [FAIL] " + msg)


func _run() -> void:
	_acct = root.get_node_or_null("AccountService")
	_login = root.get_node_or_null("LoginService")
	if _acct == null:
		_acct = load("res://core/services/account_service.gd").new()
		root.add_child(_acct)
	await process_frame

	var human := "subtest_%d" % Time.get_ticks_msec()
	_acct.create_account(human, "")
	_assert(_acct.get_account(human).get("id", "") == human, "the human account exists")

	# 1. idempotent + a real record.
	var sub1: String = _acct.ensure_subaccount(human)
	var sub2: String = _acct.ensure_subaccount(human)
	_assert(sub1 != "" and sub1 == sub2, "ensure_subaccount is idempotent")
	_assert(sub1.ends_with("~agent"), "the subaccount id carries the reserved marker")
	var rec: Dictionary = _acct.get_account(sub1)
	_assert(bool(rec.get("managed", false)), "the subaccount is marked managed")
	_assert(String(rec.get("parent_account", "")) == human, "the subaccount names its parent")

	# 2. reads.
	_assert(_acct.is_subaccount(sub1), "is_subaccount is true for the subaccount")
	_assert(not _acct.is_subaccount(human), "is_subaccount is false for the human")
	_assert(_acct.subaccount_of(human) == sub1, "subaccount_of resolves the human's lane")
	_assert(_acct.parent_of_subaccount(sub1) == human, "parent_of_subaccount resolves the human")

	# 3. never loggable (if LoginService is mounted).
	if _login != null:
		# Register the human for real so login has a store entry to reject on.
		_login.register(human + "_real", "secret123", "", "a@b.com")
		# A subaccount login must be refused by the managed gate, not by
		# "account not found" -- so make sure the store knows it too.
		var sub3: String = _acct.ensure_subaccount(human + "_real")
		var refused: bool = not _login.login(sub3, "anything")
		_assert(refused, "the subaccount login is refused")
		# 4. reserved id space.
		var squatted: bool = _login.register(sub3, "secret123", "", "c@d.com")
		_assert(not squatted, "a human may not register in the reserved subaccount space")

	# 5. the subaccount holds characters like any account.
	var agent_char := "char_agent_sub_%d" % Time.get_ticks_msec()
	var linked: bool = _acct.link_character(agent_char, sub1, {"display_name": "Rook"})
	_assert(linked, "a character links to the subaccount")
	_assert(_acct.get_account_by_character(agent_char).get("id", "") == sub1, "the character resolves back to the subaccount")

	# 6. the pairing survives a reload (rebuilt from the stamp).
	_acct._load_state()
	_assert(_acct.subaccount_of(human) == sub1, "the pairing survives a reload")

	_finish()


func _finish() -> void:
	print("--- SUBACCOUNT LAW TEST: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
