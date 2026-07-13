#!/usr/bin/env python3
"""Gaurava Retro Rubberhose deck generator (skill scaffold).

Emits self-contained 1320x2868 slide HTML; render each with headless Chrome at
--force-device-scale-factor=1 --window-size=1320,2868.

CRITICAL DIFFERENCE FROM A NAIVE BUILD: the phone is the REAL iPhone frame
(assets/iphone-mockup.png, 1022x2082) overlaid on the screenshot via the
pre-measured PHONE_SCREEN inset — NEVER a hand-drawn rounded rectangle (that
reads as an Android phone, which is a hard fail for an iOS App Store listing).

This is a STARTING SCAFFOLD. Edit the palette, copy, SLIDES, and the ecosystem
surfaces to fit the brief. Put the app captures in ./captures and surface
captures in ./surfaces, then run `python3 build_retro.py`.
"""
import base64, os, html
from mascot import mascot_svg

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = os.path.join(HERE, "captures")
SURF = os.path.join(HERE, "surfaces")
FONTS = os.path.join(HERE, "fonts")
ASSETS = HERE  # iphone-mockup.png lives next to this script
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)

# ---- palette (Retro Rubberhose) -----------------------------------------
CREAM, BUTTER, OFFW = "#F4E6CC", "#FBEFD2", "#FAF3E3"
MUSTARD, MUSTDP = "#F2BB46", "#E5A52E"
PINK, SALMON = "#F3A6B7", "#F19A8E"
MINT, MINTDP = "#BFD9B6", "#9CC692"
INK, BROWN, DARK, CAPGRAY, CORAL = "#1A1A1A", "#5C3A1E", "#2A2118", "#6B5E4D", "#E45A4A"
BODY = {"mustard": MUSTARD, "peach": "#F2B07A", "pink": "#EE92A4", "mint": MINTDP}

# ---- real iPhone frame (pre-measured screen inset, from the base skill) ---
# iphone-mockup.png is 1022x2082. Screen overlay inset, as fractions of the frame:
PS = dict(L=52/1022, T=46/2082, W=918/1022, H=1990/2082, RX=126/918, RY=126/1990)
MOCK_RATIO = 2082/1022           # phone height / width
PW = 1028                         # phone width on canvas (~73% canvas height)
PH = round(PW * MOCK_RATIO)
GUTTER_PAD = 56


def b64(path):
    return base64.b64encode(open(path, "rb").read()).decode()


def font_face(name, file, weight=400):
    return (f"@font-face{{font-family:'{name}';font-weight:{weight};font-style:normal;"
            f"src:url(data:font/ttf;base64,{b64(os.path.join(FONTS,file))}) format('truetype');}}")


FONT_CSS = "\n".join([
    font_face("Lilita", "LilitaOne.ttf"),
    font_face("Fredoka", "Fredoka.ttf", "300 700"),
    font_face("Nunito", "Nunito.ttf", "200 900"),
])

# Headline display font per locale. Lilita One / Fredoka are LATIN-ONLY and cannot
# render Devanagari (hi) / Tamil (ta) / Telugu (te). Drop a script-capable chunky
# display TTF (Baloo super-family recommended) into assets/fonts/ with these names
# to enable a locale; otherwise it falls back to Lilita (correct for en; a visible
# .notdef flag for Indic, which is the cue to add the font). See reference/localization.md
HEADLINE_FONT_BY_LOCALE = {
    "en": ("Lilita", "LilitaOne.ttf"),
    "hi": ("Baloo2", "Baloo2.ttf"),               # Devanagari
    "ta": ("BalooThambi2", "BalooThambi2.ttf"),   # Tamil
    "te": ("BalooTammudu2", "BalooTammudu2.ttf"),  # Telugu
}


def headline_font(locale):
    name, file = HEADLINE_FONT_BY_LOCALE.get(locale, HEADLINE_FONT_BY_LOCALE["en"])
    path = os.path.join(FONTS, file)
    if os.path.exists(path):
        return name, font_face(name, file)
    return "Lilita", ""  # fallback (fine for en; add the TTF for hi/ta/te)

GRAIN = "data:image/svg+xml;base64," + base64.b64encode(
    ("<svg xmlns='http://www.w3.org/2000/svg' width='300' height='300'>"
     "<filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.65' numOctaves='2' stitchTiles='stitch'/>"
     "<feColorMatrix type='saturate' values='0'/></filter><rect width='300' height='300' filter='url(#n)'/></svg>"
     ).encode()).decode()

