# Revised Evaluation: NSC-9 / Content-Hash as a Redis-Like Layer for Synmergia

**Last updated:** after the user's correction.

**TL;DR:** I was framing this as "replace the DB" when the user meant
"extend the DB, redis-like." That changes the analysis significantly.
The geometry is genuinely useful as a *state cache / sync protocol*
sitting in front of Postgres, not as a replacement. The state-tree
content-hash pattern is the real win. NSC-9 as a *display* format is
still wrong; as an *internal wire format* it's debatable.

---

## What I got wrong (and why)

I wrote an evaluation that said "use sequential int IDs, use
Postgres, the geometry is overengineered." The user pointed out the
flaw: I was treating it as a *replacement* for things Synmergia
already has. The user is asking about it as an *extension* — a
Redis-like layer for hot-path state, sync, assimilation, seeds.

That's a different problem and the geometry is the right shape for
it. I should have read the original
[`unified-nsc9-islands-builds.md`](./unified-nsc9-islands-builds.md)
more carefully — it was always about adding a layer, not replacing
anything.

---

## The corrected framing: content-hash as a Redis-like layer

```
                        ┌──────────────┐
                        │   Postgres   │   (durable record)
                        │   (servers)  │
                        └──────┬───────┘
                               │ snapshot / patch
                               │
                        ┌──────▼───────┐
                        │ Content-hash │   (hot-path cache + sync)
                        │ state layer  │   key = SHA-256(state_bytes)
                        │              │   value = serialized state
                        └──────┬───────┘
                               │ subtree-by-hash
                               │
       ┌───────────────────────┼───────────────────────┐
       │                       │                       │
  ┌────▼─────┐           ┌─────▼────┐           ┌─────▼────┐
  │  Server  │           │  Client  │           │  Peer    │
  │  (auth)  │           │ (predict)│           │  (P2P)   │
  └──────────┘           └──────────┘           └──────────┘
```

The state layer is a **content-addressed in-memory key-value store**.
Keys are SHA-256 of the value. Values are serialized subtrees. Any
node that has the same hash has the same data. Diffs are tree diffs
between two known-good subtrees.

This is the redis-like extension. Postgres stays. The hash layer
sits in front of it.

---

## What this is concretely: the Synmergia state tree

```
ROOT (hash = state_root)
├── zone:starter_plains (hash aaa)
│   ├── chunk:0,0,0 (hash bbb)
│   │   ├── entity:player_42 (hash ccc)
│   │   │   ├── component:health (hash ddd)
│   │   │   ├── component:inventory (hash eee)
│   │   │   ├── component:position (hash fff)
│   │   │   └── component:combat (hash ggg)
│   │   ├── entity:enemy_slime_7 (hash 111)
│   │   │   ├── component:health (hash 222)
│   │   │   ├── component:aggro (hash 333)
│   │   │   └── component:ai (hash 444)
│   │   ├── entity:npc_merchant_1 (hash 555)
│   │   └── ...
│   ├── chunk:1,0,0 (hash hhh)
│   └── ...
├── zone:dwarven_mines (hash iii)
└── ...
```

Every node is a hash. Two systems with the same hash have the same
subtree. This enables:

### 1. **Server → client sync (the primary use case)**

```
Client has:    state_root = "aaa"
Server has:    state_root = "bbb"

Server sends:  "your root hash is wrong, here's the diff:
               (path: zone:starter_plains/chunk:0,0,0/entity:player_42,
                old_hash: ccc,
                new_hash: xxx,
                new_value: <blob>)"

Client applies the diff → rehashes → new root = "bbb" ✓
```

This is *the* way to do authoritative-server state sync without
shipping the full state every tick. Bandwidth = O(diff size) instead
of O(state size). For an MMO with 10K entities in scope, the diff is
typically a few KB.

### 2. **Client-side prediction reconciliation**

Client predicts moves, server runs the actual sim. Every N ticks the
server says "your state at tick T had hash X, but the actual hash
was Y. Here's the patch from X to Y."

Content-hash of the prediction snapshot = the rollback point.
Server's actual snapshot = the truth. Diff = the patch the client
applies to correct.

### 3. **Multi-shard cross-zone references**

Player walks from zone A (shard 1) to zone B (shard 2). Shard 2
needs to know "is this the same player template as shard 1 had?"
Hash match = yes. No need to ship the player template.

