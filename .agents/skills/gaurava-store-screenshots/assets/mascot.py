"""Retro rubberhose can-mascot, authored as inline SVG.

A chunky upright "can" body with pie-cut eyes, white four-finger mitten gloves,
sausage-tube limbs, a halftone shadow on the lower-right, and a heavy uniform
ink outline. Recolour via `body` to get the mustard / peach / pink / mint
variants. Returned as an <svg> sized to `width` px (height follows the 240x340
viewBox aspect).
"""

INK = "#1A1A1A"
GLOVE = "#FBEFD2"
SHOE = "#3A2A1A"


def mascot_svg(body="#F2BB46", width=420, pose="wave", eye_dir="center", uid="m"):
    h = width * 340 / 240
    # darker shade of the body for the volume/shadow side
    shade = _darken(body, 0.12)
    # pupil look direction
    px, py = {"center": (0, 6), "up": (0, 0), "left": (-5, 6), "right": (5, 4)}[eye_dir]

    # right arm: waving up, or relaxed down for "walk"
    if pose == "wave":
        r_arm = "M182,182 C214,176 232,150 232,108"
        r_glove_cx, r_glove_cy = 232, 96
    else:
        r_arm = "M184,196 C214,206 226,236 228,262"
        r_glove_cx, r_glove_cy = 230, 274

    halftone = _halftone(uid, body)

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{h:.0f}" viewBox="0 0 240 340" fill="none" overflow="visible">
  <defs>
    {halftone}
    <clipPath id="{uid}-body">
      <path d="M48,176 C48,98 86,70 120,70 C154,70 192,98 192,176 C196,236 190,300 120,306 C50,300 44,236 48,176 Z"/>
    </clipPath>
  </defs>
  <!-- ground shadow -->
  <ellipse cx="120" cy="330" rx="92" ry="15" fill="{INK}" opacity="0.13"/>

  <!-- LEFT leg (lifted, walk) + shoe -->
  <path d="M96,298 C92,316 92,322 86,330" stroke="{INK}" stroke-width="30" stroke-linecap="round"/>
  <path d="M96,298 C92,316 92,322 86,330" stroke="{body}" stroke-width="20" stroke-linecap="round"/>
  <ellipse cx="80" cy="332" rx="26" ry="14" fill="{SHOE}" stroke="{INK}" stroke-width="6"/>
  <!-- RIGHT leg + shoe -->
  <path d="M146,300 C150,322 152,330 152,340" stroke="{INK}" stroke-width="30" stroke-linecap="round"/>
  <path d="M146,300 C150,322 152,330 152,340" stroke="{body}" stroke-width="20" stroke-linecap="round"/>
  <ellipse cx="158" cy="342" rx="26" ry="14" fill="{SHOE}" stroke="{INK}" stroke-width="6"/>

  <!-- LEFT arm (relaxed) -->
  <path d="M58,190 C40,206 34,232 36,256" stroke="{INK}" stroke-width="32" stroke-linecap="round"/>
  <path d="M58,190 C40,206 34,232 36,256" stroke="{body}" stroke-width="22" stroke-linecap="round"/>
  <!-- RIGHT arm -->
  <path d="{r_arm}" stroke="{INK}" stroke-width="32" stroke-linecap="round"/>
  <path d="{r_arm}" stroke="{body}" stroke-width="22" stroke-linecap="round"/>

  <!-- BODY -->
  <path d="M48,176 C48,98 86,70 120,70 C154,70 192,98 192,176 C196,236 190,300 120,306 C50,300 44,236 48,176 Z" fill="{body}" stroke="{INK}" stroke-width="6.5" stroke-linejoin="round"/>
  <!-- body shade (lower-right) clipped to body -->
  <g clip-path="url(#{uid}-body)">
    <path d="M150,120 C210,150 210,260 150,320 L230,320 L230,90 Z" fill="{shade}" opacity="0.55"/>
    <rect x="104" y="150" width="140" height="190" fill="url(#{uid}-dots)"/>
  </g>
  <!-- re-stroke body edge over shade -->
  <path d="M48,176 C48,98 86,70 120,70 C154,70 192,98 192,176 C196,236 190,300 120,306 C50,300 44,236 48,176 Z" fill="none" stroke="{INK}" stroke-width="6.5" stroke-linejoin="round"/>

  <!-- EYES (pie-cut) -->
  <g>
    <circle cx="100" cy="150" r="33" fill="{GLOVE}" stroke="{INK}" stroke-width="5.5"/>
    <circle cx="140" cy="150" r="33" fill="{GLOVE}" stroke="{INK}" stroke-width="5.5"/>
    <!-- pupils -->
    <circle cx="{102+px}" cy="{158+py}" r="18" fill="{INK}"/>
    <circle cx="{138+px}" cy="{158+py}" r="18" fill="{INK}"/>
    <!-- pie-cut wedge (cream notch up-right) -->
    <path d="M{102+px},{158+py} L{118+px},{146+py} L{112+px},{166+py} Z" fill="{GLOVE}"/>
    <path d="M{138+px},{158+py} L{154+px},{146+py} L{148+px},{166+py} Z" fill="{GLOVE}"/>
    <!-- highlight dots -->
    <circle cx="{108+px}" cy="{151+py}" r="4" fill="{GLOVE}"/>
    <circle cx="{144+px}" cy="{151+py}" r="4" fill="{GLOVE}"/>
  </g>

  <!-- rosy cheeks -->
  <ellipse cx="74" cy="186" rx="13" ry="8" fill="#F3A6B7" opacity="0.7"/>
  <ellipse cx="166" cy="186" rx="13" ry="8" fill="#F3A6B7" opacity="0.7"/>
  <!-- little smile -->
  <path d="M104,196 C114,206 126,206 136,196" stroke="{INK}" stroke-width="5" stroke-linecap="round" fill="none"/>

  <!-- GLOVES -->
  {_glove(36, 256, body, uid+'l')}
  {_glove(r_glove_cx, r_glove_cy, body, uid+'r')}
