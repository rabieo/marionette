/// Copyright (c) 2022 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import MetalKit

struct GameScene {
  static var objectId: UInt32 = 1
  let kinematics = RobotKinematics()

  // Robot part model index → joint level (0-5), -1 = static
  private var robotPartJoints: [(index: Int, level: Int)] = []
  // Home model matrices captured at init
  private var homeMatrices: [Int: float4x4] = [:]

  // Robot arm parts — transforms from URDF kinematic chain (Z-up → Y-up)
  lazy var basePart: Model = {
    var m = Model(name: "Base_SO101.stl")
    m.materialOverride = Material(
      baseColor: [0.25, 0.25, 0.28], specularColor: [0.8, 0.8, 0.8],
      roughness: 0.4, metallic: 0.7, ambientOcclusion: 1, shininess: 50)
    m.scale = 0.0040
    m.position = [-0.0255, -0.0096, 0.0000]
    m.rotation = [2.35619, 1.57079, -2.35619]
    return m
  }()
  lazy var baseMotorHolder: Model = {
    var m = Model(name: "Base_motor_holder_SO101.stl")
    m.materialOverride = Material(
      baseColor: [0.27, 0.51, 0.71], specularColor: [0.8, 0.8, 0.8],
      roughness: 0.4, metallic: 0.5, ambientOcclusion: 1, shininess: 40)
    m.scale = 0.0040
    m.position = [-0.0255, -0.0096, 0.0004]
    m.rotation = [2.35619, 1.57079, -2.35619]
    return m
  }()
  lazy var motorHolderBase: Model = {
    var m = Model(name: "Motor_holder_SO101_Base.stl")
    m.materialOverride = Material(
      baseColor: [0.8, 0.4, 0.1], specularColor: [0.9, 0.6, 0.3],
      roughness: 0.5, metallic: 0.3, ambientOcclusion: 1, shininess: 30)
    m.scale = 0.0040
    m.position = [0.4257, 0.1862, 0.0007]
    m.rotation = [0.00000, -0.00000, -1.57079]
    return m
  }()
  lazy var motorHolderWrist: Model = {
    var m = Model(name: "Motor_holder_SO101_Wrist.stl")
    m.materialOverride = Material(
      baseColor: [0.8, 0.4, 0.1], specularColor: [0.9, 0.6, 0.3],
      roughness: 0.5, metallic: 0.3, ambientOcclusion: 1, shininess: 30)
    m.scale = 0.0040
    m.position = [0.6483, 0.7887, 0.0011]
    m.rotation = [-0.00000, 0.00001, -3.14159]
    return m
  }()
  lazy var rotationPitch: Model = {
    var m = Model(name: "Rotation_Pitch_SO101.stl")
    m.materialOverride = Material(
      baseColor: [0.0, 0.59, 0.53], specularColor: [0.5, 0.8, 0.75],
      roughness: 0.4, metallic: 0.4, ambientOcclusion: 1, shininess: 40)
    m.scale = 0.0040
    m.position = [0.1065, 0.0640, -0.0001]
    m.rotation = [-3.14159, -0.00000, -3.14159]
    return m
  }()
  lazy var upperArm: Model = {
    var m = Model(name: "Upper_arm_SO101.stl")
    m.materialOverride = Material(
      baseColor: [0.85, 0.65, 0.13], specularColor: [1.0, 0.84, 0.0],
      roughness: 0.3, metallic: 0.6, ambientOcclusion: 1, shininess: 60)
    m.scale = 0.0040
    m.position = [0.2289, 0.7267, 0.0003]
    m.rotation = [0.00000, 0.00001, -1.57079]
    return m
  }()
  lazy var underArm: Model = {
    var m = Model(name: "Under_arm_SO101.stl")
    m.materialOverride = Material(
      baseColor: [0.72, 0.07, 0.12], specularColor: [0.9, 0.3, 0.3],
      roughness: 0.4, metallic: 0.4, ambientOcclusion: 1, shininess: 40)
    m.scale = 0.0040
    m.position = [0.6483, 0.7887, 0.0003]
    m.rotation = [0.00001, 0.00001, 3.14159]
    return m
  }()
  lazy var wristRoll: Model = {
    var m = Model(name: "Wrist_Roll_SO101.stl")
    m.materialOverride = Material(
      baseColor: [0.5, 0.0, 0.5], specularColor: [0.7, 0.3, 0.7],
      roughness: 0.4, metallic: 0.4, ambientOcclusion: 1, shininess: 40)
    m.scale = 0.0040
    m.position = [1.1691, 0.9374, 0.0016]
    m.rotation = [-2.65842, 1.57078, -2.00528]
    return m
  }()
  lazy var wristRollPitch: Model = {
    var m = Model(name: "Wrist_Roll_Pitch_SO101.stl")
    m.materialOverride = Material(
      baseColor: [0.53, 0.81, 0.92], specularColor: [0.7, 0.9, 1.0],
      roughness: 0.3, metallic: 0.3, ambientOcclusion: 1, shininess: 50)
    m.scale = 0.0040
    m.position = [1.0405, 0.9375, 0.0007]
    m.rotation = [0.85983, -1.57079, -2.28177]
    return m
  }()
  lazy var wristRollFollower: Model = {
    var m = Model(name: "Wrist_Roll_Follower_SO101.stl")
    m.materialOverride = Material(
      baseColor: [1.0, 0.75, 0.0], specularColor: [1.0, 0.9, 0.5],
      roughness: 0.3, metallic: 0.5, ambientOcclusion: 1, shininess: 50)
    m.scale = 0.0040
    m.position = [1.1691, 0.9374, 0.0016]
    m.rotation = [-2.65842, 1.57078, -2.00528]
    return m
  }()
  lazy var movingJaw: Model = {
    var m = Model(name: "Moving_Jaw_SO101.stl")
    m.materialOverride = Material(
      baseColor: [0.75, 0.75, 0.75], specularColor: [0.9, 0.9, 0.9],
      roughness: 0.3, metallic: 0.7, ambientOcclusion: 1, shininess: 70)
    m.scale = 0.0040
    m.position = [1.2665, 1.0182, 0.0050]
    m.rotation = [0.04868, 0.00001, 1.57080]
    return m
  }()
//  lazy var trigger: Model = {
//    var m = Model(name: "Trigger_SO101.stl")
//    m.materialOverride = Material(
//      baseColor: [0.17, 0.17, 0.17], specularColor: [0.4, 0.4, 0.4],
//      roughness: 0.6, metallic: 0.5, ambientOcclusion: 1, shininess: 20)
//    m.scale = 0.0040
//    m.position = [1.2665, 1.0218, -0.0705]
//    m.rotation = [0.04868, 0.00001, 1.57080]
//    return m
//  }()
//  lazy var handle: Model = {
//    var m = Model(name: "Handle_SO101.stl")
//    m.materialOverride = Material(
//      baseColor: [0.8, 0.0, 0.8], specularColor: [1.0, 0.4, 1.0],
//      roughness: 0.4, metallic: 0.3, ambientOcclusion: 1, shininess: 40)
//    m.scale = 0.0040
//    m.position = [1.5653, 0.9059, 0.0000]
//    m.rotation = [-2.39353, 1.57078, 0.87141]
//    return m
//  }()

