# OpenHands Canvas for Synmergia - lanes, subagents, automations

Status: reconnaissance (2026-11-06). This is a findings note, not a
committed design. It answers "what can Canvas do for Synmergia,
especially subagents/automations -- can 3 lanes work at once?"

## TL;DR

- Yes, the platform supports parallel lanes. Two mechanisms exist:
  1. **Child conversations** (`start_child_conversation`) -- an agent
     spawns a subagent that runs in the SAME sandbox, optionally in its
     own git worktree. This is the "3 lanes at once" primitive.
  2. **Cloud app-conversations** (`POST /api/v1/app-conversations`) --
     fully separate sandboxes, each with its own context window.
- This session runs on **OpenHands Cloud**, not a local Agent Canvas.
  The agent server is `127.0.0.1:60000` inside the sandbox; the app
  server is `https://app.all-hands.dev`.
- The child-conversation tool is **advertised by the server but NOT
  exposed in this agent's tool profile** -- so an agent on this profile
  cannot call it directly. It becomes available when the profile grants
  the `task` / `start_child_conversation` tools.
- The repo already has a MANUAL version of this idea: `labs/subagent-tasks.md`
  (a docs-only board a human lands). Canvas automates the same pattern.

## What was verified

| Fact | Evidence |
|---|---|
| Agent server live | `GET 127.0.0.1:60000/health` -> 200, `version 1.58.1` |
| Child-conversation endpoints exist | `/api/conversations/{id}/children` (POST), `/children` listed in `openapi.json` |
| Child isolation options | `StartChildConversationRequest.isolation` = `worktree` (default) or `shared` |
| `worktree` means a real git worktree | schema description: "runs it in a git worktree carved from the parent's workspace when that workspace is a git repository" |
| Subagent tools advertised | `server_info.usable_tools` includes `start_child_conversation`, `task`, `task_tool_set` |
| These tools are NOT in this profile | not present in this agent's function list |
| Cloud API read works | `GET /api/v1/users/me` + `app-conversations/search` with `OPENHANDS_API_KEY` |
| `RUNTIME_URL` is public | `https://ouquymneluldldjd.prod-runtime.all-hands.dev` -> webhooks viable |
| Lane budget in practice | 2 conversations running concurrently right now; guidance is <= 5 |

## Mechanism 1 - child conversations (same sandbox, worktree lanes)

The agent-side tool `start_child_conversation` POSTs to
`/api/conversations/{parent_id}/children`:

```json
{ "task": "self-contained brief", "title": "optional", "isolation": "worktree" }
```

- `isolation: worktree` carves a **git worktree** off the parent's
  workspace, so each lane gets its own checkout and cannot collide on
  files. `isolation: shared` runs in the parent directory.
- The child gets the `task` as its first user message -- it is a fresh
  context window, so the brief must be self-contained.
- Children are enumerable via `/api/conversations/{id}/children`.

**Synmergia fit:** excellent for the repo's independent, receipt-gated
work. Three lanes could be e.g. (a) shard-mesh Phase 4, (b) a terrain
lane, (c) a data/lint lane. Each lane works a distinct file set, runs
its own `test_*.gd` receipt, and the parent merges. The worktree
isolation maps cleanly onto the repo's "one law, one receipt" style.

**Caveats:**
- Worktrees and the LFS hooks: `git worktree add` triggers the LFS
  `post-checkout` hook, which exited 2 without `git-lfs` on PATH. Fixed
  this round -- `git-lfs` is now installed and `scripts/setup-dev.sh`
  provisions it. Without that fix a worktree lane would have looked
  broken (the worktree WAS created; the hook just returned non-zero).
- A lane that edits shared files (e.g. `scripts/godot_test_runner.sh`
  DEFAULT_SET, `AGENTS.md`) will conflict at merge. Keep lanes on
  disjoint file sets, or serialize the shared-file edits.

## Mechanism 2 - Cloud app-conversations (separate sandboxes)

`POST https://app.all-hands.dev/api/v1/app-conversations` with
`Authorization: Bearer $OPENHANDS_API_KEY` and
`selected_repository: dhaupin/synmergia`, `selected_branch: staging`.

- Fully separate sandbox + context window. Heavier than a child
  conversation, but the strongest isolation.
- The create call is async: it returns a start-task; poll
  `/api/v1/app-conversations/start-tasks?ids=...` until `READY`, then use
  the `app_conversation_id`.
- `GET /api/v1/app-conversations?ids=<id>` returns `session_api_key` +
  `conversation_url` (the in-sandbox agent-server URL) -- the handles to
  drive a lane's sandbox directly.
- Shareable UI link: `https://app.all-hands.dev/canvas/conversations/<id>`.
- Guidance: keep <= 5 concurrently running.

**Verified read-only this session:** `users/me`, `app-conversations/search`,
and one conversation record (which is where `session_api_key` comes from).
No conversation was created (cost control) -- an empty `POST` returned 200
but created nothing.

## Mechanism 3 - automations (scheduled / event-triggered)

The automation service (`app.all-hands.dev/api/automation/v1`) is
reachable; the account currently has **0 automations**. An automation
runs a prompt on a cron schedule or a webhook event and starts a
conversation each time. Because `RUNTIME_URL` is a public host, webhook
triggers are viable.

**Synmergia fit (candidates, not commitments):**
- A nightly "receipt sweep": run the lint suite + data-naming lint +
  a chosen subset of `test_*.gd`, and report.
- A "staging drift" watch: alert when `staging` diverges from `main`
  beyond the approved portability delta.
- The existing `labs/subagent-tasks.md` board could become an automation
  that drafts one story doc per task on a schedule.

## Recommended shape for "3 lanes at once"

1. Enable the `task` / `start_child_conversation` tools on the profile
   that runs Synmergia work (they are server-side already).
2. Define 3 disjoint lanes with explicit file ownership, e.g.:
   - Lane A: `game/core/mesh/**` + `labs/prd-shard-mesh.md`
   - Lane B: `game/tests/probe_*` + terrain scripts
   - Lane C: `game/data/**` + naming lint
3. Each lane runs its own receipt and reports the exit code + a one-line
   verdict. The parent merges worktrees and runs the full gate once.
4. Keep shared-file edits (runner DEFAULT_SET, AGENTS.md round note)
   in the PARENT, applied after the lanes land -- that is the merge point.

## Open questions for the owner

- Which profile should carry the subagent tools (this one does not)?
- Do we want lanes as worktrees (same sandbox) or separate sandboxes?
- Is there an appetite for automations, or keep everything interactive?
