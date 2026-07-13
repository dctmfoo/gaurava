#!/usr/bin/env python3
"""Gaurava "MiniHue-clean" deck generator (en/hi/ta/te).

Modeled on the MiniHue App Store listing the user liked. Style contract:
  * Soft, calm backgrounds — mostly warm light tones, with 2 DARK slides for
    rhythm (light · light · dark · light · dark · light).
  * HEAVY bold sans headline (Inter / Noto Sans <script> @ 800), 2 short lines,
    with exactly ONE word/phrase in a brand accent colour. NO brush script, NO
    squiggle underline, NO margin doodles — the app screens are the hero.
  * A REAL iPhone, UPRIGHT (no tilt), large, bleeding off the BOTTOM edge, soft
    realistic drop shadow (assets/iphone-mockup.png + measured screen inset).
  * Small top-left wordmark with a 4-dot brand mark (echoes MiniHue's grid logo).
  * Ecosystem slide = a REAL Home-Screen-with-widget capture in an iPhone frame +
    a faked Apple Watch Ultra (CSS, ported from the gaurava.app marketing site's
    devices.css, localized per deck). Copy: "Everything, at a glance."

Reuses 100% of the existing captures/<locale>/*.png and surfaces/ — this is a
generator-only restyle, no re-screenshotting. Renders 1320x2868 HTML into
./out-minihue/<locale>/ ; screenshot each with headless Chrome (see SKILL.md).
hi/ta/te marketing copy is the same transcreation DRAFT as the editorial deck.
"""
import base64, os, html

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = os.path.join(HERE, "captures")
SURF = os.path.join(HERE, "surfaces")
FONTS = os.path.join(HERE, "fonts")
OUT = os.path.join(HERE, "out-minihue")

W, H = 1320, 2868

# ---- palette ------------------------------------------------------------
# Soft light backgrounds (gentle top-down gradient for depth) + 1 dark navy.
BG = {
    "cream": "radial-gradient(125% 95% at 50% 0%, #F8F1E2 0%, #EEE4CF 100%)",
    "sage":  "radial-gradient(125% 95% at 50% 0%, #EEF3EB 0%, #DFE9DC 100%)",
    "peach": "radial-gradient(125% 95% at 50% 0%, #F9ECE2 0%, #F0DECF 100%)",
    "linen": "radial-gradient(125% 95% at 50% 0%, #F6F1E7 0%, #EBE3D4 100%)",
    "navy":  "radial-gradient(125% 95% at 50% 0%, #242D46 0%, #151C2D 100%)",
}
INK_DARK = "#20262F"     # headline/sub on light slides
INK_LIGHT = "#F5EFDF"    # headline/sub on dark slides
CORAL = "#F26A50"        # primary accent
GREEN = "#2E9E76"        # accent for the "real change" results slide

# ---- real iPhone frame (pre-measured inset, shared with build_editorial) --
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
    face("NotoDeva", "NotoSansDevanagari.ttf"),
    face("NotoTamil", "NotoSansTamil.ttf"),
    face("NotoTelugu", "NotoSansTelugu.ttf"),
])

SANS = {"en": "Inter", "hi": "NotoDeva", "ta": "NotoTamil", "te": "NotoTelugu"}
MOCK_B64 = b64(os.path.join(HERE, "iphone-mockup.png"))
ICON_B64 = b64(os.path.join(HERE, "app-icon.png"))   # real Gaurava app icon


# ---- real iPhone, UPRIGHT, large, bleeding off the bottom ----------------
def phone(shot_b64, w=1200, top=688, shadow="0 70px 90px rgba(20,15,10,.30)",
          left=None, di=True):
    h = round(w * MOCK_RATIO)
    if left is None:
        left = round((W - w) / 2)
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
    # Frame paints first (opaque black screen region); shot clipped on top; DI pill
    # drawn over the shot (the app-tab framebuffers have no Dynamic Island). Real
    # Home-Screen springboard captures already include the DI — pass di=False there.
    di_html = ("<div style=\"position:absolute;left:37%;top:2.75%;width:26%;height:2.45%;"
               "background:#000;border-radius:999px;z-index:3\"></div>") if di else ""
    return f"""
    <div class="phone" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px;
         filter:drop-shadow({shadow})">
      <img src="data:image/png;base64,{MOCK_B64}" style="position:absolute;inset:0;width:100%;height:100%;"/>
      {inner}{di_html}
    </div>"""


