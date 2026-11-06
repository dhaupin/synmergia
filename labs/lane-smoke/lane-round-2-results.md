# Lane round 2 -- bigger tasks, real receipts (2026-11-06)

Round 1 (docs-only lanes) proved the plumbing. Round 2 asked each lane to
DO work and RUN a receipt, to find where the harness actually breaks.

## The lanes

| Lane | Task | Outcome |
|---|---|---|
| A | Add 3 assertions to `test_content_packs.gd`, run it | **38/0** (+3). Harvested. |
| B | Audit every `"players"`-group consumer, run the group receipt | Report written; **converged on the same autosave risk** we found. Harvested. |
| C (1st) | Author a quest `.tres`, run the naming lint | **DIED** -- provider 429 (see below). |
| C (retry) | Same | **27/0**. Authored a valid quest, caught its own `res_ore_iron` typo. Discarded (dead data). |

## What actually blew up

1. **Shared-deployment 429.** Lane C died with
   `OpenAIError 429 -- "No deployments available for selected model ...
   cooldown_list=[...]"`, `classification: rate_limit, retryable`.
   This is litellm's router cooling down the `deepseek-v4.1-flash`
   deployment pool -- which is **account-wide**, so the owner's 2 agents
   plus our 3 lanes all shared one throttled deployment. It is retryable:
   the C-retry succeeded. **Budget lanes against the shared pool, not the
   session** -- ~3 concurrent heavy lanes is the practical ceiling while
   other agents run.

2. **Worktree import-cache friction.** `game/.godot/` is gitignored, so a
   fresh lane worktree has no `global_script_class_cache.cfg`. Any receipt
   run there fails with `Parse Error: Could not find type "Entity"` /
   `Icosahedral not declared` and HANGS (Lane B wedged ~30 min; Lane A had
   to run `godot --headless --path game --import` first). **Every
   receipt-running lane must `--import` first, or copy the primary
   checkout's `.godot/` cache.** Lane prompts now say so up front.

3. **Disk hygiene.** A wedged lane's receipt log hit 2.1 MB of per-tick
   `TickService`/`LODManager` DEBUG spam before the lane died. Bounded, but
   exactly the disk-bomb pattern the runner guards against. Lane receipt
   logs must go to a capped file, never an uncapped pipe.

## The confirmed code win

Lane B (independent) and our own trace both landed on
`player_progress.gd:294`: the `_find_tracked_player` group fallback would
hand the progress-less globe body to `save_player`, fabricating a 0/0/1
snapshot. Fixed with a surface guard; receipt
`test_globe_autosave_guard.gd` proves it (5/0).
