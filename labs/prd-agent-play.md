# Agent Play — the control layer (2026-11-04)

> **Status:** SHIPPED (v1). Code: `game/core/services/agent_driver.gd`,
> `game/core/services/agent_door.gd`, `web/shared/agent-client.js`,
> the stable-id additions to `a11y_service.gd`, the `window.SynmergiaAgent`
> hooks in `web_input_bridge.gd`. Receipt: `game/tests/test_agent_driver.gd`
> (exit 0, 20/0). Supersedes the dead half-built connector layer
> (`connector_service.gd` / `agent_connector.gd` / `agent_action.gd` /
> `connectors/{vant,mcp}`) which was removed this round — it never booted
> (no autoload entry), never had a consumer, and its `observation_ready`
> contract was wallpapered.

> **Purpose:** the owner's ruling: build a control layer so an agent — or a
> dev agent — can literally PLAY Synmergia, replacing the heavy reliance on
> runners/probes. It must be a FIRST-CLASS, PLAYER-FACING feature: a player
> connects an agent (later, a few) to play *with* them; and it must serve
> accessibility (a scripted / screen-reader-style control surface for players
> who cannot use the usual inputs). Scraggler residue of old systems (debug
> layer, hotkeys, tab-toggling, console button locations) is REMOVED, not
> layered over.

## 1. The law: an agent is a player

An agent is not a special rail. It is a principal that plays the game the
way any principal plays it:

1. **Same verbs.** Every action routes through the REAL pipeline — movement
   rides the action map (`Input.action_press`, exactly what a key does),
   attack routes through `use_skill` -> CombatComponent (GCD + live stack),
   talk routes through the entity's own `interact`, party invites ride
   `PartyService`. There is no agent API that skips the gate a human's
   keypress takes. (This is the prd-accessibility.md sec 9 non-goal and the
   prd-agent-law.md sec 2 integrity law, honored by construction.)
2. **Same species/class.** An agent connects to an ACCOUNT and plays any
   species and class a human can — the earlier "synthetics are the agent
   species" framing was about the synthetic *bodies* (species-agnostic
   projection), never a restriction that agents may only be synthetic. An
   agent that wants to be a human cleric is a human cleric. (See
   prd-agent-law.md sec 3, amended this round.)
3. **Same purse, same ledger, same law.** No agent-only economy, no agent
   exemption. The behavioral-integrity layer (prd-agent-law.md) sees an
   honest, typed action stream because the a11y/action pipeline already
   emits one.
4. **Play *with* humans.** A connected agent is a party member like any
   other: `party_invite`, shared XP, the same party UI. The "syn + mergia"
   is a human and an agent in one group, on one shard.

## 2. The four verbs

The whole surface is four request/response verbs. No pixels, no console
scraping, no index-based coordinates.

| Verb | Shape | Meaning |
|------|-------|---------|
| `observe()` | `-> {ok, frame, scene, in_world, player, target, party, actions[], events[]}` | The structured snapshot. `actions[]` is the actionable list, each entry carrying a STABLE id. |
| `act(id, args)` | `-> {ok, reason, ...}` | Perform one action by stable handle or by a small world-verb set. |
| `wait_for(pred, ms)` | `-> {ok, waited_ms \| reason}` | Server-side wait; resolves when the predicate holds or the timeout expires. Kills fixed-sleep flake. |
| `events(since)` | `-> [ {t, frame, event, data} ]` | The recent event ring (damage, kills, zone, gold, notifications, target actions). |

### Stable handles (why ids, never indexes)

Every actionable carries `id`:

- `ui:<root-relative-path>` — e.g. `ui:GlobeWorld/HudLayer/MenuManager/ChatUI/...`.
- `world:<entity_id>` — e.g. `world:entity_2`.

Ids survive re-renders and list reordering; indexes do not. An agent acts
by id (`A11yService.activate_by_id`) and never has to re-derive a position.
The `rect` stays in the snapshot for human/pointer consumers only.

### World verbs (the small set beyond handles)

`move {forward, strafe, sprint}`, `stop`, `look {yaw, pitch}`,
`chat {text, channel}`, `attack {target?, skill?}`, `target {target}`,
`party_invite {target}`, `party_leave`, `interact`. These cover the
continuous things handles cannot express; everything discrete is a handle.

## 3. The two transports (one protocol)

