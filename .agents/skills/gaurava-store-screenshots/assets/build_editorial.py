#!/usr/bin/env python3
"""Gaurava "Hand-Drawn Editorial Tasks" deck generator (en/hi/ta/te).

Style contract:
  * One SOLID colour block per slide: navy / cream / coral / electric purple.
  * Headline in an EDITORIAL SANS (Inter / Noto Sans <script>), medium weight.
  * Exactly ONE emphasis phrase per slide in a BRUSH-PEN SCRIPT (Caveat / Kalam /
    Kavivanar / NTR), coral #F26A50 (cream on the coral slide), slight rotation,
    ~120% scale. Validated to render all four scripts with no tofu (build_poc.py).
  * A REAL iPhone, tilted 10-25deg, warm soft shadow (assets/iphone-mockup.png +
    measured screen inset) — never a hand-drawn bezel (reads as Android = hard fail).
  * Sparse hand-drawn coral squiggles / stars / curved arrows, placed in the
    MARGINS, never over the type. Lowercase corner wordmark. Slightly imperfect.

6-slide narrative (one idea each, surfaces chosen with the user):
  1 Hero (Summary)  2 Trend (Results)  3 Ecosystem (Home widget + Watch)
  4 Log  5 Share card  6 Privacy closer

Captures: ./captures/<locale>/<file>.png   Surfaces: ./surfaces/<file>.png
Renders 1320x2868 HTML into ./out/<locale>/ ; screenshot each with headless Chrome.
hi/ta/te marketing copy is a transcreation DRAFT — flagged native-review-pending.
"""
import base64, os, html

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = os.path.join(HERE, "captures")
SURF = os.path.join(HERE, "surfaces")
FONTS = os.path.join(HERE, "fonts")
OUT = os.path.join(HERE, "out")

# ---- palette ------------------------------------------------------------
NAVY, CREAM, CORAL_BG, PURPLE = "#1B2336", "#F5EFDF", "#E55846", "#8B7BFF"
CORAL = "#F26A50"          # emphasis + decoration ink
INK_NAVY = "#1B2336"
W, H = 1320, 2868

# ---- real iPhone frame (pre-measured inset, shared with build_retro) -----
PS = dict(L=52/1022, T=46/2082, W=918/1022, H=1990/2082, RX=126/918, RY=126/1990)
MOCK_RATIO = 2082/1022


def b64(path):
    return base64.b64encode(open(path, "rb").read()).decode()


def face(name, file, weight="100 900"):
    p = os.path.join(FONTS, file)
    if not os.path.exists(p):
        return ""
    return (f"@font-face{{font-family:'{name}';font-weight:{weight};font-style:normal;"
            f"src:url(data:font/ttf;base64,{b64(p)}) format('truetype');}}")


FACES = "\n".join([
    face("Inter", "Inter.ttf"),
    face("Caveat", "Caveat.ttf"),
    face("Kalam", "Kalam-Bold.ttf", "700"),
    face("Kavivanar", "Kavivanar.ttf", "400"),
    face("NTR", "NTR.ttf", "400"),
    face("NotoDeva", "NotoSansDevanagari.ttf"),
    face("NotoTamil", "NotoSansTamil.ttf"),
    face("NotoTelugu", "NotoSansTelugu.ttf"),
])

SANS = {"en": "Inter", "hi": "NotoDeva", "ta": "NotoTamil", "te": "NotoTelugu"}
SCRIPT = {"en": "Caveat", "hi": "Kalam", "ta": "Kavivanar", "te": "NTR"}

MOCK_B64 = b64(os.path.join(HERE, "iphone-mockup.png"))


# ---- hand-drawn decorations (coral, in the margins only) -----------------
def _svg_uri(svg):
    return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()