</svg>'''


def _glove(cx, cy, body, uid):
    return f'''<g>
    <ellipse cx="{cx}" cy="{cy}" rx="22" ry="24" fill="{GLOVE}" stroke="{INK}" stroke-width="5.5"/>
    <path d="M{cx-20},{cy-2} q-10,-2 -12,8" fill="{GLOVE}" stroke="{INK}" stroke-width="5"/>
    <path d="M{cx-9},{cy+12} q9,6 18,0" stroke="{INK}" stroke-width="3.4" fill="none"/>
    <path d="M{cx-9},{cy+17} q9,6 18,0" stroke="{INK}" stroke-width="3.4" fill="none"/>
    <path d="M{cx-9},{cy+22} q9,6 18,0" stroke="{INK}" stroke-width="3.4" fill="none"/>
  </g>'''


def _halftone(uid, body):
    return f'''<pattern id="{uid}-dots" width="11" height="11" patternUnits="userSpaceOnUse" patternTransform="rotate(8)">
      <circle cx="3" cy="3" r="2.1" fill="{INK}" opacity="0.16"/>
    </pattern>'''


def _darken(hexc, amt):
    hexc = hexc.lstrip("#")
    r, g, b = int(hexc[0:2], 16), int(hexc[2:4], 16), int(hexc[4:6], 16)
    r = int(r * (1 - amt)); g = int(g * (1 - amt)); b = int(b * (1 - amt))
    return f"#{r:02x}{g:02x}{b:02x}"


if __name__ == "__main__":
    # quick standalone preview sheet of all four colourways
    cols = {"mustard": "#F2BB46", "peach": "#F2B07A", "pink": "#EE92A4", "mint": "#9CC692"}
    parts = []
    for name, c in cols.items():
        parts.append(f'<div style="display:inline-block;margin:20px;text-align:center">{mascot_svg(c, 260, "wave", uid=name)}<div style="font-family:sans-serif">{name}</div></div>')
    html = f'<!doctype html><html><body style="background:#F4E6CC;margin:0;padding:30px">{"".join(parts)}</body></html>'
    open("mascot_preview.html", "w").write(html)
    print("wrote mascot_preview.html")
