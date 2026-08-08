# Handoff: Askance — a value-study tool for artists

## Overview

Askance takes a photograph and flattens it into a small number of values (2–7), so an artist can see the shapes that light makes without being distracted by colour or detail. It is a viewing instrument, not an editor: the image is always fullscreen, the controls are unobtrusive, and there is nothing to save except the settings you arrived at.

Target platforms: iOS, Android and PWA, built in Flutter from one codebase. A desktop/web layout is designed and included.

## About the design files

The files in this bundle are **design references created in HTML**. They are a working prototype of the intended look and behaviour — not production code to port. The task is to **rebuild these designs in Flutter** using idiomatic Flutter patterns and packages.

The one exception worth reading closely is the image-processing pipeline. That is a specification, not a suggestion: the algorithm in "The engine" below defines what the app *is*, and the values in it were chosen deliberately. Everything else — layout, widget structure, state management — should be rebuilt the Flutter way.

`Askance.dc.html` is a single self-contained page. Open it in a browser; it needs `support.js` and `assets/ref-portrait.jpg` alongside it. It contains four sections, newest first:

- **Turn 4** — the paywall and the free/paid seam
- **Turn 3** — the desktop and web layout (option `3a`)
- **Turn 2** — the full mobile flow (option `2a`) — this is the app
- **Turn 1** — three rejected control-surface explorations (`1a`, `1b`, `1c`). `1b` was chosen and became `2a`. Kept for context only; do not build these.

## Fidelity

**High fidelity.** Colours, typography, spacing and interaction timings are final and should be matched. The design system is "Modernist": flat, zero corner radius anywhere, 2px rules, flush-left labels, one accent red used sparingly.

---

## The engine

This is the heart of the app. Everything else is chrome around it.

### Pipeline

For each frame that needs re-computing:

1. **Source.** The full-resolution decoded image, cover-cropped to the viewport aspect. Vertical alignment is 32% from the top rather than centred — this keeps a head in frame on portrait sources. Horizontal alignment is centred.

2. **Blur** — this is the "detail" control. Gaussian blur with sigma:

   ```
   sigma = (1 - detail) * 16 * (renderWidth / 480) + 0.4
   ```

   `detail` runs 0…1 (UI shows 0–100). The `renderWidth / 480` term keeps shapes the same size at any output resolution — 480 is the width the constants were tuned at. Blur happens in *screen* space, which is what makes shapes simplify uniformly regardless of how far you have zoomed.

3. **Lightness.** For each pixel, convert sRGB to CIE L\*:

   ```
   linear(c) = c <= 0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4     // c in 0..1
   Y         = 0.2126*linear(r) + 0.7152*linear(g) + 0.0722*linear(b)
   L*        = Y > 0.008856 ? 116*cbrt(Y) - 16 : 903.3*Y          // 0..100
   ```

   **Do not shortcut this to a luma of the gamma-encoded channels.** L\* tracks Munsell value closely (L\* ≈ 10 × Munsell V), which is why the output matches the printed value scale on an artist's desk. It is the single most important correctness property in the app.

4. **Quantise.** With `n` = step count (2–7):

   ```
   band = clamp(floor(L*/100 * n), 0, n-1)
   ```

   Band 0 is darkest. Thresholds are absolute — never derived from the histogram of what is on screen — so a pixel keeps its value whether it is in a wide view or a close-up.

5. **Paint.** Each band is filled with a colour from the chosen scale. The ramp is solved for **even L\*** between the scale's two endpoints, not interpolated in sRGB:

   ```
   La, Lz  = L* of the dark and light endpoints
   Lt      = La + (Lz - La) * i/(n-1)                 // target for band i
   s       = (Y(Lt) - Ya) / (Yz - Ya)                 // Y(L) is the inverse of step 3
   rgb_i   = linearRGB endpoints lerped by s, converted back to sRGB
   ```

   Sanity check: on the Graphite scale with n=3, the middle band must come out at sRGB **122,120,120**. If you get ~132 you have interpolated in the wrong space.

