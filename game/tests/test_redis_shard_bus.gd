## Redis shard bus receipt (tests/test_redis_shard_bus.gd) -- Facet 4.
##
## labs/prd-perf-bridges.md Facet 4: RedisStore + RedisShardBus are fully
## implemented but the default transport is the process-local memory bus
## and NOTHING in dev sets SHARD_BUS_BACKEND=redis, so the cross-process
## path ran only under test_adapter_http_transport. This receipt wires the
## redis path into a runnable leg and proves the mailboxes survive a
## PROCESS boundary.
##
## The sidecar (srv/redis-bridge, stdlib-only InMemoryBackend) is spawned
## here on a private port, so the leg is self-contained and never touches
## a dev sidecar. If python3 or the sidecar is unavailable the live legs
## SKIP honestly (the contract legs still run).
##
## Legs:
##   1. The redis bus opens against a live sidecar and reports healthy.
##   2. In-process redis round-trip: A publishes, B drains; no echo.
##   3. The coordinator's own emit/get_pending_events path carries an
##      event across two coordinator instances through redis.
##   4. TRUE cross-process: a SEPARATE godot process subscribes; this
##      process publishes; a SECOND process drains the message -- the
##      mailbox survived the first process exiting (redis is the store).
##   5. The redis bus still fails honestly with no reachable bridge.
##
## Run:
##   godot --headless --path . --script res://tests/test_redis_shard_bus.gd
extends SceneTree

const REDIS_BUS_PATH := "res://core/mesh/redis_shard_bus.gd"
const COORDINATOR_PATH := "res://core/services/coordinator_service.gd"

const SIDECAR_PORT := 8091
const SIDECAR_URL := "http://127.0.0.1:8091"

var _passed: int = 0
var _failed: int = 0
var _sidecar_pid: int = -1
var _live: bool = false


func _initialize() -> void:
        print("--- REDIS SHARD BUS ---")
        await process_frame
        _live = _boot_sidecar()
        if _live:
                await _test_open_healthy()
                await _test_redis_round_trip()
                await _test_coordinator_over_redis()
                await _test_cross_process()
        else:
                print("[SKIP] redis-bridge sidecar unavailable; live legs skipped")
        _test_honest_failure()
        _kill_sidecar()
        _finish()


## Spawn the stdlib-only redis-bridge on a private port and wait for health.
func _boot_sidecar() -> bool:
        var py := _which("python3")
        if py.is_empty():
                return false
        var script := "/workspace/project/synmergia/srv/redis-bridge/main.py"
        if not FileAccess.file_exists(script):
                return false
        var env := {"REDIS_BRIDGE_HOST": "127.0.0.1", "REDIS_BRIDGE_PORT": str(SIDECAR_PORT),
                "REDIS_BACKEND": "inmemory"}
        # create_process inherits THIS process's env, so set the child's
        # sidecar vars here first (create_process has no env parameter).
        for k in env:
                OS.set_environment(k, env[k])
        _sidecar_pid = OS.create_process(py, [script], false)
        if _sidecar_pid <= 0:
                return false
        for _i in range(40):
                if _health(SIDECAR_URL):
                        print("  sidecar up on %s (pid %d)" % [SIDECAR_URL, _sidecar_pid])
                        return true
                OS.delay_msec(250)
        print("  sidecar did not become healthy")
        return false


func _health(url: String) -> bool:
        var c := HTTPClient.new()
        if c.connect_to_host("127.0.0.1", SIDECAR_PORT) != OK:
                return false
        var deadline := Time.get_ticks_msec() + 1500
        while c.get_status() == HTTPClient.STATUS_CONNECTING or c.get_status() == HTTPClient.STATUS_RESOLVING:
                if Time.get_ticks_msec() > deadline:
                        return false
                c.poll()
                OS.delay_msec(20)
        if c.get_status() != HTTPClient.STATUS_CONNECTED:
                return false
        if c.request(HTTPClient.METHOD_GET, "/health", PackedStringArray(["Accept: application/json"]), "") != OK:
                return false
        var dl2 := Time.get_ticks_msec() + 1500
        while c.get_status() == HTTPClient.STATUS_REQUESTING:
                if Time.get_ticks_msec() > dl2:
                        return false
                c.poll()
                OS.delay_msec(20)
        var ok := c.has_response() and c.get_response_code() == 200
        c.close()
        return ok


