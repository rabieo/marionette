import SwiftUI
import Combine

final class AppState: ObservableObject {
  enum ControlMode: String, CaseIterable, Identifiable {
    case sim = "Sim"
    case real = "Real"
    case both = "Both"
    var id: String { rawValue }
  }

  enum OutlinerItem: Hashable, Identifiable {
    case world
    case sunLight
    case pointLights
    case mainCamera
    case ground
    case trees
    case robot
    case robotLink(String)
    var id: Self { self }
  }

  @Published var mode: ControlMode = .sim
  @Published var simRunning: Bool = true
  @Published var realArmConnected: Bool = false   // Phase 5 wires this up
  @Published var selectedItem: OutlinerItem? = .robot
  @Published var bottomTab: BottomDockTab = .handTracker
  @Published var showBottomDock: Bool = true

  let webSocket: RobotWebSocketClient
  let options: Options

  private var cancellables = Set<AnyCancellable>()

  init() {
    self.webSocket = RobotWebSocketClient()
    self.options = Options()
    // Republish nested observable changes so views that depend on
    // appState.webSocket.* through @ObservedObject AppState refresh.
    webSocket.objectWillChange
      .sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)
    options.objectWillChange
      .sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)
  }
}

enum BottomDockTab: String, CaseIterable, Identifiable {
  case handTracker = "Hand Tracker"
  case telemetry = "Telemetry"
  case timeline = "Timeline"
  case console = "Console"
  case recorder = "Recorder"

  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .handTracker: return "hand.raised"
    case .telemetry:   return "waveform.path"
    case .timeline:    return "play.rectangle"
    case .console:     return "terminal"
    case .recorder:    return "record.circle"
    }
  }
}
