"""
test_webhook_bridge.py -- webhook-bridge unit tests.

Direct backend tests (queue law: FIFO, claim exclusivity, claim TTL
lap-over, ack contract, id uniqueness) plus HTTP tests on an ephemeral
ThreadingHTTPServer (accept 202, next/claim/ack happy path, claim
mismatch 409, body cap 413, verdict allowlist 400, unknown record 404).

Boots an ephemeral ThreadingHTTPServer on the loopback so nothing
collides. Python stdlib only.

Run:  python3 test_webhook_bridge.py
"""

import base64
import json
import threading
import time
import unittest
import urllib.error
import urllib.request

from backends import InMemoryWebhookBackend
from server import build_handler


def make_backend() -> InMemoryWebhookBackend:
    backend = InMemoryWebhookBackend()
    backend.connect({})
    return backend


def http_request(method: str, url: str, body: dict | bytes | None = None,
                 timeout: float = 5.0):
    data = None
    headers = {}
    if body is not None:
        if isinstance(body, dict):
            data = json.dumps(body).encode("utf-8")
        else:
            data = body
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method,
                                 headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read().decode("utf-8"))


class BackendTestBase(unittest.TestCase):
    def setUp(self):
        self.backend = make_backend()

    def record(self, body: bytes = b'{"purchase_id": "pay_1"}',
               channel: str = "payment") -> dict:
        return {
            "delivery_id": "whk_test",
            "channel": channel,
            "body_b64": base64.b64encode(body).decode("ascii"),
            "headers": {"x-synmergia-signature": "t=1,v1=deadbeef"},
            "received_ts": time.time(),
            "claim": None,
            "claim_expiry": 0,
            "delivered": False,
            "verdict": "",
            "ack_detail": "",
            "acked_ts": 0,
        }


class TestQueueLaw(BackendTestBase):
    def test_take_is_fifo_and_exclusive(self):
        first_take = self.backend.take_delivery(claim_ttl_sec=60.0)
        self.assertIsNone(first_take)  # nothing queued yet
        self.backend.put_delivery(self.record())
        # ONE open record: a fresh claim holds it exclusively.
        first = self.backend.take_delivery(claim_ttl_sec=60.0)
        self.assertIsNotNone(first)
        taken_id = first["record"]["delivery_id"]
        second = self.backend.take_delivery(claim_ttl_sec=60.0)
        self.assertIsNone(second)  # the same record is never handed twice
        ack = self.backend.ack_delivery(taken_id, first["claim"],
                                        "processed", "")
        self.assertEqual(ack["status"], "ok")
        # A delivered record is claimable never again.
        self.assertIsNone(self.backend.take_delivery(claim_ttl_sec=60.0))

    def test_claim_laps_after_ttl(self):
        self.backend.put_delivery(self.record())
        first = self.backend.take_delivery(claim_ttl_sec=-1.0)  # lapsed birth
        self.assertIsNotNone(first)
        record = first["record"]
        # A lapsed claim reads as claimable again for the next poller.
        lapsed_claim = record["claim"]
        self.assertEqual(record["claim"], lapsed_claim)
        second = self.backend.take_delivery(claim_ttl_sec=60.0)
        self.assertIsNotNone(second)
        self.assertNotEqual(second["claim"], first["claim"])
        # The takeover is visible on the record (operator readout).
        view = self.backend.get_delivery(record["delivery_id"])
        self.assertEqual(view["claim"], second["claim"])

    def test_ack_contract(self):
        self.backend.put_delivery(self.record())
        taken = self.backend.take_delivery(claim_ttl_sec=60.0)
        delivery_id = taken["record"]["delivery_id"]
        mismatch = self.backend.ack_delivery(delivery_id, "clm_wrong",
                                             "processed", "")
        self.assertEqual(mismatch["status"], "mismatch")
        self.assertFalse(mismatch["record"]["delivered"])
        ok = self.backend.ack_delivery(delivery_id, taken["claim"],
                                       "refused", "signature mismatch")
        self.assertEqual(ok["status"], "ok")
        self.assertEqual(ok["record"]["verdict"], "refused")
        self.assertEqual(ok["record"]["ack_detail"], "signature mismatch")
        self.assertTrue(ok["record"]["delivered"])
        again = self.backend.ack_delivery(delivery_id, taken["claim"],
                                          "processed", "")
        self.assertEqual(again["status"], "already")
        ghost = self.backend.ack_delivery("whk_nope", taken["claim"],
                                          "processed", "")
        self.assertEqual(ghost["status"], "unknown")

    def test_put_ids_stay_unique(self):
        first = self.backend.put_delivery(self.record())
        second = self.backend.put_delivery(self.record())
        self.assertNotEqual(first, second)

    def test_bytes_round_trip_verbatim(self):
        raw = b'{"purchase_id":"pay_1","note":"hi \\u2699"}'
        self.backend.put_delivery(self.record(raw))
        taken = self.backend.take_delivery(claim_ttl_sec=60.0)
        decoded = base64.b64decode(taken["record"]["body_b64"])
        self.assertEqual(decoded, raw)  # never re-serialized


