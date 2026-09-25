# Branding assets

The shipped logo pack (from the 4-up logo sheet, transparent PNGs):

| File                                | Sheet variant              | Used by                     |
|-------------------------------------|----------------------------|-----------------------------|
| `logo-synmergia-emblem.png`         | bottom-left (large star)   | boot splash, about panels   |
| `logo-synmergia-emblem-small.png`   | top-left emblem            | dense UI spots, loading     |
| `logo-synmergia-horizontal.png`     | top-right lockup           | main menu header            |
| `logo-synmergia-wordmark.png`       | bottom-right wordmark      | footers, splash text        |

Consumers go through `res://core/utils/branding.gd` (Brand.*) and fall
back to plain text when a file is missing, so partial packs are fine.
