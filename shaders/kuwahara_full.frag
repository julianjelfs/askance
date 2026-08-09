#version 460 core
#include <flutter/runtime_effect.glsl>

// The unoptimised path: full resolution, window wide enough to cover the
// ground the sigma would have. 4 * 33 * 33 texture reads per pixel at the
// limit. Here to be judged and measured, not to ship.
#define KUWAHARA_MAX 32

#include <kuwahara_body.glsl>