def squiggle(color):
    # A single confident hand-drawn marker underline (one gentle rise + dip, round
    # caps, slight end flick) — NOT a tight sine wave, which distorts into jagged
    # hash when stretched under a wide word. preserveAspectRatio=none lets it span
    # the emphasis width; the soft curve reads as hand-made even when stretched.
    return _svg_uri(
        f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 320 26' preserveAspectRatio='none'>"
        f"<path d='M10,17 C80,9 150,21 210,14 C258,9 296,12 312,9' fill='none' stroke='{color}' "
        f"stroke-width='7' stroke-linecap='round' stroke-linejoin='round'/></svg>")


def arrow(color):
    return _svg_uri(
        f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 90'>"
        f"<path d='M8,12 C46,2 84,26 86,64' fill='none' stroke='{color}' stroke-width='5' stroke-linecap='round'/>"
        f"<path d='M68,58 L88,68 L92,44' fill='none' stroke='{color}' stroke-width='5' "
        f"stroke-linecap='round' stroke-linejoin='round'/></svg>")


def star(color):
    return _svg_uri(
        f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'>"
        f"<path d='M12 1 C13 8 16 11 23 12 C16 13 13 16 12 23 C11 16 8 13 1 12 C8 11 11 8 12 1 Z' fill='{color}'/></svg>")


def deco_img(uri, x, y, w, rot=0, h=None):
    hs = f"height:{h}px;" if h else ""
    return (f"<img class='deco' style='left:{x}px;top:{y}px;width:{w}px;{hs}"
            f"transform:rotate({rot}deg)' src='{uri}'/>")


# ---- real iPhone, tilted, warm soft shadow -------------------------------
def phone(shot_b64, side="right", tilt=-15, top=980, w=920, bleed=120):
    h = round(w * MOCK_RATIO)
    left = (W - w + bleed) if side == "right" else (-bleed)
    sx, sy = PS["L"] * 100, PS["T"] * 100
    sw, sh = PS["W"] * 100, PS["H"] * 100
    rx, ry = PS["RX"] * 100, PS["RY"] * 100
    inner = (f"<img class='shot' src='data:image/png;base64,{shot_b64}' "
             f"style=\"position:absolute;left:{sx:.3f}%;top:{sy:.3f}%;width:{sw:.3f}%;height:{sh:.3f}%;"
             f"border-radius:{rx:.2f}% / {ry:.2f}%;object-fit:cover;object-position:top center;\"/>"
             if shot_b64 else
             "<div style='position:absolute;left:5.1%;top:2.2%;width:89.8%;height:95.6%;"
             "border-radius:13% / 6.3%;background:linear-gradient(180deg,#11151f,#222a3a);"
             "display:flex;align-items:center;justify-content:center;color:#8893ad;"
             "font-family:Inter;font-size:40px'>app screen</div>")
    # Frame first (its screen region is OPAQUE black), screenshot on TOP clipped
    # to the measured screen inset — otherwise the frame paints over the shot.
    # Dynamic Island: simulator screenshots DON'T contain the DI (it's a hardware
    # overlay, not in the framebuffer), so we draw the pill ON TOP of the shot,
    # centred in the status-bar band. Sits between the captured time + battery.
    di = ("<div class='di' style=\"position:absolute;left:37%;top:2.75%;width:26%;height:2.45%;"
          "background:#000;border-radius:999px;z-index:3;"
          "box-shadow:0 0 0 1px rgba(0,0,0,.6)\"></div>")
    return f"""
    <div class="phone" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px;transform:rotate({tilt}deg)">
      <img class="frame" src="data:image/png;base64,{MOCK_B64}" style="position:absolute;inset:0;width:100%;height:100%;"/>
      {inner}
      {di}
    </div>"""


