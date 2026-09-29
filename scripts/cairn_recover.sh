#!/bin/sh
# cairn_recover.sh - re-exist after a workspace wipe (the Freebuff crash case).
#
# From a fresh clone of synmergia:
#     sh ./scripts/cairn_recover.sh
#
# Steps: ensure a vant axolotl install -> restore the DR horcrux from
# horcrux/ (password rides the p_<password> filename convention) ->
# pin models/state.json to the cairn stack -> boot-check memory through
# the real resolver. Exit 0 = re-existence verified.
#
# See horcrux/README.md for the airgap drill and the known open friction
# (vant #96 getPublicPath not stack-aware, #97 restore merges the host
# stack -- both worked around below, no hacks needed otherwise).
set -eu

VANT_DIR="${1:-/home/daytona/vant}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
STONE="$REPO/horcrux/cairn-p_windtheclock2026.svg"

echo "[cairn] recovering into $VANT_DIR"

# 1. vant axolotl install (clone if missing, deps if missing)
if [ ! -d "$VANT_DIR" ]; then
    git clone https://github.com/dhaupin/vant.git -b axolotl "$VANT_DIR"
fi
cd "$VANT_DIR"
[ -d node_modules ] || npm ci --no-audit --no-fund

# 2. Restore the DR stone. The p_ filename carries the password; a
#    renamed stone would need it as the second positional arg.
node bin/horcrux.js inspect "$STONE"
node bin/horcrux.js restore "$STONE"

# 3. Pin the stack (vant #97: restore union-merges the host's stale
#    stack and leaves activeBrain unset).
node -e '
const fs = require("fs");
let s = {};
try { s = JSON.parse(fs.readFileSync("models/state.json", "utf8")); } catch (e) {}
s.stack = ["cairn"];
s.activeBrain = "cairn";
fs.writeFileSync("models/state.json", JSON.stringify(s, null, 2) + "\n");
console.log("[cairn] stack pinned: [\"cairn\"]");
'

# 4. Boot check through the real memory API. Private memory goes
#    through the resolver explicitly (private-first works); public
#    memory is read from disk because getPublicPath() is not
#    stack-aware yet (vant #96 -- use fs until that lands).
node -e '
(async () => {
  const fs = require("fs");
  const brain = require("./lib/brain");
  const rt = await brain.read("roundtrip", { type: "private", brain: "cairn" });
  const raw = rt && rt.data && rt.data.raw ? rt.data.raw : String(rt || "");
  const okPriv = raw.includes("roundtrip marker");
  let okPub = false;
  try { okPub = fs.readFileSync("models/public/cairn/identity.md", "utf8").length > 0; } catch (e) {}
  console.log("[cairn] private roundtrip marker:", okPriv ? "OK" : "MISSING");
  console.log("[cairn] public identity:", okPub ? "OK" : "MISSING");
  process.exit(okPriv && okPub ? 0 : 1);
})();
'

echo "[cairn] re-existence verified. Welcome back, Cairn."
