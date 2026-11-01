extends SceneTree

## Ignore book receipt (the chat moderation round):
##   1. ChatService.ignore_player persists through the KV store (the
##      list used to evaporate every reboot) and fires
##      player_chat_ignored / player_chat_unignored.
##   2. ChatUI drops blocked senders' lines at display time (by id or
##      best-known name; System lines exempted).
##   3. the IgnoreBookUI panel renders the persisted entries and its
##      unignore path clears them.
## Run:
##   godot --headless --path . --script res://tests/test_ignore_book_loop.gd

var _ignored_emit_target: String = ""
var _unignored_emit_target: String = ""

func _initialize() -> void:
	# Autoload-lag law: the body runs on the first idle frame.
	_run.call_deferred()

func _run() -> void:
	var svc: Node = root.get_node_or_null("ChatService")
	if svc == null:
		push_error("FAIL: ChatService autoload not live in script mode")
		quit(1)
		return

	# 1. API + persistence + signals.
	var store_probe = load("res://adapters/persistence/dict_store.gd").new()
	var kv_key := "chat:ignored:probe_ignorer"
	var before: Variant = store_probe.get_value(kv_key)
	if before != null and not (before is Array) or (before is Array and (before as Array).has("Rude_One")):
		# A stale entry from a previous run: clear it so this receipt
		# starts from a known state.
		var _cleared: Variant = store_probe.erase_value(kv_key) if store_probe.has_method("erase_value") else null
	svc.unignore_player("probe_ignorer", "Rude_One")
	svc.player_chat_ignored.connect(_on_chat_ignored)
	svc.player_chat_unignored.connect(_on_chat_unignored)
	var add_result: Dictionary = svc.ignore_player("probe_ignorer", "Rude_One")
	if not bool(add_result.get("success", false)):
		push_error("FAIL: ignore_player rejected: %s" % str(add_result))
		quit(1)
		return
	if _ignored_emit_target != "Rude_One":
		push_error("FAIL: player_chat_ignored did not fire (got '%s')" % _ignored_emit_target)
		quit(1)
		return
	print("[OK] ignore_player persisted list membership + fired player_chat_ignored")
	var stored: Variant = store_probe.get_value(kv_key)
	if not (stored is Array) or not (stored as Array).has("Rude_One"):
		push_error("FAIL: the ignore entry did not reach the KV store (%s = %s)" % [kv_key, str(stored)])
		quit(1)
		return
	print("[OK] the ignore entry survives in the KV store (no more reboot evaporation)")
	var dup_result: Dictionary = svc.ignore_player("probe_ignorer", "Rude_One")
	if bool(dup_result.get("success", false)):
		push_error("FAIL: duplicate ignore accepted: %s" % str(dup_result))
		quit(1)
		return
	print("[OK] duplicate ignore refused with a named cause")
	var self_result: Dictionary = svc.ignore_player("probe_ignorer", "probe_ignorer")
	if bool(self_result.get("success", false)):
		push_error("FAIL: self-ignore accepted")
		quit(1)
		return
	print("[OK] self-ignore refused")

	# 2. Display filter: ChatUI drops blocked senders (explicit viewer
	# leg; the live leg resolves the local player the same way the
	# filter helper does).
	var panel = load("res://ui/components/chat_ui.gd").new()
	root.add_child(panel)
	if svc.is_ignored_sender("probe_ignorer", "Rude_One") == false:
		push_error("FAIL: is_ignored_sender missed a plain-id entry")
		quit(1)
		return
	print("[OK] is_ignored_sender matches a plain-id blocked sender")
	var msg_before: int = panel._message_count
	panel.add_message("Rude_One", 0, "you cannot see this", "probe_ignorer")
	if panel._message_count != msg_before:
		push_error("FAIL: a blocked sender's line was displayed (%d -> %d)" % [msg_before, panel._message_count])
		quit(1)
		return
	panel.add_message("SYSTEM", 9, "system lines always show", "probe_ignorer")
	if panel._message_count != msg_before + 1:
		push_error("FAIL: a System line was wrongly filtered")
		quit(1)
		return
	panel.add_message("Probe_Kind", 0, "this shows fine", "probe_ignorer")
	if panel._message_count != msg_before + 2:
		push_error("FAIL: an unblocked sender's line did not display")
		quit(1)
		return
	print("[OK] ChatUI drops blocked senders, keeps System + unblocked lines")

	# 3. The panel: the book resolves its OWN viewer (the empty id in
	# script mode, key ""), so seed an entry under that key first --
	# the same path the panel's buttons use live.
	var book = load("res://ui/components/ignore_book_ui.gd").new()
	root.add_child(book)
	book._ensure_content()
	if not book.has_node("Panel/Main/IgnoreRows"):
		push_error("FAIL: IgnoreBookUI did not build its standard shell")
		quit(1)
		return
	svc.unignore_player("", "Probe_Target")
	var seeded: Dictionary = svc.ignore_player("", "Probe_Target")
	if not bool(seeded.get("success", false)):
		push_error("FAIL: could not seed the panel-leg entry: %s" % str(seeded))
		quit(1)
		return
	book._refresh()
	if not book.shows_entry("Probe_Target"):
		push_error("FAIL: the book did not render the persisted entry")
		quit(1)
		return
	print("[OK] IgnoreBookUI renders the persisted entry")
	book._on_unignore_pressed("Probe_Target")
	if _unignored_emit_target != "Probe_Target":
		push_error("FAIL: player_chat_unignored did not fire via the panel (got '%s')" % _unignored_emit_target)
		quit(1)
		return
	if not svc.get_ignored_players("").is_empty():
		push_error("FAIL: the panel's unignore left the entry behind")
		quit(1)
		return
	print("[OK] the panel's unignore clears the list and fires the signal")
	panel.queue_free()
	book.queue_free()
	print("--- IGNORE BOOK LOOP: ok=true ---")
	quit(0)

func _on_chat_ignored(ignorer_id: String, ignored_id: String) -> void:
	_ignored_emit_target = ignored_id

func _on_chat_unignored(ignorer_id: String, ignored_id: String) -> void:
	_unignored_emit_target = ignored_id