# ---- ecosystem stickers (widget card + watch) ----------------------------
def card_sticker(img_b64, x, y, w, tilt, radius=64, label=None, ink=CREAM, label_font="Inter"):
    if img_b64:
        body = f"<img src='data:image/png;base64,{img_b64}' style='display:block;width:100%;border-radius:{radius}px'/>"
    else:
        body = (f"<div style='width:100%;aspect-ratio:1/1;border-radius:{radius}px;"
                f"background:linear-gradient(160deg,#11151f,#28324a);display:flex;align-items:center;"
                f"justify-content:center;color:#8893ad;font-family:Inter;font-size:34px'>widget</div>")
    lab = (f"<div style=\"font-family:'{label_font}';font-weight:600;font-size:34px;color:{ink};"
           f"opacity:.85;text-align:center;margin-top:18px\">{html.escape(label)}</div>" if label else "")
    return (f"<div class='sticker' style='position:absolute;left:{x}px;top:{y}px;width:{w}px;"
            f"transform:rotate({tilt}deg);filter:drop-shadow(0 40px 70px rgba(20,10,0,.40))'>{body}{lab}</div>")


def watch_sticker(img_b64, x, y, w, tilt, ink=CREAM, label=None, label_font="Inter"):
    h = round(w * 1.18)
    inner = (f"<img src='data:image/png;base64,{img_b64}' style='width:100%;height:100%;object-fit:cover'/>"
             if img_b64 else
             "<div style='width:100%;height:100%;display:flex;align-items:center;justify-content:center;"
             "color:#8893ad;font-family:Inter;font-size:26px'>watch</div>")
    lab = (f"<div style=\"font-family:'{label_font}';font-weight:600;font-size:34px;color:{ink};"
           f"opacity:.85;text-align:center;margin-top:18px\">{html.escape(label)}</div>" if label else "")
    return (f"<div class='wsticker' style='position:absolute;left:{x}px;top:{y}px;width:{w}px;"
            f"transform:rotate({tilt}deg);filter:drop-shadow(0 36px 60px rgba(20,10,0,.42))'>"
            f"<div style='width:{w}px;height:{h}px;background:#0a0a0a;border-radius:32%;"
            f"border:10px solid #07070a;overflow:hidden'>{inner}</div>{lab}</div>")


# ---- one slide -----------------------------------------------------------
# Indic scripts (Devanagari/Tamil/Telugu) set TALLER and WIDER than Latin, and the
# brush faces render large — so the editorial + emphasis sizes are tuned per locale
# to avoid runaway wrapping. Headline + sub flow in one top-anchored column (.copy)
# so a tall localized headline never collides with the sub-line.
HEAD_PX = {"en": 116, "hi": 92, "ta": 86, "te": 92}
EMPH_PX = {"en": 140, "hi": 120, "ta": 108, "te": 120}


def headline_block(loc, pre_lines, emph, hink, eink, emph_rot):
    sans = SANS[loc]
    script = SCRIPT[loc]
    pre = "".join(f"<div>{html.escape(p)}</div>" for p in pre_lines)
    # The squiggle is a hand-drawn UNDERLINE anchored to the emphasis phrase — it
    # scales with the text and stays aligned in every locale (no free-floating
    # decoration that points at nothing).
    underline = (f"background:url({squiggle(eink)}) left bottom/100% 0.30em no-repeat;"
                 f"padding-bottom:0.22em;-webkit-box-decoration-break:clone;box-decoration-break:clone;")
    return f"""<div class="headline" style="color:{hink};font-family:'{sans}';font-size:{HEAD_PX[loc]}px">
      {pre}<span class="emph" style="font-family:'{script}';color:{eink};
        font-size:{EMPH_PX[loc]}px;transform:rotate({emph_rot}deg);{underline}">{html.escape(emph)}</span>
    </div>"""


