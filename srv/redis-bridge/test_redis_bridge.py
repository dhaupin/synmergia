"""
test_redis_bridge.py -- unit tests for the redis-bridge sidecar.

Runs entirely on stdlib (http.server + urllib + unittest).
Spins up ThreadingHTTPServer on an ephemeral port with the
InMemoryBackend, then exercises every wire endpoint.

Run:  python3 -m pytest  (or)  python3 test_redis_bridge.py
"""
from __future__ import annotations

import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from server import make_handler, build_backend  # noqa: E402


class RedisBridgeHarness:
    """Starts a redis-bridge on an ephemeral port with the InMemory backend."""

    def __init__(self, backend=None):
        self.backend = backend or build_backend("inmemory")
        self.handler = make_handler(self.backend)
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), self.handler)
        self.port = self.httpd.server_address[1]
        self._t = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self._t.start()

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.backend.close()

    base = property(lambda self: "http://127.0.0.1:%d" % self.port)

    def post(self, path, body):
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            self.base + path, data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, json.loads(r.read())

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=5) as r:
            return r.status, json.loads(r.read())


class TestRedisBridge(unittest.TestCase):
    def setUp(self):
        self.h = RedisBridgeHarness()

    def tearDown(self):
        self.h.stop()

    # -- health --

    def test_health(self):
        status, body = self.h.get("/health")
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])
        self.assertEqual(body["backend"], "InMemoryBackend")
        self.assertIn("version", body)

    # -- basic KV --

    def test_set_and_get(self):
        _, o = self.h.post("/set", {"key": "k", "value": "v"})
        self.assertTrue(o["ok"])
        status, body = self.h.get("/get?key=k")
        self.assertEqual(status, 200)
        self.assertEqual(body["value"], "v")

    def test_get_missing_returns_null(self):
        status, body = self.h.get("/get?key=missing")
        self.assertEqual(status, 200)
        self.assertIsNone(body["value"])

    def test_set_nx_first_wins(self):
        _, o = self.h.post("/set_nx", {"key": "k", "value": "a"})
        self.assertTrue(o["ok"])
        _, o2 = self.h.post("/set_nx", {"key": "k", "value": "b"})
        self.assertFalse(o2["ok"])
        status, body = self.h.get("/get?key=k")
        self.assertEqual(body["value"], "a")

    def test_delete(self):
        self.h.post("/set", {"key": "k", "value": "v"})
        _, body = self.h.post("/del", {"key": "k"})
        self.assertEqual(body["deleted"], 1)
        _, body2 = self.h.post("/del", {"key": "k"})
        self.assertEqual(body2["deleted"], 0)

    def test_exists(self):
        _, _ = self.h.post("/set", {"key": "k", "value": "v"})
        status, body = self.h.get("/exists?key=k")
        self.assertTrue(body["exists"])
        status, body2 = self.h.get("/exists?key=missing")
        self.assertFalse(body2["exists"])

    def test_expire(self):
        self.h.post("/set", {"key": "k", "value": "v"})
        _, body = self.h.post("/expire", {"key": "k", "ttl_sec": 10})
        self.assertEqual(body["changed"], 1)
        _, body2 = self.h.post("/expire", {"key": "missing", "ttl_sec": 10})
        self.assertEqual(body2["changed"], -1)

    # -- counters --

    def test_incr(self):
        _, body = self.h.post("/incr", {"key": "c", "by": 1})
        self.assertEqual(body["value"], 1)
        _, body2 = self.h.post("/incr", {"key": "c", "by": 5})
        self.assertEqual(body2["value"], 6)

    def test_incr_with_ttl(self):
        _, body = self.h.post("/incr_with_ttl", {"key": "c", "ttl_sec": 10})
        self.assertEqual(body["value"], 1)

    # -- hashes --

    def test_hset_hget_hget_all_hdel(self):
        self.h.post("/hset", {"key": "h", "field": "f", "value": "v"})
        status, body = self.h.get("/hget?key=h&field=f")
        self.assertEqual(body["value"], "v")
        status, allbody = self.h.get("/hget_all?key=h")
        self.assertEqual(allbody["fields"], {"f": "v"})
        _, d = self.h.post("/hdel", {"key": "h", "field": "f"})
        self.assertEqual(d["deleted"], 1)

    # -- sets --

    def test_sadd_smembers_sismember_srem(self):
        self.h.post("/sadd", {"key": "s", "member": "a"})
        self.h.post("/sadd", {"key": "s", "member": "b"})
        self.h.post("/sadd", {"key": "s", "member": "a"})  # dup -> added 0
        status, body = self.h.get("/smembers?key=s")
        self.assertEqual(sorted(body["members"]), ["a", "b"])
        status, ismem = self.h.get("/sismember?key=s&member=a")
        self.assertTrue(ismem["is_member"])
        _, r = self.h.post("/srem", {"key": "s", "member": "a"})
        self.assertEqual(r["removed"], 1)

    # -- lists --

    def test_lpush_rpush_lrange_llen_lpop(self):
        self.h.post("/lpush", {"key": "l", "value": "a"})
        self.h.post("/rpush", {"key": "l", "value": "c"})
        self.h.post("/lpush", {"key": "l", "value": "b"})  # b a c
        status, body = self.h.get("/lrange?key=l&start=0&stop=-1")
        self.assertEqual(body["values"], ["b", "a", "c"])
        status, llenbody = self.h.get("/llen?key=l")
        self.assertEqual(llenbody["length"], 3)
        _, pop = self.h.post("/lpop", {"key": "l"})
        self.assertEqual(pop["value"], "b")

    # -- pub/sub --

    def test_publish_returns_delivered(self):
        _, body = self.h.post("/publish", {"channel": "chan", "message": "hi"})
        self.assertEqual(body["delivered"], 0)  # no subscribers in test

    # -- error handling --

    def test_unknown_route_returns_404(self):
        try:
            self.h.get("/nope")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 404)



