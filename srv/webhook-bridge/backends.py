"""
backends.py -- Delivery queue backends for the webhook-bridge sidecar.

webhook-bridge is the payment processor's HTTP entry. It accepts
delivery POSTs (the raw body bytes of an external processor webhook),
queues them durably, and hands each one to the game engine's poller
(which calls provider.handle_webhook once per delivery and acks with
the verdict).

Two backends:

  - InMemoryWebhookBackend : stdlib only. Local dev + unit tests. The
    queue does NOT survive a sidecar restart -- delivery is
    at-least-once, the processor retries on its own transport errors,
    and the engine armor is idempotent, so a dev reboot asks the
    processor to resend rather than losing one silently.
  - RedisWebhookBackend    : redis-py, lazy-imported. Prod (Docker
    image). Records survive sidecar reboots; the ack verdict stays on
    the record for the operator.

The SECRET LAW: the bridge never holds the HMAC secret and never
verifies signatures -- the ENGINE's provider reads the secret from its
own deployment env on every verification (webhook_payment_provider.gd
1. secret zero-knowledge). This sidecar is transport, not armor.

Record shape (one JSON-able dict per delivery):
    delivery_id      the bridge's unique id (whk_...)
    channel          subpath after /hooks/ (engine channel route)
    body_b64         RAW request body, base64 (never re-serialized)
    headers          lowercased delivered headers (hop-by-hop stripped)
    received_ts      unix ts the bridge accepted the POST
    claim            current claim token or None
    claim_expiry     unix ts the claim lapses or 0
    delivered        has the engine handled it (bool)
    verdict          processed | refused | expired | error ("" until ack)
    ack_detail       verdict detail string ("" until ack)
    acked_ts         unix ts of the ack or 0

Delivery contract: the queue is at-least-once. A claim lapses when its
TTL passes (poller death) so a standing delivery is never stranded; the
engine-side once-per-delivery ledger makes any honest redelivery a
no-op that acks the first verdict again.
"""
from __future__ import annotations

import json
import secrets
import time
import threading
from abc import ABC, abstractmethod


class Claimed:
    """Internal marker: a record another poller holds a fresh claim on."""

    @staticmethod
    def message() -> str:
        return "claim-held"


class WebhookBackend(ABC):
    """Abstract delivery backend shared by InMemory and Redis adapters."""

    @abstractmethod
    def connect(self, config: dict) -> int:
        ...

    @abstractmethod
    def close(self) -> None:
        ...

    @abstractmethod
    def healthy(self) -> bool:
        ...

    @abstractmethod
    def put_delivery(self, record: dict) -> str:
        """Enqueue a delivery; returns its unique delivery_id."""

    @abstractmethod
    def take_delivery(self, claim_ttl_sec: float) -> dict | None:
        """Claim the oldest claimable delivery.

        Returns {"record": <record>, "claim": <token>} or None when the
        queue is empty or a fresh claim already holds everything.
        """

    @abstractmethod
    def ack_delivery(self, delivery_id: str, claim: str, verdict: str,
                     detail: str) -> dict:
        """Ack with the engine's verdict.

        Returns {"status": "ok"|"already"|"mismatch"|"unknown",
                 "record": <record>}.
        """

    @abstractmethod
    def get_delivery(self, delivery_id: str) -> dict | None:
        ...

    @abstractmethod
    def stats(self) -> dict:
        ...


class InMemoryWebhookBackend(WebhookBackend):
    """In-memory delivery queue. Stdlib only; dev + tests."""

    def __init__(self) -> None:
        self._records = {}          # delivery_id -> record dict
        self._order = []            # delivery_ids in enqueue order
        self._seq = 0
        self._lock = threading.RLock()

    # -- lifecycle ----------------------------------------------------------

    def connect(self, config: dict) -> int:
        return 0

    def close(self) -> None:
        with self._lock:
            self._records.clear()
            self._order.clear()

    def healthy(self) -> bool:
        return True

    # -- helpers ------------------------------------------------------------

    @staticmethod
    def _claim_lapsed(record: dict, now: float) -> bool:
        if not record.get("claim"):
            return True
        expiry = float(record.get("claim_expiry", 0) or 0)
        if expiry <= 0:
            return True
        return now >= expiry

    # -- queue ops ----------------------------------------------------------

    def put_delivery(self, record: dict) -> str:
        with self._lock:
            self._seq += 1
            base = str(record.get("delivery_id", "whk"))
            delivery_id = base
            n = 0
            while delivery_id in self._records:
                n += 1
                delivery_id = "%s_%d" % (base, n)
            record["delivery_id"] = delivery_id
            record["seq"] = self._seq
            self._records[delivery_id] = record
            self._order.append(delivery_id)
            return delivery_id

    def take_delivery(self, claim_ttl_sec: float) -> dict | None:
        with self._lock:
            now = time.time()
            for delivery_id in self._order:
                record = self._records.get(delivery_id)
                if record is None or record.get("delivered"):
                    continue
                if not self._claim_lapsed(record, now):
                    continue
                claim = "clm_" + secrets.token_hex(8)
                record["claim"] = claim
                record["claim_expiry"] = now + claim_ttl_sec
                return {"record": record, "claim": claim}
            return None

    def ack_delivery(self, delivery_id: str, claim: str, verdict: str,
                     detail: str) -> dict:
        with self._lock:
            record = self._records.get(delivery_id)
            if record is None:
                return {"status": "unknown", "record": None}
            if record.get("delivered"):
                return {"status": "already", "record": record}
            if str(record.get("claim", "")) != str(claim) or not claim:
                return {"status": "mismatch", "record": record}
            record["delivered"] = True
            record["verdict"] = verdict
            record["ack_detail"] = detail
            record["acked_ts"] = time.time()
            record["claim"] = None
            record["claim_expiry"] = 0
            return {"status": "ok", "record": record}

    def get_delivery(self, delivery_id: str) -> dict | None:
        with self._lock:
            record = self._records.get(delivery_id)
            return dict(record) if record else None

    def stats(self) -> dict:
        with self._lock:
            pending = sum(1 for r in self._records.values() if not r.get("delivered"))
            return {
                "records": len(self._records),
                "pending": pending,
                "delivered": len(self._records) - pending,
            }


