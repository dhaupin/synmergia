## Multiplayer host probe (batch 15): boots the real NetworkManager ENet
## server on a loopback port and stays alive for clients to connect.
## Exit code 0 after serving its window. Run:
##   cd game && godot --headless --path . --script res://tests/mp_host.gd
extends SceneTree

const PORT := 9101
const WAIT_SECONDS := 30.0
const EXPECT_PEERS := 2

var _peers: Array[int] = []

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	await process_frame
	var nm = root.get_node_or_null("NetworkManager")
	if nm == null:
		print("MPHOST fail: no NetworkManager autoload")
		quit(1)
		return
	var ok: bool = nm.start_server(PORT)
	await process_frame
	await process_frame
	if not ok or not nm.is_server:
		print("MPHOST fail: start_server returned false")
		quit(1)
		return
	print("MPHOST listening on %d (wall-clock wait for %d raw peers)" % [PORT, EXPECT_PEERS])
	# Raw ENet truth: multiplayer.get_peers(). The service-level
	# peer_connected signal only fires after the higher-level session
	# handshake, which raw probes do not perform. Wall-clock deadline --
	# headless frame loops run far faster than realtime.
	var deadline_ms := Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		await process_frame
		if root.get_multiplayer().get_peers().size() >= EXPECT_PEERS:
			break
	var raw := root.get_multiplayer().get_peers()
	print("MPHOST done raw_peers=", raw)
	quit(0 if raw.size() >= EXPECT_PEERS else 1)


func _on_peer(peer_id: int) -> void:
	_peers.append(peer_id)
	print("MPHOST peer_connected %d" % peer_id)
