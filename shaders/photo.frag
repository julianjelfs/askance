#version 460 core
#include <flutter/runtime_effect.glsl>

// The photograph, as PHOTO shows it: in colour or black and white, through
// the study's tone curve, the same curve askance.frag bands it through. So the
// lightness of every pixel here is the lightness the value map quantises.
//
// Black and white is CIE L*, not a luma of the gamma-encoded channels, and
// colour keeps each pixel's hue and saturation while scaling its light to
// the toned lightness, so a passage that reads as a middle grey here falls in
// the middle band there.

uniform vec2 uOrigin;     // destination rect of the picture, top-left
uniform vec2 uSize;       // and size, in the same space as FlutterFragCoord
uniform vec4 uCrop;       // the crop, as fractions of the source: l, t, r, b
uniform float uMono;      // 1 = black and white
uniform float uShift;     // the study's bias, in L*/100
uniform float uContrast;  // -1..1

uniform sampler2D uSrc;

out vec4 fragColor;

vec3 linear(vec3 c) {
  return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 encoded(vec3 lin) {
  return mix(lin * 12.92, 1.055 * pow(lin, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), lin));
}

float luminance(vec3 lin) {
  return dot(lin, vec3(0.2126, 0.7152, 0.0722));
}

float lstarOfY(float y) {
  return y > 0.008856 ? 116.0 * pow(y, 1.0 / 3.0) - 16.0 : 903.3 * y;
}

float yOfLstar(float l) {
  return l > 8.0 ? pow((l + 16.0) / 116.0, 3.0) : l / 903.3;
}

// Contrast pivots on the middle; full travel either way is 4x steeper or
// flatter. The shift slides every value, as the study's bias does.
float tone(float v) {
  float k = pow(4.0, uContrast);
  return clamp((v - 0.5) * k + 0.5 + uShift, 0.0, 1.0);
}

void main() {
  vec2 uv = (FlutterFragCoord().xy - uOrigin) / uSize;
  vec3 lin = linear(texture(uSrc, mix(uCrop.xy, uCrop.zw, uv)).rgb);
  float y = luminance(lin);
  float toned = yOfLstar(tone(lstarOfY(y) / 100.0) * 100.0);
  if (uMono > 0.5 || y <= 0.0) {
    fragColor = vec4(encoded(vec3(toned)), 1.0);
    return;
  }
  // Scaled to the toned light, a saturated colour can run past full in a
  // channel. What clipping loses is made up by mixing towards white, which
  // adds light without moving the hue, so the lightness is still exact.
  vec3 c = clamp(lin * (toned / y), 0.0, 1.0);
  float yc = luminance(c);
  if (yc < toned && yc < 1.0) {
    c += (1.0 - c) * ((toned - yc) / (1.0 - yc));
  }
  fragColor = vec4(encoded(c), 1.0);
}
