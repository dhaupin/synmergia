# Branding assets

Drop the exported logo PNGs here (transparent background, cropped from
the 4-up logo sheet):

| File                  | Sheet variant            | Used by                     |
|-----------------------|--------------------------|-----------------------------|
| `emblem.png`          | bottom-left (large star) | boot splash, about panels   |
| `emblem_small.png`    | top-left emblem          | dense UI spots              |
| `logo_horizontal.png` | top-right lockup         | main menu header, loading   |
| `wordmark.png`        | bottom-right wordmark    | footers, splash text        |

Consumers go through `res://core/utils/branding.gd` (Brand.*) and fall
back to plain text when a file is missing, so partial packs are fine.
After adding files, let Godot import them once (editor focus or any
headless run) before screenshots.
