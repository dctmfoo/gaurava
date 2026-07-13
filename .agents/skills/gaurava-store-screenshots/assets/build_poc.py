#!/usr/bin/env python3
"""Font + style POC for the Hand-Drawn Editorial Tasks deck.

Goal: prove we can render en / hi / ta / te headlines with NO tofu, in two type
roles — an editorial sans (Inter-role) and a brush-pen script emphasis word
(Caveat-role) — and that the chosen Indic fonts keep the hand-made feel.

Brush-script (Caveat-role) mapping:  en=Caveat  hi=Kalam  ta=Kavivanar  te=NTR
Editorial-sans (Inter-role) mapping: en=Inter   hi/ta/te=Noto Sans <script>

Emits one 1320x2868 slide per locale into ./poc, render with headless Chrome.
"""
import base64, os, html

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, "fonts")
OUT = os.path.join(HERE, "poc")
os.makedirs(OUT, exist_ok=True)

NAVY, CREAM, CORAL_BG, PURPLE = "#1B2336", "#F5EFDF", "#E55846", "#8B7BFF"
CORAL = "#F26A50"   # emphasis ink
CREAMINK = "#F5EFDF"
INK_ON_CREAM = "#1B2336"


def b64(path):
    return base64.b64encode(open(path, "rb").read()).decode()


def face(name, file, weight="100 900"):
    return (f"@font-face{{font-family:'{name}';font-weight:{weight};font-style:normal;"
            f"src:url(data:font/ttf;base64,{b64(os.path.join(FONTS,file))}) format('truetype');}}")


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


def squiggle(color):
    svg = (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 120 18' preserveAspectRatio='none'>"
           f"<path d='M3,12 q12,-10 24,0 t24,0 t24,0 t24,0 t18,0' fill='none' stroke='{color}' "
           f"stroke-width='4' stroke-linecap='round'/></svg>")
    return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()


def arrow(color):
    svg = (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 80'>"
           f"<path d='M6,10 C40,2 70,20 78,54' fill='none' stroke='{color}' stroke-width='5' stroke-linecap='round'/>"
           f"<path d='M62,50 L80,58 L84,38' fill='none' stroke='{color}' stroke-width='5' "
           f"stroke-linecap='round' stroke-linejoin='round'/></svg>")
    return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()


def star(color):
    svg = (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'>"
           f"<path d='M12 1 C13 8 16 11 23 12 C16 13 13 16 12 23 C11 16 8 13 1 12 C8 11 11 8 12 1 Z' fill='{color}'/></svg>")
    return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()


# locale -> (bg, headline_ink, emphasis_ink, sans_font, script_font,
#            pre_lines[list], emphasis_phrase, sub_line)
SLIDES = {
    "en": (NAVY, CREAM, CORAL, "Inter", "Caveat",
           ["Track it with"], "dignity.",
           "Five months. Real change, your weight — quietly, on your terms."),
    "hi": (CREAM, INK_ON_CREAM, CORAL, "NotoDeva", "Kalam",
           ["अपने उपचार को"], "सम्मान के साथ।",
           "पाँच महीने। सब कुछ आपके डिवाइस पर ही रहता है।"),
    "ta": (CORAL_BG, CREAM, CREAMINK, "NotoTamil", "Kavivanar",
           ["உங்கள் சிகிச்சையை"], "கண்ணியத்துடன்",
           "ஐந்து மாதங்கள். உண்மையான மாற்றம்."),
    "te": (PURPLE, CREAM, CORAL, "NotoTelugu", "NTR",
           ["మీ చికిత్సను"], "గౌరవంగా.",
           "ఐదు నెలలు. నిజమైన మార్పు, మీ నిబంధనలపై."),
}

# emphasis rotation + scale per slide (slightly imperfect)
ROT = {"en": -3, "hi": 4, "ta": -2, "te": 5}


def slide_html(loc):
    bg, hink, eink, sans, script, pre, emph, sub = SLIDES[loc]
    rot = ROT[loc]
    pre_html = "".join(f"<div>{html.escape(p)}</div>" for p in pre)
    deco_color = eink
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
{FACES}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:1320px;height:2868px}}
.slide{{position:relative;width:1320px;height:2868px;overflow:hidden;background:{bg};
  font-family:'{sans}',sans-serif}}
.wordmark{{position:absolute;left:90px;top:96px;font-family:'{sans}';font-weight:600;
  font-size:46px;color:{hink};opacity:.8;letter-spacing:.5px}}
.headline{{position:absolute;left:96px;right:96px;top:330px;color:{hink};
  font-family:'{sans}';font-weight:500;font-size:120px;line-height:1.04;letter-spacing:-1px}}
.emph{{display:inline-block;font-family:'{script}';font-weight:700;color:{eink};
  font-size:150px;line-height:1.0;transform:rotate({rot}deg);transform-origin:left center;
  margin-top:24px;padding:0 8px}}
.sub{{position:absolute;left:100px;right:140px;top:880px;color:{hink};opacity:.82;
  font-family:'{sans}';font-weight:400;font-size:46px;line-height:1.4}}
/* tilted placeholder phone (warm soft shadow) */
.phone{{position:absolute;right:120px;bottom:150px;width:760px;height:1560px;
  background:linear-gradient(160deg,#0d1017,#171c28);border-radius:84px;
  transform:rotate(-16deg);box-shadow:0 60px 120px rgba(20,10,0,.45);
  border:14px solid #0a0d14}}
.phone .scr{{position:absolute;inset:22px;border-radius:64px;
  background:linear-gradient(180deg,{bg},rgba(255,255,255,.06));opacity:.9}}
.phone .ph-note{{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;
  font-family:'{sans}';font-weight:500;font-size:40px;color:{hink};opacity:.5;transform:rotate(0deg)}}
.deco{{position:absolute}}
.locchip{{position:absolute;right:90px;top:96px;font-family:'Inter';font-weight:600;
  font-size:40px;color:{hink};opacity:.55;letter-spacing:2px}}
</style></head><body><div class="slide">
  <div class="wordmark">gaurava</div>
  <div class="locchip">{loc.upper()}</div>
  <div class="headline">{pre_html}<span class="emph">{html.escape(emph)}</span></div>
  <div class="sub">{html.escape(sub)}</div>
  <img class="deco" style="left:110px;top:300px;width:140px" src="{star(deco_color)}"/>
  <img class="deco" style="left:760px;top:560px;width:150px;transform:rotate(8deg)" src="{arrow(deco_color)}"/>
  <img class="deco" style="left:120px;top:760px;width:360px;height:34px" src="{squiggle(deco_color)}"/>
  <div class="phone"><div class="scr"></div><div class="ph-note">app screen</div></div>
</div></body></html>"""


def main():
    for loc in ["en", "hi", "ta", "te"]:
        p = os.path.join(OUT, f"poc-{loc}.html")
        open(p, "w").write(slide_html(loc))
        print("wrote", os.path.relpath(p, HERE))


if __name__ == "__main__":
    main()