class RedisWebhookBackend(WebhookBackend):
    """Real Redis backend via redis-py. Installed in the Docker image.

    Keys:
      whb:records:<id>   JSON record hash
      whb:queue          ZSET member=delivery_id score=enqueue seq
    """

    RECORD_PREFIX = "whb:records:"
    QUEUE_KEY = "whb:queue"

    def __init__(self) -> None:
        self._client = None
        self._dsn = ""

    def connect(self, config: dict) -> int:
        try:
            import redis  # type: ignore
        except ImportError:
            raise RuntimeError(
                "redis not installed; the webhook-bridge image must include "
                "it. Use the InMemory backend for local dev."
            )
        host = config.get("host", "redis")
        port = int(config.get("port", 6379))
        password = config.get("password", None)
        db = int(config.get("db", 0))
        self._dsn = "redis://%s:%d/%d" % (host, port, db)
        self._client = redis.Redis(
            host=host, port=port, password=password, db=db,
            decode_responses=True,
        )
        return 0

    def close(self) -> None:
        if self._client is not None:
            self._client.close()
            self._client = None

    def healthy(self) -> bool:
        if self._client is None:
            return False
        try:
            return bool(self._client.ping())
        except Exception:
            return False

    # -- helpers ------------------------------------------------------------

    def _record_key(self, delivery_id: str) -> str:
        return self.RECORD_PREFIX + delivery_id

    def _read_record(self, delivery_id: str) -> dict | None:
        raw = self._client.get(self._record_key(delivery_id))
        if raw is None:
            return None
        try:
            parsed = json.loads(raw)
            return parsed if isinstance(parsed, dict) else None
        except (TypeError, ValueError):
            return None

    def _write_record(self, record: dict) -> None:
        self._client.set(self._record_key(record["delivery_id"]),
                         json.dumps(record))

    # -- queue ops ----------------------------------------------------------

    def put_delivery(self, record: dict) -> str:
        base = str(record.get("delivery_id", "whk"))
        delivery_id = base
        n = 0
        while self._client.exists(self._record_key(delivery_id)):
            n += 1
            delivery_id = "%s_%d" % (base, n)
        record["delivery_id"] = delivery_id
        # One atomic sequence: the record write and the queue push land
        # together, so /deliveries/next never sees an id without its record.
        total = int(self._client.incr("whb:seq"))
        record["seq"] = total
        pipe = self._client.pipeline()
        pipe.set(self._record_key(delivery_id), json.dumps(record))
        pipe.zadd(self.QUEUE_KEY, {delivery_id: total})
        pipe.execute()
        return delivery_id

    def take_delivery(self, claim_ttl_sec: float) -> dict | None:
        now = time.time()
        ids = self._client.zrange(self.QUEUE_KEY, 0, -1)
        for delivery_id in ids:
            record = self._read_record(delivery_id)
            if record is None:
                self._client.zrem(self.QUEUE_KEY, delivery_id)
                continue
            if record.get("delivered"):
                continue
            expiry = float(record.get("claim_expiry", 0) or 0)
            claim_held = bool(record.get("claim")) and 0 < expiry and now < expiry
            if claim_held:
                continue
            if record.get("claim"):
                # A lapsed claim from a dead poller: the record carries it
                # only so the takeover is visible to the operator.
                record["claim"] = None
                record["claim_expiry"] = 0
            claim = "clm_" + secrets.token_hex(8)
            record["claim"] = claim
            record["claim_expiry"] = now + claim_ttl_sec
            self._write_record(record)
            return {"record": record, "claim": claim}
        return None

    def ack_delivery(self, delivery_id: str, claim: str, verdict: str,
                     detail: str) -> dict:
        record = self._read_record(delivery_id)
        if record is None:
            return {"status": "unknown", "record": None}
        if record.get("delivered"):
            return {"status": "already", "record": record}
        if str(record.get("claim", "")) != str(claim) or not claim:
            return {"status": "mismatch", "record": record}
        record["delivered"] = True
        record["verdict"] = verdict
        record["ack_detail"] = detail
        record["acked_ts"] = time.time()
        record["claim"] = None
        record["claim_expiry"] = 0
        self._write_record(record)
        self._client.zrem(self.QUEUE_KEY, delivery_id)
        return {"status": "ok", "record": record}

    def get_delivery(self, delivery_id: str) -> dict | None:
        return self._read_record(delivery_id)

    def stats(self) -> dict:
        ids = self._client.zrange(self.QUEUE_KEY, 0, -1)
        pending = 0
        for delivery_id in ids:
            record = self._read_record(delivery_id)
            if record is not None and not record.get("delivered"):
                pending += 1
        return {"queue": len(ids), "pending": pending}


def build_backend(backend_name: str = "inmemory", config: dict | None = None) -> WebhookBackend:
    """Factory: 'inmemory' (default) or 'redis'."""
    if backend_name == "redis":
        b: WebhookBackend = RedisWebhookBackend()
    else:
        b = InMemoryWebhookBackend()
    b.connect(config or {})
    return b
