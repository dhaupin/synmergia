# Contributing to Synmergia

Thanks for wanting to help build a world. Synmergia is a browser-first
MMORPG (Godot 4.7.2 + a React/TypeScript website) and it is open source
under the [MIT License](./LICENSE). This file is the practical path from
"clone" to "merged pull request."

By participating you agree to the [Code of Conduct](./CODE_OF_CONDUCT.md).

## Ways to help (you do not have to write engine code)

- **Engineers** — GDScript, the authoritative server, the frame.
- **Artists & modelers** — characters, creatures, gear, the look of the
  world (there is a Blender pipeline in `scripts/`).
- **World builders** — zones, quests, dungeons, and lore; it is all data
  under `game/data/`.
- **Architects** — spatial geometry, the state tree, orchestration.
- **Testers** — play it, break it, write a probe, file a clean report.
- **Idea people** — open an issue with the thing you would build.

Not sure where to start? Open an issue titled `Idea: ...` or
`Help wanted: ...` and describe it. Good ideas change the roadmap.

## Getting set up

You need **Godot 4.7.2** (the exact version matters — it matches the
`.tres` format writer across `game/data/`), **Node 20+**, and **bun** (or
npm). Python 3 is used by a couple of sidecar scripts.

The fastest path installs the whole toolchain from the repo alone:

```bash
sh ./scripts/setup-dev.sh            # base toolchain
sh ./scripts/setup-dev.sh --all      # + web export templates, blender, web probe
```

Add flags as you need them: `--with-templates` (web export),
`--with-blender` (3D pipeline), `--with-web-probe` (chromium). Use
`--dry-run` to see the plan first.

Then:

```bash
git clone https://github.com/dhaupin/synmergia.git
cd synmergia
bun install          # or: npm install
```

Open the `game/` folder in the Godot editor to work on the game. The
website lives in `src/` and builds with `npm run build`.

Full environment notes are in [DEVCODE.md](./DEVCODE.md); product and
architecture overview is in [README.md](./README.md).

## Running the tests

The game test suite runs headless:

```bash
sh ./scripts/godot_test_runner.sh            # the default regression set
sh ./scripts/godot_test_runner.sh --all      # every test (parallel)
sh ./scripts/godot_test_runner.sh probe_startup_flow   # one named probe
```

The website checks:

```bash
npm run lint      # tsc --noEmit
npm run build     # type-check + vite build + prerender
```

**Tests are the arbiter.** A change is not done until the relevant probes
pass and the default set stays green. If you fix a bug, add or extend a
test that would have caught it.

## Conventions (these bite if you ignore them)

Read [AGENTS.md](./AGENTS.md) before touching GDScript — it is the
long-form style guide. The short version:

- **Tabs, not spaces, in `.gd` files.** Mixed indentation is a parse
  error in Godot 4.7.2.
- **ASCII only in source.** No emoji or smart quotes — they cause Godot
  import failures. The website and docs may use them; `.gd` files may not.
- **`extends` before `class_name`.** And never give a script a
  `class_name` equal to an autoload name.
- **Snake_case files**, `PascalCase` classes, past-tense signal names
  (`entity_spawned`).
- **Use the existing systems.** Data ids follow the prefixes documented in
  AGENTS.md (`npc_`, `quest_`, `zone_`, `wep_`, ...), and the naming lint
  enforces them — run `game/tests/test_data_naming_lint.gd` after adding
  or renaming any data id.
- Keep comments honest and minimal; do not narrate the diff.

## Pull requests

1. **Branch** off `staging` (the integration branch; `main` is promoted
   from it). Use a short descriptive
   name (`fix/aura-binding`, `feat/harvest-service`).
2. **Keep it focused.** One logical change per PR.
3. **Test it.** Say in the description what you ran and what passed.
4. **Describe it.** What changed, why, and how you verified. If it is a
   gameplay or balance change, say what a player will notice.
5. **Be patient and kind.** This is a small crew; reviews may take a bit.

CI runs the website build and lint. Game-side changes are verified by the
probe suite; run it locally before pushing so CI is not your first signal.

### Commit messages

Short imperative subject line (`fix(hud): un-dead the player buff bar`),
blank line, then body if it helps. Reference issues with `#123` when
relevant. If you can, add a `Signed-off-by:` line (a DCO-style
sign-off) — it certifies you wrote the change or have the right to
contribute it.

## Reporting bugs

Open a GitHub issue. A great report includes:

- What you did, what you expected, what happened.
- Steps to reproduce (the more exact, the better).
- Your environment (browser, OS; for engine bugs, the Godot version).
- Any error output from the console or `GameLog`.

Security issues do **not** go in the public tracker — see
[SECURITY.md](./SECURITY.md).

## Licensing of contributions

By submitting a contribution you agree it is licensed under the
project's [MIT License](./LICENSE) and that you have the right to
submit it. Do not paste in code or assets you did not write unless their
license is compatible and you note the source and license in the PR and
in [CREDITS.md](./CREDITS.md).

## Where things live

| Path | What |
|------|------|
| `game/` | the Godot project (the game itself) |
| `src/` | the website (React + Vite + Tailwind) |
| `web/` | the raw engine shell served at `/game/` |
| `game/data/` | all game content (`.tres` resources) |
| `labs/` | design docs and PRDs |
| `scripts/` | build, test, and generation scripts |

Questions that are not a bug or a feature request are welcome in issues
too. Welcome aboard.
