#!/usr/bin/env bash
# Synmergia dev environment bootstrap.
#
# Rebuilds the toolchain a code-side dev loop needs, from the repo alone:
# the system libraries, Godot 4.7.2, Node 20 and bun (for the web client /
# probes), plus optional pieces for the web export, the 3D pipeline and the
# browser probes. Safe to re-run: every step checks first and skips what is
# already present.
#
# The Dockerfile is the source of truth for the apt package list and the
# Godot / Node version pins, so this script and the container image cannot
# drift apart. If you add a package or bump a version there, this script
# picks it up with no edit here.
#
# Usage:
#   sh ./scripts/setup-dev.sh                  # base toolchain
#   sh ./scripts/setup-dev.sh --with-templates # + Godot web export templates
#   sh ./scripts/setup-dev.sh --with-blender   # + Blender (3D pipeline)
#   sh ./scripts/setup-dev.sh --with-web-probe # + chromium for the web probes
#   sh ./scripts/setup-dev.sh --all            # everything above
#   sh ./scripts/setup-dev.sh --skip-apt       # binaries only, no apt
#   sh ./scripts/setup-dev.sh --dry-run        # print the plan, install nothing
#
# Options:
#   --with-templates   Godot export templates (~800 MB, needed by --export-pack)
#   --with-blender     Blender, for scripts/gen_*_model.py (the 3D pipeline)
#   --with-web-probe   chromium for scripts/web_probe (playwright-core)
#   --all              enable all three optional pieces
#   --skip-apt         do not touch the system package manager
#   --dry-run          resolve versions/packages and print the plan, then exit
#   --prefix DIR       where user-local binaries go (default: ~/.local)
#   -h, --help         show this help
#
# Needs sudo (or root) for the apt packages only; the engine, Node and bun
# install into the user prefix and need no elevation.

set -euo pipefail

# ── Bash re-exec ───────────────────────────────────────────────────────────
# Uses arrays and [[ ]], so re-exec under bash when invoked as `sh script`.
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

# ── Args ───────────────────────────────────────────────────────────────────
WITH_TEMPLATES=0
WITH_BLENDER=0
WITH_WEB_PROBE=0
SKIP_APT=0
DRY_RUN=0
PREFIX="${HOME}/.local"

usage() { awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0; }

while [ $# -gt 0 ]; do
    case "$1" in
        --with-templates) WITH_TEMPLATES=1 ;;
        --with-blender)   WITH_BLENDER=1 ;;
        --with-web-probe) WITH_WEB_PROBE=1 ;;
        --all)            WITH_TEMPLATES=1; WITH_BLENDER=1; WITH_WEB_PROBE=1 ;;
        --skip-apt)       SKIP_APT=1 ;;
        --dry-run)        DRY_RUN=1 ;;
        --prefix)         shift; PREFIX="${1:?--prefix needs a directory}" ;;
        -h|--help)        usage ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

# ── Paths ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKERFILE="${REPO_ROOT}/Dockerfile"
TOOLS_DIR="${PREFIX}/share/synmergia-tools"
BIN_DIR="${PREFIX}/bin"

