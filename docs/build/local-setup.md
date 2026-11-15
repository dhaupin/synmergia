---
permalink: /build/local-setup/
layout: default
title: Local Setup
description: Godot 4.7.2, Node 20+, Bun, the setup script, and the first game import.
---

# Local setup

The repository is designed to come up from a fresh clone with one setup script and two toolchains. The deep environment notes live in [DEVCODE.md](https://github.com/dhaupin/synmergia/blob/main/DEVCODE.md); this page is the shortest path.

## What you need

- **Godot 4.7.2** - the engine version is pinned. Do not substitute a newer patch.
- **Node 20+** - the website and docs tooling.
- **Bun** - the repository's package manager; npm also works for the scripts.
- **Python 3** - a few sidecar and asset scripts.
- **Blender** - only if you are working the 3D pipeline.

## First clone

```bash
git clone https://github.com/dhaupin/synmergia.git
cd synmergia

# Base toolchain. Add --with-templates, --with-blender,
# --with-web-probe, or --all as needed.
sh ./scripts/setup-dev.sh
```

The setup script provisions the local tools the repository expects. It does not download a Godot editor for you; put the pinned 4.7.2 binary on `PATH` or set `GODOT_BIN` when running tests.

## Open the game

```bash
godot --editor game/
```

The Godot project root is `game/`. The first open builds the `.godot` import cache. A freshly pulled tree has no class cache, so run the import once before trusting a test result:

```bash
godot --headless --path game --import
```

Skipping that step can make every `class_name` look undeclared and let a suite exit 0 while compiling only part of the project.

## Run the site

```bash
bun install
npm run dev
```

The site is a React/Vite app. The game client is served at `/game/` beside it, not as a separate web app.

```bash
npm run build    # sync data, type-check, prerender
npm run lint     # type-check only
```

## Build the docs

The docs portal is a separate Jekyll site in `docs/`. It needs Ruby 3.3.

```bash
cd docs
bundle install
bundle exec jekyll build
cd ..
node node_modules/freestruct/bin/freestruct.mjs --strict
```

Or use the wrappers:

```bash
npm run docs:build
npm run docs:serve
```

## Next

- [Run the tests]({{ '/build/testing/' | relative_url }}).
- [Read CONTRIBUTING.md](https://github.com/dhaupin/synmergia/blob/main/CONTRIBUTING.md).
- [Read AGENTS.md](https://github.com/dhaupin/synmergia/blob/main/AGENTS.md) before touching GDScript.
- [Browse the repository map]({{ '/build/' | relative_url }}) if you are looking for a subsystem.
