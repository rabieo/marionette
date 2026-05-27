

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

  let sunlight: Light = {
    var light = Self.buildDefaultLight()
    light.position = [3, 3, -2]
    light.color = float3(repeating: 1)
    return light
  }()

  let ambientLight: Light = {
    var light = Self.buildDefaultLight()
    light.color = float3(repeating: 0.1)
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
    sunlights = [sunlight, ambientLight]
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
