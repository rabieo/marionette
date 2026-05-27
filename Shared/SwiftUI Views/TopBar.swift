import SwiftUI

struct TopBar: View {
  @ObservedObject var appState: AppState

  var body: some View {
    HStack(spacing: 16) {
      // App / scene title
      HStack(spacing: 8) {
        Image(systemName: "cube.transparent.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 0) {
          Text("Robot Sim")
            .font(.headline)
          Text("SO-101 · Untitled Scene")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 12)

      // Mode picker — centered focus
      Picker("", selection: $appState.mode) {
        ForEach(AppState.ControlMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 220)
      .tint(modeTint)

      Spacer(minLength: 12)

      // Connection pills
      ConnectionPill(
        label: "Hand",
        symbol: "hand.raised.fill",
        connected: appState.webSocket.isConnected,
        detail: appState.webSocket.isConnected
          ? "\(Int(appState.webSocket.messageRate)) Hz" : nil)
      ConnectionPill(
        label: "Arm",
        symbol: "cable.connector",
        connected: appState.realArmConnected,
        detail: nil)

      // Play / pause
      Button {
        appState.simRunning.toggle()
      } label: {
        Image(systemName: appState.simRunning ? "pause.fill" : "play.fill")
          .font(.system(size: 14, weight: .bold))
          .frame(width: 28, height: 22)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)
      .help(appState.simRunning ? "Pause sim" : "Play sim")

      // E-stop
      Button {
        appState.simRunning = false
        // Phase 5: also send stop to real arm.
      } label: {
        Image(systemName: "stop.fill")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 32, height: 22)
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
      .help("Emergency stop")
    }
    .padding(.horizontal, 14)
    .frame(height: 48)
    .background(.bar)
    .overlay(Divider(), alignment: .bottom)
  }

  private var modeTint: Color {
    switch appState.mode {
    case .sim:  return .blue
    case .real: return .orange
    case .both: return .purple
    }
  }
}

private struct ConnectionPill: View {
  let label: String
  let symbol: String
  let connected: Bool
  let detail: String?

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .medium))
      Text(label)
        .font(.system(size: 11, weight: .medium))
      Circle()
        .fill(connected ? Color.green : Color.secondary.opacity(0.4))
        .frame(width: 7, height: 7)
      if let detail {
        Text(detail)
          .font(.system(size: 10, weight: .regular).monospacedDigit())
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(
      Capsule().fill(.quaternary.opacity(0.6))
    )
    .overlay(
      Capsule().strokeBorder(.separator, lineWidth: 0.5)
    )
  }
}
