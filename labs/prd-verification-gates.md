# PRD: Verification Gates — the structural parse guard and the "merged red" law

> **Status:** ACTIVE. The guard (`game/tests/test_parse_check.gd`) is shipped
> and in the runner `DEFAULT_SET`. This doc is the ledger for how the gate
> works, why it exists, and the incident that proved it was needed.

(2026-11-17, OSS parity round. Owner directive: "If you see something say
something, make an issue or ledger it in a proper `/labs/prd` doc.")

## 0. The incident (PR #117 merged RED)

`origin/staging` was broken by a merge that CI had already marked failing.

- **The break.** PR #117 (commit `816d79c7`, "Add dual wield...") added
  `func _inventory_bag()` to `game/entities/player/player_base.gd`. The
  subclass `game/entities/globe_player.gd` (`class_name GlobeWorldPlayer
  extends PlayerBase`) already declared `var _inventory_bag = null`. In Godot
  4.7.2 a subclass member with the same name as a parent member is a **hard
  parse error**:

  ```
  Parse Error: The member "_inventory_bag" already exists in parent class PlayerBase.
  ```

- **The blast radius.** The parse error stops `globe_player.gd` from loading,
  which stops the world scene from loading, which stops the **wasm web export**
  from ever reaching the world. The one thing the product is for.

- **The tell.** `gh api .../commits/816d79c7/check-runs` shows
  `default-set: failure` on the very commit that was merged. The gate was
  red and the merge went through anyway. `staging` carried the break until
  this round.

- **The trap that let it pass locally too.** The world smoke tests
  (`test_globe_player_players_group`, etc.) assert `load("...globe_player.gd")
  != null`. **`load()` returns a NON-NULL script even for a file that failed
  to parse.** So the assertion is vacuous for exactly the failure it should
  catch. The test only "failed" here because the broken script later hung the
  boot for 240 s and tripped the runner's per-test timeout — a slow, fragile
  signal, not a check.

## 1. The law

> A gate that reports failure on a commit that then merges is not a gate.
> Two things must hold: (a) the check must FAIL on the real defect, and
> (b) the check must be in the runner's `DEFAULT_SET` so CI actually runs it.

Both halves were violated by PR #117: the world tests could not fail on the
defect (the `load() != null` trap), and the one signal that did fire
(`default-set: failure`) was merged past.

## 2. The fix (this round)

### 2a. The staging break itself

`game/entities/globe_player.gd`: removed the shadowing `var _inventory_bag`
declaration and consolidated every use onto the inherited
`inventory_component` (declared `player_base.gd:77`). `PlayerBase.func
_inventory_bag()` is the reader; the globe body now writes the same field the
reader reads. Parse clean; the world journey probe passes with zero errors.

### 2b. The durable guard (`game/tests/test_parse_check.gd`)

A whole-tree structural parse check. It walks every `.gd` under `res://`,
`load()`s it, calls `Script.reload()`, and FAILS on any file that returns
`ERR_PARSE_ERROR` (43). It is registered in
`scripts/godot_test_runner.sh` `DEFAULT_SET` (first entry), so CI runs it.

## 3. Why `reload() == ERR_PARSE_ERROR` is the honest signal

Three candidate discriminators were measured against a known-broken file
(`_tmp_child.gd` = duplicate member) and known-good files:

| Signal | Clean file | Missing-autoload file (`--script` mode) | Structural break | Verdict |
| --- | --- | --- | --- | --- |
| `load() != null` | true | true | **true** | useless — never sees the break |
| `can_instantiate()` | true | **false** | false | useless — 133 false positives |
| `reload() == OK` | true | **false (36)** | false | too strict — 133 false positives |
| `reload() == ERR_PARSE_ERROR (43)` | false | **false (36)** | **true** | **the discriminator** |

- `--script` mode does **not** mount autoloads. So ~133 legit scripts that
  reference `GameLog`, `EntityService`, etc. return code **36** (a missing
  identifier), not 43. Failing on "any non-OK" would flag all of them.
- A structural defect returns exactly **43** (`ERR_PARSE_ERROR`), independent
  of autoload presence. Verified across three defect classes: duplicate
  member (43), syntax error (43), bad type annotation (43); and a file with
  BOTH a structural defect and an autoload reference still returns 43.

Measured on the whole tree (`res://`, 839 files, ~14 s):
`698 × OK(0)`, `133 × 36`, `4 × 43`, `3 × 22`, `1 × null` — the 22s were a
transient reload-ordering artifact (double-reload returns 0); only the 43s
were real structural breaks.

## 4. The baseline (explicit, not hidden)

One file is a documented exception, listed in the test's `BASELINE` const:

- `res://core/combat/healing.gd` — a Godot-3-style legacy file with several
  top-level `class_name` declarations (`RegenerationOverTime`, `HoT`, `MoT`,
  `SoT`) plus a self-preload. **Zero live references** (verified: no
  preload/load/extends/new names it or its classes). It needs a real refactor
  or removal — tracked here, not papered over. A NEW structural break still
  fails the guard; only this one path is excused.

Two other pre-existing 43s were **fixed** rather than baselined, because they
were one-liners or live:

- `res://core/combat/projectile.gd` — `var collider := result["collider"]`
  could not infer a type from the Variant raycast result; typed it `Object`.
  (Dead code — no live references — but a one-line fix.)
- `res://connectors/webhook/webhook_base.gd` + `discord_webhook.gd` —
  `webhook_base.gd` failed on `var parts := header.split(...)` (Variant
  inference) and `var delay := max(...)` (Variant inference); `discord_
  webhook.gd` (LIVE: `WebhookManager._get_discord()` loads it) failed on a
  `const WebhookBase = preload(...)` sitting between `extends WebhookBase`
  and `class_name DiscordWebhook`, which pushes `class_name` into the class
  body. Fixed the types and dropped the now-redundant const (the base carries
  `class_name WebhookBase`). This un-broke a live feature.

After the fixes: **836 compiled, 1 baselined, 0 broken.**

## 5. The receipt

- The guard, run against a tree with the PR #117 break reintroduced
  (`git checkout origin/staging -- game/entities/globe_player.gd`), FAILS in
  ~14 s naming `res://entities/globe_player.gd`. That is the exact defect the
  incident shipped, caught in seconds instead of a 240 s hang.
- Against the fixed tree: exit 0.
- Registered first in `DEFAULT_SET`; a named run is
  `sh ./scripts/godot_test_runner.sh test_parse_check`.

## 6. Open items

1. **Refactor or delete `healing.gd`** (remove the `BASELINE` entry when done;
   the file is a Godot-3 relic — split the inner classes into their own
   files, or drop the file if the DoT/HoT behaviour lives elsewhere now).
2. **Audit the merge policy.** PR #117 merged with `default-set: failure`.
   The gate existed and fired; the merge ignored it. Worth a branch-protection
   rule: `default-set` must be green before merge to `staging`/`main`.
3. **Re-check other `load() != null` world tests** — the same vacuous-assertion
   trap may hide in sibling smoke tests. The parse guard now covers the class
   of defect globally, so they need not each be hardened, but the pattern is
   worth retiring where it is the only check.
