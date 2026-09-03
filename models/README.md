# Synmergia Modeling Pipeline

This directory contains the modeling infrastructure for Synmergia's
multi-iso world system, NPC AI, procedural generation, and content pipelines.

## Structure

```
models/
├── julia/           # Julia hot math (server-side)
│   ├── multi_iso.jl  # Multi-iso orchestrator
│   ├── nsc9.jl      # NSC-9 encoding/decoding
│   └── pipeline.jl   # Content generation pipeline
├── python/          # Python tools (offline processing)
│   ├── iso_math.py   # Multi-iso prototype (existing)
│   └── generate.py   # Content generation scripts
├── data/            # Generated data outputs
│   └── .gitkeep
├── notebooks/        # Jupyter notebooks for exploration
│   └── .gitkeep
└── README.md        # This file
```

## Languages

| Language | Use Case | Runtime |
|----------|----------|---------|
| **Julia** | Hot math, real-time calculations, NPC AI | Server-side (Docker) |
| **Python** | Offline generation, data processing | Dev tools |
| **GDScript** | Godot game logic | In-engine |

## Multi-ISO System

The multi-iso orchestrator handles entity queries across multiple axes:

- **Spatial**: Icosahedral vertex mapping (12 vertices)
- **Faction**: Player/faction relationships
- **Temporal**: Time-based queries
- **Social**: Guild/group relationships
- **Game**: Class/item axis

See `labs/multi-iso/prototype/iso_math.py` for the prototype proof.

## Running Julia Models

```bash
# In Docker
docker compose -f docker-compose.prod.yml run julia

# Or locally
julia --project=. julia/pipeline.jl
```

## Data Flow

```
[Design] → [Python/Julia] → [Generated Data] → [Postgres/SQLite]
                ↓
           [Redis Cache]
                ↓
           [Godot Server]
```

## Redis Cache Layer

Redis is used as a cache layer before Postgres for:
- Session data
- Entity state snapshots
- Query results
- Rate limiting

## SQLite Support

For lightweight instances or testing, SQLite can be used instead of Postgres:
- Set `SQLITE_ENABLED=true`
- Data stored in `synmergia-data:/var/lib/synmergia/data.db`