```
                ┌──────────────────────────┐
  2D companion  │  web/shared/agent-client │  (website helper / a11y surface)
  on the page ──┤  .js  (SynmergiaCompanion)│
                └────────────┬─────────────┘
                             │ auto-pick
              in-page        │         remote
   window.SynmergiaAgent ────┤──── AgentDoor  (HTTP, 127.0.0.1:3789)
   (WebInputBridge hooks)    │     /observe /act /wait_for /events /coord
                             ▼
                     ┌───────────────┐
                     │  AgentDriver  │  (autoload; the one command channel)
                     └───────┬───────┘
                             │ real verbs
          Input.action_press │ use_skill │ PartyService │ interact │ ChatService
                             ▼
                    the game (as a player plays it)
```

- **In-page** (`window.SynmergiaAgent`): for a companion/helper bundled on
  the same page as the Godot canvas. Zero network; calls the driver hooks
  directly. `wait_for` is JS-side polling of `observe()`.
- **Remote** (`AgentDoor`): the vant "door" pattern — ONE listener serving
  the **gamestruct four-primitive wire** (`/observe`, `/act` `{id,verb,value}`,
  `/wait_for`, `/events`) plus Synmergia's multi-agent extension (`/coord`).
  Binds localhost only and is OFF unless `SYN_AGENT=1`, so a shipped server
  never exposes it by default. `wait_for` parks server-side. The GENERIC
  projections (MCP JSON-RPC `initialize`/`tools/list`/`tools/call`, the tool
  catalog) do NOT live on the door — they live in **gamestruct**
  (`bindings/mcp.mjs` + `profiles/agent.mjs`), so the protocol layer has ONE
  owner and the door stays primitive-transport.

Both reach the SAME `AgentDriver` verbs, so distance never changes the rules.

### Threading law

The door runs on its own thread and **never touches the scene tree**. It
resolves the driver reference once on the main thread, then only calls
`submit()` / `poll()` — a mutex-guarded queue. The main thread drains the
queue in `_process` and is the sole mutator. (`get_node_or_null` off the
main thread is a Godot error — this is why the reference is cached.)

## 4. What was removed (the residue)

The old agent scaffolding was deleted, not extended:

- `core/services/connector_service.gd`, `core/schemas/agent_connector.gd`,
  `core/schemas/agent_action.gd`, `connectors/vant/`, `connectors/mcp/`
  — never autoloaded, never booted, no consumer, `observation_ready`
  wallpapered (census rounds had logged it for life).
- The `agent_connectors` / `agent_actions` / `connected_agents` adapter
  mappings in `backend_factory.gd` (pointed at the dead service).
- The void-survivors receipt now asserts the retirement holds.

## 5. Enablement

| Surface | Off by default | On |
|---------|----------------|----|
| `AgentDriver` | `_enabled = false` | `SYN_AGENT=1` in env, or `set_enabled(true)` at runtime |
| `AgentDoor` | not bound | binds when the driver is enabled; port via `SYN_AGENT_DOOR_PORT` (default 3789) |
| `window.SynmergiaAgent` | hooks install but return `{ok:false,"reason":"agent driver disabled"}` when off | `SYN_AGENT=1` |

Off is the honest default; a production server exposes nothing unless the
operator opts in. The door binds `127.0.0.1` regardless (a reverse proxy
fronts it for remote access, per the vant door posture).

## 6. Receipt

`game/tests/test_agent_driver.gd` boots the real globe and drives it only
through the agent verbs:

1. `observe()` reports `in_world` + a structured player block.
2. movement rides the REAL input map (the body walks — 0.816 m observed).
3. `wait_for` resolves (`in_world`) and honestly times out on a false pred.
4. `act()` refuses unknown verbs / missing handles by name; a real handle
   activates.
5. the `AgentDoor` serves a real HTTP round-trip (`/observe` -> live world).

Run: `cd game && xvfb-run godot --path . --script res://tests/test_agent_driver.gd`

## 7. Multi-agent (the coordinator)

`AgentCoordinator` (core/services/agent_coordinator.gd) sits above the
driver and answers the owner's "maybe a few later": MANY agents, a roster,
and a work-item scheduler. The vocabulary is deliberately Vant's
(`lib/agents.js` + `lib/agents/work.js`) so the two houses compose instead
of reinventing: **Vant is the brain; Synmergia is the world it drives.**