Guild spans 3 shards. Guild roster as content-hashed tree. Shards
that need a guild member's data just ask "do you have hash X?" If
yes, done. If no, fetch from the shard that has it.

### 4. **Inventory + trading cross-server**

Two players trade across shard boundaries. Each carries a "set of
item instance hashes." Trade = exchange sets + authoritative
transfer. Server reconciles. Bandwidth = O(unique items) instead
of O(union).

### 5. **Save games as content-hashed trees**

Save v1.2 root = hash `aaa`. Save v1.3 root = hash `bbb`. To upgrade
an old save, ship the diff `(aaa → bbb)`. Player on slow connection
only downloads the patch.

Bonus: tampering detection. If the player edits their save, the
hash changes, and the server detects the mismatch on next login.

### 6. **Server tick verification (anti-cheat)**

Server tick = `hash(previous_state_root + new_inputs)`. Players can
verify the tick is legitimate by re-running the hash on the
publicly-known previous state. Cheaters who fake server ticks can't
fake the hash chain.

### 7. **Peer-to-peer entity sync (bandwidth optimization)**

Two players near each other can exchange "what entity hashes do
you know?" Set reconciliation via hash sets. Ship only the
entities the other side doesn't have. Reduces server load.

This is the "assimilation" piece the user mentioned. Two
nearby players' worlds *assimilate* via set reconciliation.

### 8. **Seeds (deterministic worldgen)**

A world seed + a chunk coordinate deterministically produces the
same chunk. So a "seed pack" is a content-hashed bundle: (seed,
coverage_map, sample_chunks). Other players receive the seed pack
and reconstruct locally. No need to ship chunks unless they
diverge from the seed (e.g., player-built structures).

This is the "seeds" piece. Worldgen IS the seed.

### 9. **Content distribution (mods, custom zones)**

A custom zone = content-hashed tree. "Download zone hash `7c4a...`"
= a clear, versioned reference. Players can verify they have the
exact zone the designer intended. The hash is the version ID.

### 10. **Asset addressing**

Texture/sound/model = content-hash. The hash is the asset path on
the CDN. If the asset changes, the hash changes, so old clients
can still find the old asset (no broken references). This is how
IPFS works and how Vant distributes content.

---

## Where the geometry specifically shines

### NSC-9 barcode format
- **As internal wire format:** debatable. 12 digits = 10^12
  unique values = 1 trillion. A single MMO shard has maybe 10K
  entities. Even 1M entities (very large) is 0.0001% of the
  address space. So 12 digits is plenty. SHA-256 hex is 64 chars,
  way more. NSC-9 is more compact. **But** SHA-256 hex is a
  one-liner, and the wire format for diffs is "path + hash +
  blob" where the hash is the largest part. 64 chars vs 12 chars
  is a 5x bandwidth difference per diff entry.
- **As player-facing format:** no, still wrong. Players see names.
- **Verdict:** optional. SHA-256 hex works fine. NSC-9 is a
  bandwidth optimization that's only worth it if profiling
  shows it's needed.

### Icosahedral coords for chunk routing
- **For shard routing:** chunk coordinates already do this. A
  shard is a 3D range of chunks. Players in adjacent chunks go to
  adjacent shards. No need for icosahedral projection.
- **For spatial indexing of the world:** if Synmergia has a 2D
  world (top-down tile-based), then a Penrose / icosahedral
  spatial index gives you a "no seams" property. But this is a
  world-design decision, not a technical win.
- **Verdict:** not needed for the Redis-like layer. Maybe useful
  for the world geometry itself if tile-based.

### Quasicrystal paths
- **For content distribution:** the content-hash IS the path on
  the CDN. `cdn.synmergia.com/a3f4b2c1d5e6f7...` is the path.
  No quasicrystal needed.
- **For state cache:** the hash IS the key in the in-memory
  hashtable. `state_cache["a3f4..."] = <blob>`. No quasicrystal.
- **Verdict:** not needed. The hash table is its own path scheme.

### Penrose tiling
- **For storage:** no, see above.
- **For world map:** actually useful. A Penrose P3 tiling is
  aperiodic (no visible seam pattern), gives you a natural
  "infinite" world without periodic repetition. This is a real
  win for an MMORPG with procedural worldgen. Whether Synmergia
  is tile-based is the open question.

