import SwiftUI

struct Inspector: View {
  @ObservedObject var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      SidebarHeader(title: inspectorTitle, trailing: { EmptyView() })

      ScrollView {
        VStack(spacing: 0) {
          switch appState.selectedItem {
          case .robot, .robotLink, .none:
            RobotInspectorSection(appState: appState)
          case .sunLight:
            PlaceholderSection(title: "Light", message: "Color · intensity · position (Phase 3).")
          case .pointLights:
            PlaceholderSection(title: "Point Lights", message: "List + per-light controls (Phase 3).")
          case .mainCamera:
            PlaceholderSection(title: "Camera", message: "fov · near · far · target (Phase 3).")
          case .ground, .trees:
            PlaceholderSection(title: "Mesh", message: "Material editor (Phase 3).")
          case .world:
            PlaceholderSection(title: "World", message: "Scene-wide settings (Phase 3).")
          }
        }
      }
    }
    .background(.regularMaterial)
  }

  private var inspectorTitle: String {
    switch appState.selectedItem {
    case .robot:                return "SO-101"
    case .robotLink(let name):  return name
    case .sunLight:             return "Sun"
    case .pointLights:          return "Point Lights"
    case .mainCamera:           return "Main Camera"
    case .ground:               return "Ground"
    case .trees:                return "Trees"
    case .world, .none:         return "Inspector"
    }
  }
}

// MARK: - Robot section

private struct RobotInspectorSection: View {
  @ObservedObject var appState: AppState

  // Mirror of RobotKinematics.joints (URDF order, no Swift import needed).
  private let joints: [(key: String, label: String, gripper: Bool)] = [
    ("shoulder_pan",  "Shoulder Pan",  false),
    ("shoulder_lift", "Shoulder Lift", false),
    ("elbow_flex",    "Elbow Flex",    false),
    ("wrist_flex",    "Wrist Flex",    false),
    ("wrist_roll",    "Wrist Roll",    false),
    ("gripper",       "Gripper",       true),
  ]

  var body: some View {
    InspectorGroup(title: "Joint State") {
      VStack(spacing: 10) {
        ForEach(joints, id: \.key) { joint in
          JointRow(
            label: joint.label,
            value: appState.webSocket.latestActionPublished["\(joint.key).pos"] ?? 0,
            range: joint.gripper ? 0...100 : -100...100)
        }
      }
    }

    InspectorGroup(title: "Source") {
      VStack(alignment: .leading, spacing: 6) {
        KeyValueRow(key: "Mode", value: appState.mode.rawValue)
        KeyValueRow(key: "WebSocket",
                    value: appState.webSocket.isConnected ? "ws://localhost:8765" : "Disconnected",
                    monospaced: true)
        KeyValueRow(key: "Update rate",
                    value: "\(Int(appState.webSocket.messageRate)) Hz")
      }
    }

    InspectorGroup(title: "Description") {
      Text("SO-101 5-DOF arm + gripper. Driven by IK targets from a webcam hand-tracking pipeline (see python_sender/).")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct JointRow: View {
  let label: String
  let value: Float
  let range: ClosedRange<Float>

  var body: some View {
    VStack(spacing: 3) {
      HStack {
        Text(label)
          .font(.system(size: 11, weight: .medium))
        Spacer()
        Text(String(format: "%+6.1f", value))
          .font(.system(size: 11, weight: .regular).monospacedDigit())
          .foregroundStyle(.secondary)
      }
      JointMeter(value: value, range: range)
        .frame(height: 4)
    }
  }
}

private struct JointMeter: View {
  let value: Float
  let range: ClosedRange<Float>

  var body: some View {
    GeometryReader { geo in
      let span = range.upperBound - range.lowerBound
      let normalized = max(0, min(1, (value - range.lowerBound) / span))
      let signed = range.lowerBound < 0
      ZStack(alignment: .leading) {
        Capsule().fill(.quaternary.opacity(0.6))
        if signed {
          // bipolar: bar grows from center
          let centerX = geo.size.width / 2
          let valueX = CGFloat(normalized) * geo.size.width
          let leftX = min(centerX, valueX)
          let width = abs(valueX - centerX)
          Capsule()
            .fill(.tint)
            .frame(width: width)
            .offset(x: leftX)
        } else {
          // unipolar: bar grows from left
          Capsule()
            .fill(.tint)
            .frame(width: CGFloat(normalized) * geo.size.width)
        }
      }
    }
  }
}

// MARK: - Generic inspector helpers

struct InspectorGroup<Content: View>: View {
  let title: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(title.uppercased())
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
          .tracking(0.6)
        Spacer()
      }
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .padding(.bottom, 6)

      content()
        .padding(.horizontal, 14)
        .padding(.bottom, 14)

      Divider()
    }
  }
}

struct KeyValueRow: View {
  let key: String
  let value: String
  var monospaced: Bool = false

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(key)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(valueFont)
        .foregroundStyle(.primary)
    }
  }

  private var valueFont: Font {
    monospaced
      ? .system(size: 11, design: .monospaced)
      : .system(size: 11).monospacedDigit()
  }
}

struct PlaceholderSection: View {
  let title: String
  let message: String

  var body: some View {
    InspectorGroup(title: title) {
      Text(message)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