class TestRedisStoreContract(unittest.TestCase):
    """Mirror the exact HTTP sequence game/adapters/cache/redis_store.gd
    uses, to prove the bridge contract matches the adapter's expectations.

    This is the Python-side twin of the (currently stub) RedisStore.
    When RedisStore is wired for real, this test is the first thing to
    run against a live bridge.
    """

    def setUp(self):
        self.h = RedisBridgeHarness()

    def tearDown(self):
        self.h.stop()

    def _set(self, key, value, ttl_sec=0):
        return self.h.post("/set", {"key": key, "value": value, "ttl_sec": ttl_sec})

    def _fetch(self, key):
        return self.h.get("/get?key=" + key)

    def test_kv_store_fetch_roundtrip(self):
        st, o = self._set("session:tok1", "acc_alice", 86400)
        self.assertEqual(st, 200)
        self.assertTrue(o.get("ok"))
        st2, body = self._fetch("session:tok1")
        self.assertEqual(st2, 200)
        self.assertEqual(body.get("value"), "acc_alice")

    def test_session_token_lifecycle(self):
        # LoginService stores session:TOKEN -> account_id with 24h TTL.
        self._set("session:tok_abc", "acc_42", 86400)
        st, body = self.h.get("/exists?key=session:tok_abc")
        self.assertTrue(body["exists"])
        # Logout deletes the token.
        _, d = self.h.post("/del", {"key": "session:tok_abc"})
        self.assertEqual(d["deleted"], 1)
        st2, body2 = self.h.get("/exists?key=session:tok_abc")
        self.assertFalse(body2["exists"])

    def test_rate_limit_counter_pipeline(self):
        # QoSService / LoginService rate limiting: incr_with_ttl returns
        # the new count; the 6th attempt over the limit is rejected.
        for _ in range(5):
            _, b = self.h.post("/incr_with_ttl", {"key": "rl:alice", "ttl_sec": 60})
        self.assertGreaterEqual(b["value"], 5)
        # 6th push over the limit.
        _, b6 = self.h.post("/incr_with_ttl", {"key": "rl:alice", "ttl_sec": 60})
        self.assertGreater(b6["value"], 5)

    def test_online_status_hash(self):
        # FriendsService tracks per-player online status in a hash.
        self.h.post("/hset", {"key": "online:shard_1", "field": "acc_7", "value": "true"})
        st, body = self.h.get("/hget_all?key=online:shard_1")
        self.assertEqual(body["fields"].get("acc_7"), "true")