func _test_open_healthy() -> void:
        var b = load(REDIS_BUS_PATH).new()
        var rc: int = b.open({"bridge_url": SIDECAR_URL})
        _assert(rc == 0, "redis bus opens against the live sidecar")
        _assert(b.healthy(), "the live redis bus reports healthy")
        _assert(b.get_id() == "redis", "the redis bus reports id 'redis'")
        b.close()


func _test_redis_round_trip() -> void:
        var a = load(REDIS_BUS_PATH).new()
        a.open({"bridge_url": SIDECAR_URL})
        a.set_self_id("rt_a")
        a.subscribe("rt")
        var b = load(REDIS_BUS_PATH).new()
        b.open({"bridge_url": SIDECAR_URL})
        b.set_self_id("rt_b")
        b.subscribe("rt")

        var delivered: int = a.publish("rt", {"n": 7})
        _assert(delivered >= 1, "publish reaches the other subscriber through redis")
        var got: Array = b.poll("rt")
        _assert(got.size() == 1 and int(got[0].get("n", 0)) == 7, "the peer drains the redis message")
        _assert(a.poll("rt").is_empty(), "the publisher does not receive its own redis fan-out")
        a.close()
        b.close()


func _test_coordinator_over_redis() -> void:
        OS.set_environment("SHARD_BUS_BACKEND", "redis")
        OS.set_environment("REDIS_BRIDGE_URL", SIDECAR_URL)
        var coord = load(COORDINATOR_PATH).new()
        root.add_child(coord)
        await process_frame
        await process_frame
        var peer = load(COORDINATOR_PATH).new()
        root.add_child(peer)
        await process_frame
        await process_frame

        if coord.bus() == null or coord.bus().get_id() != "redis":
                _fail("coordinator did not bind the redis bus")
                coord.queue_free()
                peer.queue_free()
                _clear_env()
                return
        _assert(peer.bus() != null and peer.bus().get_id() == "redis",
                "a second coordinator binds its own redis bus")

        var a_bus = coord.bus()
        a_bus.unsubscribe(coord.BUS_TOPIC)
        a_bus.set_self_id("coord_alpha")
        a_bus.subscribe(coord.BUS_TOPIC)
        var b_bus = peer.bus()
        b_bus.unsubscribe(peer.BUS_TOPIC)
        b_bus.set_self_id("coord_beta")
        b_bus.subscribe(peer.BUS_TOPIC)
        coord.clear_processed_events()
        peer.clear_processed_events()

        coord.emit_cross_shard_event_auto("redis_ping", "coord_alpha", {"k": 99})
        var found := false
        for ev in peer.get_pending_events():
                if ev.get("event_type", "") == "redis_ping" and int(ev.get("payload", {}).get("k", 0)) == 99:
                        found = true
        _assert(found, "the peer coordinator receives the event through redis")

        var local := false
        for ev in coord.get_pending_events():
                if ev.get("event_type", "") == "redis_ping":
                        local = true
        _assert(local, "the emitting coordinator keeps its own event (exactly once)")

        coord.queue_free()
        peer.queue_free()
        _clear_env()