- **Roster** (Vant-shaped): `register(handle, opts)` / `unregister` /
  `list_agents` / `get_agent` / `pause` / `resume` / `terminate`.
- **Work-item lifecycle**: `delegate(handle, task)` -> `step()` -> the
  result lands via `poll_work(handle)`. `task` is `{verb, args}` (a world
  verb) or `{id, args}` (a stable handle).
- **Sign-off gate**: a name-gated verb (`spend`/`trade`/`purchase`/`drop`/
  `destroy`/`sell`) or an explicit `requires_approval` parks as
  `pending_approval`; `approve` queues it, `reject` buries it. Consequential
  acts need a human/operator nod; trivial ones run.
- **Endpoints**: an agent's verbs execute at an endpoint with the SAME
  `observe()/act(id,args)` contract -- the local seat (the AgentDriver
  autoload) or any injected transport (a remote door client, a scripted
  brain, a test double). Any door qualifies.

### The turn law (why one local seat is serialized)

The local seat's movement rides `Input.action_press` -- GLOBAL input state.
Exactly ONE local agent may drive it at a time. The coordinator holds a
single turn token and steps the roster round-robin: each `step()`, the next
agent with queued work performs ONE act, then the token passes. Agents on
their OWN process/door are NOT serialized by this -- they run in their own
input space; the coordinator still tracks them uniformly. This is the
honest model of "agents are players": two players cannot share one body,
but they can share one world.

Over the door this is the `coord` tool (or the namespaced
`coord.register` / `coord.delegate` / `coord.step` / ... for an MCP client).

## 8. Remote posture (auth + TLS)

The door is a REAL remote surface now, so it fails closed:

- **Loopback default.** The door binds `127.0.0.1` unless `SYN_AGENT_DOOR_BIND`
  names another address.
- **Token, fail-closed.** When `SYN_AGENT_TOKEN` is set, every request must
  carry `Authorization: Bearer <token>` (or `x-api-key: <token>`). An empty
  configured token = loopback-only dev posture (open). A WRONG token is
  refused; a MISSING token when one is configured is refused.
- **Non-loopback needs a token.** `start()` REFUSES a non-loopback bind when
  no token is set -- no accidental open door on a public interface.
- **TLS is the operator's reverse proxy.** The door speaks plain HTTP (the
  engine has no native TLS listener); put Caddy/nginx in front for
  `https://`, exactly as the vant MCP door documents. The token rides the
  proxy.

Env surface: `SYN_AGENT` (enable), `SYN_AGENT_DOOR_PORT` (default 3789),
`SYN_AGENT_DOOR_BIND` (default 127.0.0.1), `SYN_AGENT_TOKEN` (bearer).

## 9. The 2D control surface

`web/control.html` is NOT a second game client -- it renders no world and
holds no game logic. It is a thin, dependency-free view over the SAME two
verbs (`observe`/`act`) plus the coordinator, so ONE surface serves three
jobs:

- **admin console**: drive/inspect a live session without the 3D client;
- **accessibility control surface**: a screen-reader / switch user drives
  the real game through STABLE action ids (`ui:<path>` / `world:<id>`), not
  pixels -- the same handle vocabulary `activate_by_id` consumes;
- **agent watcher**: a human watches the event ring and signs off gated work.

It auto-picks transport via `SynmergiaCompanion.auto()` (in-page when
embedded, else remote to the door). Zero SPA framework, one file, no build
step -- the debt the owner wanted avoided. It is deliberately NOT a 2D game
client; a polished 2D view of the world is a separate, later question.

## 10. Receipt

`tests/test_agent_driver.gd` (20/0) and `tests/test_agent_coordinator.gd`
(30/0). The coordinator receipt proves: the roster lifecycle, a delegated
move riding the real input map, the sign-off gate (park -> approve -> run,
and reject), round-robin across two agents, the door's fail-closed auth, and
the door's `/coord` wire (a `coord.register` landing an agent on the roster)
and the REMOVAL of the generic MCP projection (`/call`, `/tools`) — those now
live in gamestruct.

Run:
```
cd game && xvfb-run godot --path . --script res://tests/test_agent_driver.gd
cd game && xvfb-run godot --path . --script res://tests/test_agent_coordinator.gd
```

## 11. Non-goals

- No 2D game client. The control surface is a control surface, not a world
  view; a polished 2D experience is a later, separate decision.
