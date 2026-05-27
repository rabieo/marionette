

#include <metal_stdlib>
using namespace metal;

#import "Vertex.h"
#import "Lighting.h"

struct GBufferOut {
  float4 albedo [[color(RenderTargetAlbedo)]];
  float4 normal [[color(RenderTargetNormal)]];
  float4 position [[color(RenderTargetPosition)]];
};

// Blender-style procedural grid floor.
// Uses screen-space derivatives so lines stay crisp at any zoom level.
// `worldXZ` is in scene meters; major lines at 1 m, minor at 0.1 m.
static float3 blenderGrid(float2 worldXZ, float distToCamera) {
  // Base ground color (Blender's "Workbench" floor)
  float3 base      = float3(0.270, 0.270, 0.290);
  float3 majorLine = float3(0.440, 0.440, 0.470);
  float3 minorLine = float3(0.330, 0.330, 0.360);
  float3 xAxisCol  = float3(0.700, 0.260, 0.260);  // red — X axis (Blender)
  float3 zAxisCol  = float3(0.350, 0.560, 0.870);  // blue — Y/up in Blender ≈ Z here

  // Major grid (every 1 m)
  float2 d1 = fwidth(worldXZ);
  float2 g1 = abs(fract(worldXZ - 0.5) - 0.5) / d1;
  float majorMask = 1.0 - saturate(min(g1.x, g1.y));

  // Minor grid (every 0.1 m)
  float2 uv2 = worldXZ * 10.0;
  float2 d2  = fwidth(uv2);
  float2 g2  = abs(fract(uv2 - 0.5) - 0.5) / d2;
  float minorMask = 1.0 - saturate(min(g2.x, g2.y));

  // Axis lines (X axis runs along +X with Z=0; Y/up axis line: X=0 column).
  float xAxisMask = 1.0 - saturate(abs(worldXZ.y) / d1.y);
  float zAxisMask = 1.0 - saturate(abs(worldXZ.x) / d1.x);

  float3 col = base;
  col = mix(col, minorLine, minorMask * 0.5);
  col = mix(col, majorLine, majorMask);
  col = mix(col, xAxisCol,  xAxisMask);
  col = mix(col, zAxisCol,  zAxisMask);

  // Distance fade — lines vanish into base as the floor recedes
  float fade = exp(-distToCamera * 0.05);
  col = mix(base, col, fade);
  return col;
}

fragment GBufferOut fragment_gBuffer(
  VertexOut in [[stage_in]],
  depth2d<float> shadowTexture [[texture(ShadowTexture)]],
  constant Material &material [[buffer(MaterialBuffer)]],
  constant uint &materialKind [[buffer(MaterialKindBuffer)]],
  constant Params &params      [[buffer(ParamsBuffer)]])
{
  GBufferOut out;
  if (materialKind == 1) {
    float dist = distance(in.worldPosition, params.cameraPosition);
    out.albedo = float4(blenderGrid(in.worldPosition.xz, dist), 1.0);
  } else {
    out.albedo = float4(material.baseColor, 1.0);
  }
  out.albedo.a = calculateShadow(in.shadowPosition, shadowTexture);
  out.normal = float4(normalize(in.worldNormal), 1.0);
  out.position = float4(in.worldPosition, 1.0);
  return out;
}

constant float3 vertices[6] = {
  float3(-1,  1,  0),    // triangle 1
  float3( 1, -1,  0),
  float3(-1, -1,  0),
  float3(-1,  1,  0),    // triangle 2
  float3( 1,  1,  0),
  float3( 1, -1,  0)
};

vertex VertexOut vertex_quad(uint vertexID [[vertex_id]])
{
  VertexOut out {
    .position = float4(vertices[vertexID], 1)
  };
  return out;
}

fragment float4 fragment_deferredSun(
  VertexOut in [[stage_in]],
  constant Params &params [[buffer(ParamsBuffer)]],
  constant Light *lights [[buffer(LightBuffer)]],
  texture2d<float> albedoTexture [[texture(BaseColor)]],
  texture2d<float> normalTexture [[texture(NormalTexture)]],
  texture2d<float> positionTexture [[texture(NormalTexture + 1)]])
{
  uint2 coord = uint2(in.position.xy);
  float4 albedo = albedoTexture.read(coord);
  float3 normal = normalTexture.read(coord).xyz;
  float3 position = positionTexture.read(coord).xyz;
  Material material {
    .baseColor = albedo.xyz,
    .specularColor = float3(0),
    .shininess = 500
  };
  float3 color = phongLighting(normal, position, params, lights, material);
  color *= albedo.a;
  return float4(acesTonemap(color), 1);
}

struct PointLightIn {
  float4 position [[attribute(Position)]];
};

struct PointLightOut {
  float4 position [[position]];
  uint instanceId [[flat]];
};

vertex PointLightOut vertex_pointLight(
  PointLightIn in [[stage_in]],
  constant Uniforms &uniforms [[buffer(UniformsBuffer)]],
  constant Light *lights [[buffer(LightBuffer)]],
  // 1
  uint instanceId [[instance_id]])
{
  // 2
  float4 lightPosition = float4(lights[instanceId].position, 0);
  float4 position =
    uniforms.projectionMatrix * uniforms.viewMatrix
  // 3
    * (in.position + lightPosition);
  PointLightOut out {
    .position = position,
    .instanceId = instanceId
  };
  return out;
}

fragment float4 fragment_pointLight(
  PointLightOut in [[stage_in]],
  texture2d<float> normalTexture [[texture(NormalTexture)]],
  texture2d<float> positionTexture
    [[texture(NormalTexture + 1)]],
  constant Light *lights [[buffer(LightBuffer)]])
{
  Light light = lights[in.instanceId];
  uint2 coords = uint2(in.position.xy);
  float3 normal = normalTexture.read(coords).xyz;
  float3 position = positionTexture.read(coords).xyz;
  
  Material material {
    .baseColor = 1
  };
  float3 lighting =
    calculatePoint(light, position, normal, material);
  lighting *= 0.5;
  // Additive blending: framebuffer is .bgra8Unorm_srgb so the HW decodes the
  // existing sun pass back to linear before adding. Tonemapping per-pass is
  // technically wrong (ideal: ACES(sun + points)) but visually acceptable.
  return float4(acesTonemap(lighting), 1);
}

// MARK: - Tiling functions

fragment float4 fragment_tiled_deferredSun(
  VertexOut in [[stage_in]],
  constant Params &params [[buffer(ParamsBuffer)]],
  constant Light *lights [[buffer(LightBuffer)]],
  GBufferOut gBuffer)
{
  float4 albedo = gBuffer.albedo;
  float3 normal = gBuffer.normal.xyz;
  float3 position = gBuffer.position.xyz;
  Material material {
    .baseColor = albedo.xyz,
    .specularColor = float3(0),
    .shininess = 500
  };
  float3 color = phongLighting(normal, position, params, lights, material);
  color *= albedo.a;
  return float4(acesTonemap(color), 1);
}

fragment float4 fragment_tiled_pointLight(
  PointLightOut in [[stage_in]],
  constant Light *lights [[buffer(LightBuffer)]],
  GBufferOut gBuffer)
{
  Light light = lights[in.instanceId];
  float3 normal = gBuffer.normal.xyz;
  float3 position = gBuffer.position.xyz;

  Material material {
    .baseColor = 1
  };
  float3 lighting =
    calculatePoint(light, position, normal, material);
  lighting *= 0.5;
  return float4(acesTonemap(lighting), 1);
}