MOCK_B64 = b64(os.path.join(ASSETS, "iphone-mockup.png"))


def squiggle(color=CORAL):
    svg = (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 120 18' preserveAspectRatio='none'>"
           f"<path d='M3,11 q12,-9 24,0 t24,0 t24,0 t24,0 t18,0' fill='none' stroke='{color}' "
           f"stroke-width='5' stroke-linecap='round'/></svg>")
    return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()


def sparkle(x, y, s, color=INK, rot=0):
    return (f"<svg class='deco' style='left:{x}px;top:{y}px;width:{s}px;height:{s}px;transform:rotate({rot}deg)' "
            f"viewBox='0 0 24 24'><path d='M12 0 C13 8 16 11 24 12 C16 13 13 16 12 24 C11 16 8 13 0 12 C8 11 11 8 12 0 Z' fill='{color}'/></svg>")


def star4(x, y, s, color=INK, rot=0):
    return (f"<svg class='deco' style='left:{x}px;top:{y}px;width:{s}px;height:{s}px;transform:rotate({rot}deg)' "
            f"viewBox='0 0 24 24'><path d='M12 2 L14 10 L22 12 L14 14 L12 22 L10 14 L2 12 L10 10 Z' fill='none' stroke='{color}' stroke-width='2.4' stroke-linejoin='round'/></svg>")


def dot(x, y, s, color):
    return f"<div class='deco' style='left:{x}px;top:{y}px;width:{s}px;height:{s}px;border-radius:50%;background:{color}'></div>"


def img_b64(folder, name):
    return b64(os.path.join(folder, name))


# ---- iPhone (REAL FRAME) -------------------------------------------------
def phone(screenshot_b64, side="right", tilt=0, top=860, w=PW):
    h = round(w * MOCK_RATIO)
    left = (1320 - w - GUTTER_PAD) if side == "right" else GUTTER_PAD
    sx, sy = PS["L"] * 100, PS["T"] * 100
    sw, sh = PS["W"] * 100, PS["H"] * 100
    rx, ry = PS["RX"] * 100, PS["RY"] * 100
    return f"""
    <div class="phone" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px;transform:rotate({tilt}deg)">
      <img class="shot" src="data:image/png;base64,{screenshot_b64}"
           style="position:absolute;left:{sx:.3f}%;top:{sy:.3f}%;width:{sw:.3f}%;height:{sh:.3f}%;
                  border-radius:{rx:.2f}% / {ry:.2f}%;object-fit:cover;object-position:top center;"/>
      <img class="frame" src="data:image/png;base64,{MOCK_B64}"
           style="position:absolute;inset:0;width:100%;height:100%;"/>
    </div>"""


# ---- Apple Watch frame (simple rounded-square cushion) --------------------
def watch(screenshot_b64, w=300, left=0, top=0):
    h = round(w * 1.20)
    return f"""
    <div class="watch" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px">
      <div class="wband"></div>
      <div class="wbody"><img src="data:image/png;base64,{screenshot_b64}"/></div>
    </div>"""


def brand():
    return f"""<div class="brand"><span class="bmark">G</span><span class="bname">Gaurava</span></div>"""


def headline(lines, hl_word, align="left"):
    out = []
    for ln in lines:
        if hl_word and hl_word in ln:
            before, after = ln.split(hl_word, 1)
            ln = html.escape(before) + f"<span class='hl'>{html.escape(hl_word)}</span>" + html.escape(after)
        else:
            ln = html.escape(ln)
        out.append(f"<div>{ln}</div>")
    return f"<div class='headline {align}'>{''.join(out)}</div>"


# ---- ecosystem slide: surface stickers -----------------------------------
def surface_sticker(s_b64, label, x, y, w, tilt=0):
    return f"""
    <div class="surface" style="left:{x}px;top:{y}px;width:{w}px;transform:rotate({tilt}deg)">
      <img src="data:image/png;base64,{s_b64}"/>
      <div class="slabel">{html.escape(label)}</div>
    </div>"""