### Scales

Four, each a dark and a light endpoint in sRGB:

| Name     | Dark      | Light     |
|----------|-----------|-----------|
| Graphite | `#111010` | `#f8f4f4` |
| Warm     | `#2a0b05` | `#ffe0d9` |
| Cool     | `#0d1520` | `#eef2f7` |
| Sepia    | `#241a10` | `#f6efe2` |

The swatch buttons show each scale as a four-stop linear gradient at 0/25/50/75%.

### View modes

- **Value** — the quantised image.
- **Photo** — the untouched source (still gets the grid).
- **Split** — source on the left of a draggable position, quantised on the right, with a 2px `#ec3013` rule at the boundary. The handle travels the **full width**, edge to edge.
- **Skeleton** — ground filled `#f3f2f2`, then a pixel is drawn `#201e1d` if its band differs from its right or bottom neighbour. Line weight scales with output: `max(1, round(renderWidth/480))` px.

### Value numbers (skeleton mode only)

Connected-component labelling over the band map:

- Downsample the band map by `S = max(8, round(8 * renderWidth/480))`.
- Flood-fill 4-connected regions of equal band.
- Keep regions with area > `(gridW * gridH) / 150`.
- Sort by area, label the largest 16.
- Draw at the region centroid: the band index + 1 (so "1" is darkest), Archivo 700 at `round(21 * renderWidth/480)`px, `#201e1d` fill over a `#f3f2f2` stroke of `7 × scale` px width with round joins.

Centroids can land outside concave regions. It is a known imperfection and a good candidate for improvement (pole of inaccessibility, or the centroid of the largest inscribed rectangle).

### Grid

Off, square or diamond, with a divisions control (2–10). Drawn in **screen space, over everything**, never baked into the processed raster — otherwise it rides the zoom transform and jumps.

- Square: vertical and horizontal rules every `viewportWidth / n`.
- Diamond: rules at ±45°, same spacing.
- Colour `rgba(236,48,19,0.65)`, 2px.

In *exports* the grid is drawn into the image, dividing the exported frame.

### Zoom, and why detail follows it

Pinch and scroll zoom, one-finger pan when zoomed in, range 1×–6×. Double-tap cycles 1× → 2.4× → 4× → 1×, centred on the tap point.

The important behaviour: **zooming resolves finer shapes, without changing the scale.** Because the blur is applied in screen space and the band thresholds are absolute, re-running the pipeline on just the visible crop at full resolution gives more detail exactly where the user is looking, while every value stays exactly where it was.

The HTML prototype fakes this with a CSS transform during the gesture and a re-render 180ms after it settles, because per-pixel work in JavaScript is too slow to run live.

**In Flutter you should not need the settle step.** If the pipeline runs as a fragment shader sampling the decoded image, zoom is just a UV transform and the detail is correct every frame. Getting this genuinely live is the single biggest quality win over the prototype.

### Suggested Flutter implementation

- **Steps 3–5 as a fragment shader** (`FragmentProgram.fromAsset`, GLSL). Uniforms: step count, the `n` ramp colours (or the two endpoints plus solve in-shader), mode, split position, viewport size. Skeleton mode needs four extra texture taps to compare neighbouring bands.
- **Blur** cannot go in the same pass at sigma 16. Pre-render the source through `ImageFilter.blur` into an offscreen `ui.Image` and feed that to the shader as a sampler. Recompute that pass only when detail or zoom changes, not every frame.
- **Value numbers on the CPU.** Run the labelling in an isolate over the downsampled band map and paint the results with a `CustomPainter`. Debounce ~150ms. **Note for PWA:** Flutter web has no real isolates — `compute` runs on the main thread — so on web either accept a hitch, move it to a web worker, or reduce the resolution of the labelling pass.
- **Zoom** with `InteractiveViewer` or a `Matrix4` you own; feed the transform to the shader rather than transforming the widget.
- **Grid** as a `CustomPainter` above the image, in screen coordinates.
- **Verify the shader path early on PWA.** `FragmentProgram` needs CanvasKit/Skwasm; test it in week one, because the fallback (per-pixel Dart on the main thread) would change the design.