# ---- ecosystem stickers (widget card + quick actions + watch) ------------
def card_sticker(img_b64, x, y, w, radius=56, label=None, ink=INK_LIGHT, font="Inter",
                 shadow="0 44px 70px rgba(8,10,20,.45)"):
    if img_b64:
        body = f"<img src='data:image/png;base64,{img_b64}' style='display:block;width:100%;border-radius:{radius}px'/>"
    else:
        body = (f"<div style='width:100%;aspect-ratio:16/8;border-radius:{radius}px;"
                f"background:linear-gradient(160deg,#11151f,#28324a);display:flex;align-items:center;"
                f"justify-content:center;color:#8893ad;font-family:Inter;font-size:34px'>widget</div>")
    lab = (f"<div style=\"font-family:'{font}';font-weight:600;font-size:34px;color:{ink};"
           f"opacity:.8;text-align:center;margin-top:20px\">{html.escape(label)}</div>" if label else "")
    return (f"<div style='position:absolute;left:{x}px;top:{y}px;width:{w}px;"
            f"filter:drop-shadow({shadow})'>{body}{lab}</div>")


def watch_sticker(img_b64, x, y, w, ink=INK_LIGHT, label=None, font="Inter", glow=True):
    h = round(w * 1.18)
    inner = (f"<img src='data:image/png;base64,{img_b64}' style='width:100%;height:100%;object-fit:cover'/>"
             if img_b64 else
             "<div style='width:100%;height:100%;display:flex;align-items:center;justify-content:center;"
             "color:#8893ad;font-family:Inter;font-size:26px'>watch</div>")
    lab = (f"<div style=\"font-family:'{font}';font-weight:600;font-size:34px;color:{ink};"
           f"opacity:.8;text-align:center;margin-top:18px\">{html.escape(label)}</div>" if label else "")
    # On a dark slide a black watch body vanishes into the background. A soft warm
    # halo behind it + a light rim on the body lift it off the navy. Drop-shadows
    # are useless on dark, so the separation comes from light, not shadow.
    halo = ""
    if glow:
        gw = round(w * 1.55)
        off = round((gw - w) / 2)
        halo = (f"<div style='position:absolute;left:{-off}px;top:{-off}px;width:{gw}px;height:{gw}px;"
                f"border-radius:50%;background:radial-gradient(circle,rgba(245,239,223,.28) 0%,"
                f"rgba(245,239,223,0) 68%);filter:blur(6px);z-index:0'></div>")
    rim = "box-shadow:0 0 0 2px rgba(245,239,223,.22),0 24px 48px rgba(0,0,0,.45);" if glow else \
          "filter:drop-shadow(0 40px 64px rgba(8,10,20,.5));"
    return (f"<div style='position:absolute;left:{x}px;top:{y}px;width:{w}px;z-index:4'>{halo}"
            f"<div style='position:relative;width:{w}px;height:{h}px;background:#0a0a0a;border-radius:32%;"
            f"border:8px solid #11131a;overflow:hidden;{rim}'>{inner}</div>{lab}</div>")


# ---- realistic Apple Watch Ultra (faked in CSS, reused from the marketing
#      site's devices.css port) — same titanium frame + orange Action button, so
#      the store deck matches gaurava.app. Screen UI is ours; localized per deck. -
WATCH_ICONS = (
    '<svg width="0" height="0" style="position:absolute">'
    '<symbol id="i-syringe" viewBox="0 0 256 256"><path d="M237.66,66.34l-48-48a8,8,0,0,0-11.32,11.32L196.69,48,168,76.69,133.66,42.34a8,8,0,0,0-11.32,11.32L128.69,60l-84,84A15.86,15.86,0,0,0,40,155.31v49.38L18.34,226.34a8,8,0,0,0,11.32,11.32L51.31,216h49.38A15.86,15.86,0,0,0,112,211.31l84-84,6.34,6.35a8,8,0,0,0,11.32-11.32L179.31,88,208,59.31l18.34,18.35a8,8,0,0,0,11.32-11.32ZM100.69,200H56V155.31l18-18,20.34,20.35a8,8,0,0,0,11.32-11.32L85.31,126,98,113.31l20.34,20.35a8,8,0,0,0,11.32-11.32L109.31,102,140,71.31,184.69,116Z"/></symbol>'
    '<symbol id="i-waveform" viewBox="0 0 256 256"><path d="M56,96v64a8,8,0,0,1-16,0V96a8,8,0,0,1,16,0ZM88,24a8,8,0,0,0-8,8V224a8,8,0,0,0,16,0V32A8,8,0,0,0,88,24Zm40,32a8,8,0,0,0-8,8V192a8,8,0,0,0,16,0V64A8,8,0,0,0,128,56Zm40,32a8,8,0,0,0-8,8v64a8,8,0,0,0,16,0V96A8,8,0,0,0,168,88Zm40-16a8,8,0,0,0-8,8v96a8,8,0,0,0,16,0V80A8,8,0,0,0,208,72Z"/></symbol>'
    '</svg>'
)

