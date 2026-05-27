

// swiftlint:disable force_unwrapping

import MetalKit

struct SceneLighting {
  static func buildDefaultLight() -> Light {
    var light = Light()
    light.position = [0, 0, 0]
    light.color = float3(repeating: 1.0)
    light.specularColor = float3(repeating: 0.6)
    light.attenuation = [1, 0, 0]
    light.type = Sun
    return light
  }

  /// Blender-style three-point rig.
  /// - Key: warm sun from upper-front-right (casts shadow — must be lights[0]).
  /// - Fill: cool dim sun from upper-front-left to lift shadow side.
  /// - Rim: bluish sun from behind-above to outline silhouettes.
  /// - Ambient: slightly sky-tinted base.

  let keyLight: Light = {
    var light = Self.buildDefaultLight()
    light.position = [3.5, 4.0, 2.0]               // upper-front-right
    light.color = [1.00, 0.96, 0.88]                // warm ~5500 K
    light.specularColor = [0.95, 0.92, 0.85]
    return light
  }()

  let fillLight: Light = {
    var light = Self.buildDefaultLight()
    light.position = [-3.0, 3.0, 2.5]               // upper-front-left
    light.color = [0.18, 0.21, 0.26]                // cool, ~30% intensity
    light.specularColor = [0.05, 0.07, 0.10]
    return light
  }()

  let rimLight: Light = {
    var light = Self.buildDefaultLight()
    light.position = [0.0, 3.5, -3.0]               // behind-above
    light.color = [0.16, 0.19, 0.25]                // bluish, ~25% intensity
    light.specularColor = [0.20, 0.24, 0.32]        // crisper rim highlight
    return light
  }()

  let ambientLight: Light = {
    var light = Self.buildDefaultLight()
    light.color = [0.10, 0.11, 0.14]                // sky-tinted ambient
    light.type = Ambient
    return light
  }()

  var lights: [Light] = []
  var sunlights: [Light]
  var pointLights: [Light]
  var lightsBuffer: MTLBuffer
  var sunBuffer: MTLBuffer
  var pointBuffer: MTLBuffer

  init() {
    // Order matters: lights[0] is what the shadow camera uses (Renderer.swift).
    sunlights = [keyLight, fillLight, rimLight, ambientLight]
    sunBuffer = Self.createBuffer(lights: sunlights)
    lights = sunlights
    pointLights = Self.createPointLights(
      count: 40,
      min: [-6, 0.1, -6],
      max: [6, 0.3, 6])
    pointBuffer = Self.createBuffer(lights: pointLights)
    lights += pointLights
    lightsBuffer = Self.createBuffer(lights: lights)
  }

  static func createBuffer(lights: [Light]) -> MTLBuffer {
    var lights = lights
    return Renderer.device.makeBuffer(
      bytes: &lights,
      length: MemoryLayout<Light>.stride * lights.count,
      options: [])!
  }

  static func createPointLights(count: Int, min: float3, max: float3) -> [Light] {
    let colors: [float3] = [
      float3(1, 0, 0),
      float3(1, 1, 0),
      float3(1, 1, 1),
      float3(0, 1, 0),
      float3(0, 1, 1),
      float3(0, 0, 1),
      float3(0, 1, 1),
      float3(1, 0, 1)
    ]
    var lights: [Light] = []
    for _ in 0..<count {
      var light = Self.buildDefaultLight()
      light.type = Point
      let x = Float.random(in: min.x...max.x)
      let y = Float.random(in: min.y...max.y)
      let z = Float.random(in: min.z...max.z)
      light.position = [x, y, z]
      light.color = colors[Int.random(in: 0..<colors.count)]
      light.attenuation = [0.2, 10, 50]
      lights.append(light)
    }
    return lights
  }
}
