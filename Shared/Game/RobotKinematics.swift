import simd

/// SO-101 URDF joint definition.
struct JointDef {
  let position: float3       // URDF origin xyz (in parent frame)
  let fixedRotation: float3  // URDF origin rpy (Euler XYZ)
  let motorKey: String
  let minRad: Float
  let maxRad: Float
  let isGripper: Bool
}

/// Forward kinematics for the SO-101 robot arm.
///
/// `computeWorldFrames()` returns one world-space matrix per kinematic level
/// (0 = base, 1..6 = each joint after rotation). Callers render visuals as
/// `frames[level+1] * visualOrigin * scale`, where `visualOrigin` is the
/// URDF `<visual><origin>` for that mesh in its link frame.
class RobotKinematics {

  /// URDF rpy convention: fixed-axis x→y→z. Matrix = Rz * Ry * Rx.
  /// Different from `float4x4(rotation:)` which does Rx * Ry * Rz.
  static func urdfRPY(_ rpy: float3) -> float4x4 {
    float4x4(rotationZ: rpy.z)
      * float4x4(rotationY: rpy.y)
      * float4x4(rotationX: rpy.x)
  }

  // URDF kinematic chain (matches RobotArm.tsx)
  static let joints: [JointDef] = [
    JointDef(position: [0.0388, 0, 0.0624],
             fixedRotation: [Float.pi, 0, -Float.pi],
             motorKey: "shoulder_pan",
             minRad: -1.92, maxRad: 1.92, isGripper: false),
    JointDef(position: [-0.0304, -0.0183, -0.0542],
             fixedRotation: [-Float.pi / 2, -Float.pi / 2, 0],
             motorKey: "shoulder_lift",
             minRad: -1.75, maxRad: 1.75, isGripper: false),
    JointDef(position: [-0.1126, -0.028, 0],
             fixedRotation: [0, 0, Float.pi / 2],
             motorKey: "elbow_flex",
             minRad: -1.69, maxRad: 1.69, isGripper: false),
    JointDef(position: [-0.1349, 0.0052, 0],
             fixedRotation: [0, 0, -Float.pi / 2],
             motorKey: "wrist_flex",
             minRad: -1.66, maxRad: 1.66, isGripper: false),
    JointDef(position: [0, -0.0611, 0.0181],
             fixedRotation: [Float.pi / 2, 0.0487, Float.pi],
             motorKey: "wrist_roll",
             minRad: -2.74, maxRad: 2.84, isGripper: false),
    JointDef(position: [0.0202, 0.0188, -0.0234],
             fixedRotation: [Float.pi / 2, 0, 0],
             motorKey: "gripper",
             minRad: -0.17, maxRad: 1.75, isGripper: true),
  ]

  // Z-up → Y-up
  private let rootTransform = float4x4(rotationX: -Float.pi / 2)

  // Interpolated / target angles (radians)
  private var currentAngles: [Float]
  private var targetAngles: [Float]

  private let lerpFactor: Float = 0.3

  init() {
    let n = Self.joints.count
    currentAngles = Array(repeating: 0, count: n)
    targetAngles = Array(repeating: 0, count: n)
  }

  // MARK: - Conversion

  /// Normalized motor value → radians using URDF joint limits.
  private func toRadians(_ joint: JointDef, _ norm: Float) -> Float {
    if joint.isGripper {
      return joint.minRad + (norm / 100) * (joint.maxRad - joint.minRad)
    }
    return joint.minRad + ((norm + 100) / 200) * (joint.maxRad - joint.minRad)
  }

  // MARK: - Update

  /// Feed latest motor values and smooth-interpolate joint angles.
  func update(motorValues: [String: Float]) {
    for (i, joint) in Self.joints.enumerated() {
      if let norm = motorValues["\(joint.motorKey).pos"] {
        targetAngles[i] = toRadians(joint, norm)
      }
    }
    for i in 0..<currentAngles.count {
      currentAngles[i] += (targetAngles[i] - currentAngles[i]) * lerpFactor
    }
  }

  // MARK: - Forward kinematics

  /// `frames[0]` = chain root (base, no joint rotations).
  /// `frames[i+1]` = world frame at joint `i` with its current angle applied.
  func computeWorldFrames() -> [float4x4] {
    var frames: [float4x4] = [rootTransform]
    var accum = rootTransform
    for (i, joint) in Self.joints.enumerated() {
      let frame = float4x4(translation: joint.position)
                * Self.urdfRPY(joint.fixedRotation)
                * float4x4(rotationZ: currentAngles[i])
      accum = accum * frame
      frames.append(accum)
    }
    return frames
  }
}
