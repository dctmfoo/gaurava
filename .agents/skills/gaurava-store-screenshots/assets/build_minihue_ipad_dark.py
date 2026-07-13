#!/usr/bin/env python3
"""English dark-mode iPad App Store deck generator.

This keeps the MiniHue copy/type system from the light iPad deck, but sources
dark-mode app captures from captures-ipad-dark/en/ and adds pale staging/rims so
dark app UI, bezels, widgets, and share surfaces do not sink into dark backdrops.
"""
import base64
import html
import os

import build_minihue as phone

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = os.path.join(HERE, "captures-ipad-dark")
SURF = os.path.join(HERE, "surfaces")
OUT = os.path.join(HERE, "out-minihue-ipad-dark")

W, H = 2064, 2752
RAW_W, RAW_H = 2064, 2752
RAW_RATIO = RAW_H / RAW_W

BG = phone.BG
INK_DARK = phone.INK_DARK
INK_LIGHT = phone.INK_LIGHT
CORAL = phone.CORAL
GREEN = phone.GREEN
FACES = phone.FACES
SANS = phone.SANS
COPY = phone.COPY
WATCH_CSS = phone.WATCH_CSS
ICON_B64 = phone.ICON_B64

HEAD_PX = {"en": 164}

SLIDE_STYLE = [
    dict(bg="cream", dark=False, accent=CORAL),
    dict(bg="sage", dark=False, accent=GREEN),
    dict(bg="navy", dark=True, accent=CORAL),
    dict(bg="peach", dark=False, accent=CORAL),
    dict(bg="navy", dark=True, accent=CORAL),
    dict(bg="linen", dark=False, accent=CORAL),
]


def b64(path):
    return base64.b64encode(open(path, "rb").read()).decode()


def cap(loc, name):
    for folder in (os.path.join(CAP, loc), CAP):
        path = os.path.join(folder, name)
        if os.path.exists(path):
            return b64(path)
    return None


def surf(name, loc="en"):
    for folder in (os.path.join(SURF, loc), SURF):
        path = os.path.join(folder, name)
        if os.path.exists(path):
            return b64(path)
    return None


def wordmark(loc, ink, dark):
    ring = "rgba(245,239,223,.18)" if dark else "rgba(20,30,25,.10)"
    icon = (
        f"<img src='data:image/png;base64,{ICON_B64}' "
        f"style='width:76px;height:76px;border-radius:18px;display:block;"
        f"box-shadow:0 0 0 1px {ring},0 10px 22px rgba(20,30,25,.14)'/>"
    )
    return (
        f"<div class='wordmark'>{icon}"
        f"<div style=\"font-family:'{SANS[loc]}';font-weight:800;font-size:62px;"
        f"color:{ink};letter-spacing:0\">Gaurava</div></div>"
    )


def headline_block(loc, pre_lines, emph, ink, accent):
    pre = "".join(f"<div>{html.escape(p)}</div>" for p in pre_lines)
    return (
        f"<div class='headline' style=\"color:{ink};font-family:'{SANS[loc]}';"
        f"font-size:{HEAD_PX[loc]}px\">"
        f"{pre}<div class='emph' style='color:{accent}'>{html.escape(emph)}</div></div>"
    )


def doc(loc, bg, inner, extra_css=""):
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
{FACES}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}px;height:{H}px}}
.slide{{position:relative;width:{W}px;height:{H}px;overflow:hidden;background:{bg};
  font-family:'{SANS[loc]}',sans-serif}}
