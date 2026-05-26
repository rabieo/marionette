import Foundation

class RobotWebSocketClient {
  private var webSocketTask: URLSessionWebSocketTask?
  private let url: URL
  private let lock = NSLock()
  private var _latestAction: [String: Float] = [:]

  init(url: URL = URL(string: "ws://localhost:8765")!) {
    self.url = url
  }

  func connect() {
    let session = URLSession(configuration: .default)
    webSocketTask = session.webSocketTask(with: url)
    webSocketTask?.resume()
    listen()
  }

  private func listen() {
    webSocketTask?.receive { [weak self] result in
      switch result {
      case .success(let message):
        if case .string(let text) = message {
          self?.parse(text)
        }
        self?.listen()
      case .failure:
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
          self?.connect()
        }
      }
    }
  }

  private func parse(_ json: String) {
    guard let data = json.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data)
            as? [String: Double]
    else { return }
    lock.lock()
    _latestAction = dict.mapValues { Float($0) }
    lock.unlock()
  }

  var latestAction: [String: Float] {
    lock.lock()
    defer { lock.unlock() }
    return _latestAction
  }

  func disconnect() {
    webSocketTask?.cancel(with: .goingAway, reason: nil)
  }
}