---

## Screens

All three phone screens are full-bleed on a `#201e1d` ground. Design size 320 × 664 logical px; scale proportionally.

### 1. Studies (the shelf) — the launch screen

Light screen, ground `#f3f2f2`, text `#201e1d`.

- Status bar row, 46px tall, 18px side padding, time flush left, Archivo 700 11px.
- Title row: "Askance", Archivo 800 26px, letter-spacing −0.02em, flush left; a 28 × 28 outlined `?` button flush right opening onboarding. Bottom border 2px `rgba(32,30,29,0.4)`.
- Scrolling body, 18px side padding, 16px top:
  - Section label "RECENT STUDIES", Archivo 700 9px, letter-spacing 0.16em, uppercase, `rgba(32,30,29,0.5)`, 10px below.
  - Two-column grid, 14px gap. Each card: 2px border `rgba(32,30,29,0.4)` (hover `#ec3013`), background `#eae9e9`, a 4:5 thumbnail rendered **by the engine** using that study's own settings, then a 2px rule and a caption block — name in Archivo 700 11px, meta in Archivo 400 10px `rgba(32,30,29,0.55)` reading `"3 values · grey · 8 Aug"`.
  - One dashed empty slot: 2px dashed `rgba(32,30,29,0.3)`, 45° 6px stripe background at 5% ink, label "empty slot" in 9px monospace.
- Footer, 2px top rule, 14px/18px padding, two 46px full-width buttons with flush-left labels and a trailing `→`: "New study from photos" (solid `#ec3013`, text `#f3f2f2`, hover `#dd2b0f`) and "Take a photo" (2px outline, hover 7% ink tint).

The thumbnails showing the value map rather than the source photograph is deliberate — the shelf shows what you made, not what you started from.

### 2. Canvas — the app

Fullscreen image. Chrome sits over it and can be dismissed entirely.

- **Top bar**, 46px, over a scrim `linear-gradient(180deg, rgba(32,30,29,0.55), transparent)` 62px tall. Back `←` (42 × 32), study name flush left in Archivo 700 10px letter-spacing 0.05em `#f3f2f2` with a text shadow, ellipsised; a share icon button (Lucide `share-2`, 18px, ghost, hover `#ec3013`) at the right.
- **Mode rail**, right edge, 14px inset, 60px from top, 44px wide, ground `#201e1d`, four 44px buttons — VAL / PHOTO / SPLIT / EDGE — Archivo 700 9px letter-spacing 0.06em, divided by 2px `rgba(243,242,242,0.18)`. Active button fills `#ec3013`. In skeleton mode a fifth `№` button appears to toggle value numbers, also filling red when on.
- **Tool bar**, flush to the bottom and both sides, 44px tall, ground `#201e1d`, four equal cells: "{n} VAL", "DETAIL", "SCALE", "GRID". Archivo 700 10px letter-spacing 0.08em. The open tool fills `#ec3013`. Tapping the open tool closes it.
- **Tool panel**, directly above the tool bar, full width, ground `#201e1d`, 2px `#ec3013` top rule, 14px/16px padding. One tool at a time:
  - *Values* — a six-cell segmented control 2…7, 34px tall on a `rgba(243,242,242,0.1)` track, with a red marker that slides between cells over 220ms `cubic-bezier(.2,.8,.2,1)`.
  - *Detail* — a 2px track with a 4px red thumb, drag anywhere on the row; the value 0–100 shown in `#ec3013` at the right of the label line.
  - *Scale* — four 32px gradient swatches, 2px borders, 8px gaps.
  - *Grid* — a three-cell segmented control OFF / SQUARE / DIAMOND with the same sliding marker, plus a `–  n  +` stepper in a 2px outlined box.
