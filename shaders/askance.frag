#version 460 core
#include <flutter/runtime_effect.glsl>

// Askance value engine.
//
// Samples a pre-blurred, already-cropped copy of the source (blur is the
// "detail" control and must happen in screen space, so it is done on the
// Flutter side into an offscreen image of exactly the output resolution).
// This pass does steps 3-5 of the pipeline: sRGB -> CIE L*, absolute
// quantisation into `uSteps` bands, then paint from a ramp solved for even
// L* on the CPU and handed in as uC0..uC6.

uniform vec2 uSize;      // logical size of the drawn rect
uniform vec2 uOrigin;    // its top-left, in the same space as FlutterFragCoord
uniform vec2 uDevice;    // the same rect in output pixels
uniform float uSteps;    // 2..7
uniform float uMode;     // 0 = value map, 1 = skeleton
uniform float uLineWidth;// skeleton stroke, output px
uniform float uBias;     // slides every threshold together, in L*/100

uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
uniform vec3 uC4;
uniform vec3 uC5;
uniform vec3 uC6;

// Skeleton only: how many bands, counted from the darkest, are filled with
// their ramp colour. The rest stay ground — the untouched paper of a real
// painting blocked in dark-first.
uniform float uFill;

// The photograph is banded as PHOTO shows it: brightness and contrast, on
// the lightness in black and white and on each channel in colour. Off for
// BLOCK, whose pass is already its bands' greys.
uniform float uTone;      // 1 = apply
uniform float uToneMono;  // 1 = black and white
uniform float uBrightness;// -1..1
uniform float uContrast;  // -1..1

uniform sampler2D uSrc;

out vec4 fragColor;

const vec3 SKELETON_GROUND = vec3(243.0, 242.0, 242.0) / 255.0;
const vec3 SKELETON_INK = vec3(32.0, 30.0, 29.0) / 255.0;

vec3 rampAt(float i) {
  if (i < 0.5) return uC0;
  if (i < 1.5) return uC1;
  if (i < 2.5) return uC2;
  if (i < 3.5) return uC3;
  if (i < 4.5) return uC4;
  if (i < 5.5) return uC5;
  return uC6;
}

// sRGB -> CIE L*, 0..100. Not a luma shortcut: L* tracks Munsell value, which
// is the whole point of the tool.
float lstar(vec3 c) {
  vec3 lin = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
  float y = dot(lin, vec3(0.2126, 0.7152, 0.0722));
  return y > 0.008856 ? 116.0 * pow(y, 1.0 / 3.0) - 16.0 : 903.3 * y;
}

// The tone curve, as photo.frag and PhotoTone.curve have it.
float tone(float v) {
  float k = pow(4.0, uContrast);
  return clamp((v - 0.5) * k + 0.5 + uBrightness * 0.5, 0.0, 1.0);
}

// Thresholds are absolute, never derived from what happens to be on screen,
// so a pixel keeps its value between a wide view and a close-up.
float bandAt(vec2 devPx) {
  vec3 c = texture(uSrc, devPx / uDevice).rgb;
  float l;
  if (uTone < 0.5) {
    l = lstar(c);
  } else if (uToneMono > 0.5) {
    l = tone(lstar(c) / 100.0) * 100.0;
  } else {
    l = lstar(vec3(tone(c.r), tone(c.g), tone(c.b)));
  }
  // uBias slides the whole ladder of thresholds at once. The steps stay
  // evenly spaced in L*, so a value still means the same thing; it only
  // decides which side of a boundary a borderline passage falls on.
  return clamp(
    floor((l / 100.0 + uBias) * uSteps),
    0.0,
    uSteps - 1.0
  );
}

void main() {
  // The rect is only the part of the frame the photograph occupies, so
  // fragment coordinates have to be made relative to it before they mean
  // anything to the sampler.
  vec2 devPx = (FlutterFragCoord().xy - uOrigin) / uSize * uDevice;

  if (uMode > 0.5) {
    // Ink a pixel if any of the uLineWidth pixels to its left sits on a band
    // boundary, which grows the 1px edge rightwards exactly as the reference
    // implementation does. Bound is constant so the loop unrolls.
    bool ink = false;
    for (int k = 0; k < 8; k++) {
      if (float(k) >= uLineWidth) continue;
      vec2 p = devPx - vec2(float(k), 0.0);
      float b = bandAt(p);
      if (b != bandAt(p + vec2(1.0, 0.0)) || b != bandAt(p + vec2(0.0, 1.0))) {
        ink = true;
      }
    }
    float band = bandAt(devPx);
    vec3 base = band < uFill - 0.5 ? rampAt(band) : SKELETON_GROUND;
    fragColor = vec4(ink ? SKELETON_INK : base, 1.0);
    return;
  }

  fragColor = vec4(rampAt(bandAt(devPx)), 1.0);
}
