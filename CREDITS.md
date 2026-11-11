# Credits & Third-Party Notices

Synmergia's own code, art, audio, and content are licensed under the
[MIT License](./LICENSE), copyright Creadev.org. This file records the
third-party software and assets the project depends on or ships, and the
terms under which they are used.

If you add a dependency or asset, note it here (and in your pull request).

## Engine & runtime

| Component | License | Notes |
|-----------|---------|-------|
| [Godot Engine](https://godotengine.org) 4.7.2 | MIT | The game engine. Its license text ships with the web export at [`web/LICENSE.godot.txt`](./web/LICENSE.godot.txt). |

## Website & build

| Component | License |
|-----------|---------|
| [React](https://react.dev) / react-dom | MIT |
| [React Router](https://reactrouter.com) | MIT |
| [Vite](https://vite.dev) | MIT |
| [Tailwind CSS](https://tailwindcss.com) | MIT |
| [lucide-react](https://lucide.dev) | ISC |
| [Motion](https://motion.dev) (framer-motion) | MIT |
| [canvas-confetti](https://github.com/catdad/canvas-confetti) | ISC |
| [TypeScript](https://www.typescriptlang.org) | Apache-2.0 |

Build-time only: [gamestruct](https://github.com/dhaupin/gamestruct) (MIT),
[tsx](https://github.com/privatenumber/tsx) (MIT).

## Fonts

Both fonts are self-hosted (no third-party CDN) and used under the SIL
Open Font License 1.1. Their license texts ship beside them in
`public/fonts/`.

| Font | License | License text |
|------|---------|--------------|
| [Cinzel](https://fonts.google.com/specimen/Cinzel) | SIL OFL 1.1 | [`public/fonts/OFL-Cinzel.txt`](./public/fonts/OFL-Cinzel.txt) |
| [Plus Jakarta Sans](https://fonts.google.com/specimen/Plus+Jakarta+Sans) | SIL OFL 1.1 | [`public/fonts/OFL-PlusJakartaSans.txt`](./public/fonts/OFL-PlusJakartaSans.txt) |

## Art & audio

All game art, models, audio, and branding are original to Synmergia and
generated or authored in-repo, so they fall under the project's MIT
license unless noted otherwise:

- **3D models** (`game/models/`) are produced by deterministic Python
  generators in `scripts/` (`gen_wolf_model.py`, `gen_bandit_model.py`,
  `gen_blacksmith_model.py`, `gen_slime_model.py`,
  `gen_thistle_boar_model.py`, `gen_training_dummy_model.py`).
- **Audio** (`game/audio/`) is synthesized by
  `scripts/gen_ambience_audio.py` and `scripts/gen_door_open_audio.py`
  (byte-reproducible, fixed seed).
- **Branding and site art** (`public/branding/`, `public/og-image.png`,
  favicons) derive from the in-repo logo pack via
  `scripts/gen_site_branding.py` and `scripts/gen_icons.py`.
- **Screenshots** (`art/screenshots/`) are captured from the game itself.

The **Synmergia name and logo** are covered by [TRADEMARK.md](./TRADEMARK.md)
— the MIT license covers the code and assets, not the brand.

## Attribution requests

If you believe your work is used here without proper credit or a
compatible license, please open an issue or report it privately per
[SECURITY.md](./SECURITY.md); we will fix it promptly.
