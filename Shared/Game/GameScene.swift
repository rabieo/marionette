
import MetalKit

/// Placement of one STL inside the SO-101 kinematic chain.
/// Values come straight from the URDF (`so101_new_calib.urdf`):
///   `level`     = -1 for base_link, 0..5 for joint output frames
///   `visualXYZ` = `<visual><origin xyz=...>` in the link frame (meters)
///   `visualRPY` = `<visual><origin rpy=...>` in URDF fixed-axis convention
private struct RobotPart {
  let modelIndex: Int
  let level: Int
  let visualXYZ: float3
  let visualRPY: float3
}

struct GameScene {
  static var objectId: UInt32 = 1
  let kinematics = RobotKinematics()

  // STL meshes are in millimeters; URDF and chain are in meters.
  static let robotMeshScale: Float = 0.001

  private var robotParts: [RobotPart] = []

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
      position: [0.0, 0.3, 0.7],
      rotation: [-0.3, 0.0, 0.0])
  }

  var lighting = SceneLighting()

  init() {
    camera.transform = defaultView
    camera.target = [0, 0.15, 0]
    camera.distance = 0.7
    camera.far = 10
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

    // URDF link + visual origin per active robot model.
    // Source: SO-ARM100/Simulation/SO101/so101_new_calib.urdf
    let pi2 = Float.pi / 2
    robotParts = [
      // base_link (static, level -1)
      RobotPart(modelIndex: 4, level: -1,
                visualXYZ: [-0.00636471, 0, -0.0024],
                visualRPY: [pi2, 0, pi2]),                 // base_so101_v2
      RobotPart(modelIndex: 5, level: -1,
                visualXYZ: [-0.00636471, 0, -0.0024],
                visualRPY: [pi2, 0, pi2]),                 // base_motor_holder_so101_v1
      // shoulder_link (joint 0 = shoulder_pan)
      RobotPart(modelIndex: 6, level: 0,
                visualXYZ: [-0.0675992, 0, 0.0158499],
                visualRPY: [pi2, -pi2, 0]),                // motor_holder_so101_base_v1
      RobotPart(modelIndex: 8, level: 0,
                visualXYZ: [0.0122008, 0, 0.0464],
                visualRPY: [-pi2, 0, 0]),                  // rotation_pitch_so101_v1
      // upper_arm_link (joint 1 = shoulder_lift)
      RobotPart(modelIndex: 9, level: 1,
                visualXYZ: [-0.065085, 0.012, 0.0182],
                visualRPY: [Float.pi, 0, 0]),              // upper_arm_so101_v1
      // lower_arm_link (joint 2 = elbow_flex)
      RobotPart(modelIndex: 7, level: 2,
                visualXYZ: [-0.0648499, -0.032, 0.018],
                visualRPY: [-Float.pi, 0, 0]),             // motor_holder_so101_wrist_v1
      RobotPart(modelIndex: 10, level: 2,
                visualXYZ: [-0.0648499, -0.032, 0.0182],
                visualRPY: [Float.pi, 0, 0]),              // under_arm_so101_v1
      // wrist_link (joint 3 = wrist_flex)
      RobotPart(modelIndex: 11, level: 3,
                visualXYZ: [0, -0.028, 0.0181],
                visualRPY: [-pi2, -pi2, 0]),               // wrist_roll_pitch_so101_v2
      // gripper_link (joint 4 = wrist_roll)
      RobotPart(modelIndex: 12, level: 4,
                visualXYZ: [0, -0.000218214, 0.000949706],
                visualRPY: [-Float.pi, 0, 0]),             // wrist_roll_follower_so101_v1
      // moving_jaw_so101_v1_link (joint 5 = gripper)
      RobotPart(modelIndex: 13, level: 5,
                visualXYZ: [0, 0, 0.0189],
                visualRPY: [0, 0, 0]),                     // moving_jaw_so101_v1
    ]
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

    // Forward kinematics: place each robot mesh inside its URDF link frame.
    //   modelMatrix = frames[level+1] * T(visualXYZ) * R(visualRPY, URDF) * scale
    kinematics.update(motorValues: motorValues)
    let frames = kinematics.computeWorldFrames()
    let scaleMatrix = float4x4(scaling: Self.robotMeshScale)

    for part in robotParts {
      let frameIndex = part.level + 1
      guard frameIndex < frames.count else { continue }
      let visual = float4x4(translation: part.visualXYZ)
                 * RobotKinematics.urdfRPY(part.visualRPY)
      models[part.modelIndex].modelMatrixOverride =
        frames[frameIndex] * visual * scaleMatrix
    }
  }
}