log()  { echo "[setup] $*"; }
warn() { echo "[setup] WARN: $*" >&2; }
die()  { echo "[setup] ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# sudo only when not already root and sudo exists
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif have sudo; then
    SUDO="sudo"
else
    SUDO=""
fi

[ -f "$DOCKERFILE" ] || die "Dockerfile not found at ${DOCKERFILE} (run from the repo)"

# ── Versions + package list, parsed from the Dockerfile ────────────────────
# Single source of truth: the image and this script read the same pins.
GODOT_VERSION="$(grep -oE 'GODOT_VERSION=[0-9.]+' "$DOCKERFILE" | head -1 | cut -d= -f2)"
NODE_VERSION="$(grep -oE 'NODE_VERSION=[0-9]+' "$DOCKERFILE" | head -1 | cut -d= -f2)"
[ -n "$GODOT_VERSION" ] || die "could not read GODOT_VERSION from Dockerfile"
[ -n "$NODE_VERSION" ]  || die "could not read NODE_VERSION from Dockerfile"
TEMPLATES_DIR="${GODOT_VERSION}.stable"

# Node patch release: newest v<NODE_VERSION>.x from the dist index, so the
# pin in the Dockerfile (major) is honoured without hardcoding a patch here.
NODE_PATCH="$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null \
    | grep -oE '"version":"v'"${NODE_VERSION}"'\.[0-9]+\.[0-9]+"' \
    | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
[ -n "$NODE_PATCH" ] || NODE_PATCH="${NODE_VERSION}.0.0"

BLENDER_VERSION="4.3.2"

# The apt package list is the apt-get install block in the Dockerfile:
# strip comments, line continuations and the trailing cleanup, then split.
mapfile -t APT_PACKAGES < <(
    awk '/apt-get install -y --no-install-recommends \\/{f=1} f{print} f&&/rm -rf \/var\/lib\/apt\/lists/{exit}' "$DOCKERFILE" \
        | sed 's/#.*$//' \
        | sed 's/.*--no-install-recommends//' \
        | sed 's/&&.*//' \
        | tr -d '\\' \
        | tr -s ' \t\n' '\n' \
        | grep -vE '^[[:space:]]*$'
)

# ── Arch ───────────────────────────────────────────────────────────────────
case "$(uname -m)" in
    x86_64|amd64)   GODOT_ARCH="x86_64";  NODE_ARCH="x64";   BLENDER_ARCH="x64" ;;
    aarch64|arm64)  GODOT_ARCH="arm64";   NODE_ARCH="arm64"; BLENDER_ARCH="arm64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac

log "repo:        ${REPO_ROOT}"
log "Godot:       ${GODOT_VERSION} (${GODOT_ARCH})"
log "Node:        ${NODE_PATCH}"
log "tools dir:   ${TOOLS_DIR}"
log "apt pkgs:    ${#APT_PACKAGES[@]} (from Dockerfile)"

mkdir -p "$TOOLS_DIR" "$BIN_DIR"

# ── Dry run: show the resolved plan and stop ───────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY RUN -- resolved plan (nothing will be installed)"
    log "  apt packages (${#APT_PACKAGES[@]}): ${APT_PACKAGES[*]}"
    log "  godot:  https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}.zip"
    log "  node:   https://nodejs.org/dist/v${NODE_PATCH}/node-v${NODE_PATCH}-linux-${NODE_ARCH}.tar.gz"
    log "  git-lfs: (not used -- stale LFS hooks are stripped, repo uses plain git)"
    log "  bun:    via npm (bun.lock convention)"
    [ "$WITH_TEMPLATES" -eq 1 ] && log "  templates: ${TEMPLATES_DIR} (~800 MB)"
    [ "$WITH_BLENDER" -eq 1 ]   && log "  blender: ${BLENDER_VERSION} (linux-${BLENDER_ARCH})"
    [ "$WITH_WEB_PROBE" -eq 1 ] && log "  web_probe: playwright-core + chromium"
    exit 0
fi

# ── 1. System packages (from the Dockerfile) ───────────────────────────────
install_apt() {
    if [ "$SKIP_APT" -eq 1 ]; then
        log "skipping apt (--skip-apt)"
        return 0
    fi
    have apt-get || { warn "apt-get not found; skipping system packages"; return 0; }
    log "installing ${#APT_PACKAGES[@]} system packages via apt..."
    $SUDO apt-get update -qq
    $SUDO env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y -qq --no-install-recommends "${APT_PACKAGES[@]}"
}