  lazy var treefir1: Model = {
    Model(name: "treefir.obj")
  }()
  lazy var treefir2: Model = {
    Model(name: "treefir.obj")
  }()
  lazy var treefir3: Model = {
    Model(name: "treefir.obj")
  }()
  lazy var ground: Model = {
    Model(name: "large_plane.obj")
  }()

  var models: [Model] = []
  var camera = ArcballCamera()

  var defaultView: Transform {
    Transform(
      position: [0.6, 1.5, 3.0],
      rotation: [-0.3, 0.0, 0.0])
  }

  var lighting = SceneLighting()

  init() {
    camera.transform = defaultView
    camera.target = [0.6, 0.5, 0]
    camera.distance = 4
    camera.far = 20
    treefir1.position = [-1, 0, 2.5]
    treefir2.position = [-3, 0, -2]
    treefir3.position = [1.5, 0, -0.5]
    models = [
      ground, treefir1, treefir2, treefir3,        // 0-3
      basePart, baseMotorHolder,                    // 4-5  (static)
      motorHolderBase, motorHolderWrist,            // 6-7
      rotationPitch, upperArm, underArm,            // 8-10
      wristRollPitch, wristRollFollower,            // 11-12
      movingJaw                                     // 13
    ]

    // Map each robot part to its kinematic joint level
    // joint -1 = static (base), 0 = shoulder_pan, 1 = shoulder_lift,
    // 2 = elbow_flex, 3 = wrist_flex, 4 = wrist_roll, 5 = gripper
    robotPartJoints = [
      (4, -1), (5, -1),     // base parts: static
      (6,  0), (8,  0),     // motorHolderBase, rotationPitch: shoulder_pan
      (9,  1),              // upperArm: shoulder_lift
      (7,  2), (10, 2),     // motorHolderWrist, underArm: elbow_flex
      (11, 3),              // wristRollPitch: wrist_flex
      (12, 4),              // wristRollFollower: wrist_roll
      (13, 5),              // movingJaw: gripper
    ]

    // Capture home model matrices
    for part in robotPartJoints {
      homeMatrices[part.index] = models[part.index].transform.modelMatrix
    }
  }

  mutating func update(size: CGSize) {
    camera.update(size: size)
  }

  mutating func update(deltaTime: Float, motorValues: [String: Float] = [:]) {
    let input = InputController.shared
    if input.keysPressed.contains(.one) {
      camera.transform = Transform()
    }
    if input.keysPressed.contains(.two) {
      camera.transform = defaultView
    }
    input.keysPressed.removeAll()
    camera.update(deltaTime: deltaTime)

    // Forward kinematics: compute delta transforms from motor values
    kinematics.update(motorValues: motorValues)
    let deltas = kinematics.computeDeltas()

    for part in robotPartJoints {
      guard part.level >= 0,
            part.level < deltas.count,
            let home = homeMatrices[part.index]
      else { continue }
      models[part.index].modelMatrixOverride = deltas[part.level] * home
    }
  }
}
