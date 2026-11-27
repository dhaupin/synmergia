# agent_play -- play the game the way a player does

An agent (or a screen reader, or a human) drives the running wasm build with
four verbs: **look**, **read**, **act**, **wait**. Labels are what a screen
reader announces, so the same command works for NVDA and for an agent with no
eyes -- there is one tree, not two.

This is the *outside-in* rig: it talks to the deployed build through the same
in-page wire (`window.SynmergiaAgent`) that `web_input_bridge.gd` exposes, so
whatever it can do, a screen reader on the same page can do.

## Setup

Playwright is already installed for the probe rig:

```sh
npm install --prefix scripts/web_probe        # once, if node_modules is absent
```

Nothing else. A session finds `/usr/bin/chromium` (or `$PROBE_CHROME`) itself.

## Play

```sh
node scripts/agent_play/play.mjs start          # boot the game (~15-60 s)
node scripts/agent_play/play.mjs look           # where am I
node scripts/agent_play/play.mjs act "Start playing"
node scripts/agent_play/play.mjs wait scene:Login
node scripts/agent_play/play.mjs read           # the screen-reader view
```

Every command auto-starts the session if it is not running, so the first
command is the only slow one. `play quit` stops it.

### Verbs

| command | what it does |
|---|---|
| `look` | scene, body (name/class/species/level/hp/position), target, first 24 actions |
| `read` | the a11y tree as a screen reader reads it: `role "label" - detail [state]` |
| `act "<label>"` | activate the action with that label (exact, then case-insensitive, then unique substring; ambiguity is refused, never guessed) |
| `act "<label>" --verb set_value --value X` | write a field (same verbs as the native door) |
| `act --id ui:Path/To/Button` | act on a stable handle when you already have one |
| `wait in_world` / `scene:Login` / `label:"Create New"` / `gone:"Play"` / `moving` / `still` | poll the observation until the predicate holds |
| `move forward\|back\|left\|right` then `halt` | hold a movement input, release it |
| `events [--since N]` | live-region announcements (what a screen reader speaks unprompted) |
| `shot [--out f.png]` | screenshot, for eyes and for `eyestruct` |
| `status` / `quit` | session info / stop |

Add `--json` to any command for the raw object.

### Targets

```sh
play start                                   # local web/ export (default)
play start --target live                     # https://synmergia.creadev.org
play start --target live --url http://127.0.0.1:8000
play start --headed                          # watch it play
```

The local target serves `web/` with the COOP/COEP headers the threaded build
needs, and appends `window.SynmergiaConfig.agent = true` to `config.js` for the
session only -- the deployed config stays fail-closed.

## A whole play-through, label-only

```sh
P="node scripts/agent_play/play.mjs"
$P act "Start playing"      && $P wait scene:Login
$P act "Create a new account"
$P act "Username input field" --verb set_value --value scout1
$P act "Password input field" --verb set_value --value hunter2hunter2
$P act "Email input field"    --verb set_value --value scout1@example.com
$P act "Create account and enter" && $P wait label:"Create New"
$P act "Create New"         && $P wait label:"Choose Akkan"
$P act "Choose Akkan"       && $P wait label:"Play Attacker"
$P act "Play Attacker"      && $P act "Enter World"
$P wait in_world
$P move forward && $P wait moving && $P halt
$P look
```

Note the pauses: the wasm build runs at a few fps under software GL, so a
scene swap can take tens of seconds. `wait` polls the state, so give it a
generous `--timeout` (default 60 s) rather than sleeping.

## Rules of the rig

- **Assert state, never a timed distance.** `wait moving` / `wait in_world`
  are state transitions; fps changes how far a body travels, not whether it
  moved. A probe that measures distance in a fixed wall-clock window is a
  flake waiting for a loaded CI runner.
- **Speak labels.** If a control has no label, that is an a11y bug in the game
  (see `@Button@5823` in the HUD), not a reason to hard-code a path.
- **One session, many commands.** The session is a daemon on 127.0.0.1:8137
  (state in `$TMPDIR/syn_agent_play.json`); it idles out after an hour.

## Files

- `session.mjs` -- the daemon: chromium + wasm + the JSON API + `read`/`wait`/label resolution.
- `play.mjs` -- the CLI; thin client, auto-starts the session.
