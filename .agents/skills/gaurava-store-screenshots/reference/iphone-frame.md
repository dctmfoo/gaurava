# Render a REAL iPhone — never a hand-drawn bezel

> This is the #1 lesson from the first run. A hand-drawn black rounded rectangle
> with a pill cut-out **reads as an Android phone** at a glance — a hard fail for
> an iOS App Store listing. Always frame the screenshot in a genuine iPhone Pro
> mockup.

## Why the naive version fails
A `border-radius` rounded rect + a centered pill looks generic. A real iPhone has
a specific **continuous** corner curvature, a thin **titanium rail**, the
**Dynamic Island** at the correct size/position, the **Action + volume buttons**
on the left and the **side button** on the right. Miss these and the eye says
"Android" or "generic phone."

## The fix (use the measured mockup)
The base `app-store-screenshots` skill ships a correct iPhone frame. This skill
copies it to `assets/iphone-mockup.png` (1022×2082, transparent screen cut-out).
Overlay it on the screenshot using the **pre-measured screen inset** (already
wired in `assets/build_retro.py`):

```python
PS = dict(L=52/1022, T=46/2082, W=918/1022, H=1990/2082, RX=126/918, RY=126/1990)
```

Composition (screenshot UNDER, frame PNG ON TOP — the frame's screen area is
transparent):

```html
<div class="phone" style="width:1028px;height:2095px">
  <img class="shot"  style="position:absolute;left:5.09%;top:2.21%;width:89.8%;height:95.6%;
       border-radius:13.7%/6.3%;object-fit:cover;object-position:top center" src="<screenshot>">
  <img class="frame" style="position:absolute;inset:0;width:100%;height:100%" src="<iphone-mockup.png>">
</div>
```

- Keep the phone's aspect ratio at **1022:2082** (height = width × 2.0372). Do not
  stretch.
- The source screenshots are already **1320×2868** (the App Store iPhone 6.9"
  size) captured on **iPhone 17 Pro Max** — they fill the screen cut-out cleanly
  with `object-fit:cover; object-position:top`.
- Phone width ≈ **1000–1080px** on the 1320-wide canvas puts the phone at
  ~71–76% of canvas height — within the quality bar's 68–82% band while leaving a
  gutter for the mascot (see below).

## If you must draw a frame instead of using the PNG
Don't, unless the PNG is unavailable. If forced: corner radius ≈ width/8 with a
**continuous** (squircle) curve, Dynamic Island ≈ 31% width × 1.0% height placed
≈ 2.3% from the top, a 2-tone titanium rail (light edge + darker inner), and the
button cut-outs. It is almost always faster and better to use the mockup PNG.

## Mascot gutter trick (so the mascot is actually visible)
A near-full-width phone leaves no room beside it, so the mascot becomes an
invisible sliver. Instead, hug the phone to one canvas edge (`side="left"` /
`side="right"`) and stand the mascot in the **opposite gutter**, slightly
overlapping the phone's near edge (z below the phone), waving outward. Alternate
the side each slide for rhythm. This is already implemented in `build_retro.py`
(`masc_left` / `masc_right`).

## Other devices
- **iPad** (13"): the base skill's template has an iPad frame + ratio
  (`device-frames.tsx`, `TAB_P_RATIO`). Capture from an iPad 13" simulator at
  2064×2752 and reuse the same overlay technique.
- **Apple Watch**: there is no photoreal frame in the base kit; the cushion
  `watch()` helper in `build_retro.py` is acceptable for an ecosystem sticker, or
  capture the watch sim screen and round its corners.