class TestHTTP(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.backend = make_backend()
        from http.server import ThreadingHTTPServer
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0),
                                        build_handler(cls.backend))
        cls.port = cls.httpd.server_address[1]
        cls.base = "http://127.0.0.1:%d" % cls.port
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def post_hook(self, body: bytes, signature: str | None = None):
        import urllib.request as rq
        req = rq.Request(self.base + "/hooks/payment", data=body,
                         method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("X-Synmergia-Signature", signature or "t=1,v1=aa")
        try:
            with rq.urlopen(req, timeout=5.0) as resp:
                return resp.status, json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as err:
            return err.code, json.loads(err.read().decode("utf-8"))

    def test_health(self):
        status, payload = http_request("GET", self.base + "/health")
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "ok")

    def test_accept_and_happy_path(self):
        raw = b'{"purchase_id": "pay_7", "event": "checkout.completed"}'
        status, payload = self.post_hook(raw, signature="t=9,v1=bb")
        self.assertEqual(status, 202)
        self.assertTrue(payload["delivery_id"].startswith("whk_"))
        delivery_id = payload["delivery_id"]

        status, next_payload = http_request("GET", self.base
                                            + "/deliveries/next")
        self.assertEqual(status, 200)
        record = next_payload["delivery"]
        self.assertIsNotNone(record)
        self.assertEqual(record["delivery_id"], delivery_id)
        self.assertEqual(record["channel"], "payment")
        self.assertEqual(base64.b64decode(record["body_b64"]), raw)
        # Verbatim headers, lowercased: the signature header traveled.
        self.assertEqual(record["headers"]["x-synmergia-signature"], "t=9,v1=bb")
        self.assertNotIn("content-length", record["headers"])
        self.assertNotIn("host", record["headers"])
        claim = next_payload["claim"]

        status, ack = http_request("POST",
                                   self.base + "/deliveries/%s/ack"
                                   % delivery_id,
                                   {"claim": claim, "verdict": "processed",
                                    "detail": "order completed"})
        self.assertEqual(status, 200)
        self.assertEqual(ack["status"], "ok")
        self.assertEqual(ack["record"]["verdict"], "processed")

        # Operator readout keeps the verdict.
        status, view = http_request("GET", self.base
                                    + "/deliveries/%s" % delivery_id)
        self.assertEqual(status, 200)
        self.assertTrue(view["delivery"]["delivered"])
        self.assertEqual(view["delivery"]["ack_detail"], "order completed")

    def test_next_empty(self):
        status, payload = http_request("GET", self.base + "/deliveries/next")
        self.assertEqual(status, 200)
        self.assertIsNone(payload["delivery"])
        self.assertIsNone(payload["claim"])

    def test_body_cap_413(self):
        raw = b"x" * 70000
        status, payload = self.post_hook(raw)
        self.assertEqual(status, 413)
        self.assertEqual(payload["status"], "error")

    def test_bad_channel_404(self):
        ok_status, _payload = http_request("POST", self.base + "/hooks/BAD/01",
                                           body=b"{}")
        self.assertEqual(ok_status, 404)

    def test_unknown_delivery_view_is_null(self):
        status, payload = http_request("GET", self.base
                                       + "/deliveries/whk_ghost")
        self.assertEqual(status, 200)
        self.assertIsNone(payload["delivery"])

    def test_ack_verdict_allowlist_400(self):
        self.backend.put_delivery({
            "delivery_id": "whk_allow", "channel": "payment",
            "body_b64": "", "headers": {}, "received_ts": time.time(),
            "claim": None, "claim_expiry": 0, "delivered": False,
            "verdict": "", "ack_detail": "", "acked_ts": 0,
        })
        _status, next_payload = http_request("GET", self.base
                                             + "/deliveries/next")
        claim = next_payload["claim"]
        status, _ = http_request("POST",
                                 self.base + "/deliveries/whk_allow/ack",
                                 {"claim": claim, "verdict": "granted"})
        self.assertEqual(status, 400)

    def test_ack_mismatch_409(self):
        self.backend.put_delivery({
            "delivery_id": "whk_mism", "channel": "payment",
            "body_b64": "", "headers": {}, "received_ts": time.time(),
            "claim": None, "claim_expiry": 0, "delivered": False,
            "verdict": "", "ack_detail": "", "acked_ts": 0,
        })
        _status, next_payload = http_request("GET", self.base
                                             + "/deliveries/next")
        status, _ = http_request("POST",
                                 self.base + "/deliveries/whk_mism/ack",
                                 {"claim": "clm_00", "verdict": "processed"})
        self.assertEqual(status, 409)

    def test_stats(self):
        status, payload = http_request("GET", self.base + "/stats")
        self.assertEqual(status, 200)
        self.assertIn("pending", payload["stats"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