- **Split handle** (split mode) — a 44px-wide invisible drag target centred on the boundary, containing a 2px `#ec3013` rule and a 32 × 32 red grip with `◀▶`.
- **Single tap anywhere on the image** fades all chrome out over 220ms; tap again brings it back. **Press and hold** (280ms) peeks the untouched photograph; releasing returns. **Double tap** zooms.

### 3. Onboarding

Ground `#201e1d`, text `#f3f2f2`. Bottom-anchored: content sits at the bottom of the screen, not centred.

- Status row with a flush-right SKIP in Archivo 700 10px `rgba(243,242,242,0.6)`.
- A 44 × 2px `#ec3013` rule, then the title in Archivo 800 34px, line-height 1.05, letter-spacing −0.03em; then body in Archivo 400 14px/1.55 `rgba(243,242,242,0.7)`, max-width 250px.
- Three 2px progress rules across the bottom, filled `#ec3013` up to the current step, otherwise `rgba(243,242,242,0.25)`.
- A 56px full-width `#ec3013` CTA with a flush-left label and trailing `→`.

Copy, verbatim:

1. **Value before colour.** / "Askance flattens a photograph into a handful of values, so you can see the shapes light actually makes. The steps are spaced the way the eye reads them, not the way a camera measures them — so they line up with the value scale on your desk." / *Next*
2. **Look askance.** / "Hold the image to peek at the photo. Split it down the middle. Strip it back to edges and number every value." / *Next*
3. **Grid when you want it.** / "Square or diamond, as fine as you like — then get it out of the way with a single tap." / *Start a study*

### 4. Desktop and web

Designed at 1180 × 760; the rail is fixed and the stage flexes.

- **Left rail**, 284px, ground `#201e1d`, sections divided by 2px `rgba(243,242,242,0.22)` rules:
  - Brand row — "Askance" Archivo 800 22px, and a SHELF button (2px outline, 30px tall).
  - Study block — label "STUDY", the study name on its own line in Archivo 700 14px, then a full-width `#ec3013` SHARE button with a trailing `↗`.
  - View — four 38px full-width flush-left buttons, VALUE MAP / PHOTOGRAPH / SPLIT / SKELETON, active filling red; a fifth indented `№ NUMBER THE REGIONS` appears in skeleton mode.
  - Values, Detail, Root of the scale, Grid — the same controls as the phone, at rail width.
  - Footer line: "{n} studies on the shelf · scroll to zoom · hold to peek", Archivo 400 11px `rgba(243,242,242,0.55)`.
  - **The View→Grid block scrolls**; brand, study and footer are pinned. Necessary — the tallest state overflows 760px.
- **Stage**, ground `#eae9e9`, with the image centred in a 496 × 744 frame with a 2px `rgba(32,30,29,0.4)` border. The image sits *whole on the ground* here rather than filling the frame.
- **Shelf overlay** — SHELF covers the stage with a `#f3f2f2` panel: a "Studies" title row with a `×`, a three-column card grid identical in construction to the phone shelf, and a bottom bar with "New study from an image". Picking a study loads its settings and closes the overlay.

---

## Share, export and the paywall

One action on each surface: SHARE. There is no separate save.

**Sheet contents** (a bottom sheet on phone, a 360px centred dialog on desktop), ground `#201e1d`, 2px `#ec3013` top edge / border:

1. Title "Share this study" (Archivo 800 18px) with a `×`.
2. **Keep on the shelf** — full-width `#ec3013` button with a trailing `★`. Writes the current settings back to the open study, or creates a new one if this study has never been saved. On phone it then returns to the shelf; on desktop it stays put and reports "Saved to the shelf".
3. Size — a two-cell segmented control SCREEN / PRINT, then a note reading "Image size · {dims} · exactly what you see".
   - Screen: 1200 × 1800
   - Print: 2480 × 3720 (300 dpi)
