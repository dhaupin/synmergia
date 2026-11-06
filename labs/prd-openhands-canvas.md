# OpenHands Canvas lanes for Synmergia

Status: working reference (2026-11-06). Supersedes the earlier recon note.
Answers: what can Canvas do for Synmergia, do subagents actually work, and
how do we run parallel lanes without spending money we did not intend to.

## TL;DR

- **Subagents work** -- verified end-to-end this session. A child
  conversation spawned in its own git worktree, ran a task, and returned
  the right answer.
- **The `start_child_conversation` tool is NOT in this profile** -- the
  agent cannot add it, and no env var enables it (see "The subagent-tool
  question, settled" below). Lanes still run because the agent calls the
  same endpoint the tool wraps.
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

## The subagent-tool question, settled (2026-11-06)

**Can the agent create its own subagent tooling? No. Does the owner have to
set an env var? No.** The evidence, all from this session's probes:

- The agent-server advertises `task_tool_set`, `task`, and
  `start_child_conversation` in `GET /server_info.usable_tools`
  (server v1.58.1). So the *capability* is present on the box.
- A child spawned through `POST /api/conversations/<parent>/children`
  inherits the parent's agent settings, which carry the **default exec
  toolset -- no subagent tool**. Asked to list its tools, a child returned
  terminal/file_editor/task_tracker/browser/... and said, verbatim, "I do
  not have a tool named `task`, `task_tool_set`, or
  `start_child_conversation`."
- `POST /api/conversations` (full creation) DOES accept an explicit
  `agent_settings.tools` list, and a conversation created with
  `{"name":"task_tool_set"}` genuinely reports `task_tool_set` among its
  tools. **But** that conversation needs its own LLM credentials: with
  `parent_conversation_id` set for inheritance it fails at creation
  ("belongs to a different workspace"), and without inheritance it errors
  on the first turn with `LLMAuthenticationError` -- the platform injects
  the LLM key at the serving layer, not into `agent_settings.llm.api_key`
  (that field comes back null even under `X-Expose-Secrets: encrypted`).
- `PATCH /api/settings` accepts only an `agent_settings_diff` whose schema
  exposes `mcp_config` (plus `additionalProperties`); there is no
  `enable_sub_agents` field in the openhands `AgentSettings` schema
  (`/api/settings/agent-schema` lists `tools`,
  `enable_classify_and_switch_llm_tool`, `active_meta_profile`, ... -- no
  subagent switch). So there is no settings knob to flip either.

**Conclusion.** The `start_child_conversation` tool is granted by the
*profile* the conversation runs under, and this profile does not include
it. Neither the agent nor an env var can add it -- it is a server-side
profile setting on OpenHands Cloud. The owner's Google-Gemini note is
right that Cloud needs no manual enablement *in the normal case*: the tool
ships when the profile carries it. It is simply not in this conversation's
profile.

**Workaround (what we actually do).** The agent drives lanes through the
same endpoint the tool wraps -- `POST /api/conversations/<parent>/children`
with the session key -- so parallel lanes work TODAY without the tool. The
only cost of not having the tool is that lane-spawning is a shell call, not
a native tool call. Ask OpenHands support to add the `task` /
`start_child_conversation` tools to the profile to get the native version.

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

### Lane D -- Modeling / assets / art (Blender + gen pipelines)

- **Owns:** `art/**` (source `.blend`, textures, renders),
  `game/models/**` (exported `.glb`), `scripts/gen_*_model.py`,
  `scripts/gen_icons.py`, `scripts/blender_*.sh`, and a new
  `labs/prd-art-pipeline.md`. Reads `labs/prd-3d-pipeline.md` as law.
- **Work:** author/generate 3D models (NPCs, enemies, mounts, props,
  dwellings), UV/rig/texture work, icon and texture generation, and
  long-running batch exports. This is the lane that legitimately runs
  for a LONG time -- model generation and Blender batch exports are
  minutes-to-hours, and that is exactly why it must not block A/B/C.
- **Foundation already in the repo:** Blender 4.3.2 is on PATH; the
  pipeline is PROVEN (`labs/prd-3d-pipeline.md` sec 1 + sec 6);
  `scripts/gen_blacksmith_model.py` / `gen_wolf_model.py` /
  `gen_icons.py` are the working recipes; `scripts/blender_smoke_test.sh`
  proves the chain. `game/models/**` is the `.glb` registry (filename ==
  data id).
- **Lane D obeys the locked decisions** (`labs/prd-spherical-mvp.md` sec
  2): (5) no resource packs -- the `.glb` naming registry + pck flow
  stays; (6) **Blender MCP is NOT adopted** -- the python generator
  pipeline + `model_export_lib.py` + in-engine probes remain the asset
  path. A lane D that reached for Blender MCP would violate a locked
  owner decision.
- **Receipt:** `scripts/blender_smoke_test.sh` (chain), the naming lint
  (a data file must never point at a phantom `.glb` path), and the
  in-engine model probes (`probe_blacksmith_model.gd`, etc.). A new
  model is "done" when it imports and the probe sees it -- not when the
  `.blend` looks right.
- **Google Colab / cloud GPU (the "T3" idea):** Colab is a reasonable
  *external* accelerator for heavy generation (a Colab notebook runs
  Blender headless or an image/texture model on a GPU the sandbox lacks),
  but it is a SEPARATE compute surface: the lane would push inputs out
  and pull `.glb`/textures back. Treat it as a tool a lane *calls*, not
  a lane by itself, and keep the artifacts flowing through the repo
  (`art/src/` -> `game/models/`) so the pipeline law still holds. Before
  wiring it, confirm the owner wants that external hop (it leaves the
  sandbox).
- **Why D is separate:** it is the only lane whose tasks are
  unbounded-time and resource-heavy (GPU/CPU, large binaries). Running
  it beside A/B/C means a 40-minute Blender batch never stalls the
  code lanes, and vice versa. It also rarely collides on files: `art/`
  and `game/models/` are disjoint from every code lane.

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
