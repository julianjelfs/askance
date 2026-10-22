# Askance — a value-study tool for artists

Askance takes a photograph and flattens it into a small number of values
(2–7), so an artist can see the shapes that light makes without being
distracted by colour or detail. It is a viewing instrument, not an editor: the
image is always fullscreen, the controls are unobtrusive, and there is nothing
to save except the settings you arrived at.

One Flutter codebase; runs on Android, iOS, macOS and the web. A phone layout
and a desktop/web layout share every control.

A build of the web version is published at
<https://askance.julianjelfs.co.uk/> and installs as a PWA that opens
offline. The web build works everywhere but renders noticeably slower than a
device build — the engine leans on GPU round trips that WebGL makes expensive.

## What it does

- **Value map.** The photograph quantised to 2–7 values, spaced the way the
  eye reads them rather than the way a camera measures them, so they line up
  with the printed value scale on an artist's desk.
- **Five ways of looking.** Values (the value map), Photo (the source, in
  colour or black and white with brightness and contrast), Split (photograph
  on one side of a draggable rule, the processed image on the other — laid
  over whichever colouring was showing when you entered it), Random (see
  below), and Edges (the skeleton: just the boundaries between values, with
  the darkest values blocked in on request).
- **Random mode.** Each value band is painted an arbitrary hue *of exactly the
  correct value* — convert the result to greyscale and you get the value map
  back. Tapping Random again deals another palette. It exists to make one point
  viscerally: if the values are right, the colours can be almost anything.
- **Detail control with two characters.** A screen-space blur decides how much
  merges (so zooming in resolves finer shapes without moving any value);
  Smooth leaves it at that, Rough follows with a Kuwahara pass that turns soft
  gradients back into flat patches with definite edges, and Block traces every
  boundary and pulls it straight, for blocking in a drawing.
- **Stages.** Six quick picks that set values and detail together, from a
  two-value block-in to a finished study. Set either by hand and no stage is
  picked; nothing else depends on them.
- **Palette numbered in Munsell values.** Every colour the picture is painted
  in, labelled V1–V9 the way a printed value scale is; tap one to see where
  it falls on its own.
- **Bias.** Slides every threshold together, so a borderline passage can be
  pushed to one side of a boundary or the other — what an under- or
  over-exposed photograph needs.
- **Root of the scale.** Neutral grey, or a tint of any hue, picked from a
  continuous strip. Moving the tint never moves a value.
- **Grid** (the picture halved 1–4 times, with or without diagonals), pinch/scroll **zoom** to 6×,
  press-and-hold **peek** at the photograph, and a **shelf** of saved studies,
  each remembered with its settings, its crop and its source image.
- **Share.** Save, print or copy a PNG at screen (1200×1800) or print
  (2480×3720) size. Exports re-run the engine from the original image at the
  target size — never an upscale of the screen — and honour the current zoom.

### Free, everywhere

The whole app is free: every mode, every control, every export, no watermark,
no accounts, no payments. A photograph you open lands on the shelf
immediately — there is no separate keep step — and the share sheet is purely
about the ways out: an image file, a print, the clipboard, another device.

The web build counts visits and a handful of named events (a photograph
opened, the sample opened, an export saved, copied or printed, a study
received, the app installed) with GoatCounter, which sets no cookies.
`lib/analytics/` takes nothing but an event name, so no image, filename or
setting can be sent. The native apps count nothing.

## The engine

The heart of the app; everything else is chrome around it. The full story is
told in comments in `lib/engine/` and `shaders/`, but the invariants are:

1. **Blur in screen space** (`engine.dart`). Sigma ramps geometrically with
   the detail control — blur reads logarithmically, so a linear ramp wastes
   half the slider — and scales with render width so shapes are the same at
   any resolution. ROUGH adds a Kuwahara pass over the blurred result.
2. **Lightness is CIE L\*** (`lstar.dart`), computed from linear-light RGB.
   Never a luma of the gamma-encoded channels: L\* ≈ 10 × Munsell value,
   which is the single most important correctness property in the app.
3. **Quantise absolutely** (`shaders/askance.frag`). `floor((L*/100 + bias) ×
   steps)`, thresholds never derived from the histogram of what is on screen,
   so a pixel keeps its value whether it is in a wide view or a close-up.
4. **Paint from a ramp solved for even L\*** (`value_scale.dart`). The grey
   ramp interpolates the graphite endpoints in linear light to hit each L\*
   target; sanity check: grey at 3 steps must give a middle band of sRGB
   122,120,120 (interpolating in the wrong space gives ~132). A tinted ramp
   gives every band a fixed share of the gamut's chroma at that band's own
   luminance, so colour peaks in the middle values and tapers into the
   endpoints. Every scale shares the same L\* targets, which is why changing
   the tint never changes a value. The random ramp (`random_ramp.dart`) picks
   a hue and chroma per band by the same constant-luminance construction.

Steps 2–4 run as a fragment shader over the pre-blurred offscreen. The value
numbers run on the CPU (`regions.dart`): connected-component labelling over a
downsampled band map, mirroring the shader's quantisation exactly, debounced
so a gesture never waits for it.

## Developing

`make help` lists everything; the Makefile's comments explain the flags. The
short version:

| Command            | What                                            |
| ------------------ | ----------------------------------------------- |
| `make web`         | hot-reload session in Chrome                    |
| `make android`     | hot-reload session on the attached Android      |
| `make iphone`      | hot-reload session on the attached iPhone       |
| `make check`       | format, analyze, test — run before committing   |
| `make ship-android`| release APK, installed on the device            |
| `make deploy-web`  | build and publish the GitHub Pages site         |
| `make og-image`    | regenerate the link-preview card                |

The Pages site lives in a separate public repository (`askance-web`) holding
only compiled output, because GitHub's free plan will not serve Pages from a
private repository; this repository stays private and is the only source of
truth.

`web/index.html` carries Open Graph tags for link previews and a short
description for search engines, which otherwise see an empty canvas. The
description is visually hidden: the app's own splash and tour are the
introduction. Offline support is `web/sw.js`, not Flutter's
deprecated worker: `tool/stamp-sw.sh` writes a hash of the build into it on
every web build, which gives each deploy its own cache.

Release Android builds are signed with an upload key held outside the
repository, with its passwords in `android/key.properties` (gitignored). A
machine without either still builds — release falls back to the debug key,
which installs on a device but cannot go to Play.

## Design reference

`design/` holds the original HTML design handoff: a working prototype
(`Askance.dc.html`) and reference captures of every screen, in the first
visual language (Modernist: flat, zero radius, 2px rules, Archivo). The app
has since moved to *Gesso*, defined in `lib/theme.dart`: gesso-white panels,
graphite chrome and type, one cadmium accent, Bricolage Grotesque, rounded
controls, and the picture shown on a Munsell value 5 surround — the neutral
grey a value is judged against. The handoff is history now; where they
disagree, the code is the product.