# ── 2. Godot engine ────────────────────────────────────────────────────────
install_godot() {
    if have godot; then
        log "godot already on PATH: $(godot --version 2>/dev/null | head -1)"
        return 0
    fi
    local url dest
    url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}.zip"
    dest="${TOOLS_DIR}/godot"
    mkdir -p "$dest"
    log "downloading Godot ${GODOT_VERSION}..."
    curl -fsSL "$url" -o "${dest}/godot.zip"
    unzip -q -o "${dest}/godot.zip" -d "$dest"
    mv "${dest}/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}" "${dest}/godot"
    chmod +x "${dest}/godot"
    rm -f "${dest}/godot.zip"
    ln -sfn "${dest}/godot" "${BIN_DIR}/godot"
    log "godot -> ${BIN_DIR}/godot"
}

# ── 3. Node.js (for the web client, sync:data, prerender) ──────────────────
install_node() {
    if have node; then
        log "node already on PATH: $(node --version)"
        return 0
    fi
    local url dest
    url="https://nodejs.org/dist/v${NODE_PATCH}/node-v${NODE_PATCH}-linux-${NODE_ARCH}.tar.gz"
    dest="${TOOLS_DIR}/node"
    mkdir -p "$dest"
    log "downloading Node ${NODE_PATCH}..."
    curl -fsSL "$url" -o "${dest}/node.tar.gz"
    tar -xzf "${dest}/node.tar.gz" -C "$dest" --strip-components=1
    rm -f "${dest}/node.tar.gz"
    ln -sfn "${dest}/bin/node" "${BIN_DIR}/node"
    ln -sfn "${dest}/bin/npm"  "${BIN_DIR}/npm"
    ln -sfn "${dest}/bin/npx"  "${BIN_DIR}/npx"
    log "node -> ${BIN_DIR}/node ($(node --version 2>/dev/null || echo pending))"
}

# ── 4. bun (repo uses bun.lock) ────────────────────────────────────────────
install_bun() {
    if have bun; then
        log "bun already on PATH: $(bun --version)"
        return 0
    fi
    if have npm; then
        log "installing bun via npm (into ${TOOLS_DIR}/bun)..."
        # Prefix it so bun lands under our tools dir (not npm's global root)
        # and symlink it onto PATH, matching the godot/node installs.
        if npm install -g --prefix "${TOOLS_DIR}/bun" bun >/dev/null 2>&1; then
            ln -sfn "${TOOLS_DIR}/bun/bin/bun"  "${BIN_DIR}/bun"
            ln -sfn "${TOOLS_DIR}/bun/bin/bunx" "${BIN_DIR}/bunx"
            log "bun -> ${BIN_DIR}/bun"
        else
            warn "npm install -g bun failed (install manually: https://bun.sh)"
        fi
    else
        warn "npm unavailable; skipping bun (install manually: https://bun.sh)"
    fi
}

# ── 4b. strip stale Git LFS hooks (this repo does NOT use LFS) ─────────────
# An early commit added a `.gitattributes` LFS pattern for the Godot engine
# binary, but that binary is gitignored under tools/ and was never committed,
# so no LFS object exists. `git lfs install` nonetheless writes hooks
# (pre-push / post-commit / post-checkout / post-merge) that abort EVERY git
# operation -- including `git worktree add`, which is how subagent lanes get
# their checkout -- when git-lfs is missing from PATH. Nothing here needs LFS,
# so remove any such hook rather than depending on git-lfs being present.
strip_lfs_hooks() {
    local hooks_dir hook
    hooks_dir="$(git -C "${REPO_ROOT}" rev-parse --git-path hooks 2>/dev/null)" || return 0
    [ -d "$hooks_dir" ] || return 0
    for hook in pre-push post-commit post-checkout post-merge; do
        # Only remove hooks git-lfs wrote -- never a hand-authored hook.
        if [ -f "${hooks_dir}/${hook}" ] && grep -q "git-lfs\|git lfs" "${hooks_dir}/${hook}" 2>/dev/null; then
            rm -f "${hooks_dir}/${hook}"
            log "removed stale LFS ${hook} hook (repo does not use LFS)"
        fi
    done
}