---

## The new migration plan (revised)

### Session 1 — Islands POC ✅
Done (commit `3e942bb`).

### Session 2 — UIPanel → islands
Convert remaining panels. UI work. Independent of state tree.

### Session 3 — State tree content-hash layer (the redis-like core)
**This is the new big one.**

- `core/state/state_tree.gd` — generic content-addressed tree
  - `node = { path, hash, value, children[] }`
  - `compute_hash(node)` = SHA-256(serialize(node))
  - `diff(old_root, new_root)` = list of (path, new_hash, new_value)
  - `apply_diff(root, diff)` = new_root
  - `get_subtree(root, path)` = subtree
  - `set_subtree(root, path, value)` = new_root
- `core/state/state_sync.gd` — sync protocol
  - `client_request_sync(server_endpoint, my_root_hash)` → server
    returns diff
  - `server_announce_tick(root_hash, diff)` → client applies
- `core/state/snapshot_service.gd` — Postgres integration
  - Reads/writes root hashes to `state_snapshots` table
  - Periodically takes snapshots (every N ticks)
  - Loads from snapshot on restart
  - In-memory content-hash cache for hot paths

This is the foundation. Everything else builds on it.

### Session 4 — State tree applied to game state
- `core/entities/` entities become state tree nodes
- `core/components/` components are sub-nodes
- Each entity: hash = SHA-256(component_hashes + base_template)
- Each zone: hash = SHA-256(zone_metadata + chunk_hashes)
- Server tick = `state_root = hash(previous_state_root + inputs)`
- Client prediction rollback = `state_root → known_good_state_root → patch`

This is the integration with existing code.

### Session 5 — Save games as content-hashed trees
- Save file = content-hash tree
- Save upgrade = diff between save root hashes
- Tampering detection = server re-verifies hash on load

### Session 6 — Item template content-hash (cross-shard dedup)
- Item templates identified by content-hash
- Cross-shard reference = "I have hash X, you don't? Here."
- Reduces template storage across shards

### Session 7 — Asset addressing (pck + CDN)
- Build pck with content-hashed asset paths
- CDN serves by hash
- Old clients can still find old assets (no broken refs on update)

### Session 8 — Build pipeline (data.pck + CI)
- `tools/build.sh` for the actual build
- Separate `client.pck` and `data.pck`

---

## What I conceded

- Sequential int IDs are still the right *display* format. Player
  shows "Bronze Sword" or item ID `12450`, not a hash.
- The user-facing ID is separate from the system ID. NSC-9 is wrong
  for the former, debatable for the latter.
- A real DB (Postgres) is still the right *durable* layer. The hash
  layer is the *hot-path* layer in front of it.

## What I now recommend

- **Adopt content-hash for state trees** (Session 3, the big one).
- **Adopt content-hash for save games and item templates** (Sessions
  5, 6).
- **Adopt asset addressing by content-hash** (Session 7).
- **Defer NSC-9 specifically** — SHA-256 hex is fine, NSC-9 is a
  bandwidth optimization that's not worth the complexity unless
  profiling demands it.
- **Defer icosahedral coords** — chunk coordinates work.
- **Defer quasicrystal paths** — hash table is the path.
- **Consider Penrose tiling for the world map** if Synmergia is
  tile-based. This is a real win for procedural MMOs.

## Open questions for the user

These affect the design and I don't have enough context:

1. **Is Synmergia tile-based or continuous?** Tile-based →
   Penrose tiling for the world map is worth considering.
   Continuous → icosahedral coords aren't useful.
2. **Does Synmergia plan cross-shard play?** (Trading across
   shards, guilds across shards, etc.) If yes → content-hash
   item templates and inventory trees are a real win. If no →
   Session 6 is less important.
3. **Peer-to-peer sync?** (Players near each other gossiping
   entity state without server.) If yes → set reconciliation
   via hash sets is a real bandwidth win. If no → drop Session
   7 partial.
4. **Save file format?** Currently a binary blob? JSON? Custom?
   Affects how Session 5 (content-hashed saves) is implemented.
5. **Asset distribution mechanism?** (pck only? CDN? Web fetch?)
   Affects Session 7.

These are blockers for finalizing the design, not blockers for
starting Session 3 (state tree core) which is independent.
