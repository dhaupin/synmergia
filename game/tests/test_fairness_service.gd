## test_fairness_service - the human/agent equality service is live.
##
## FairnessService (trust scores, anti-marathon debuff, consensus, and
## fairness violations) existed since birth but was never autoloaded and
## never compiled (four untyped `:=` inferences were parse errors). This
## receipt proves it now loads, is registered, wires the real lifecycle
## seams (player_entered_world registers, player_left unregisters, a real
## anti-cheat exploit drops trust), and persists trust through the KV door.
##
## Run: godot --headless --path game --script res://tests/test_fairness_service.gd
extends SceneTree

var _passed := 0
var _failed := 0


func _check(cond: bool, msg: String) -> void:
        if cond:
                _passed += 1
                print("   PASS  %s" % msg)
        else:
                _failed += 1
                print("   FAIL  %s" % msg)


func _finish() -> void:
        print("=== FAIRNESS SERVICE RECEIPT: %d passed, %d failed ===" % [_passed, _failed])
        quit(0 if _failed == 0 else 1)


func _initialize() -> void:
        call_deferred("_run")


func _run() -> void:
        await process_frame
        var svc = root.get_node_or_null("FairnessService")
        _check(svc != null, "FairnessService is autoloaded (registered on /root)")
        if svc == null:
                _finish()
                return
        _check(String(svc.get_script().resource_path).ends_with("fairness_service.gd"),
                "the autoload runs fairness_service.gd")

        # 1. Trust book: register -> initial trust -> violation drops it.
        svc.unregister_player("fx_a")
        svc.register_player("fx_a")
        _check(is_equal_approx(svc.get_trust("fx_a"), 0.5), "a fresh player starts at trust 0.5")
        var violations := [0]
        svc.fairness_violation.connect(func(_p, _t, _s) -> void: violations[0] += 1)
        svc.report_violation("fx_a", "speed_hack", 2)
        _check(is_equal_approx(svc.get_trust("fx_a"), 0.3),
                "a severity-2 violation costs 0.2 trust (0.5 -> 0.3)")
        _check(violations[0] == 1, "fairness_violation was emitted once")

        # 2. Anti-marathon debuff math.
        svc._player_session_start["fx_a"] = Time.get_ticks_msec() - int(7.0 * 3600000.0)
        _check(svc.get_marathon_debuff("fx_a") > 0.0,
                "a 7h session is past the 6h marathon threshold (debuff > 0)")
        _check(is_equal_approx(svc.get_marathon_debuff("fx_a"), 0.05),
                "1h past the threshold = 0.05 debuff")

        # 3. The real lifecycle seam: player_entered_world registers.
        svc.unregister_player("fx_b")
        svc._on_player_entered_world("fx_b", null)
        _check(svc._player_trust.has("fx_b"), "player_entered_world registers the player")
        # The real anti-cheat seam: exploit_detected drops trust.
        var before: float = svc.get_trust("fx_b")
        svc._on_exploit_detected("fx_b", "pattern_anomaly", {"confidence": 0.9})
        _check(svc.get_trust("fx_b") < before,
                "a high-confidence exploit_detected lowers trust")

        # 4. player_left unregisters (duck-typed entity with entity_id).
        svc._on_player_left({"entity_id": "fx_b"})
        _check(not svc._player_trust.has("fx_b"), "player_left unregisters the player")

        # 5. Persistence: a fresh instance reads the persisted trust back.
        svc._player_trust["fx_kv"] = 0.77
        svc._persist_trust("fx_kv")
        var fresh = load("res://core/services/fairness_service.gd").new()
        fresh._load_state()
        _check(is_equal_approx(fresh.get_trust("fx_kv"), 0.77),
                "trust survives a fresh instance via the KV door (0.77)")
        # cleanup
        var store := DictStore.new()
        store.erase("fairness:trust:fx_kv")
        svc.unregister_player("fx_a")

        _finish()
