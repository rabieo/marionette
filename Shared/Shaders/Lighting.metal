

#include <metal_stdlib>
using namespace metal;

#import "Lighting.h"

float3 calculateSun(
                    Light light,
                    float3 normal,
                    Params params,
                    Material material)
{
  float3 diffuseColor = 0;
  float3 specularColor = 0;
  float3 lightDirection = normalize(-light.position);
  float diffuseIntensity =
    saturate(-dot(lightDirection, normal));
  diffuseColor += light.color * material.baseColor * diffuseIntensity;
  if (diffuseIntensity > 0) {
    float3 reflection =
        reflect(lightDirection, normal);
    float3 viewDirection =
        normalize(params.cameraPosition);
    float specularIntensity =
        pow(saturate(dot(reflection, viewDirection)),
            material.shininess);
    specularColor +=
        light.specularColor * material.specularColor
          * specularIntensity;
  }
  return diffuseColor + specularColor;
}

float3 calculatePoint(
  Light light,
  float3 position,
  float3 normal,
  Material material)
{
  float d = distance(light.position, position);
  float3 lightDirection = normalize(light.position - position);
  float attenuation = 1.0 / (light.attenuation.x +
      light.attenuation.y * d + light.attenuation.z * d * d);

  float diffuseIntensity =
      saturate(dot(lightDirection, normal));
  float3 color = light.color * material.baseColor * diffuseIntensity;
  color *= attenuation;
  return color;
}

float3 calculateSpot(
  Light light,
  float3 position,
  float3 normal,
  Material material)
{
  float d = distance(light.position, position);
  float3 lightDirection = normalize(light.position - position);
  float3 coneDirection = normalize(light.coneDirection);
  float spotResult = dot(lightDirection, -coneDirection);
  float3 color =  0;
  if (spotResult > cos(light.coneAngle)) {
    float attenuation = 1.0 / (light.attenuation.x +
        light.attenuation.y * d + light.attenuation.z * d * d);
    attenuation *= pow(spotResult, light.coneAttenuation);
    float diffuseIntensity =
             saturate(dot(lightDirection, normal));
    color = light.color * material.baseColor * diffuseIntensity;
    color *= attenuation;
  }
  return color;
}

float3 phongLighting(
  float3 normal,
  float3 position,
  constant Params &params,
  constant Light *lights,
  Material material)
{
  float3 ambientColor = 0;
  float3 accumulatedLighting = 0;
  
  for (uint i = 0; i < params.lightCount; i++) {
    Light light = lights[i];
    switch (light.type) {
      case Sun: {
        accumulatedLighting += calculateSun(light, normal, params, material);
        break;
      }
      case Point: {
        accumulatedLighting += calculatePoint(light, position, normal, material);
        break;
      }
      case Spot: {
        accumulatedLighting += calculateSpot(light, position, normal, material);
        break;
      }
      case Ambient: {
        ambientColor += material.baseColor * light.color;
        break;
      }
      case unused: {
        break;
      }
    }
  }
  float3 color = accumulatedLighting + ambientColor;
  return color;
}

float calculateShadow(
  float4 shadowPosition,
  depth2d<float> shadowTexture)
{
  // shadow calculation
  float3 position
    = shadowPosition.xyz / shadowPosition.w;
  float2 xy = position.xy;
  xy = xy * 0.5 + 0.5;
  xy.y = 1 - xy.y;
  constexpr sampler s(
    coord::normalized, filter::nearest,
    address::clamp_to_edge,
    compare_func:: less);
  float shadow_sample = shadowTexture.sample(s, xy);
  return (position.z > shadow_sample + 0.001) ? 0.5 : 1;
}