# ── 5. Godot export templates (web export) ─────────────────────────────────
install_templates() {
    [ "$WITH_TEMPLATES" -eq 1 ] || return 0
    local dest
    dest="${HOME}/.local/share/godot/export_templates/${TEMPLATES_DIR}"
    if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
        log "export templates already present: ${dest}"
        return 0
    fi
    log "downloading Godot export templates (~800 MB)..."
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
        -o "${tmp}/templates.tpz"
    unzip -q "${tmp}/templates.tpz" -d "$tmp"
    mkdir -p "$dest"
    # The tpz nests a templates/ dir; flatten into the version dir.
    if [ -d "${tmp}/templates" ]; then
        mv "${tmp}/templates/"* "$dest/"
    else
        mv "${tmp}/"* "$dest/" 2>/dev/null || true
    fi
    rm -rf "$tmp"
    log "templates -> ${dest}"
}

# ── 6. Blender (3D pipeline: scripts/gen_*_model.py) ───────────────────────
install_blender() {
    [ "$WITH_BLENDER" -eq 1 ] || return 0
    if have blender; then
        log "blender already on PATH: $(blender --version 2>/dev/null | head -1)"
        return 0
    fi
    local url dest
    url="https://download.blender.org/release/Blender${BLENDER_VERSION%.*}/blender-${BLENDER_VERSION}-linux-${BLENDER_ARCH}.tar.xz"
    dest="${TOOLS_DIR}/blender"
    log "downloading Blender ${BLENDER_VERSION}..."
    mkdir -p "$dest"
    curl -fsSL "$url" -o "${dest}/blender.tar.xz"
    tar -xJf "${dest}/blender.tar.xz" -C "$dest" --strip-components=1
    rm -f "${dest}/blender.tar.xz"
    ln -sfn "${dest}/blender" "${BIN_DIR}/blender"
    log "blender -> ${BIN_DIR}/blender"
}

# ── 7. chromium for the web probes (playwright-core) ───────────────────────
install_web_probe() {
    [ "$WITH_WEB_PROBE" -eq 1 ] || return 0
    local probe_dir="${REPO_ROOT}/scripts/web_probe"
    [ -d "$probe_dir" ] || { warn "no scripts/web_probe; skipping"; return 0; }
    log "installing web_probe deps + chromium..."
    ( cd "$probe_dir" && { have bun && bun install || npm install; } ) \
        || warn "web_probe dependency install failed"
    ( cd "$probe_dir" && npx --yes playwright install chromium ) \
        || warn "chromium install failed (set PROBE_CHROME to a browser path)"
}

# ── 8. PATH ────────────────────────────────────────────────────────────────
ensure_path() {
    local line="export PATH=\"${BIN_DIR}:\$PATH\""
    local rc
    for rc in "${HOME}/.bashrc" "${HOME}/.profile"; do
        [ -f "$rc" ] || continue
        if ! grep -qF "$BIN_DIR" "$rc" 2>/dev/null; then
            printf '\n# Synmergia dev tools\n%s\n' "$line" >> "$rc"
            log "added ${BIN_DIR} to ${rc}"
        fi
    done
    export PATH="${BIN_DIR}:${PATH}"
}

# ── Run ────────────────────────────────────────────────────────────────────
install_apt
install_godot
install_node
strip_lfs_hooks
ensure_path
install_bun
install_templates
install_blender
install_web_probe

# ── Summary ────────────────────────────────────────────────────────────────
echo
log "toolchain summary"
for tool in godot node npm bun blender; do
    if have "$tool"; then
        printf '  %-9s %s\n' "$tool:" "$("$tool" --version 2>&1 | head -1)"
    else
        printf '  %-9s (not installed)\n' "$tool:"
    fi
done
echo
log "next steps:"
log "  export PATH=\"${BIN_DIR}:\$PATH\"   # or open a new shell"
log "  bun install                            # repo deps"
log "  sh ./scripts/godot_test_runner.sh      # serial smoke tests"
log "  sh ./scripts/godot_test_parallel.sh    # parallel smoke tests"
