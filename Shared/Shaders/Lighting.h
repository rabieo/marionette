

#ifndef Lighting_h
#define Lighting_h

#import "Common.h"

float3 phongLighting(
  float3 normal,
  float3 position,
  constant Params &params,
  constant Light *lights,
  Material material);

float calculateShadow(
  float4 shadowPosition,
  depth2d<float> shadowTexture);

float3 calculateSun(
  Light light,
  float3 normal,
  Params params,
  Material material);

float3 calculatePoint(
  Light light,
  float3 position,
  float3 normal,
  Material material);

float3 calculateSpot(
  Light light,
  float3 position,
  float3 normal,
  Material material);

float calculateShadow(
  float4 shadowPosition,
  depth2d<float> shadowTexture);

/// ACES filmic tone map. Maps HDR linear → display-referred linear [0,1].
/// Pair with a .bgra8Unorm_srgb framebuffer so the hardware applies the
/// sRGB encode for free.
float3 acesTonemap(float3 hdr);

#endif /* Lighting_h */
