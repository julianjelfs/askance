#version 460 core
#include <flutter/runtime_effect.glsl>

// The photograph, as PHOTO shows it: optionally in black and white, with
// brightness and contrast. askance.frag bands the photograph through the
// same curve, so the value map is made from what this shows.
//
// Black and white is CIE L*, the lightness the value map quantises, rather
// than a luma of the gamma-encoded channels, so a passage that reads as a
// middle grey here falls in the middle band there.

uniform vec2 uOrigin;     // destination rect of the picture, top-left
uniform vec2 uSize;       // and size, in the same space as FlutterFragCoord
uniform vec4 uCrop;       // the crop, as fractions of the source: l, t, r, b
uniform float uMono;      // 1 = black and white
uniform float uBrightness;// -1..1
uniform float uContrast;  // -1..1

uniform sampler2D uSrc;

out vec4 fragColor;

float lstar(vec3 c) {
  vec3 lin = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
  float y = dot(lin, vec3(0.2126, 0.7152, 0.0722));
  return y > 0.008856 ? 116.0 * pow(y, 1.0 / 3.0) - 16.0 : 903.3 * y;
}

// L* (0..100) back to a gamma-encoded grey.
float greyOfLstar(float l) {
  float y = l > 8.0 ? pow((l + 16.0) / 116.0, 3.0) : l / 903.3;
  return y <= 0.0031308 ? y * 12.92 : 1.055 * pow(y, 1.0 / 2.4) - 0.055;
}

// Contrast pivots on the middle; full travel either way is 4x steeper or
// flatter. Brightness slides by up to half the range.
float tone(float v) {
  float k = pow(4.0, uContrast);
  return clamp((v - 0.5) * k + 0.5 + uBrightness * 0.5, 0.0, 1.0);
}

void main() {
  vec2 uv = (FlutterFragCoord().xy - uOrigin) / uSize;
  vec3 c = texture(uSrc, mix(uCrop.xy, uCrop.zw, uv)).rgb;
  if (uMono > 0.5) {
    float g = greyOfLstar(tone(lstar(c) / 100.0) * 100.0);
    fragColor = vec4(vec3(g), 1.0);
  } else {
    fragColor = vec4(tone(c.r), tone(c.g), tone(c.b), 1.0);
  }
}