def doc(loc, bg, inner):
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
{FACES}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}px;height:{H}px}}
.slide{{position:relative;width:{W}px;height:{H}px;overflow:hidden;background:{bg};font-family:'{SANS[loc]}',sans-serif}}
.wordmark{{position:absolute;left:90px;bottom:84px;font-family:'{SANS[loc]}';font-weight:600;font-size:44px;opacity:.7;letter-spacing:.5px;z-index:20}}
.copy{{position:absolute;left:96px;right:104px;top:236px;z-index:15}}
.headline{{font-weight:500;line-height:1.06;letter-spacing:-1px}}
.emph{{display:inline-block;font-weight:700;line-height:1.04;transform-origin:left center;margin-top:22px;padding:0 6px}}
.sub{{margin-top:40px;font-weight:400;font-size:42px;line-height:1.36;opacity:.82;max-width:1010px}}
.phone{{position:absolute;z-index:6}}
.deco{{position:absolute;z-index:9}}
</style></head><body><div class="slide">{inner}</div></body></html>"""


def build_slide(loc, cfg):
    bg = cfg["bg"]
    hink = cfg["hink"]
    eink = cfg["eink"]
    wm_color = hink
    head = headline_block(loc, cfg["pre"], cfg["emph"], hink, eink, cfg.get("emph_rot", -3))
    sub = (f"<div class='sub' style='color:{hink}'>{html.escape(cfg['sub'])}</div>"
           if cfg.get("sub") else "")
    copy = f"<div class='copy'>{head}{sub}</div>"
    decos = "".join(cfg.get("decos", []))
    wm = f"<div class='wordmark' style='color:{wm_color}'>gaurava</div>"
    body = cfg["body"]  # phone / stickers html
    return doc(loc, bg, f"{copy}{decos}{body}{wm}")


# ---- captures / surfaces loading (graceful) ------------------------------
def cap(loc, name):
    for folder in (os.path.join(CAP, loc), CAP):
        p = os.path.join(folder, name)
        if os.path.exists(p):
            return b64(p)
    return None


def surf(name, loc="en"):
    """Per-locale surface render (surfaces/<locale>/) falling back to surfaces/."""
    for folder in (os.path.join(SURF, loc), SURF):
        p = os.path.join(folder, name)
        if os.path.exists(p):
            return b64(p)
    return None


# ---- copy (en + transcreation drafts; hi/ta/te native-review-pending) ----
# Each slide: pre lines (editorial sans) + ONE emphasis phrase (brush script).
COPY = {
    "en": [
        (["Track it with"],            "dignity."),
        (["Five months."],             "Real change."),
        (["On every"],                 "screen you own."),
        (["How you feel,"],            "in one tap."),
        (["Your progress,"],           "worth sharing."),
        (["Private"],                  "by design."),
    ],
    "hi": [
        (["अपने सफ़र को"],              "सम्मान के साथ।"),
        (["पाँच महीने।"],              "असली बदलाव।"),
        (["हर स्क्रीन पर,"],           "एक नज़र में।"),
        (["आपकी भावना,"],              "बस एक टैप में।"),
        (["आपकी प्रगति,"],             "गर्व के साथ।"),
        (["पूरी तरह निजी,"],           "सिर्फ़ आपकी।"),
    ],
    "ta": [
        (["உங்கள் பயணம்,"],            "கண்ணியத்துடன்."),
        (["ஐந்து மாதங்கள்."],          "உண்மையான மாற்றம்."),
        (["எல்லா திரையிலும்,"],        "ஒரே பார்வையில்."),
        (["உங்கள் உணர்வு,"],            "ஒரே தட்டலில்."),
        (["உங்கள் முன்னேற்றம்,"],       "பெருமையுடன்."),
        (["முழுமையாக தனிப்பட்டது,"],   "உங்களுக்கு மட்டுமே."),
    ],
    "te": [
        (["మీ ప్రయాణం,"],              "గౌరవంగా."),
        (["ఐదు నెలలు."],               "నిజమైన మార్పు."),
        (["ప్రతి స్క్రీన్‌పై,"],          "ఒక్క చూపులో."),
        (["మీ భావన,"],                 "ఒకే ట్యాప్‌తో."),
        (["మీ పురోగతి,"],              "గర్వంగా."),
        (["పూర్తిగా ప్రైవేట్,"],          "మీది మాత్రమే."),
    ],
}

# per-slide solid bg + ink + emphasis rotation (slightly imperfect)
SLIDE_STYLE = [
    dict(bg=NAVY,     hink=CREAM,     eink=CORAL, emph_rot=-3),   # 1 hero
    dict(bg=CREAM,    hink=INK_NAVY,  eink=CORAL, emph_rot=4),    # 2 trend
    dict(bg=PURPLE,   hink=CREAM,     eink=CORAL, emph_rot=-2),   # 3 ecosystem
    dict(bg=CORAL_BG, hink=CREAM,     eink=CREAM, emph_rot=5),    # 4 log (cream on coral)
    dict(bg=NAVY,     hink=CREAM,     eink=CORAL, emph_rot=-4),   # 5 share
    dict(bg=CREAM,    hink=INK_NAVY,  eink=CORAL, emph_rot=3),    # 6 privacy
]


# Localized ecosystem sticker captions ("Apple Watch" stays a brand name).
CAPTIONS = {
    "home":  {"en": "Home Screen",   "hi": "होम स्क्रीन",      "ta": "முகப்புத் திரை",  "te": "హోమ్ స్క్రీన్"},
    "quick": {"en": "Quick actions", "hi": "त्वरित क्रियाएँ",   "ta": "விரைவுச் செயல்கள்", "te": "త్వరిత చర్యలు"},
    "watch": {"en": "Apple Watch",   "hi": "Apple Watch",      "ta": "Apple Watch",     "te": "Apple Watch"},
}


def deck(loc):
    copy = COPY[loc]
    S = SLIDE_STYLE
    sans = SANS[loc]
    slides = []

    # 1 — Hero / Summary (phone right, tilt -14)
    s = dict(S[0]); pre, emph = copy[0]
    s.update(pre=pre, emph=emph,
             sub={"en": "Five months of weekly GLP-1 treatment — your weight, quietly, on your terms.",
                  "hi": "साप्ताहिक इलाज के पाँच महीने — सब कुछ आपके डिवाइस पर।",
                  "ta": "ஐந்து மாதங்கள் — உங்கள் முன்னேற்றம், உங்கள் சாதனத்தில்.",
                  "te": "ఐదు నెలలు — మీ పురోగతి, మీ పరికరంలో."}[loc],
             body=phone(cap(loc, "01-summary-journey.png"), side="right", tilt=-14, top=1010, w=900),
             decos=[deco_img(star(s["eink"]), 1184, 250, 54, 8)])
    slides.append(s)

    # 2 — Trend / Results chart (phone left, tilt 14)
    s = dict(S[1]); pre, emph = copy[1]
    s.update(pre=pre, emph=emph,
             sub={"en": "A clear, judgement-free summary of your change over time.",
                  "hi": "समय के साथ आपके बदलाव का स्पष्ट, आलोचना-मुक्त सारांश।",
                  "ta": "காலப்போக்கில் உங்கள் மாற்றத்தின் தெளிவான, விமர்சனமற்ற சுருக்கம்.",
                  "te": "కాలక్రమేణా మీ మార్పు యొక్క స్పష్టమైన, విమర్శలు లేని సారాంశం."}[loc],
             # The Results OVERVIEW screen shows the dose-coloured trend chart +
             # metric tiles (Total change / weekly avg / to-goal) — the chart, NOT
             # the weight-entry list (03b, which the test over-scrolled into).
             body=phone(cap(loc, "03-results-overview.png"), side="left", tilt=14, top=1010, w=900),
             decos=[deco_img(star(s["eink"]), 1184, 250, 54, -10)])
    slides.append(s)

    # 3 — Ecosystem: Home widget + Watch cluster (no phone)
    s = dict(S[2]); pre, emph = copy[2]
    s.update(pre=pre, emph=emph,
             sub={"en": "Widgets and Apple Watch — your next step, at a glance.",
                  "hi": "विजेट और Apple Watch — आपका अगला कदम, एक नज़र में।",
                  "ta": "விட்ஜெட்கள் & Apple Watch — அடுத்த படி, ஒரே பார்வையில்.",
                  "te": "విడ్జెట్‌లు & Apple Watch — మీ తదుపరి అడుగు, ఒక్క చూపులో."}[loc],
             body=(card_sticker(surf("home-widget.png", loc), 96, 1040, 760, -5,
                                label=CAPTIONS["home"][loc], ink=s["hink"], label_font=sans)
                   + card_sticker(surf("quick-actions.png", loc), 150, 1570, 720, 4,
                                  label=CAPTIONS["quick"][loc], ink=s["hink"], label_font=sans)
                   + watch_sticker(surf("watch.png", loc), 858, 2020, 400, 9,
                                   ink=s["hink"], label=CAPTIONS["watch"][loc], label_font=sans)),
             decos=[deco_img(star(s["eink"]), 1184, 250, 54, 10)])
    slides.append(s)

    # 4 — Log capture (phone right, tilt -16, cream on coral)
    s = dict(S[3]); pre, emph = copy[3]
    s.update(pre=pre, emph=emph,
             sub={"en": "Note how you feel and log a side effect — then let it go.",
                  "hi": "आप कैसा महसूस करते हैं नोट करें, दुष्प्रभाव दर्ज करें — फिर जाने दें।",
                  "ta": "எப்படி உணர்கிறீர்கள் என குறியுங்கள், பக்க விளைவைப் பதியுங்கள்.",
                  "te": "మీరు ఎలా ఉన్నారో గమనించండి, సైడ్ ఎఫెక్ట్ నమోదు చేయండి."}[loc],
             body=phone(cap(loc, "04-log-capture.png"), side="right", tilt=-16, top=1010, w=900),
             decos=[deco_img(star(s["eink"]), 1184, 250, 54, -8)])
    slides.append(s)

    # 5 — Share card (tilted card sticker, navy)
    s = dict(S[4]); pre, emph = copy[4]
    s.update(pre=pre, emph=emph,
             sub={"en": "A private progress card for the community or your clinician — only when you choose.",
                  "hi": "समुदाय या अपने चिकित्सक के लिए एक निजी प्रगति कार्ड — सिर्फ़ जब आप चाहें।",
                  "ta": "சமூகத்திற்கு அல்லது மருத்துவருக்கு ஒரு தனிப்பட்ட முன்னேற்ற கார்டு — நீங்கள் விரும்பினால் மட்டும்.",
                  "te": "సంఘం కోసం లేదా మీ డాక్టర్ కోసం ప్రైవేట్ ప్రోగ్రెస్ కార్డ్ — మీరు ఎంచుకున్నప్పుడే."}[loc],
             # The standalone share-card OUTPUT (what people post) — single pure
             # Story card, large + tilted (all 3 templates carry the chart, so two
             # cards read as duplicate charts; one hero reads cleaner). 9:16.
             body=card_sticker(surf("card-story.png", loc), 300, 1150, 720, -5, radius=40),
             decos=[deco_img(star(s["eink"]), 1184, 250, 54, 8)])
    slides.append(s)

    # 6 — Privacy closer (phone left, tilt 12, cream)
    s = dict(S[5]); pre, emph = copy[5]
    s.update(pre=pre, emph=emph,
             sub={"en": "Stored on your device. Synced only through your own iCloud.",
                  "hi": "आपके डिवाइस पर संग्रहीत। केवल आपके अपने iCloud से सिंक।",
                  "ta": "உங்கள் சாதனத்தில் சேமிப்பு. உங்கள் iCloud வழியாக மட்டுமே ஒத்திசைவு.",
                  "te": "మీ పరికరంలో నిల్వ. మీ స్వంత iCloud ద్వారా మాత్రమే సింక్."}[loc],
             body=phone(cap(loc, "05-care.png"), side="left", tilt=12, top=1010, w=900),
             decos=[deco_img(star(s["eink"]), 1184, 260, 54, 10)])
    slides.append(s)

    return slides


def main():
    for loc in ["en", "hi", "ta", "te"]:
        outdir = os.path.join(OUT, loc)
        os.makedirs(outdir, exist_ok=True)
        for i, cfg in enumerate(deck(loc), 1):
            p = os.path.join(outdir, f"slide-{i:02d}.html")
            open(p, "w").write(build_slide(loc, cfg))
        print(f"wrote 6 slides -> out/{loc}/")


if __name__ == "__main__":
    main()
