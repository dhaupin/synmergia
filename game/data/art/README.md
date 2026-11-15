# Art workspace

Canonical home for source art, GPU scratch output, and reference renders under
`game/data`. The directory carries `.gdignore`, so Godot does not import it into
the game.

| Path | What lives there | Tracked |
|---|---|---|
| `src/` | `.blend` sources, reference images, and textures used to build models | Yes |
| `out/` | GPU-generated `.glb` and texture scratch, before normalization | No |
| `screenshots/` | Rendered model references and review images | Yes |

Only the exported `.glb` belongs in `game/data/models/<family>/<data_id>.glb`;
the source and scratch stay here. The five enemy GLBs, the blacksmith, and the
calibration block are a prototype pass; the target `ModelData` schema and
pipeline are in [`labs/prd-models.md`](../../../labs/prd-models.md).
