# webhook-bridge

Payment-processor webhook entry. Mirrors `srv/redis-bridge/` --
same shape, same stdlib-only default backend, lazy redis import for
prod.

The external processor POSTs its webhook to the public route and this
sidecar queues the delivery VERBATIM (raw body bytes, lowercased
headers). The game engine's poller
(`game/core/economy/webhook_transport.gd`) claims deliveries, feeds
them ONCE each into the provider board's webhook door
(`WebhookPaymentProvider.handle_webhook(raw_bytes, headers)`) and acks
with the verdict the armor chain produced.

## Trust law

The bridge is TRANSPORT, not armor. It holds no HMAC secret and
verifies nothing: the secret lives only in the engine process env
(`PAYMENT_WEBHOOK_SECRET`), and the engine's provider revalidates
everything that matters (signature, freshness, order binding,
idempotence). A processor that retries after a lost network hop is
safe by design -- transport is at-least-once, the armor deduplicates.

## Godot's WebhookTransport (adapters-style) speaks this HTTP API.

Wire protocol is defined in the two files:

| Caller | File |
|--------|------|
| processor (HTTP POST) | nginx `/hooks/` -> `server.py` |
| engine poller | `game/core/economy/webhook_transport.gd` |

## Routes

```
GET  /health                    -> { status: ok|degraded, backend }
POST /hooks/<channel>           -> the processor's RAW webhook body.
                                   202 accepted (queued verbatim),
                                   413 over the body cap (not stored),
                                   503 queue saturated (processor
                                   retries with its own backoff).
GET  /deliveries/next           -> { delivery: <record>|null, claim }
                                   claims the oldest claimable record
                                   for claim TTL seconds.
GET  /deliveries/<id>           -> operator readout ({ delivery: <record>|null })
POST /deliveries/<id>/ack       -> { claim, verdict, detail } marks the
                                   delivery handled with the engine's
                                   verdict (processed|refused|expired|error).
                                   stale/mismatched claim -> 409;
                                   already delivered -> 200 (idempotent);
                                   unknown id -> 404.
GET  /stats                     -> queue readout.
```

Delivery record: `delivery_id`, `channel`, `body_b64` (raw bytes,
never re-serialized JSON), `headers` (hop-by-hop stripped,
lowercased, duplicates `, `-joined; the processor's signature header
travels untouched), `received_ts`, claim fields, `delivered`,
`verdict`, `ack_detail`, `acked_ts`. Delivered records stay as
operator audit (no TTL).

## Env

```
WEBHOOK_BACKEND=inmemory|redis     (default: inmemory)
WEBHOOK_HOST / WEBHOOK_PORT / WEBHOOK_PASSWORD / WEBHOOK_DB  (redis backend)
WEBHOOK_BRIDGE_HOST=0.0.0.0        (prod entrypoint sets 127.0.0.1)
WEBHOOK_BRIDGE_PORT=8083
WEBHOOK_MAX_BODY=65536             (413 above the cap)
WEBHOOK_CLAIM_TTL=120              (seconds a claim may hold a delivery)
```

## Run

```bash
python3 main.py
```

In the container the entrypoint starts it in TEST mode (CI) and PROD
mode with the other sidecars (pg-bridge 8080, redis-bridge 8081,
noaa-kp 8082); nginx routes `/hooks/` on the public 80/443 server to
`127.0.0.1:8083`. The engine transport is OFF unless
`WEBHOOK_BRIDGE_URL` is in its env, so game clients never poll.

## Test Results

```bash
python3 test_webhook_bridge.py
```

```
Ran 14 tests in 0.5s  -> OK
```
