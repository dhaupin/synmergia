# Art workspace

Canonical home for source art, GPU scratch output, and reference renders.
The directory carries `.gdignore`, so Godot does not import it into the game.

| Path | What lives there | Tracked |
|---|---|---|
| `src/` | `.blend` sources, reference images, and textures used to build models | Yes |
| `out/` | GPU-generated `.glb` and texture scratch, before normalization | No |
| `screenshots/` | Rendered model references and review images | Yes |

Only the exported `.glb` belongs in `game/models/<data_id>.glb`; the source
and scratch stay here. The old root `art/` tree is retired.