4. **Save image** (outlined) → PNG named `{study-name-slugified}-{W}x{H}.png`.
5. **Print** (outlined) → the same render, at page width.
6. **Copy to clipboard** (outlined) → PNG to the clipboard.
7. A status line in `#ec3013`, Archivo 700 10px uppercase.

Exports re-run the engine at the target size from the **original image** — never an upscale of the screen raster — and honour the current zoom, exporting the passage being studied rather than the whole frame.

### The paywall

**Free forever: everything on the canvas.** Every value count, every scale, detail, grid, split, skeleton, numbers, zoom, peek. No watermark, no timer, no limit.

**£3.99, one payment, no subscription: everything that outlives the session.** Keeping a study on the shelf, and every export.

The unlock lives *inside* the share sheet — there is no separate upsell screen and nothing interrupts the user while working. When locked:

- A block bordered 2px `#ec3013` appears above the options: kicker "ONE PAYMENT · LIFETIME" in `#ec3013` 9px; heading "Keep and export your studies" Archivo 800 17px; body "Looking is free, always. £3.99 unlocks the shelf and every way out of the app."; a full-width `#ec3013` button "Unlock — £3.99" with a trailing `→`; and a quiet "RESTORE PURCHASE" text button.
- The options below drop to 40% opacity but **stay tappable** — tapping a locked option starts the purchase rather than showing an error. This is deliberate: a tap on a locked control is intent to buy.
- While purchasing, the button reads "Confirming…". On success the block disappears and the status line reads "Unlocked — thank you".

**Implementation notes.** Use `in_app_purchase` with a single **non-consumable** product; wire "Restore purchase" properly (required by App Store review). Store the entitlement locally and re-verify on launch.

**The PWA cannot use store IAP.** Options, in order of preference for a first release: keep the web version free as a shop window for the apps; or take web payments (Stripe) and gate on an account, which means building accounts. Do not attempt to share an entitlement across stores without accounts — a one-time purchase does not travel between App Store, Play and web. Charging per store and saying so plainly is the honest first release.

---

## State

Per study (what gets saved to the shelf):

| Field | Type | Default | Range |
|---|---|---|---|
| `steps` | int | 3 | 2–7 |
| `scale` | enum | Graphite | 4 values |
| `detail` | double | 0.5 | 0–1 |
| `mode` | enum | value | value / photo / split / skeleton |
| `grid` | enum | off | off / square / diamond |
| `gridDivisions` | int | 4 | 2–10 |
| `numbers` | bool | true | — |
| `splitPosition` | double | 0.5 | 0–1 |

Plus, not saved: `zoom` / `pan` (view only), `peeking` (transient), `chromeVisible`, `openTool`, `pro` (entitlement).

Shelf entries add `id`, `name`, `date` and a reference to the source image. **The prototype does not persist the source image** — a real implementation must, either by copying it into app storage or by holding a platform image identifier. Copying is safer: photo-library references can be revoked.

---

## Design tokens

**Colour**

| Token | Value | Use |
|---|---|---|
| Ink | `#201e1d` | Chrome ground, dark screens, text on light |
| Ground | `#f3f2f2` | Light screens, text on dark |
| Surface | `#eae9e9` | Card fills, desktop stage |
| Accent | `#ec3013` | Active state, primary action, grid rules, split rule |
| Accent pressed | `#dd2b0f` | Hover / pressed on primary |
| Divider (light) | `rgba(32,30,29,0.4)` | 2px rules on light |
| Divider (dark) | `rgba(243,242,242,0.22)` | 2px rules on dark |
| Muted (light) | `rgba(32,30,29,0.55)` | Secondary text on light |
| Muted (dark) | `rgba(243,242,242,0.5)` | Section labels on dark |

**Type** — Archivo throughout (Google Fonts). Weights 400, 700, 800.