.wordmark{{position:absolute;left:150px;top:112px;display:flex;align-items:center;gap:24px;z-index:20}}
.copy{{position:absolute;left:150px;right:150px;top:252px;z-index:15}}
.headline{{font-weight:800;line-height:1.0;letter-spacing:0}}
.emph{{font-weight:800;line-height:1.0}}
.ipad{{position:absolute;z-index:7}}
.stage{{position:absolute;z-index:3;background:rgba(247,241,226,.92);
  box-shadow:0 0 0 2px rgba(255,255,255,.50),0 44px 92px rgba(7,11,20,.34)}}
{extra_css}
</style></head><body><div class="slide">{inner}</div></body></html>"""


def ipad_frame(
    shot_b64,
    width=1840,
    top=704,
    left=None,
    shadow="0 74px 110px rgba(20,15,10,.34)",
):
    if left is None:
        left = round((W - width) / 2)
    bezel = 30
    inner_w = width - bezel * 2
    inner_h = round(inner_w * RAW_RATIO)
    height = inner_h + bezel * 2
    img = (
        f"<img src='data:image/png;base64,{shot_b64}' "
        f"style='position:absolute;left:{bezel}px;top:{bezel}px;width:{inner_w}px;height:{inner_h}px;"
        f"border-radius:54px;object-fit:cover;object-position:top center'/>"
        if shot_b64
        else f"<div style='position:absolute;left:{bezel}px;top:{bezel}px;width:{inner_w}px;height:{inner_h}px;"
             "border-radius:54px;background:#10171f'></div>"
    )
    return f"""
    <div class="ipad" style="left:{left}px;top:{top}px;width:{width}px;height:{height}px;
      border-radius:76px;background:#0a0e14;box-shadow:0 0 0 8px rgba(247,241,226,.92),
      0 0 0 10px rgba(22,31,28,.14),{shadow};overflow:hidden">
      <div style="position:absolute;inset:12px;border-radius:66px;background:#242a34"></div>
      {img}
    </div>"""


def stage(x, y, w, h, radius=90, opacity=.92):
    return (
        f"<div class='stage' style='left:{x}px;top:{y}px;width:{w}px;height:{h}px;"
        f"border-radius:{radius}px;opacity:{opacity}'></div>"
    )


def surface_sticker(img_b64, x, y, w, radius=72, shadow="0 58px 92px rgba(8,10,20,.46)"):
    body = (
        f"<img src='data:image/png;base64,{img_b64}' style='display:block;width:100%;border-radius:{radius}px'/>"
        if img_b64
        else f"<div style='width:100%;aspect-ratio:2.1/1;border-radius:{radius}px;background:#e8e1d2'></div>"
    )
    return (
        f"<div style='position:absolute;left:{x}px;top:{y}px;width:{w}px;"
        f"filter:drop-shadow({shadow});z-index:7'>{body}</div>"
    )


def build_slide(loc, i, body, extra_css=""):
    style = SLIDE_STYLE[i]
    ink = INK_LIGHT if style["dark"] else INK_DARK
    pre, emph = COPY[loc][i]
    copy = f"<div class='copy'>{headline_block(loc, pre, emph, ink, style['accent'])}</div>"
    return doc(loc, BG[style["bg"]], f"{wordmark(loc, ink, style['dark'])}{copy}{body}", extra_css=extra_css)


def deck(loc):
    out = []
    out.append(build_slide(loc, 0, ipad_frame(cap(loc, "01-summary-journey.png"))))
    out.append(build_slide(loc, 1, ipad_frame(cap(loc, "03-results-overview.png"))))

    ecosystem = (
        stage(110, 772, 1844, 894, radius=104, opacity=.96)
        + surface_sticker(surf("home-widget-extra-large.png", loc), 154, 836, 1756, radius=80)
        + phone.ultra_watch(loc, left=1328, top=1718, s=1.46)
    )
    out.append(build_slide(loc, 2, ecosystem, extra_css=WATCH_CSS))

    out.append(build_slide(loc, 3, ipad_frame(cap(loc, "04-log-capture.png"))))
    out.append(build_slide(
        loc,
        4,
        ipad_frame(
            cap(loc, "06-share-composer.png"),
            width=1620,
            top=714,
            shadow="0 76px 116px rgba(4,7,16,.58)",
        ),
    ))
    out.append(build_slide(loc, 5, ipad_frame(cap(loc, "05b-care-privacy.png"))))
    return out


def main():
    loc = "en"
    outdir = os.path.join(OUT, loc)
    os.makedirs(outdir, exist_ok=True)
    for index, htmlstr in enumerate(deck(loc), 1):
        with open(os.path.join(outdir, f"slide-{index:02d}.html"), "w") as handle:
            handle.write(htmlstr)
    print("wrote 6 slides -> out-minihue-ipad-dark/en/")


if __name__ == "__main__":
    main()
