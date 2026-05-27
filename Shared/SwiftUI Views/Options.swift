

import Foundation

enum RenderChoice: Int {
  case tiledDeferred = 0, deferred, forward
}

class Options: ObservableObject {
  @Published var renderChoice = RenderChoice.tiledDeferred
  @Published var tiledSupported = false
}
