import SwiftUI

struct BottomDock: View {
  @ObservedObject var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      Divider()
      DockTabStrip(appState: appState)
      Divider()
      Group {
        switch appState.bottomTab {
        case .handTracker: HandTrackerPanel(appState: appState)
        case .telemetry:   PlaceholderTab(title: "Telemetry", subtitle: "Live joint plots — Phase 4.")
        case .timeline:    PlaceholderTab(title: "Timeline", subtitle: "Trajectory playback — Phase 4.")
        case .console:     PlaceholderTab(title: "Console", subtitle: "Log output — Phase 4.")
        case .recorder:    PlaceholderTab(title: "Recorder", subtitle: "Demonstration capture — Phase 4.")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.regularMaterial)
    }
  }
}

private struct DockTabStrip: View {
  @ObservedObject var appState: AppState

  var body: some View {
    HStack(spacing: 2) {
      ForEach(BottomDockTab.allCases) { tab in
        DockTabButton(tab: tab, active: appState.bottomTab == tab) {
          appState.bottomTab = tab
        }
      }
      Spacer()
      Button {
        appState.showBottomDock.toggle()
      } label: {
        Image(systemName: "chevron.down")
          .font(.system(size: 11))
      }
      .buttonStyle(.borderless)
      .help("Hide dock")
    }
    .padding(.horizontal, 8)
    .frame(height: 30)
    .background(.bar)
  }
}

private struct DockTabButton: View {
  let tab: BottomDockTab
  let active: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: tab.symbol)
          .font(.system(size: 10, weight: .medium))
        Text(tab.rawValue)
          .font(.system(size: 11, weight: active ? .semibold : .regular))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(background)
      .foregroundStyle(active ? Color.primary : Color.secondary)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder private var background: some View {
    if active {
      RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.18))
    } else {
      Color.clear
    }
  }
}

// MARK: - Hand Tracker tab

private struct HandTrackerPanel: View {
  @ObservedObject var appState: AppState

  var body: some View {
    HStack(spacing: 0) {
      // Left: status + workspace info
      VStack(alignment: .leading, spacing: 12) {
        StatusBlock(
          title: "WebSocket",
          value: appState.webSocket.isConnected ? "Connected" : "Waiting…",
          subtitle: "ws://localhost:8765",
          ok: appState.webSocket.isConnected)
        StatusBlock(
          title: "Message rate",
          value: "\(Int(appState.webSocket.messageRate)) Hz",
          subtitle: "rolling 1-second window",
          ok: appState.webSocket.messageRate > 0)
        StatusBlock(
          title: "Camera preview",
          value: "External window",
          subtitle: "cv2.imshow in python_sender",
          ok: nil)
        Spacer()
      }
      .padding(14)
      .frame(width: 240, alignment: .topLeading)

      Divider()

      // Right: latest motor commands
      VStack(alignment: .leading, spacing: 8) {
        Text("Latest motor command")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
          .tracking(0.6)

        if appState.webSocket.latestActionPublished.isEmpty {
          ContentUnavailableHint(
            symbol: "wave.3.left",
            title: "No data yet",
            subtitle: "Start python_sender/sender.py and show your hand.")
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(appState.webSocket.latestActionPublished
                        .sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                HStack {
                  Text(key)
                    .font(.system(size: 11, design: .monospaced))
                  Spacer()
                  Text(String(format: "%+6.1f", val))
                    .font(.system(size: 11, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        Spacer()
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }
}

private struct StatusBlock: View {
  let title: String
  let value: String
  let subtitle: String
  /// nil = neutral, true = green dot, false = red dot.
  let ok: Bool?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(title.uppercased())
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
          .tracking(0.6)
        if let ok {
          Circle()
            .fill(ok ? Color.green : Color.secondary.opacity(0.4))
            .frame(width: 6, height: 6)
        }
      }
      Text(value)
        .font(.system(size: 13, weight: .semibold))
      Text(subtitle)
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }
  }
}

private struct ContentUnavailableHint: View {
  let symbol: String
  let title: String
  let subtitle: String

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 28, weight: .light))
        .foregroundStyle(.tertiary)
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
      Text(subtitle)
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct PlaceholderTab: View {
  let title: String
  let subtitle: String
  var body: some View {
    VStack(spacing: 4) {
      Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
      Text(subtitle).font(.system(size: 11)).foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
