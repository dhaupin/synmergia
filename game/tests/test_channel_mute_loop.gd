extends SceneTree

## Channel-mute receipt (the channel_settings_changed owner round):
##   1. ChatService.set_channel_muted carries named refusals (System
##      protected, duplicates) and every real change EMITS
##      channel_settings_changed (the signal's consumer is real: this
##      panel + the display filter).
##   2. The mute list persists in the KV settings row
##      (chat:settings:<viewer>) and survives a fresh-service
##      reboot via _load_chat_state.
##   3. The slash commands (/mute //unmute //channels) ride the same
##      API -- /mute Global mutes exactly Global.
##   4. ChatUI.add_message drops a muted channel's incoming lines
##      (receive-side; System keeps its exemption inside the API).
##   5. ChannelSettingsUI renders every channel row and its toggle
##      writes the service truth it displays.
## Run:
##   godot --headless --path . --script res://tests/test_channel_mute_loop.gd

var _emit_viewer: String = ""
var _emit_channel: int = -1

func _initialize() -> void:
	# Autoload-lag law: the body runs on the first idle frame.
	_run.call_deferred()

func _run() -> void:
	var svc: Node = root.get_node_or_null("ChatService")
	if svc == null:
		push_error("FAIL: ChatService autoload not live in script mode")
		quit(1)
		return
	var trade: int = svc.Channel.TRADE
	var global: int = svc.Channel.GLOBAL
	var system: int = svc.Channel.SYSTEM

	# Start from a known state (a stale settings row from a previous
	# run would flip duplicate-refusal legs into successes).
	var store_probe = load("res://adapters/persistence/dict_store.gd").new()
	var kv_key := "chat:settings:mute_probe"
	var _erased: Variant = store_probe.erase(kv_key)
	svc.set_channel_muted("mute_probe", trade, false)
	svc.set_channel_muted("mute_probe", global, false)

	# 1a. API mute + signal truth.
	svc.channel_settings_changed.connect(_on_settings_changed)
	var mute_result: Dictionary = svc.set_channel_muted("mute_probe", trade, true)
	if not bool(mute_result.get("success", false)):
		push_error("FAIL: set_channel_muted refused: %s" % str(mute_result))
		quit(1)
		return
	if _emit_viewer != "mute_probe" or _emit_channel != trade:
		push_error("FAIL: channel_settings_changed did not fire with the change (viewer='%s' channel=%d)" % [_emit_viewer, _emit_channel])
		quit(1)
		return
	print("[OK] mute fires channel_settings_changed with viewer + channel")

	# 1b. Named refusals: duplicate + protected channel.
	var dup_result: Dictionary = svc.set_channel_muted("mute_probe", trade, true)
	if bool(dup_result.get("success", false)):
		push_error("FAIL: duplicate mute accepted: %s" % str(dup_result))
		quit(1)
		return
	if not str(dup_result.get("message", "")).contains("already"):
		push_error("FAIL: duplicate refusal carried no named cause: %s" % str(dup_result))
		quit(1)
		return
	var sys_result: Dictionary = svc.set_channel_muted("mute_probe", system, true)
	if bool(sys_result.get("success", false)):
		push_error("FAIL: System was muted (it is the game's feedback voice)")
		quit(1)
		return
	if not svc.is_channel_muted("mute_probe", trade) or svc.is_channel_muted("mute_probe", system):
		push_error("FAIL: the mute state drifted (Trade=%s System=%s)" % [str(svc.is_channel_muted("mute_probe", trade)), str(svc.is_channel_muted("mute_probe", system))])
		quit(1)
		return
	print("[OK] duplicate + System-mute refused with named causes, state exact")

	# 2. Persistence: the settings KV row carries the record, and a
	# FRESH service instance revived through _load_chat_state sees it.
	var stored: Variant = store_probe.get_value(kv_key)
	if not (stored is Dictionary) or not (stored as Dictionary).has("muted_channels"):
		push_error("FAIL: the mute did not reach the settings KV row (%s = %s)" % [kv_key, str(stored)])
		quit(1)
		return
	var reborn = load("res://core/services/chat_service.gd").new()
	reborn._load_chat_state()
	if not reborn.is_channel_muted("mute_probe", trade):
		push_error("FAIL: a revived service lost the mute (reboot evaporation)")
		quit(1)
		return
	reborn.free()
	print("[OK] the mute survives a fresh-service reboot through _load_chat_state")

	# 3. The slash commands ride the API: /mute Global mutes exactly
	# Global; /channels runs the state board.
	if not svc._handle_command("mute_probe", 0, "mute Global", ""):
		push_error("FAIL: /mute Global did not report success")
		quit(1)
		return
	if not svc.is_channel_muted("mute_probe", global) or svc.is_channel_muted("mute_probe", trade) == false:
		push_error("FAIL: /mute hit the wrong channel")
		quit(1)
		return
	if not svc._handle_command("mute_probe", 0, "channels", ""):
		push_error("FAIL: /channels did not complete")
		quit(1)
		return
	print("[OK] /mute + /channels ride the API")

	# 4. The display filter: a muted channel's incoming line never
	# reaches the panel under the same viewer; other channels flow.
	var panel = load("res://ui/components/chat_ui.gd").new()
	root.add_child(panel)
	await process_frame
	var msg_before: int = panel._message_count
	panel.add_message("Trade_Spammer", trade, "you cannot see this", "mute_probe")
	if panel._message_count != msg_before:
		push_error("FAIL: a muted channel's line was displayed (%d -> %d)" % [msg_before, panel._message_count])
		quit(1)
		return
	panel.add_message("Zone_Crier", 3, "this shows fine", "mute_probe")
	if panel._message_count != msg_before + 1:
		push_error("FAIL: an unmuted channel's line was dropped (count=%d)" % panel._message_count)
		quit(1)
		return
	panel.add_message("SYSTEM", system, "system lines always show", "mute_probe")
	if panel._message_count != msg_before + 2:
		push_error("FAIL: the System line vanished (count=%d)" % panel._message_count)
		quit(1)
		return
	print("[OK] ChatUI drops muted-channel lines, keeps other channels + System")

	# 5. The panel leg: standard shell, every-channel rows, and its
	# toggle writes the service truth it displays (viewer "" in
	# script mode -- the same key the live panel resolves to).
	var book = load("res://ui/components/channel_settings_ui.gd").new()
	root.add_child(book)
	book._ensure_content()
	if not book.has_node("Panel/Main/ChannelRows"):
		push_error("FAIL: ChannelSettingsUI did not build its standard shell")
		quit(1)
		return
	book._refresh()
	if not book.shows_channel("Trade") or not book.shows_channel("System (always shown)"):
		push_error("FAIL: the panel is missing catalog rows (Trade/System)")
		quit(1)
		return
	print("[OK] ChannelSettingsUI renders the channel catalog incl. protected System")

	book._on_toggle_pressed(trade, true)
	if not svc.is_channel_muted("", trade):
		push_error("FAIL: the panel toggle did not write the service truth")
		quit(1)
		return
	if _emit_viewer != "" or _emit_channel != trade:
		push_error("FAIL: the panel toggle did not fire the service signal")
		quit(1)
		return
	# queue_free is deferred: the old Row_Trade lingers for this frame
	# and Godot renames the fresh twin, so read truth through the rows
	# (latest added wins), never through a flat node path.
	var row_state: Label = null
	for child in book.get_node("Panel/Main/ChannelRows").get_children():
		if child is HBoxContainer:
			var nm: Label = null
			var st: Label = null
			for entry in child.get_children():
				if entry is Label and str(entry.name) == "RowName" and str(entry.text) == "Trade":
					nm = entry
				if entry is Label and str(entry.name) == "RowState":
					st = entry
			if nm != null and st != null:
				row_state = st
	if row_state == null or str(row_state.text) != "hidden":
		push_error("FAIL: the row state did not flip with the truth (text='%s')" % str(row_state.text))
		quit(1)
		return
	print("[OK] the panel's toggle writes the truth it displays + fires the signal")

	# Tidy: leave both probe keys unmuted (the erase above covers
	# next-run state; the live singleton list keeps nothing behind).
	svc.set_channel_muted("mute_probe", trade, false)
	svc.set_channel_muted("mute_probe", global, false)
	svc.set_channel_muted("", trade, false)
	panel.queue_free()
	book.queue_free()
	print("--- CHANNEL MUTE LOOP: ok=true ---")
	quit(0)

func _on_settings_changed(viewer_id: String, channel: int) -> void:
	_emit_viewer = viewer_id
	_emit_channel = channel
