#!/usr/bin/env python3
"""Build Gaurava's Liquid Glass `AppIcon.icon` from the approved flat SVG.

The approved mark (output/imagegen/gaurava-logo-mark-flat-v2.svg) has two clean
vector paths with exact brand colours:
  - teal "G" stroke  (#176D5D)
  - terracotta crescent fill (#925030)

We render each path to its own transparent 1024x1024 PNG (perfect registration,
no baked background/shadow) and author an icon.json that lets Icon Composer /
the system own the Liquid Glass material, the sage->cream background, and the
Dark / Tinted variants.

Usage:
    python3 scripts/build_app_icon.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
# Committed canonical design source (the approved flat mark).
SRC_SVG = REPO / "docs" / "assets" / "app-icon" / "gaurava-logo-mark-flat-v2.svg"
OUT_DIR = REPO / "output" / "imagegen"
ICON_DIR = OUT_DIR / "AppIcon.icon"
ASSETS_DIR = ICON_DIR / "Assets"
SIZE = 1024

TEAL = (0x17, 0x6D, 0x5D)
TERRA = (0x92, 0x50, 0x30)


def _f(hexval: int) -> str:
    return f"{hexval/255:.5f}"


def extract_layers(svg_text: str) -> tuple[str, str, str]:
    """Return (open_svg_tag, g_open_tag, [teal_path, terra_path])."""
    svg_open = re.search(r"<svg\b[^>]*>", svg_text).group(0)
    g_open = re.search(r"<g\b[^>]*>", svg_text).group(0)
    paths = re.findall(r"<path\b.*?/>", svg_text, flags=re.DOTALL)
    if len(paths) != 2:
        raise SystemExit(f"expected 2 paths, found {len(paths)}")
    teal = next(p for p in paths if "176D5D" in p or "176d5d" in p)
    terra = next(p for p in paths if "925030" in p)
    return svg_open, g_open, [teal, terra]


def render_layer(svg_open: str, g_open: str, path: str, out: Path) -> None:
    doc = f'{svg_open}\n{g_open}\n{path}\n</g>\n</svg>'
    cairosvg.svg2png(
        bytestring=doc.encode("utf-8"),
        write_to=str(out),
        output_width=SIZE,
        output_height=SIZE,
        background_color="rgba(0,0,0,0)",
    )


def build_icon_json() -> dict:
    grad_orientation = {"start": {"x": 0.10, "y": 0.05}, "stop": {"x": 0.90, "y": 0.95}}
    return {
        # Calm sage -> warm cream diagonal, so the mark has presence on the home screen.
        "fill": {
            "linear-gradient": [
                "extended-srgb:0.74902,0.87843,0.79608,1.00000",  # soft sage #BFE0CB
                "extended-srgb:0.98431,0.96471,0.91765,1.00000",  # warm cream #FBF6EA
            ],
            "orientation": grad_orientation,
        },
        "fill-specializations": [
            {
                "appearance": "dark",
                "value": {
                    "linear-gradient": [
                        "extended-srgb:0.06667,0.06667,0.05882,1.00000",  # ink #11110F
                        "extended-srgb:0.10196,0.12549,0.10980,1.00000",  # green-ink #1A201C
                    ],
                    "orientation": grad_orientation,
                },
            },
            {"appearance": "tinted", "value": "automatic"},
        ],
        # Back -> front: teal G first, terracotta crescent on top (matches source SVG).
        # Keep layers mostly OPAQUE (low translucency) so the deep teal stays rich and
        # confident; rely on specular + shadow for the Liquid Glass depth/sheen rather
        # than translucency (high translucency washes the mark out over a light bg).
        "groups": [
            {
                "name": "Teal G",
                "layers": [{"image-name": "teal-g.png", "name": "Teal G"}],
                "lighting": "individual",
                "specular": True,
                "shadow": {"kind": "neutral", "opacity": 0.35},
                "translucency": {"enabled": True, "value": 0.10},
            },
            {
                "name": "Terracotta accent",
                "layers": [{"image-name": "terracotta.png", "name": "Terracotta accent"}],
                "lighting": "individual",
                "specular": True,
                "shadow": {"kind": "neutral", "opacity": 0.30},
                "translucency": {"enabled": True, "value": 0.10},
            },
        ],
        "supported-platforms": {"squares": "shared", "circles": ["watchOS"]},
    }


def squircle_preview(teal_png: Path, terra_png: Path, out: Path) -> None:
    """Flat composite (no glass) over the sage gradient, masked to an iOS squircle.

    This is a rough 'what it'll look like' preview; the system adds Liquid Glass.
    """
    bg = Image.new("RGB", (SIZE, SIZE))
    top = (0xBF, 0xE0, 0xCB)
    bot = (0xFB, 0xF6, 0xEA)
    px = bg.load()
    for y in range(SIZE):
        for x in range(SIZE):
            t = (x + y) / (2 * SIZE)
            px[x, y] = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    bg = bg.convert("RGBA")
    for layer in (teal_png, terra_png):
        img = Image.open(layer).convert("RGBA")
        bg.alpha_composite(img)
    # iOS squircle-ish rounded rect
    radius = int(SIZE * 0.2237)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=radius, fill=255)
    bg.putalpha(mask)
    bg.save(out)


def main() -> None:
    svg_text = SRC_SVG.read_text()
    svg_open, g_open, (teal_path, terra_path) = extract_layers(svg_text)
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)

    teal_png = ASSETS_DIR / "teal-g.png"
    terra_png = ASSETS_DIR / "terracotta.png"
    render_layer(svg_open, g_open, teal_path, teal_png)
    render_layer(svg_open, g_open, terra_path, terra_png)

    (ICON_DIR / "icon.json").write_text(json.dumps(build_icon_json(), indent=2) + "\n")

    preview = OUT_DIR / "appicon-flat-preview.png"
    squircle_preview(teal_png, terra_png, preview)

    print("layers:", teal_png, terra_png)
    print("icon.json:", ICON_DIR / "icon.json")
    print("preview:", preview)


if __name__ == "__main__":
    main()
