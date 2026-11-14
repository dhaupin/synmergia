#!/usr/bin/env python3
"""Fail on broken relative links in tracked Markdown files.

External URLs, anchors and root-relative site paths are out of scope; this
gate is deliberately local so it can run on every PR without network access.

Usage:
    python3 scripts/check_docs_links.py [path ...]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
CODE_SPAN_RE = re.compile(r"`[^`]*`")


def tracked_markdown() -> list[Path]:
    out = subprocess.check_output(["git", "ls-files", "*.md"], text=True)
    return [Path(line) for line in out.splitlines() if line]


def strip_code(text: str) -> str:
    kept: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if FENCE_RE.match(line):
            in_fence = not in_fence
            kept.append("")
            continue
        if in_fence:
            kept.append("")
            continue
        kept.append(CODE_SPAN_RE.sub("", line))
    return "\n".join(kept)


def link_target(raw: str) -> str:
    target = raw.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    # Markdown titles: [x](path "title")
    target = target.split(" ", 1)[0]
    return target


def check_file(path: Path) -> list[str]:
    failures: list[str] = []
    text = strip_code(path.read_text(encoding="utf-8", errors="replace"))
    for match in LINK_RE.finditer(text):
        target = link_target(match.group(1))
        if not target or target.startswith("#"):
            continue
        parsed = urlsplit(target)
        if parsed.scheme or parsed.netloc or target.startswith("/"):
            continue
        rel = unquote(parsed.path)
        if not rel:
            continue
        resolved = (path.parent / rel).resolve()
        if not resolved.exists():
            failures.append(f"{path}: {target}")
    return failures


def main() -> int:
    paths = [Path(p) for p in sys.argv[1:]] or tracked_markdown()
    failures: list[str] = []
    for path in sorted(set(paths)):
        if path.suffix.lower() != ".md" or not path.is_file():
            continue
        failures.extend(check_file(path))
    if failures:
        print("Broken relative Markdown links:")
        for failure in failures:
            print("  " + failure)
        return 1
    print(f"Markdown links OK ({len(paths)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
