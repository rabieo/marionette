import Foundation
import Combine

/// Reads motor commands from a Python sender over WebSocket.
///
/// Two access patterns:
/// - `latestAction` is read synchronously from the Metal render thread
///   every frame; guarded by an internal lock.
/// - `isConnected` / `latestActionPublished` / `messageRate` are
///   `@Published` for SwiftUI binding; mutated on the main queue.
class RobotWebSocketClient: ObservableObject {
  @Published private(set) var isConnected: Bool = false
  @Published private(set) var latestActionPublished: [String: Float] = [:]
  @Published private(set) var messageRate: Double = 0

  private var webSocketTask: URLSessionWebSocketTask?
  private let url: URL
  private let lock = NSLock()
  private var _latestAction: [String: Float] = [:]
  private var messageTimestamps: [Date] = []

  init(url: URL = URL(string: "ws://localhost:8765")!) {
    self.url = url
  }

  /// Snapshot for the render thread — does not touch @Published state.
  var latestAction: [String: Float] {
    lock.lock(); defer { lock.unlock() }
    return _latestAction
  }

  func connect() {
    let session = URLSession(configuration: .default)
    webSocketTask = session.webSocketTask(with: url)
    webSocketTask?.resume()
    listen()
  }

  private func listen() {
    webSocketTask?.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let message):
        if case .string(let text) = message {
          self.handle(text)
        }
        self.listen()
      case .failure:
        DispatchQueue.main.async { self.isConnected = false }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { self.connect() }
      }
    }
  }

  private func handle(_ json: String) {
    guard let data = json.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data)
            as? [String: Double]
    else { return }
    let parsed = dict.mapValues { Float($0) }

    lock.lock()
    _latestAction = parsed
    lock.unlock()

    DispatchQueue.main.async { [parsed] in
      self.latestActionPublished = parsed
      self.isConnected = true

      let now = Date()
      self.messageTimestamps.append(now)
      let cutoff = now.addingTimeInterval(-1.0)
      self.messageTimestamps.removeAll { $0 < cutoff }
      self.messageRate = Double(self.messageTimestamps.count)
    }
  }

  func disconnect() {
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    DispatchQueue.main.async { self.isConnected = false }
  }
}