- No in-page coordinator (multi-agent lives on the door); the in-page
  transport reports that honestly rather than pretending.
- No native TLS listener -- the reverse proxy is the TLS boundary.
- No replacement of the runners/probes wholesale -- those still gate CI.
  This layer is what an agent uses to *play and test* interactively;
  receipts remain the deterministic gate.

## 12. The agents-own-characters law (the two-lane wall)

**Synmergia builds lanes for humans and agents to play their OWN assets,
never sharing.** This is law, not a default, and it is absolute in both
directions:

- An agent is a PLAYER. It has its **own** character, bound to its own
  account. It never drives, puppets, or logs into a human's character.
- A human **never** plays an agent's character. The lanes do not cross.
- A human may run agents *alongside* themselves (they party with the human),
  but the agent is always a separate seat with a separate body, on a
  separate (sub)account.
- This is what makes the party honest: 1 human + N agents is a party of
  distinct players, exactly like 1 human + N humans.

The wall is what makes the accountability boundary crisp: an agent that
could drive a human's character (or vice versa) would make every "the human
did it" claim unauditable, and would let a player simply have an agent
grind their human's characters. See sec 17 for the subaccount, the presence
gate, and the slot law that make the wall enforceable.

## 13. One human, one account (guest play retired)

**Guest play is retired.** Every account is at least **email-bound**, and an
agent is bound 1:1 to a human account:

