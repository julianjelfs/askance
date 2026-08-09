#version 460 core
#include <flutter/runtime_effect.glsl>

// Must stay >= kKuwaharaRadius in the engine, which is what the window is
// actually set to; see there for what widening it costs.
#define KUWAHARA_MAX 6

#include <kuwahara_body.glsl>