def build_ecosystem(cfg):
    """cfg['surfaces'] = list of (image_b64, label, x, y, w, tilt). Place a small
    phone + a few surface stickers (widget / lock screen / watch / live activity)."""
    decos = "".join(cfg.get("decos", []))
    stickers = "".join(surface_sticker(*s) for s in cfg["surfaces"])
    masc = mascot_block(cfg)
    return _doc(cfg, f"""
      <div class="deco-layer">{decos}</div>
      {brand()}
      {headline(cfg['lines'], cfg.get('hl'), cfg.get('align','center'))}
      {stickers}
      {masc}
    """)


def mascot_block(cfg):
    mc = cfg.get("mascot")
    if not mc:
        return ""
    svg = mascot_svg(BODY[mc["color"]], mc["w"], mc.get("pose", "wave"), mc.get("eye", "center"), uid=cfg["id"] + mc["color"])
    flip = "scaleX(-1)" if mc.get("flip") else ""
    return (f"<div class='mascot' style='left:{mc['x']}px;bottom:{mc['y']}px;z-index:{mc.get('z',4)};transform:{flip}'>{svg}</div>")


def build_phone_slide(cfg):
    decos = "".join(cfg.get("decos", []))
    sub = f"<div class='sub {cfg.get('align','left')}'>{html.escape(cfg['sub'])}</div>" if cfg.get("sub") else ""
    ph = phone(cfg["img"], cfg.get("side", "right"), cfg.get("tilt", 0), cfg.get("phone_top", 860))
    return _doc(cfg, f"""
      <div class="deco-layer">{decos}</div>
      {brand()}
      {headline(cfg['lines'], cfg.get('hl'), cfg.get('align','left'))}
      {sub}
      {mascot_block(cfg)}
      {ph}
    """)