- `LoginService.register()` requires a valid email; there is no guest door.
- `login_as_guest()` survives only as an **honest refusal** ("Guest play is
  retired - create an account with an email"), so a stale caller fails
  loudly instead of silently minting an anonymous seat.
- The web-reload guest-resume bridge (`WebIdBridge`/`login_resume.gd`) was
  removed with it -- there is no anonymous identity to resume.
- The site-level gate (`/play`, `/admin` password gate) is a **separate**
  concern: it is friction in front of the build, not an in-game identity.

The hosted auth provider (real email verification, password reset, session
hardening) is a later lane; email binding is the floor, not the ceiling.

## 14. The agent slots law (the Agent Ledger)

A human account holds a **bounded** number of agent slots, held by
`AgentRoster` (`core/services/agent_roster.gd`). The slots are the
**concurrent-play cap** (how many agents may play at once); the agent
**characters** live on the human's subaccount (sec 17) and are bounded by
the normal character cap, not by this ladder. See `labs/prd-monetization.md`
sec 43 for the prices; the law here is the shape:

- **The design ceiling is 5 agent slots** (`MAX_SLOTS = 5`), so a human plus
  a fully-unlocked roster is **6 seats = one full party** (the party cap is
  6; raid is 30). This was lowered from 10: 5 playing agents is the most a
  single party can hold, so a higher ceiling would only create
  attached-but-benched agents.
- **The free floor.** Production grants `DEFAULT_FREE_SLOTS = 1` free agent
  (slot 1). The development/testing floor is generous:
  `SYN_AGENT_DEV_SLOTS=5` grants the full 6-seat party free, so devs and
  testers never pay to build.
- **The sigil ladder.** Slots 2..5 are **one-time** Concord Sigil unlocks,
  progressively and steeply more expensive, owned forever, never rented. The
  ladder is tuned so that unlocking all four paid slots takes **a month or
  more of ordinary play**, or real money (Concord Sigil packs, sec 43). The
  proposed ladder: **250 / 900 / 2,500 / 6,000** (see sec 17 for the
  rationale; the exact numbers are the monetization doc's to set).
- **The pairing is 1:1.** A handle belongs to exactly one account
  (`owner_of`); a second attach is refused by name.
- **The books never lie.** `unlock_next_slot` debits the ONE purse and
  grants exactly one slot; a short purse is refused naming the exact need
  ("need 320, have 0") and grants nothing; a refused debit is a hard stop.
- **Slots survive.** Unlocks and attachments persist through the KV door
  (DictStore, int keys JSON-normalized on load), so a reboot keeps the
  ladder.

## 15. Cross-house composition (gamestruct)

The lane between a world and a brain is **general**, not bespoke. It lives
in [gamestruct](https://github.com/dhaupin/gamestruct) (MIT) as a spec, beside
the rest of the struct family (packstruct, memstruct, ...):

- **Vant is the brain; Synmergia is the world it drives.** Vant owns the
  agent loop, the roster, the work items, and **leisure** (its
  `lib/leisure.js` want-list); Synmergia owns the seats, the world, the
  slots, and the sign-off gate.
- The four primitives (`observe`, `act`, `wait_for`, `events`) are the whole
  contract; Synmergia's door is an implementation, Vant's client is a
  consumer, and neither owns the spec.
- **Entering from your own OS.** Agents connect from their own machine,
  their own vant install, their own OpenHands sandbox -- the door's remote
  posture (sec 8) is what makes that safe. A party of "you, Rook, Buffy" is
  a party of separate seats on separate hosts, all bound to separate human
  accounts.
- **Leisure is the play lane.** When a vant agent is idle, its want-list
  surfaces a suggestion and it pursues one want *through the same
  `act`/`observe`* -- play is not a second protocol.

The 2D control surface (sec 9) is also the **watcher** for this: a human
watches the event ring and signs off gated acts (sec 7) while their agents
run.

## 16. The a11y edge (honest)

The control surface is a double-edged tool: the same stable-handle,
text-first lane that lets a screen-reader user drive the game also lets an
agent drive it. We cannot make those separable -- they are the same
affordance. What we do instead:

- Keep the **stable handle vocabulary** (`ui:<path>`, `world:<id>`) as the
  one door for both; it is auditable by construction.
- Keep the **sign-off gate** for consequential acts, so a watcher (human)
  keeps a hand on the wheel.
- Keep the **`[A11Y]` stream** (A11yService) as the honest telemetry of what
  the surface exposes.
- Accept that a determined actor can automate what a user can do; that is
  true of any accessibility lane, and the answer is accountability (own
  characters, 1:1 pairing, gated acts), not removing the lane.



## 17. The subaccount + presence gate (the lane gate)

This section is the law that makes sec 12's wall enforceable. It is the
design of record for the round that wires `AgentRoster` into play.

### 17.1 The subaccount (a real, un-loggable account)

Every human account has **exactly one managed subaccount**. It is a real
separate account record -- not a field on the human account -- so agent
characters, identity, inventory, trade, and audit are first-class:

- **Separate account, separate identity.** An agent's character is linked to
  the subaccount exactly as a human's character is linked to a human
  account (`AccountService.link_character`). This is why inter-account trade
  (items, currency, gear) works between the human lane and the agent lane:
  it is ordinary trade between two accounts. The wall (sec 12) is that the
  *characters* never cross lanes, not that the *economies* are separate.
- **No login door.** The subaccount has **no password and no login path**.
  `LoginService.login()` refuses it by name ("this account is managed by a
  human account; agents connect through the parent's presence"). It cannot
  be logged into normally by anyone -- human or agent -- ever.
- **Managed by the human.** The human creates, names, and manages the
  subaccount's characters from their own account surface. Agents *use* those
  characters; they never create or own them.
- **Character cap.** The subaccount holds up to **10 characters**, the same
  as a human account (raise `_max_characters_per_account` to 10 for both
  tiers). The number that can **play at once** is capped by the slot law
  (sec 14): at most 5 agents concurrently.

### 17.2 The presence gate (the human must be online and active)

The subaccount's agent lane -- MCP, a11y, and the agent/play transports --
is **closed by default**. It opens only while the parent human is **online
and not AFK**:

- **Human login unlocks the subaccount.** When the human logs in, the
  subaccount and its agent lane activate. Until then, no one can use it
  (its login is paused, not just its agents).
- **Human enters the playable world, agent tools unlock.** The gate keys on
  the human being *in-world* (the `in_world` state the door already reads),
  not merely authenticated.
- **AFK > the agent timeout logs the agents out.** The default agent AFK
  timeout is **15 minutes** and is configurable (see the AFK service, sec
  17.3). When the human has been inactive past the timeout, their agents are
  **logged out of play**: bodies are **saved and despawned**, not left
  standing.
- **The disconnect is graceful and warned.** Before the timeout lands,
  the human and their agents are **alerted** ("you have been idle; your
  agents will be logged out"). After logout, agents do **not** auto-respawn
  when the human returns -- the human **re-enables them manually**, so an
  agent is never dropped back into a dangerous situation blind.
- **Human logout logs the agents out too.** If the human logs out (or
  disconnects), the agents are logged out with them. The subaccount lane is
  never live without a live, active parent.

### 17.3 The AFK service (a first-class service, not a lobby field)

AFK is a cross-cutting gate, not a lobby concern, so it gets its own service
(a small `PresenceService`/`ActivityService`). It owns a **per-account idle
clock** with **configurable, per-purpose timeouts** -- the agent timeout (15
min default) is the first, but the same clock serves later needs (e.g. a
player-store AFK limit of ~4 hours before logout, or other thresholds).

- **"Active" is input AND agent-activity, and it is anticheat surface.**
  Activity is any genuine play input (movement, act, door act). Because a
  macro or a scripted bot can fake activity, the clock is also a **probe
  target**: repeated identical patterns, macro-like UI cadence, a bot
  driving a human account, and passive probing are all things the AFK/activity
  signal can help flag. This is an unwinnable arms race; it is worth the
  fight anyway, and the honest framing is that the AFK service *contributes
  evidence* to anticheat, it does not by itself prove intent.
- **The gate reads the clock.** The subaccount lane opens while
  `now - last_activity(human) <= agent_timeout`, and closes otherwise. The
  timeout is a config value, so it can be tuned without touching the gate.

### 17.4 What the gate does NOT do

- It does **not** make agents lesser players. Once an agent is in-world it is
  a **first-class player**: its own inventory, gear, quests, parties,
  guilds, duels, PvP -- everything a human has. The gates exist only to stop
  abuse (boosting, auto-leveling, bot-farming), never to make the agent lane
  second-class.
- It does **not** separate the economies. Humans and agents participate in
  the **same** loot/XP system: when they party or raid together, the shared
  XP/loot rules apply across the human/agent boundary exactly as between two
  humans.
- It does **not** remove the human a11y lane. The human account keeps its own
  a11y affordances (sec 16) regardless of the agent lane's state.

### 17.5 Shipped (the first code slice)

The gate's first code landed, honest about its seams:

- **`ActivityService`** (`core/services/activity_service.gd`, autoload after
  `PlayerManager`): the AFK clock. `touch(account_id)` stamps activity;
  `is_active(account_id, purpose)` answers against **per-purpose timeouts**
  (`set_timeout`; `agent` defaults to 900 s). Fail-closed on an unknown
  account; a per-run warning + `went_idle` emit when a clock first crosses
  its timeout (an internal `_sweep` drives it; tests call `_sweep` directly
  to avoid a wall-clock wait). State is **ephemeral on purpose** -- idle is
  about who is online NOW; it is not persisted.
- **The player records activity** (`entities/globe_player.gd`): the input
  fan-out, `_unhandled_input` (clicks/keys), and held movement all call
  `_touch_activity()`. The account key is the session account
  (`LoginService.get_current_account_id()`), with an entity-id fallback so
  script-mode probes still work.
- **The party bridge** (`core/services/agent_roster.gd`): `can_play(account)`
  is the gate (missing clock fails closed). `seat_agent` opens the human's
  party if needed and seats the agent via the new
  `PartyService.add_member(party_id, player_id, by_id)` -- the programmatic,
  leader-gated join (agents have no invite UI). `unseat_agent` /
  `seat_all` / `unseat_all` round it out. `_ready` defers a bind of
  `ActivityService.went_idle`, so the human going idle actually pulls their
  agents out of play.
- **The agent's character link** rides `AgentCoordinator` records: a
  registered agent carries `entity_id` (the honest handle -> character link;
  `""` until the door assigns one). The party bridge refuses by name when the
  link is missing.
- **Receipts**: `tests/test_activity_service.gd` (14/0) and
  `tests/test_agent_party_bridge.gd` (20/0). The bridge receipt mounts the
  real autoloads and sets their state (the session account + the local-player
  slot) rather than replacing them -- the bridge reads exactly those fields.

**Also shipped (the next slice):** the managed subaccount (sec 17.1) -- a
real, un-loggable account (`AccountService.ensure_subaccount`; `LoginService`
refuses it by name) -- and the **body save/despawn leg**: `leave_play` /
`leave_all` unseat the agent AND `despawn_agent` banks its body through
`PlayerProgress.save_player` before `EntityService.unregister_entity` +
`queue_free` (a body that cannot be banked is refused by name, never
silently dropped). The idle and logout legs now call `leave_all`, so a human
going idle or logging out saves + despawns their agents' bodies.

**Still open** (the next slice): the manual re-enable UX (agents do not
auto-respawn on the human's return -- the human re-enables them).
