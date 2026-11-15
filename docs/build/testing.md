---
permalink: /build/testing/
layout: default
title: Testing
description: The one Godot test runner, the website checks, the docs build, and what CI actually runs.
---

# Testing

There is one Godot test runner. It is already parallel, and it is the local loop to use before opening a pull request.

## The Godot runner

```bash
# The default regression set, parallel.
sh ./scripts/godot_test_runner.sh

# Every test_*.gd.
sh ./scripts/godot_test_runner.sh --all

# One named test.
sh ./scripts/godot_test_runner.sh test_foo

# Fully serial, when a timing-sensitive probe needs it.
JOBS=1 sh ./scripts/godot_test_runner.sh
```

The runner boots overlapping test processes, but timing-sensitive movement and terrain probes run alone first so CPU contention cannot fake a result. `GODOT_BIN` points the runner at a specific Godot binary.

Before the first run on a fresh tree, import the project once:

```bash
godot --headless --path game --import
```

## The website

```bash
npm run lint     # TypeScript
npm run build    # sync data, type-check, prerender
npm run dev      # local Vite server
```

`npm run build` also regenerates `src/data/godot_data.json` from `game/data/*.tres`. The generated file is committed; do not hand-edit it.

## The docs

```bash
npm run docs:build
```

That runs Jekyll, then freestruct with `--strict`. The docs deploy lane also runs pagefind and a freestruct audit. A broken internal docs link fails the strict build.

## What CI runs

| Workflow | What it verifies |
|---|---|
| `godot-ci.yml` | The default Godot regression set on PRs to `staging`/`main` and staging pushes |
| `web-ci.yml` | Web validation, the PCK export, and the client build path |
| `docs-ci.yml` | Relative Markdown links across the repository |
| `docs.yml` | Jekyll, freestruct, pagefind, and the GitHub Pages artifact |

The default Godot set is green on current staging. The full `--all` set still
includes environment-only legs (agent driver, full boot, and the web/UI probes)
that can fail outside a complete local checkout. Check
[AGENTS.md](https://github.com/dhaupin/synmergia/blob/main/AGENTS.md) before
treating one of those as your regression.

## Before you open a PR

- Run the narrowest test that covers your change.
- Run the full default set when the change crosses services or data.
- Run `npm run lint` for website changes.
- Run `npm run docs:build` for docs changes.
- Do not weaken an assertion to make a failure disappear. Fix the cause or report the failure.
