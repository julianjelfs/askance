#version 460 core
#include <flutter/runtime_effect.glsl>

// Kuwahara: the other way to simplify a photograph into shapes.
//
// A Gaussian softens everything equally, so as the detail comes down the
// boundaries drift away from where they actually are in the photograph. This
// looks at four overlapping quadrants around each pixel and takes the mean of
// whichever is flattest, so a pixel next to an edge is filled from its own
// side of it. Regions go flat; the edges between them stay put.
//
// The pass runs on a downscaled copy — the shapes are meant to be coarse, so
// there is nothing to gain from doing it at full resolution, and the cost of
// the window goes with the square of its radius.

uniform vec2 uSize;    // size of the rect being drawn, in its own pixels
uniform float uRadius; // quadrant radius, same pixels, at most kMaxRadius

uniform sampler2D uSrc;

out vec4 fragColor;

// Luma is enough to decide which quadrant is flattest; the value the pipeline
// actually reads is computed in L* later, from the colour this returns.
float luma(vec3 c) {
  return dot(c, vec3(0.299, 0.587, 0.114));
}

void main() {
  vec2 texel = 1.0 / uSize;
  vec2 here = FlutterFragCoord().xy;

  vec3 flattest = texture(uSrc, here * texel).rgb;
  float lowest = 1e9;

  for (int q = 0; q < 4; q++) {
    // The four quadrants overlap on the pixel itself.
    vec2 towards = vec2(
      (q == 0 || q == 3) ? -1.0 : 1.0,
      (q < 2) ? -1.0 : 1.0
    );

    vec3 sum = vec3(0.0);
    float sumSquares = 0.0;
    float count = 0.0;

    // Constant bounds so the loop unrolls; uRadius decides how much of it
    // actually contributes.
    for (int i = 0; i <= 6; i++) {
      if (float(i) > uRadius) continue;
      for (int j = 0; j <= 6; j++) {
        if (float(j) > uRadius) continue;
        vec2 at = here + vec2(float(i) * towards.x, float(j) * towards.y);
        vec3 c = texture(uSrc, clamp(at * texel, vec2(0.0), vec2(1.0))).rgb;
        sum += c;
        float l = luma(c);
        sumSquares += l * l;
        count += 1.0;
      }
    }

    vec3 mean = sum / count;
    float meanLuma = luma(mean);
    float variance = sumSquares / count - meanLuma * meanLuma;
    if (variance < lowest) {
      lowest = variance;
      flattest = mean;
    }
  }

  fragColor = vec4(flattest, 1.0);
}
