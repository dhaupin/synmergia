# OpenHands Canvas lanes for Synmergia

Status: working reference (2026-11-06). Supersedes the earlier recon note.
Answers: what can Canvas do for Synmergia, do subagents actually work, and
how do we run parallel lanes without spending money we did not intend to.

## TL;DR

- **Subagents work** -- verified end-to-end this session. A child
  conversation spawned in its own git worktree, ran a task, and returned
  the right answer.
- **The blocker was our own dead Git LFS vestige**, not the platform. The
  LFS `post-checkout` hook exited 2 because the agent server's PATH has no
  `git-lfs`, so `git worktree add` (how lanes get a checkout) returned
  non-zero and the spawn failed. Removed in commit `3b37efec`.
- **Lanes share the parent sandbox** (no extra sandbox cost) but each lane
  is a full agent run, so it **consumes LLM tokens** -- it is not free.
  Run lanes when the work is worth the tokens; do not fan out for trivia.
- **Automations cost tokens too** (each scheduled run starts a
  conversation). We do not need them; the interactive lanes are enough.

## What was verified (this session)

| Fact | Evidence |
|---|---|
| Child conversations spawn | `POST /api/conversations/{id}/children` returned a child id |
| Worktree isolation works | child workspace was `/tmp/conversation-worktrees/<id>/synmergia` |
| The child actually ran | status `idle` -> `finished`; final response was the exact HEAD hash `b9f0629f...` |
| The LFS hook was the blocker | before removal: `Git command failed: git worktree add ...`; after removal: spawn succeeded |
| Agent server PATH | `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` (no `~/.local/bin`) |
| `start_child_conversation` tool | advertised in `server_info.usable_tools` |
| Lane budget | <= 5 concurrent recommended; 2 were running during this session |

## The spawn recipe (what the agent-side tool does under the hood)

```
POST /api/conversations/<parent_id>/children
  X-Session-API-Key: <session key>
  { "task": "<self-contained brief>",
    "title": "<short>",
    "isolation": "worktree" }        # or "shared"
```

- `worktree` = its own git checkout off the parent's HEAD. Lanes cannot
  collide on files. This is what we want for parallel work.
- The child gets `task` as its first message -- it has a FRESH context
  window, so the brief must be self-contained (goal, files, receipt,
  definition of done). It cannot see this conversation.
- Poll `GET /api/conversations/<child_id>` for `execution_status`; read
  the answer from `.../agent_final_response`.
- Children are deleted with `DELETE /api/conversations/<child_id>`.

In an agent turn the equivalent is simply calling the
`start_child_conversation` tool (same endpoint). It is exposed only when
the profile grants the `task` / `start_child_conversation` tools.

## The three lanes

The repo's work splits cleanly into three disjoint lanes. Disjoint file
ownership is the rule -- two lanes editing the same file is a merge fight.

### Lane A -- High-level systems (architecture / services)

- **Owns:** `game/core/**`, `game/adapters/**`, `labs/prd-*.md`
- **Work:** shard mesh phases, frame primitives, service APIs, the
  cross-cutting laws (e.g. ShardParameters, ContentPacks, the mesh bus).
- **Receipt:** the matching `tests/test_<system>.gd` plus the lint suite.

### Lane B -- Game loop / wiring

- **Owns:** `game/scenes/worlds/**`, `game/entities/**`, `game/ui/**`,
  `game/core/components/**`
- **Work:** boot path, world/globe, player controller, HUD wiring, the
  moment-to-moment loop (combat/aggro/quest bridges, interact menus).
- **Receipt:** the relevant `probe_*.gd` / `test_*.gd` + a boot probe.

### Lane C -- World / data building (tres + schemas)

- **Owns:** `game/data/**` (items, quests, npcs, zones, loot, mounts,
  content packs), `game/core/schemas/**`
- **Work:** authoring content on the existing schemas, the data-naming
  lint, cross-file reference integrity. No phantom SKUs.
- **Receipt:** `tests/test_data_naming_lint.gd` + the catalog/quest
  receipts that read the data.

**Shared-file rule:** `scripts/godot_test_runner.sh` (DEFAULT_SET),
`AGENTS.md`, and `labs/TASKS.md` are edited in the PARENT only, after the
lanes land. That is the merge point, not a lane's job.

## Cost honesty

- **Sandbox:** lanes share the parent sandbox, so there is no extra
  sandbox/VM charge -- only LLM tokens.
- **Tokens:** every lane is a full agent run. Three lanes is roughly
  three agents' worth of inference. Spend it on real work, not on
  "let's see what it does".
- **Automations:** each scheduled/event run starts a conversation and
  bills tokens the same way. They also depend on the automation service.
  We have 0 configured and do not need any right now.
- **Practical guidance:** use lanes when a task decomposes into genuinely
  independent, receipt-gated work (e.g. "author 5 quests" beside "fix the
  mesh bus"). Do not fan out a single small change.

## Smoke test results (2026-11-06) -- LANES WORK

Ran the three lanes for real, each a small read-only task with a docs-only
receipt. All three spawned in parallel, ran to `finished`, wrote exactly
one file in their OWN worktree, and touched nothing else.

| Lane | Task | Outcome |
|---|---|---|
| A systems | inventory the shard-mesh phases -> file map | 139-line map; found all 6 phases implemented + their receipts; flagged the un-run receipts honestly |
| B game-loop | trace player boot + input->movement | 128-line map; surfaced a REAL bug candidate (below) |
| C data | audit item naming + refs | 94-line audit; 8/8 filename==id, zero dangling refs, 2 soft data-semantics notes |

**What blew up:** nothing. Isolation held (each lane wrote only in
`/tmp/conversation-worktrees/<id>/synmergia`; the parent `staging` tree
stayed clean). The only friction was environmental and pre-fixed: `godot`
and `bun` had to be on the SERVER's PATH (`/usr/local/bin` symlinks) or a
lane that runs a receipt would fail -- a lane that only reads files does
not need them.

**The bug Lane B found (confirmed by the parent):** `globe_player.gd` never
calls `add_to_group("players")`, while the planar `player_controller.gd:452`
does. `ActionBar._on_player_input()` resolves its caster via
`get_first_node_in_group("players")` (`action_bar.gd:431`), so on the globe
that lookup cannot find the local body. Real wiring gap, not a lane
hallucination.

**Harvested artifacts:** `labs/lane-smoke/` (the three maps, kept as
evidence + reference).

**Cost:** three lanes = three agent runs. Fine for a smoke test; for real
work, size the lane to the value.

## Preconditions for lanes on this repo

1. No Git LFS hooks (fixed: `3b37efec`; `scripts/setup-dev.sh`
   `strip_lfs_hooks` keeps it fixed on fresh/rebooted boxes).
2. A profile that grants the `task` / `start_child_conversation` tools.
3. A self-contained brief per lane (goal, owned files, receipt, done).
4. The parent merges the worktrees and runs the full gate once at the end.

## Open questions for the owner

- Which profile should carry the subagent tools?
- Do we want lanes as worktrees (same sandbox) or separate sandboxes?