# Localized watch UI strings (Gemini generator/reviewer/judge approved — see
# scratch/marketing-l10n-review/slide3-result.json). Dose unit matches each
# locale's captured Home-Screen widget on the same slide.
WATCH_COPY = {
    "en": dict(track="On track", num="4", days="days", nextline="Next Sun, 7 Jun",
               dose="Dose", dosev="12.5 mg", log="Log", updated="Updated"),
    "hi": dict(track="सही राह पर", num="4", days="दिन", nextline="अगला रवि, 7 जून",
               dose="खुराक", dosev="12.5 मिग्रा", log="दर्ज", updated="अपडेटेड"),
    "ta": dict(track="சரியான பாதையில்", num="4", days="நாட்கள்", nextline="அடுத்த ஞா, 7 ஜூன்",
               dose="அளவு", dosev="12.5மி.கி.", log="பதிவு", updated="புதுப்பிப்பு"),
    "te": dict(track="సరైన మార్గంలో", num="4", days="రోజులు", nextline="వచ్చే ఆది, 7 జూన్",
               dose="మోతాదు", dosev="12.5మి.గ్రా.", log="నమోదు", updated="నవీకృతం"),
}

# The frame + screen CSS, verbatim port of styles.css `.awu*` / `.wu-*`. {{ }} so
# it survives the f-string in doc(); .wu-track tracking is overridden per-locale.
WATCH_CSS = """
.eco-watch{position:absolute;z-index:8}
.awu{position:absolute;top:0;left:0;height:380px;width:360px;transform:scale(var(--s));
  transform-origin:top left;filter:drop-shadow(0 30px 52px rgba(8,10,16,.55))}
.awu .icon{width:1em;height:1em;fill:currentColor;display:inline-block;vertical-align:-0.14em}
.awu-frame{background:#0d0d0d;border-radius:92px;
  box-shadow:inset 0 0 12px 1px rgba(13,13,13,.75),inset 0 0 0 6px #d6ccc2,inset 0 0 0 12px #d6ccc2;
  height:380px;margin:0 20px;padding:38px;position:relative;width:320px}
.awu-frame::before{border:1px solid #f5f2f0;border-radius:80px;
  box-shadow:0 0 6px rgba(13,13,13,.2),inset 0 0 4px 1px #f5f2f0,inset 0 0 0 10px #d6ccc2;
  content:"";height:356px;left:12px;position:absolute;top:12px;width:296px}
.awu-screen{border:2px solid #121212;border-radius:62px;height:304px;width:244px;
  position:relative;overflow:hidden;background:radial-gradient(130% 90% at 50% -8%,#181b21 0%,#07080b 74%)}
.awu-crown{background:radial-gradient(circle at center,#d6ccc2 50%,#ebe6e1 85%,#a38c76 100%);
  border-radius:4px 4px 4px 4px/8px 4px 4px 8px;
  box-shadow:inset 0 0 16px 1px rgba(13,13,13,.5),-8px 0 4px rgba(13,13,13,.2),inset 4px 0 4px rgba(13,13,13,.2);
  height:214px;margin-top:-107px;position:absolute;right:4px;top:50%;width:18px;z-index:1}
.awu-crown::before{border-radius:8px 4px 4px 8px/32px 4px 4px 32px;box-shadow:-10px 0 8px rgba(13,13,13,.2);
  content:"";height:194px;margin-top:-97px;position:absolute;right:8px;top:50%;width:12px}
.awu-btns{background:#d6ccc2;border-left:1px solid #4c4033;border-radius:8px 6px 6px 8px/20px 6px 6px 20px;
  box-shadow:inset 8px 0 8px 0 #5c4d3e,inset -2px 0 6px #a38c76;
  height:72px;position:absolute;right:1px;top:108px;width:24px;z-index:9}
.awu-btns::after{background:#d6ccc2;border-radius:2px 4px 4px 2px/20px 8px 8px 20px;
  box-shadow:inset -2px 0 2px 0 #6b5948,inset -6px 0 18px #a38c76;
  content:"";height:78px;position:absolute;right:0;top:-4px;width:6px}
.awu-stripe{background:#e0d9d1;border-radius:2px 8px 8px 2px;box-shadow:0 14px 0 #d6ccc2,0 28px 0 #d6ccc2;
  height:10px;left:19px;position:absolute;top:98px;width:4px;z-index:1}
.awu-power{background:#d6ccc2;border-radius:2px 4px 4px 2px/2px 8px 8px 2px;box-shadow:inset 0 0 2px 1px #a38c76;
  height:72px;position:absolute;right:1px;top:212px;width:4px}
.awu-action{background:#f18f42;border:1px solid #a7500c;border-radius:2px 4px 4px 2px/2px 8px 8px 2px;
  box-shadow:inset 0 0 1px 1px #ef812a;height:106px;left:19px;position:absolute;top:162px;width:4px;z-index:1}
.wu-screen{position:absolute;inset:0;padding:24px 24px 20px;display:flex;flex-direction:column;color:#fff}
.wu-bar{display:flex;align-items:center;justify-content:space-between;font-size:18px;color:#e9e9ec;font-weight:600}
.wu-dots{width:4px;height:4px;border-radius:50%;background:#b9bdc6;box-shadow:0 7px 0 #b9bdc6}
.wu-track{margin-top:18px;color:#7fd1ad;font-weight:800;font-size:15px}
.wu-hero{display:flex;align-items:baseline;gap:7px;margin-top:4px;line-height:1}
.wu-hero b{font-size:62px;font-weight:800;color:#fff;letter-spacing:-0.03em}
.wu-hero span{font-size:28px;font-weight:600;color:#c4c8d0}
.wu-next{margin-top:7px;color:#969cb0;font-size:17px}
.wu-dose{display:flex;align-items:center;gap:8px;margin-top:auto;background:#191c23;
  border:1px solid rgba(255,255,255,0.06);border-radius:999px;padding:12px 16px;font-size:17px;
  color:#aeb3bf;white-space:nowrap}
.wu-dose .icon{color:#e3935b;font-size:22px}
.wu-dose strong{margin-left:auto;color:#fff;font-weight:700}
.wu-log{display:flex;align-items:center;justify-content:center;gap:7px;margin-top:13px;background:#7fd1ad;
  color:#06281d;border-radius:999px;padding:14px 0;font-weight:800;font-size:20px}
.wu-log .icon{font-size:22px}
.wu-updated{margin-top:12px;color:#676d7c;font-size:15px}
"""


