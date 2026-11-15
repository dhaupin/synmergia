---
permalink: /
layout: default
title: Synmergia Docs
description: How Synmergia works, how it is built, and how to run a world of your own.
---

# Synmergia Docs

<p class="lede">How the world works, how it is built, and how to run your own. The player-facing codex, lore, rules, guides, and community wiki stay on the main website.</p>

<div class="doors">
  <a class="door" href="{{ '/world/' | relative_url }}">
    <span class="door-kicker">For players</span>
    <strong>Understand the world</strong>
    <span>The systems behind the planet, combat, economy, housing, and the browser client.</span>
  </a>
  <a class="door" href="{{ '/build/' | relative_url }}">
    <span class="door-kicker">For builders</span>
    <strong>Build or contribute</strong>
    <span>Clone the repo, run the tests, and find your first thread in the open source.</span>
  </a>
  <a class="door" href="{{ '/create/' | relative_url }}">
    <span class="door-kicker">For creators</span>
    <strong>Make content</strong>
    <span>Author data, quests, items, and art without touching the engine.</span>
  </a>
  <a class="door" href="{{ '/operate/' | relative_url }}">
    <span class="door-kicker">For operators</span>
    <strong>Run a world</strong>
    <span>The server, web client, sidecars, backups, and the deployment path.</span>
  </a>
  <a class="door" href="{{ '/access/' | relative_url }}">
    <span class="door-kicker">For everyone</span>
    <strong>Access and agents</strong>
    <span>One semantic tree for screen readers and MCP clients, carried by gamestruct.</span>
  </a>
</div>

## Start with the world

Synmergia is a browser-first, persistent 3D world: a spherical planet with player housing, territory, guilds, action combat, and an economy shaped by players. The main world runs on a 20 km sphere; the game server is authoritative; the client is a WebAssembly build of the Godot project.

- [The planet]({{ '/world/planet/' | relative_url }}) - the sphere, the clipmap, and the world declarations.
- [Combat, economy, and social systems]({{ '/world/' | relative_url }}) - the systems view, with links into the Codex for the full data.
- [Play the early-access build](https://synmergia.creadev.org/play) - the live browser client.
- [Browse the Codex](https://synmergia.creadev.org/codex) - every class, skill, item, enemy, recipe, and mount, read from the data the server loads.

## Access is part of the architecture

Human accessibility and agent access are not two projects. They are two readings of one semantic tree: native labels and focus order for people, stable handles and an event stream for MCP clients. [Access and agents]({{ '/access/' | relative_url }}) is the published contract, [human accessibility]({{ '/access/human/' | relative_url }}) covers the engine tree and settings, and [gamestruct]({{ '/access/gamestruct/' | relative_url }}) is the shared carrier.

The engine accessibility drill merged on `staging`; the open lane is real
assistive-technology and keyboard verification
([#101](https://github.com/dhaupin/synmergia/issues/101)). These pages describe
the shipped surface and the verification gate.

## What lives where

| Home | What it is |
|---|---|
| [synmergia.creadev.org](https://synmergia.creadev.org/) | The player surface: Play, Codex, Lore, Rules, Experiences, future guides, and Fandom/community wiki |
| These docs | The systems view, build and contribution paths, content authoring, operations, reference, and the access and agent contract |
| [labs/](https://github.com/dhaupin/synmergia/tree/main/labs) | In-flight PRDs, design history, session logs, and lane briefs - the workshop, not published truth |
| [GitHub](https://github.com/dhaupin/synmergia) | The source, issues, pull requests, and release history |

The rule is one canonical home per fact. The Codex is generated from `game/data` and lives on the website. Lore and story canon live on the website. This portal explains how the machinery works and points at those pages rather than copying them.

## Build these docs

The docs site is Jekyll with a freestruct post-build pass, served as a GitHub Pages project site at `/synmergia/`.

```bash
cd docs
bundle install
bundle exec jekyll build
cd ..
node node_modules/freestruct/bin/freestruct.mjs --strict
```

The repository scripts wrap that:

```bash
npm run docs:build
npm run docs:serve
```

The source lives in `docs/`. The built tree is `docs/_site/` and is never committed.