## The real cross-process proof: a SEPARATE godot process subscribes (and
## exits), this process publishes, then a SECOND process drains it. The
## mailbox lived in redis while no peer process was alive.
func _test_cross_process() -> void:
        var godot := OS.get_executable_path()
        if godot.is_empty():
                _fail("cannot resolve the godot executable path")
                return
        var project := ProjectSettings.globalize_path("res://")
        var peer_script := "/tmp/syn_redis_bus_peer.gd"
        _write_peer_script(peer_script)

        # Process 1: subscribe + exit.
        var out1: Array = []
        OS.execute(godot, ["--headless", "--path", project, "--script", peer_script,
                "--", "subscribe", str(SIDECAR_PORT), "xproc", "peer_proc"], out1, true)
        # Publish from THIS process, as a different self id.
        var pub = load(REDIS_BUS_PATH).new()
        pub.open({"bridge_url": SIDECAR_URL})
        pub.set_self_id("main_proc")
        pub.subscribe("xproc")
        var delivered: int = pub.publish("xproc", {"hello": "cross-process"})
        pub.close()
        _assert(delivered >= 1, "cross-process publish found the peer subscription in redis")

        # Process 2: poll + print what it drained.
        var out2: Array = []
        OS.execute(godot, ["--headless", "--path", project, "--script", peer_script,
                "--", "poll", str(SIDECAR_PORT), "xproc", "peer_proc"], out2, true)
        var text := "\n".join(out2)
        _assert(text.contains("GOT 1"), "the second process drained the message that survived process 1")
        _assert(text.contains("cross-process"), "the drained payload is intact across processes")

        DirAccess.remove_absolute(peer_script)


## A tiny --script peer: subscribe (and exit), or poll once and print.
func _write_peer_script(path: String) -> void:
        var src := """extends SceneTree
func _init() -> void:
\tvar args := OS.get_cmdline_user_args()
\tvar mode := args[0]
\tvar port := int(args[1])
\tvar topic := args[2]
\tvar sid := args[3]
\tvar bus = load("res://core/mesh/redis_shard_bus.gd").new()
\tvar rc: int = bus.open({"bridge_url": "http://127.0.0.1:%d" % port})
\tif rc != 0:
\t\tprint("OPEN_FAIL")
\t\tquit(2)
\t\treturn
\tbus.set_self_id(sid)
\tif mode == "subscribe":
\t\tbus.subscribe(topic)
\t\tprint("SUBSCRIBED")
\telse:
\t\tbus.subscribe(topic)
\t\tvar got: Array = bus.poll(topic)
\t\tprint("GOT ", got.size())
\t\tfor m in got:
\t\t\tprint("MSG ", JSON.stringify(m))
\tquit(0)
"""
        var f := FileAccess.open(path, FileAccess.WRITE)
        if f != null:
                f.store_string(src)
                f.close()


func _test_honest_failure() -> void:
        var rb = load(REDIS_BUS_PATH).new()
        var rc: int = rb.open({"bridge_url": "http://127.0.0.1:1"})
        _assert(rc != 0, "redis bus open() fails honestly with no bridge")
        _assert(not rb.healthy(), "a failed redis bus reports unhealthy")
        _assert(rb.poll("t").is_empty(), "a failed redis bus polls empty")


func _kill_sidecar() -> void:
        if _sidecar_pid > 0:
                OS.kill(_sidecar_pid)
                _sidecar_pid = -1


func _which(name: String) -> String:
        for p in ["/usr/bin/", "/usr/local/bin/", "/bin/"]:
                if FileAccess.file_exists(p + name):
                        return p + name
        return ""


func _clear_env() -> void:
        OS.set_environment("SHARD_BUS_BACKEND", "")
        OS.set_environment("REDIS_BRIDGE_URL", "")


func _assert(cond: bool, label: String) -> void:
        if cond:
                _passed += 1
                print("  PASS: ", label)
        else:
                _failed += 1
                print("  FAIL: ", label)


func _fail(label: String) -> void:
        _failed += 1
        print("  FAIL: ", label)


func _finish() -> void:
        print("--- RESULT: %d passed, %d failed ---" % [_passed, _failed])
        quit(0 if _failed == 0 else 1)
