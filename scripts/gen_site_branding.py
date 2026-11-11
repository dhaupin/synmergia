#!/usr/bin/env python3
"""Generate the site's brand-derived assets from the game's logo pack.

The shipped logos live in game/assets/branding/ (the same 4-up pack the
engine uses via res://core/utils/branding.gd). The website needs the
derivative shapes a browser/OG consumer wants -- a favicon, an
apple-touch-icon, and a social card -- which are NOT the raw game art.
This script mints them deterministically so they stay in lockstep with
the pack (re-run after the logos change; the math is idempotent).

Inputs (copied to public/branding/ by the build, or read from the game
tree directly):
  game/assets/branding/logo-synmergia-emblem.png        (the large star)
  game/assets/branding/logo-synmergia-wordmark.png      (the wordmark)

Outputs (public/):
  favicon.ico              multi-size 16/32/48 (browsers, tabs)
  favicon-32.png           crisp tab icon for modern browsers
  apple-touch-icon.png     180x180 on the nocturne paper (iOS home screen)
  og-image.png             1200x630 social card (the site's --paper field)

No third-party deps beyond Pillow; no network. Re-runs overwrite.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "game" / "assets" / "branding"
PUBLIC = ROOT / "public"

EMBLEM = BRANDING / "logo-synmergia-emblem.png"
WORDMARK = BRANDING / "logo-synmergia-wordmark.png"

# The site's Nocturne tokens (src/index.css :root) -- the card must sit
# on the same field the site uses so it reads as one brand.
PAPER = (11, 14, 20)
SURFACE = (17, 21, 31)
INK = (230, 226, 216)
INK_SOFT = (154, 163, 178)
ACCENT = (232, 182, 76)
LINE = (35, 42, 58)

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def _font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def _fit(img: Image.Image, max_w: int, max_h: int) -> Image.Image:
    """Scale to fit inside max_w x max_h, preserving aspect."""
    ratio = min(max_w / img.width, max_h / img.height)
    return img.resize((max(1, round(img.width * ratio)), max(1, round(img.height * ratio))), Image.LANCZOS)


def _emblem_square(size: int) -> Image.Image:
    """The emblem centered on a transparent square of the given size."""
    emblem = Image.open(EMBLEM).convert("RGBA")
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    scaled = _fit(emblem, round(size * 0.86), round(size * 0.86))
    canvas.paste(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2), scaled)
    return canvas


def make_favicon() -> None:
    sizes = [16, 32, 48]
    frames = [_emblem_square(s) for s in sizes]
    frames[0].save(
        PUBLIC / "favicon.ico",
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=frames[1:],
    )
    _emblem_square(32).save(PUBLIC / "favicon-32.png", format="PNG")
    print(f"[branding] favicon.ico ({'/'.join(str(s) for s in sizes)}) + favicon-32.png")


def make_touch_icon() -> None:
    size = 180
    canvas = Image.new("RGBA", (size, size), PAPER + (255,))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=0, fill=PAPER)
    emblem = _fit(Image.open(EMBLEM).convert("RGBA"), round(size * 0.78), round(size * 0.78))
    canvas.paste(emblem, ((size - emblem.width) // 2, (size - emblem.height) // 2), emblem)
    canvas.convert("RGB").save(PUBLIC / "apple-touch-icon.png", format="PNG")
    print("[branding] apple-touch-icon.png (180x180)")


def make_og_image() -> None:
    W, H = 1200, 630
    canvas = Image.new("RGB", (W, H), PAPER)
    draw = ImageDraw.Draw(canvas)

    # A subtle accent glow top-center (mirrors the hero's radial wash).
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(60):
        r = 320 - i * 4
        if r <= 0:
            break
        alpha = max(0, 26 - i)
        gd.ellipse([W // 2 - r, -r // 2, W // 2 + r, r + r // 2], fill=ACCENT + (alpha,))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), glow).convert("RGB")
    draw = ImageDraw.Draw(canvas)

    # Hairline frame + baseline rules in the token line color.
    draw.rectangle([24, 24, W - 24, H - 24], outline=LINE, width=2)

    # The lockup: emblem beside the wordmark, centered as one unit.
    emblem = _fit(Image.open(EMBLEM).convert("RGBA"), 190, 190)
    wordmark = _fit(Image.open(WORDMARK).convert("RGBA"), 520, 120)
    gap = 34
    unit_w = emblem.width + gap + wordmark.width
    x = (W - unit_w) // 2
    y = 175
    canvas.paste(emblem, (x, y + (140 - emblem.height) // 2), emblem)
    canvas.paste(wordmark, (x + emblem.width + gap, y + (140 - wordmark.height) // 2), wordmark)

    # Tagline + supporting line, in the site's voice.
    tagline = "A free and open source spherical-world MMORPG"
    sub = "Plays in your browser - no download, no launcher"
    tf = _font(38)
    sf = _font(26)
    for text, font, color, yy in (
        (tagline, tf, INK, 372),
        (sub, sf, INK_SOFT, 432),
    ):
        tw = draw.textlength(text, font=font)
        draw.text(((W - tw) / 2, yy), text, font=font, fill=color)

    # Accent rule + site line at the foot.
    draw.line([(W // 2 - 60, 500), (W // 2 + 60, 500)], fill=ACCENT, width=3)
    foot = "synmergia.creadev.org"
    ff = _font(24)
    fw = draw.textlength(foot, font=ff)
    draw.text(((W - fw) / 2, 524), foot, font=ff, fill=ACCENT)

    canvas.save(PUBLIC / "og-image.png", format="PNG")
    print("[branding] og-image.png (1200x630)")


def main() -> None:
    PUBLIC.mkdir(exist_ok=True)
    for src in (EMBLEM, WORDMARK):
        if not src.exists():
            raise SystemExit(f"missing source logo: {src}")
    make_favicon()
    make_touch_icon()
    make_og_image()


if __name__ == "__main__":
    main()
