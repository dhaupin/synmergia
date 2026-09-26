## Multiplayer client probe (batch 15): connects to the host probe's
## ENet server over loopback and verifies the handshake. Writes its
## progress to /tmp/mp_client_state so the shell can correlate both
## processes. Run (in parallel with mp_host):
##   cd game && godot --headless --path . --script res://tests/mp_client.gd
extends SceneTree

const PORT := 9101

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	await process_frame
	_write_state("starting")
	var nm = root.get_node_or_null("NetworkManager")
	if nm == null:
		_write_state("fail_no_networkmanager")
		quit(1)
		return
	var ok: bool = nm.connect_to_server("127.0.0.1", PORT)
	if not ok:
		_write_state("fail_connect_call")
		quit(1)
		return
	_write_state("connecting")
	var deadline_ms := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline_ms:
		await process_frame
		if nm.connection_state == nm.ConnectionState.CONNECTED:
			# Hold the session open like a real player (the host probe
			# polls for concurrent raw peers; an instant quit closes the
			# socket before it can ever be observed).
			_write_state("connected")
			print("MPCLIENT connected, holding 8s")
			var hold_until := Time.get_ticks_msec() + 8000
			while Time.get_ticks_msec() < hold_until:
				await process_frame
			quit(0)
			return
	_write_state("fail_timeout_state=%s" % str(nm.connection_state))
	quit(1)


func _write_state(s: String) -> void:
	var f := FileAccess.open("/tmp/mp_client_state", FileAccess.WRITE)
	if f != null:
		f.store_string(s)
		f.close()