def ultra_watch(loc, left, top, s=1.2):
    """Realistic Apple Watch Ultra at (left,top), scaled by s, localized for loc."""
    c = WATCH_COPY[loc]
    # Latin gets the uppercase + wide tracking of watchOS caps; Indic scripts
    # mustn't be uppercased or wide-tracked (it breaks conjunct shaping).
    if loc == "en":
        track_style = "letter-spacing:.16em;text-transform:uppercase"
    else:
        track_style = "letter-spacing:.01em"
    return (
        f"<div class='eco-watch' style='left:{left}px;top:{top}px;--s:{s}'>"
        f"{WATCH_ICONS}"
        "<div class='awu'>"
        "<div class='awu-frame'><div class='awu-screen'><div class='wu-screen'>"
        f"<div class='wu-bar'><span>9:41</span><span class='wu-dots'></span></div>"
        f"<div class='wu-track' style='{track_style}'>{html.escape(c['track'])}</div>"
        f"<div class='wu-hero'><b>{html.escape(c['num'])}</b><span>{html.escape(c['days'])}</span></div>"
        f"<div class='wu-next'>{html.escape(c['nextline'])}</div>"
        f"<div class='wu-dose'><svg class='icon'><use href='#i-syringe'/></svg>"
        f"<span>{html.escape(c['dose'])}</span><strong>{html.escape(c['dosev'])}</strong></div>"
        f"<div class='wu-log'><svg class='icon'><use href='#i-waveform'/></svg>{html.escape(c['log'])}</div>"
        f"<div class='wu-updated'>{html.escape(c['updated'])}</div>"
        "</div></div></div>"
        "<div class='awu-crown'></div><div class='awu-btns'></div>"
        "<div class='awu-stripe'></div><div class='awu-power'></div><div class='awu-action'></div>"
        "</div></div>"
    )


