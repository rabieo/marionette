import SwiftUI

struct ContentView: View {
  @StateObject private var appState = AppState()

  var body: some View {
    #if os(macOS)
    macOSLayout
    #else
    iOSLayout
    #endif
  }

  // MARK: - macOS

  #if os(macOS)
  private var macOSLayout: some View {
    VStack(spacing: 0) {
      TopBar(appState: appState)

      HSplitView {
        SceneOutliner(appState: appState)
          .frame(minWidth: 200, idealWidth: 240, maxWidth: 400)

        VSplitView {
          Viewport(appState: appState)
            .frame(minHeight: 200)

          if appState.showBottomDock {
            BottomDock(appState: appState)
              .frame(minHeight: 140, idealHeight: 220, maxHeight: 400)
          }
        }
        .frame(minWidth: 400)

        Inspector(appState: appState)
          .frame(minWidth: 240, idealWidth: 300, maxWidth: 500)
      }

      StatusBar(appState: appState)
    }
    .frame(minWidth: 1100, minHeight: 700)
  }
  #endif

  // MARK: - iOS (single-pane fallback)

  #if !os(macOS)
  private var iOSLayout: some View {
    VStack(spacing: 0) {
      TopBar(appState: appState)
      Viewport(appState: appState)
      BottomDock(appState: appState)
        .frame(height: 220)
    }
  }
  #endif
}

// MARK: - Viewport (center)

private struct Viewport: View {
  @ObservedObject var appState: AppState

  var body: some View {
    ZStack {
      // The Metal view fills the viewport.
      MetalView(options: appState.options,
                robotWebSocket: appState.webSocket)
        .background(Color.black)

      // Reopen the dock when it's hidden.
      if !appState.showBottomDock {
        VStack {
          Spacer()
          HStack {
            Spacer()
            Button {
              appState.showBottomDock = true
            } label: {
              Image(systemName: "chevron.up")
                .padding(6)
            }
            .buttonStyle(.borderedProminent)
            .padding(10)
          }
        }
      }
    }
  }
}

// MARK: - Status bar

private struct StatusBar: View {
  @ObservedObject var appState: AppState

  var body: some View {
    HStack(spacing: 12) {
      Label(appState.simRunning ? "Running" : "Paused",
            systemImage: appState.simRunning ? "circle.fill" : "pause.circle.fill")
        .foregroundStyle(appState.simRunning ? .green : .secondary)
        .font(.system(size: 10, weight: .medium))

      Divider().frame(height: 12)

      Text("Render: \(renderModeName)")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)

      Spacer()

      Text("Selection: \(selectionName)")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .frame(height: 22)
    .background(.bar)
    .overlay(Divider(), alignment: .top)
  }

  private var renderModeName: String {
    switch appState.options.renderChoice {
    case .tiledDeferred: return "Tiled Deferred"
    case .deferred:      return "Deferred"
    case .forward:       return "Forward"
    }
  }

  private var selectionName: String {
    switch appState.selectedItem {
    case .robot:               return "SO-101"
    case .robotLink(let n):    return n
    case .sunLight:            return "Sun"
    case .pointLights:         return "Point Lights"
    case .mainCamera:          return "Camera"
    case .ground:              return "Ground"
    case .trees:               return "Trees"
    case .world, .none:        return "—"
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View { ContentView() }
}
