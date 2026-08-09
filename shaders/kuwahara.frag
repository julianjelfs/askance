#version 460 core
#include <flutter/runtime_effect.glsl>

// The shipping path. A small window on a downscaled copy; unrolls.
#define KUWAHARA_MAX 6

#include <kuwahara_body.glsl>