def _doc(cfg, inner):
    bg = cfg["bg"]
    loc = cfg.get("locale", "en")
    hf_name, hf_face = headline_font(loc)            # script-capable headline font
    sub_font = "Fredoka" if loc == "en" else hf_name  # Indic sub-lines need the script font too
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
{FONT_CSS}
{hf_face}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:1320px;height:2868px}}
.slide{{position:relative;width:1320px;height:2868px;overflow:hidden;background:{bg};font-family:'Fredoka',sans-serif}}
.grain{{position:absolute;inset:0;background-image:url({GRAIN});background-size:600px;opacity:.09;mix-blend-mode:multiply;pointer-events:none;z-index:30}}
.brand{{position:absolute;top:70px;left:0;right:0;display:flex;gap:18px;align-items:center;justify-content:center;z-index:20}}
.bmark{{width:62px;height:62px;border-radius:18px;background:{MUSTARD};border:4px solid {INK};color:{BROWN};font-family:'Lilita';font-size:40px;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 0 {INK};line-height:1}}
.bname{{font-family:'Lilita';font-size:46px;color:{BROWN};letter-spacing:.5px;text-shadow:1px 1px 0 {BUTTER}}}
.headline{{position:absolute;top:196px;left:84px;right:84px;font-family:'{hf_name}';font-size:128px;line-height:1.02;color:{DARK};letter-spacing:-1.5px;z-index:18}}
.headline.center{{text-align:center}} .headline.left{{text-align:left}}
.hl{{color:{CORAL};background:url({squiggle()}) center bottom/100% 20px no-repeat;padding-bottom:26px;-webkit-box-decoration-break:clone}}
.sub{{position:absolute;left:90px;right:90px;top:560px;font-family:'{sub_font}';font-weight:500;font-size:46px;line-height:1.28;color:{CAPGRAY};z-index:18}}
.sub.center{{text-align:center}}
.phone{{position:absolute;z-index:6}}
.phone .shot,.phone .frame{{display:block}}
.mascot{{position:absolute;line-height:0}}
.deco{{position:absolute;z-index:9}}
.surface{{position:absolute;z-index:8}}
.surface img{{display:block;width:100%;border:3px solid {INK};border-radius:34px;box-shadow:0 4px 0 {INK};background:#000}}
.slabel{{font-family:'Fredoka';font-weight:600;font-size:32px;color:{DARK};text-align:center;margin-top:14px}}
.watch{{position:absolute;z-index:8}}
.watch .wbody{{position:absolute;inset:0;background:#0a0a0a;border-radius:30%;border:3px solid {INK};box-shadow:0 5px 0 {INK};overflow:hidden}}
.watch .wbody img{{width:100%;height:100%;object-fit:cover}}
</style></head><body><div class="slide">{inner}<div class="grain"></div></div></body></html>"""


def build_slide(cfg):
    if cfg.get("kind") == "ecosystem":
        return build_ecosystem(cfg)
    return build_phone_slide(cfg)


# ---- gutter mascot helpers ----------------------------------------------
def masc_left(color, w=486):
    return dict(color=color, w=w, x=-30, y=22, z=4, pose="wave", flip=True)

def masc_right(color, w=486):
    return dict(color=color, w=w, x=1320 - w + 30, y=22, z=4, pose="wave", flip=False)


# =========================================================================
# EXAMPLE DECK — edit copy / colours / order, and wire your real captures.
# Narrative arc: Hero -> Differentiator -> Ecosystem -> Core features -> Trust.
# =========================================================================
def load_captures(locale="en"):
    """Map slide -> captured PNG. Looks in ./captures/<locale>/ then ./captures/.
    Capture per-locale app screenshots with the -AppleLanguages/-AppleLocale launch
    args (see reference/localization.md)."""
    want = {"summary": "01-summary-journey.png", "results": "03-results-overview.png",
            "jabs": "02-jabs-timeline.png", "log": "04-log-capture.png", "care": "05-care.png"}
    folders = [os.path.join(CAP, locale), CAP]
    out = {}
    for k, v in want.items():
        for folder in folders:
            if os.path.exists(os.path.join(folder, v)):
                out[k] = img_b64(folder, v)
                break
    return out


def example_deck(IMG):
    return [
        dict(id="s1", bg=CREAM, side="right", lines=["Every week,", "a little lighter."], hl="lighter",
             align="left", img=IMG["summary"], tilt=-1.5, mascot=masc_left("mustard", 520),
             decos=[sparkle(150, 470, 46, CORAL, 10), star4(1180, 360, 60, INK, 8), sparkle(1150, 690, 38, MUSTDP, -8)]),
        dict(id="s2", bg=MUSTARD, side="left", lines=["Your trend,", "in living color."], hl="color",
             align="left", img=IMG["results"], tilt=1.5, mascot=masc_right("peach"),
             decos=[dot(1150, 470, 40, OFFW), star4(140, 470, 54, BROWN, 0), sparkle(90, 1180, 40, BROWN, -10)]),
        # ECOSYSTEM slide — REQUIRED. Wire ./surfaces captures (see reference doc).
        dict(id="s3", kind="ecosystem", bg=PINK, lines=["On every", "screen you own."], hl="every",
             align="center", mascot=masc_left("mint", 430),
             surfaces=[
                 # (image_b64, label, x, y, width, tilt) — fill from ./surfaces
                 # (img_b64(SURF,'home-widget.png'),'Home Screen', 150, 760, 470, -3),
                 # (img_b64(SURF,'lockscreen.png'),'Lock Screen', 700, 980, 470, 3),
                 # (img_b64(SURF,'live-activity.png'),'Live Activity', 320, 1640, 640, -2),
             ],
             decos=[dot(130, 430, 64, BUTTER), sparkle(1150, 360, 58, CORAL, 10)]),
        dict(id="s4", bg=MINT, side="left", lines=["How you feel,", "in one tap."], hl="tap",
             align="left", img=IMG["log"], tilt=1.5, mascot=masc_right("pink"),
             decos=[star4(150, 430, 56, INK, 6), sparkle(1170, 380, 56, CORAL, -8)]),
        dict(id="s5", bg=CREAM, side="right", lines=["Yours.", "Only yours."], hl="yours",
             align="left", img=IMG["care"], tilt=0, phone_top=900,
             sub="Stored on your device. Synced only through your own iCloud.",
             mascot=masc_left("mustard", 520),
             decos=[star4(1180, 360, 60, INK, 8), sparkle(150, 470, 46, CORAL, 10)]),
    ]


def main():
    IMG = load_captures()
    if not IMG:
        print("No captures found in ./captures — see reference/seeding-and-capture.md")
        return
    for i, cfg in enumerate(example_deck(IMG), 1):
        loc = cfg.get("locale", "en")
        outdir = OUT if loc == "en" else os.path.join(OUT, loc)
        os.makedirs(outdir, exist_ok=True)
        p = os.path.join(outdir, f"slide-{i:02d}-{cfg['id']}.html")
        open(p, "w").write(build_slide(cfg))
        print("wrote", os.path.relpath(p, HERE))


if __name__ == "__main__":
    main()
