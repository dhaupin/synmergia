---
permalink: /reference/
layout: default
title: Reference
description: The shared vocabulary and the stable lookup sources for Synmergia code and docs.
---

# Look it up

Reference material is for the thing you need to check mid-task: a term, a schema, a command, or a contract. It is intentionally narrower than the build and world sections.

## Available now

- [Glossary]({{ '/reference/glossary/' | relative_url }}) - the shared vocabulary: frame, clipmap, shard, scope band, tier, `.tres`, Codex, AgentDoor, and more.

## Stable sources still in the repository

These are authoritative today. They graduate into this section as they are rewritten for the docs audience.

| Topic | Source |
|---|---|
| Persistence and adapter contracts | [labs/prd-db.md](https://github.com/dhaupin/synmergia/blob/main/labs/prd-db.md) |
| Data authoring | [labs/data-authoring-baseline.md](https://github.com/dhaupin/synmergia/blob/main/labs/data-authoring-baseline.md) |
| Spherical world math | [labs/world-building-spherical.md](https://github.com/dhaupin/synmergia/blob/main/labs/world-building-spherical.md) |
| Agent and code conventions | [AGENTS.md](https://github.com/dhaupin/synmergia/blob/main/AGENTS.md) |
| Web client and portal | [labs/prd-web.md](https://github.com/dhaupin/synmergia/blob/main/labs/prd-web.md) |

## The rule

A reference page is only useful if it matches the code. If a schema, command, or field name changes, the page changes in the same pull request. If it cannot be verified, it does not belong here yet.