| Role | Spec |
|---|---|
| Screen title | 800 26px / 1, −0.02em |
| Onboarding title | 800 34px / 1.05, −0.03em |
| Sheet title | 800 18px / 1, −0.02em |
| Button label | 800 13–14px / 1 |
| Section label | 700 9px, 0.16em, uppercase |
| Control label | 700 10–11px, 0.06–0.1em |
| Body | 400 12–14px / 1.5 |
| Caption | 400 10–11px / 1.3 |

**Spacing** — 4 / 8 / 12 / 16 / 18 / 22 / 28px. **Radius — 0 everywhere. No exceptions.** **Rules — 2px, never hairlines.**

**Motion**

| What | Spec |
|---|---|
| Segmented marker | `left` 220ms `cubic-bezier(.2,.8,.2,1)` |
| Chrome fade | `opacity` 220ms |
| Sheet slide | `transform` 320ms `cubic-bezier(.2,.8,.2,1)` |
| Long-press to peek | 280ms threshold |
| Double-tap window | 300ms |
| Re-render after gesture | 180ms (should be unnecessary in Flutter) |
| Purchase confirmation | ~900ms simulated |

**Icons** — Lucide. Only `share-2` is used so far.

---

## Assets

- `assets/ref-portrait.jpg` — the reference photograph used throughout, from Unsplash (Filipp Romanovski), downscaled to 900 × 1350. **Prototype only.** Do not ship it; the real app opens the user's own images.
- Archivo, from Google Fonts. Bundle it rather than fetching it at runtime.

No other assets. The design deliberately contains no illustration or iconography beyond the one share glyph.

---

## Files in this bundle

| File | What it is |
|---|---|
| `Askance.dc.html` | The complete prototype. Open in a browser. |
| `support.js` | Runtime the prototype needs. Not part of the design. |
| `assets/ref-portrait.jpg` | The reference photograph. |
| `screens/` | Reference captures of every screen and state, listed below. |

### Screens folder

Phone captures are 648 × 1336 (2× a 324 × 668 card, including its 2px border). Desktop captures are 1180 × 764 at 1×.

| File | State shown |
|---|---|
| `01-shelf.png` | Studies shelf — two saved studies and an empty slot |
| `02-canvas-detail.png` | Canvas, value mode, DETAIL tool open |
| `03-canvas-grid.png` | Canvas with the square grid and the GRID tool open |
| `04-canvas-split.png` | Split mode with the drag handle |
| `05-canvas-skeleton.png` | Skeleton with value numbers, `№` toggle active |
| `06-canvas-clean.png` | All chrome dismissed by a single tap — the resting state |
| `07-onboarding.png` | Onboarding, panel one |
| `08-share-locked.png` | Share sheet with the paywall; options dimmed but still live |
| `09-share-unlocked.png` | Share sheet after purchase |
| `10-desktop.png` | Desktop, value mode |
| `11-desktop-shelf.png` | Desktop shelf overlay |
| `12-desktop-skeleton-diamond.png` | Desktop skeleton with numbers and the diamond grid |

In `10` and `12` the rail's control stack is scrolled — the GRID section sits below the fold in the tallest states. That is intended behaviour, not a crop.

Two details worth reading off the captures rather than the prose: the phone's fullscreen crop is much tighter than the shelf thumbnail's 4:5 (a 320 × 664 viewport crops a 2:3 photograph hard at the sides), and the value numbers in `05` and `12` sit at region centroids, which for concave shapes can land just outside the region they label — the known imperfection noted above.

The processing code lives in the `<script>` block at the end of `Askance.dc.html` — look for `draw()`, `ramp()`, `renderExport()`, `drawNumbers()` and the `lstar` helper at the top. It is readable and worth reading before writing the shader, but it is a reference implementation, not a port target.

## What is not designed yet

- The photo picker. Both shelf CTAs currently jump straight to the canvas.
- Renaming a study.
- Deleting a study.
- Empty state for a shelf with nothing on it.
- Anything offline, sync or account related — deliberately, there is none.
