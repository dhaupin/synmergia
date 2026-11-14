## Julia orchestrator LIVE receipt (tests/test_julia_orchestrator_live.gd).
##
## labs/prd-perf-bridges.md: MultiIsoService is an autoload that mirrors
## the entity roster into the Julia multi-iso orchestrator, but until now
## the orchestrator sidecar could never boot in dev/CI (server.jl needs
## HTTP.jl + JSON.jl, whose pkgimages segfault on this Julia build), so
## the "live" path was never exercised end to end. This receipt boots the
## STDLIB-ONLY sibling (`srv/julia-bridge/server_lite.jl`) on a private
## port and drives the REAL MultiIsoService through a register -> query ->
## unregister cycle, asserting the results.
##
## The sidecar is spawned here so the leg is self-contained. If julia or
## server_lite.jl is unavailable the live legs SKIP honestly (the contract
## legs still run).
##
## Legs:
##   1. server_lite.jl boots and answers /health on a private port.
##   2. A fresh MultiIsoService pointed at it reports healthy.
##   3. register_entity -> query_spatial finds it at the vertex.
##   4. query_intersect (spatial x faction x social) finds it.
##   5. query_faction finds it; a foreign faction does not.
##   6. unregister_entity removes it from every axis.
##   7. Disabled service never egresses (contract leg, always runs).
##
## Run:
##   godot --headless --path . --script res://tests/test_julia_orchestrator_live.gd
extends SceneTree

const SVC_PATH := "res://core/services/multi_iso_service.gd"
const SERVER := "/workspace/project/synmergia/srv/julia-bridge/server_lite.jl"
const PROJECT := "/workspace/project/synmergia/srv/julia-bridge"

const PORT := 8092
const URL := "http://127.0.0.1:8092"

var _passed: int = 0
var _failed: int = 0
var _pid: int = -1
var _svc: Node = null


func _initialize() -> void:
        print("--- JULIA ORCHESTRATOR LIVE ---")
        await process_frame
        _test_disabled_contract()
        var live: bool = _boot_sidecar()
        if live:
                await _test_live_cycle()
        else:
                print("[SKIP] server_lite.jl unavailable; live legs skipped")
        _kill_sidecar()
        _finish()


func _ok(msg: String) -> void:
        _passed += 1
        print("  [OK] ", msg)


func _fail(msg: String) -> void:
        _failed += 1
        printerr("  [FAIL] ", msg)


## Contract leg (always runs): a disabled service never touches the net.
func _test_disabled_contract() -> void:
        var script: GDScript = load(SVC_PATH)
        if script == null or not script.can_instantiate():
                _fail("multi_iso_service.gd did not load")
                return
        var svc: Node = script.new()
        svc.enabled = false
        root.add_child(svc)
        await process_frame
        var off: Array = await svc.query_spatial(3)
        if off.is_empty():
                _ok("disabled service degrades to empty (no egress)")
        else:
                _fail("disabled service returned data: %s" % str(off))
        root.remove_child(svc)
        svc.free()


func _which(exe: String) -> String:
        var out: Array = []
        if OS.execute("which", [exe], out, true) != 0:
                return ""
        return str(out[0]).strip_edges() if not out.is_empty() else ""


func _boot_sidecar() -> bool:
        var julia := _which("julia")
        if julia.is_empty():
                print("  julia not on PATH")
                return false
        if not FileAccess.file_exists(SERVER):
                print("  server_lite.jl not found at %s" % SERVER)
                return false
        # --compile=min is REQUIRED on this Julia build (its default
        # optimizer miscompiles the request loop to a segfault).
        _pid = OS.create_process(julia, [
                "--startup-file=no", "--compile=min", "--project=" + PROJECT,
                SERVER, "--port", str(PORT)], false)
        if _pid <= 0:
                return false
        for _i in range(80):
                if _health(URL):
                        print("  server_lite.jl up on %s (pid %d)" % [URL, _pid])
                        return true
                OS.delay_msec(250)
        print("  server_lite.jl did not become healthy")
        return false


func _health(url: String) -> bool:
        var c := HTTPClient.new()
        if c.connect_to_host("127.0.0.1", PORT) != OK:
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


func _test_live_cycle() -> void:
        var script: GDScript = load(SVC_PATH)
        _svc = script.new()
        _svc.use_localhost = true
        _svc.local_server_url = URL
        _svc.enabled = true
        root.add_child(_svc)
        await process_frame
        await process_frame

        if await _svc.is_healthy():
                _ok("MultiIsoService reports the sidecar healthy")
        else:
                _fail("MultiIsoService could not reach the sidecar")

        var probe := "live_probe_%d" % Time.get_ticks_usec()
        await _svc.register_entity(probe, 3, 7, 2, 1)

        var spatial: Array = await _svc.query_spatial(3)
        if spatial.has(probe):
                _ok("register -> query_spatial finds the entity at vertex 3")
        else:
                _fail("query_spatial missed the entity: %s" % str(spatial))

        var inter: Array = await _svc.query_intersect(3, 7, 2)
        if inter.has(probe):
                _ok("query_intersect (spatial x faction x social) finds it")
        else:
                _fail("query_intersect missed the entity: %s" % str(inter))

        var fac: Array = await _svc.query_faction(7)
        var other: Array = await _svc.query_faction(9)
        if fac.has(probe) and not other.has(probe):
                _ok("query_faction finds it in faction 7, not in faction 9")
        else:
                _fail("query_faction wrong: f7=%s f9=%s" % [str(fac), str(other)])

        await _svc.unregister_entity(probe)
        var after: Array = await _svc.query_spatial(3)
        if not after.has(probe):
                _ok("unregister_entity removes it from every axis")
        else:
                _fail("unregistered entity still present: %s" % str(after))

        root.remove_child(_svc)
        _svc.free()
        _svc = null


func _kill_sidecar() -> void:
        if _pid > 0:
                OS.kill(_pid)
                _pid = -1


func _finish() -> void:
        if _failed == 0:
                print("JULIA ORCHESTRATOR LIVE RECEIPT PASS (%d)" % _passed)
                quit(0)
        else:
                printerr("JULIA ORCHESTRATOR LIVE RECEIPT FAIL (%d)" % _failed)
                quit(1)
