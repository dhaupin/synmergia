---
permalink: /operate/
layout: default
title: Operate a World
description: The server, web client, sidecars, backups, and the deployment path for running Synmergia.
---

# Run a world

This section is for self-hosters, operators, and contributors working on the deployment path. It is not a managed hosting offer.

## The moving parts

| Part | What it does | Current runbook |
|---|---|---|
| **Game server** | The authoritative Godot server and world state | [DEPLOY.md](https://github.com/dhaupin/synmergia/blob/main/DEPLOY.md) |
| **Web client** | The site and the `/game/` WebAssembly client | [DEPLOY_WEB.md](https://github.com/dhaupin/synmergia/blob/main/DEPLOY_WEB.md) |
| **Sidecars** | Postgres, Redis, webhook, and Julia bridges | [srv/README.md](https://github.com/dhaupin/synmergia/blob/main/srv/README.md) |
| **Shard mesh** | Multi-container server topology | [Shard mesh PRD](https://github.com/dhaupin/synmergia/blob/main/labs/prd-shard-mesh.md) |
| **Backups** | The hot-tier backup and restore path | [srv/backup/README.md](https://github.com/dhaupin/synmergia/blob/main/srv/backup/README.md) |

## What a real deployment needs

- A host with Docker and Docker Compose.
- A public domain and TLS certificates if the server is exposed beyond localhost.
- The ports your chosen profile uses; the production profile is not a single-port demo.
- A persistence choice. The adapter layer supports memory, Postgres, and Redis-backed configurations; the game server should not talk to those backends directly outside the adapter layer.
- A backup destination you have actually tested a restore from.

The exact compose profiles, environment variables, certificate steps, and systemd units are in the root deployment runbooks. They are kept there until they graduate into this portal.

## The current boundary

`DEPLOY.md`, `DEPLOY_WEB.md`, and the sidecar READMEs are the authoritative operational truth today. This page is the index and the orientation. If a command here and a runbook disagree, the runbook wins.

## Before you expose a server

- Read [SECURITY.md](https://github.com/dhaupin/synmergia/blob/main/SECURITY.md).
- Keep secrets in environment variables or a secret store; never commit them.
- Do not publish admin surfaces or credentials.
- Test a backup restore, not just a backup creation.

For deployment fixes, open an issue or a PR against `staging` with the failing command and the exact log line.