# ---- top-left wordmark: the REAL Gaurava app icon + name -----------------
def wordmark(loc, ink, dark):
    # The actual rounded-square app icon (teal G + terracotta swoosh), small, with
    # a hairline ring so it reads as an app chip on both light and dark slides.
    ring = "rgba(245,239,223,.16)" if dark else "rgba(20,30,25,.10)"
    icon = (f"<img src='data:image/png;base64,{ICON_B64}' "
            f"style='width:62px;height:62px;border-radius:15px;display:block;"
            f"box-shadow:0 0 0 1px {ring}, 0 8px 18px rgba(20,30,25,.14)'/>")
    return (f"<div class='wordmark'>{icon}"
            f"<div style=\"font-family:'{SANS[loc]}';font-weight:800;font-size:46px;"
            f"color:{ink};letter-spacing:-.5px\">Gaurava</div></div>")


# ---- headline (heavy bold sans, one accent line) -------------------------
# Indic scripts set taller/wider than Latin — tune sizes per locale to keep the
# headline to ~2 punchy lines.
HEAD_PX = {"en": 124, "hi": 100, "ta": 94, "te": 100}


def headline_block(loc, pre_lines, emph, ink, accent):
    sans = SANS[loc]
    pre = "".join(f"<div>{html.escape(p)}</div>" for p in pre_lines)
    return (f"<div class='headline' style=\"color:{ink};font-family:'{sans}';font-size:{HEAD_PX[loc]}px\">"
            f"{pre}<div class='emph' style='color:{accent}'>{html.escape(emph)}</div></div>")


def doc(loc, bg, ink, inner, extra_css=""):
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
{FACES}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}px;height:{H}px}}
.slide{{position:relative;width:{W}px;height:{H}px;overflow:hidden;background:{bg};
  font-family:'{SANS[loc]}',sans-serif}}