class TestPgRedisEndToEnd(unittest.TestCase):
    """Boot BOTH bridges (pg-bridge + redis-bridge) on ephemeral ports
    and prove the full adapter contract end-to-end, mirroring the
    LoginService vertical slice from labs/prd-db.md sec.10 step 5:

        AccountService -> AccountStore -> Postgres (pg-bridge)
        LoginService  -> SessionStore -> Redis  (redis-bridge)

    This is the Python-side twin of the (currently stub) Godot
    PostgresStore + RedisStore. When those adapters are wired for real,
    this test is the first thing to run against live bridges.
    """

    def setUp(self):
        import importlib.util
        import sys

        # Bring in the pg-bridge harness from the sibling sidecar. We load
        # it by file path (not `import`) because both sidecars define
        # `server` / `backends` modules -- a bare import would resolve to
        # whichever directory is already on sys.path (redis-bridge, here),
        # silently binding the pg-bridge harness to the wrong backend and
        # producing 404s on /execute and /query.
        here = os.path.dirname(os.path.abspath(__file__))
        pg_dir = os.path.abspath(os.path.join(here, "..", "pg-bridge"))
        pg_path = os.path.join(pg_dir, "test_pg_bridge.py")
        # Snapshot and clear the colliding module names so the file-path
        # loader below re-resolves them against pg-bridge's directory.
        saved = {}
        for name in ("server", "backends", "test_pg_bridge"):
            if name in sys.modules:
                saved[name] = sys.modules.pop(name)
        pg_spec = importlib.util.spec_from_file_location("test_pg_bridge", pg_path)
        pg_mod = importlib.util.module_from_spec(pg_spec)
        # test_pg_bridge does `sys.path.insert(0, <its own dir>)` at import
        # time, so its `from server import ...` resolves correctly.
        pg_spec.loader.exec_module(pg_mod)
        PgBridgeHarness = pg_mod.PgBridgeHarness

        # Load the redis-bridge backends by file path. We can't use a
        # bare `from backends import ...` because pg-bridge also defines
        # a `backends` module and sys.path ordering would pick the wrong one.
        spec = importlib.util.spec_from_file_location(
            "redis_backends", os.path.join(here, "backends.py"),
        )
        redis_backends = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(redis_backends)

        self.pg = PgBridgeHarness()
        self.redis = RedisBridgeHarness(
            backend=redis_backends.build_backend("inmemory")
        )

    def tearDown(self):
        self.pg.stop()
        self.redis.stop()

    def test_account_create_then_session_roundtrip(self):
        # 1. AccountService writes an account to Postgres (pg-bridge).
        st, body = self.pg.post("/execute", {
            "sql": "CREATE TABLE IF NOT EXISTS accounts ("
                   "id TEXT PRIMARY KEY, username TEXT NOT NULL, "
                   "password_hash TEXT NOT NULL)",
        })
        self.assertEqual(st, 200)
        st, body = self.pg.post("/execute", {
            "sql": "INSERT INTO accounts (id, username, password_hash) "
                   "VALUES ($1, $2, $3)",
            "params": ["acc_1", "alice", "h:12"],
        })
        self.assertEqual(body.get("affected", -1), 1)

        # 2. LoginService stores the session token in Redis (redis-bridge).
        st, o = self.redis.post("/set", {"key": "session:tok_x", "value": "acc_1", "ttl_sec": 86400})
        self.assertTrue(o.get("ok"))

        # 3. Cross-store verification: the token in Redis resolves to an
        #    account that exists in Postgres.
        st, sess = self.redis.get("/get?key=session:tok_x")
        self.assertEqual(sess.get("value"), "acc_1")
        st, rows = self.pg.post("/query", {
            "sql": "SELECT * FROM accounts WHERE id = $1",
            "params": ["acc_1"],
        })
        self.assertEqual(len(rows.get("rows", [])), 1)
        self.assertEqual(rows["rows"][0]["username"], "alice")

    def test_rate_limit_lives_in_redis_not_postgres(self):
        # QoSService rate limiting: counters in Redis, never in Postgres.
        # Each test gets a fresh backend, so create the accounts table
        # first (the query below targets it).
        self.pg.post("/execute", {
            "sql": "CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY)",
        })
        for _ in range(5):
            self.redis.post("/incr_with_ttl", {"key": "rl:alice", "ttl_sec": 60})
        st, body = self.redis.get("/get?key=rl:alice")
        self.assertGreaterEqual(int(body.get("value", 0)), 5)
        # Postgres accounts table should NOT have a row named rl:alice.
        st, rows = self.pg.post("/query", {
            "sql": "SELECT * FROM accounts WHERE id = $1",
            "params": ["rl:alice"],
        })
        self.assertEqual(rows.get("rows", []), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)

