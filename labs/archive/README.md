# Archive

Deprecated documentation from earlier rounds. **Do not rely on these as source
of truth.** They may contain information that is no longer accurate, designs
that were abandoned, or approaches that were never implemented.

## Contents

| Path | What it is |
| --- | --- |
| `prd/prd-spatial-geometry.md` | Superseded geometry slice; merged into `../prd-geometry.md`. |
| `prd/prd-planar-retirement.md` | Completed PRD. The planar world is retired and its gameplay setups now live on the globe; history only. |
| `audit/gap-analysis-2026-08-31.md` | Gap analysis from before the vertical slice. |
| `audit/m3-initial-world-audit.md` | 2026-09-05 code-state snapshot ("where we are today" at the time). |
| `docs/architecture/` | Pre-`labs` architecture notes. Some are still useful background (NSC-9 evaluation, multi-iso frame, autoload races); none are current. |
| `docs/docker-setup.md`, `docs/vps-architecture.md` | Superseded deployment notes; see `DEPLOY.md` instead. |
| `captures-session-log.md` | Session logs from old rounds. |
| `refactor-npc-plan.md` | Abandoned NPC refactor plan. |
| `quest_guide_npc_stub.gd` | Orphan script kept as a stub reference. |

Note: `labs/polyglot-ffi/` and `labs/jolt-playground/` are still at the `labs/`
root — they are design/experiment folders, not archived work.

## Where current documentation lives

Start at [`../README.md`](../README.md). The short version:

- Product spec — `../prd.md`
- Frame architecture — `../world-building-arch.md`
- Terrain renderer — `../prd-clipmap.md`
- Dead / migrating systems — `../legacy-inventory.md`
- Agent-facing reference — `../../AGENTS.md`