.wordmark{{position:absolute;left:96px;top:104px;display:flex;align-items:center;gap:22px;z-index:20}}
.copy{{position:absolute;left:96px;right:96px;top:226px;z-index:15}}
.headline{{font-weight:800;line-height:1.0;letter-spacing:-2.5px}}
.emph{{font-weight:800;line-height:1.0}}
.phone{{position:absolute;z-index:6}}
{extra_css}
</style></head><body><div class="slide">{inner}</div></body></html>"""


# ---- copy (en + transcreation drafts; hi/ta/te native-review-pending) ----
COPY = {
    "en": [(["Track it with"], "dignity."),
           (["Five months."], "Real change."),
           (["Everything,"], "at a glance."),
           (["How you feel,"], "in one tap."),
           (["Your progress,"], "worth sharing."),
           (["Private"], "by design.")],
    "hi": [(["अपने सफ़र को"], "सम्मान के साथ।"),
           (["पाँच महीने।"], "असली बदलाव।"),
           (["सब कुछ,"], "एक नज़र में।"),
           (["आपकी भावना,"], "बस एक टैप में।"),
           (["आपकी प्रगति,"], "गर्व के साथ।"),
           (["पूरी तरह निजी,"], "सिर्फ़ आपकी।")],
    "ta": [(["உங்கள் பயணம்,"], "கண்ணியத்துடன்."),
           (["ஐந்து மாதங்கள்."], "உண்மையான மாற்றம்."),
           (["அனைத்தும்,"], "ஒரே பார்வையில்."),
           (["உங்கள் உணர்வு,"], "ஒரே தட்டலில்."),
           (["உங்கள் முன்னேற்றம்,"], "பெருமையுடன்."),
           (["முழுமையாக தனிப்பட்டது,"], "உங்களுக்கு மட்டுமே.")],
    "te": [(["మీ ప్రయాణం,"], "గౌరవంగా."),
           (["ఐదు నెలలు."], "నిజమైన మార్పు."),
           (["అన్నీ,"], "ఒక్క చూపులో."),
           (["మీ భావన,"], "ఒకే ట్యాప్‌తో."),
           (["మీ పురోగతి,"], "గర్వంగా."),
           (["పూర్తిగా ప్రైవేట్,"], "మీది మాత్రమే.")],
}

# per-slide: background key, dark?, accent colour
SLIDE_STYLE = [
    dict(bg="cream", dark=False, accent=CORAL),   # 1 hero
    dict(bg="sage",  dark=False, accent=GREEN),   # 2 trend
    dict(bg="navy",  dark=True,  accent=CORAL),   # 3 ecosystem
    dict(bg="peach", dark=False, accent=CORAL),   # 4 log
    dict(bg="navy",  dark=True,  accent=CORAL),   # 5 share
    dict(bg="linen", dark=False, accent=CORAL),   # 6 privacy
]

CAPTIONS = {
    "home":  {"en": "Home Screen",   "hi": "होम स्क्रीन",      "ta": "முகப்புத் திரை",   "te": "హోమ్ స్క్రీన్"},
    "quick": {"en": "Quick actions", "hi": "त्वरित क्रियाएँ",   "ta": "விரைவுச் செயல்கள்", "te": "త్వరిత చర్యలు"},
    "watch": {"en": "Apple Watch",   "hi": "Apple Watch",      "ta": "Apple Watch",      "te": "Apple Watch"},
}


# ---- captures / surfaces loading (graceful, per-locale fallback) ----------
def cap(loc, name):
    for folder in (os.path.join(CAP, loc), CAP):
        p = os.path.join(folder, name)
        if os.path.exists(p):
            return b64(p)
    return None


def surf(name, loc="en"):
    for folder in (os.path.join(SURF, loc), SURF):
        p = os.path.join(folder, name)
        if os.path.exists(p):
            return b64(p)
    return None


def build_slide(loc, i, body, extra_css=""):
    st = SLIDE_STYLE[i]
    ink = INK_LIGHT if st["dark"] else INK_DARK
    pre, emph = COPY[loc][i]
    head = headline_block(loc, pre, emph, ink, st["accent"])
    copy = f"<div class='copy'>{head}</div>"
    wm = wordmark(loc, ink, st["dark"])
    return doc(loc, BG[st["bg"]], ink, f"{wm}{copy}{body}", extra_css=extra_css)


def deck(loc):
    sans = SANS[loc]
    out = []

    # 1 — Hero / Summary (upright phone, bottom-bleed)
    out.append(build_slide(loc, 0, phone(cap(loc, "01-summary-journey.png"))))

    # 2 — Trend / Results overview (upright phone, bottom-bleed)
    out.append(build_slide(loc, 1, phone(cap(loc, "03-results-overview.png"))))

    # 3 — Ecosystem (DARK): the REAL Home-Screen-with-widget capture in an iPhone
    # frame + a faked Apple Watch Ultra (CSS, identical to gaurava.app's). The
    # phone is nudged left so the watch clusters into the lower-right gutter,
    # mirroring the marketing site's ecosystem composition. "At a glance."
    eco = (phone(cap(loc, "07-home-widget.png"), w=1140, left=70, top=752, di=False,
                 shadow="0 60px 90px rgba(8,10,20,.55)")
           + ultra_watch(loc, left=842, top=2168, s=1.22))
    out.append(build_slide(loc, 2, eco, extra_css=WATCH_CSS))

    # 4 — Log capture (upright phone, bottom-bleed)
    out.append(build_slide(loc, 3, phone(cap(loc, "04-log-capture.png"))))

    # 5 — Share card (DARK): standalone Story card, centred + large
    share = card_sticker(surf("card-story.png", loc), 160, 960, 1000, radius=44,
                         shadow="0 60px 90px rgba(8,10,20,.55)")
    out.append(build_slide(loc, 4, share))

    # 6 — Privacy closer: the Care tab scrolled to its Privacy & Sync section
    # (Privacy Statement: Local-first, Data Controls, Widget Privacy, iCloud Sync)
    # — the real "private by design" surface, not the profile at the top of Care.
    out.append(build_slide(loc, 5, phone(cap(loc, "05b-care-privacy.png"))))

    return out


def main():
    for loc in ["en", "hi", "ta", "te"]:
        outdir = os.path.join(OUT, loc)
        os.makedirs(outdir, exist_ok=True)
        for i, htmlstr in enumerate(deck(loc), 1):
            open(os.path.join(outdir, f"slide-{i:02d}.html"), "w").write(htmlstr)
        print(f"wrote 6 slides -> out-minihue/{loc}/")


if __name__ == "__main__":
    main()
