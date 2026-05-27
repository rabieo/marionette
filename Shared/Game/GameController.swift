

import MetalKit

class GameController: NSObject {
  var scene: GameScene
  var renderer: Renderer
  var options = Options()
  var fps: Double = 0
  var deltaTime: Double = 0
  var lastTime: Double = CFAbsoluteTimeGetCurrent()
  let robotWebSocket: RobotWebSocketClient

  init(metalView: MTKView,
       options: Options,
       robotWebSocket: RobotWebSocketClient)
  {
    self.robotWebSocket = robotWebSocket
    renderer = Renderer(metalView: metalView, options: options)
    scene = GameScene()
    super.init()
    self.options = options
    metalView.delegate = self
    fps = Double(metalView.preferredFramesPerSecond)
    robotWebSocket.connect()
  }
}

extension GameController: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    scene.update(size: size)
    renderer.mtkView(view, drawableSizeWillChange: size)
  }

  func draw(in view: MTKView) {
    let currentTime = CFAbsoluteTimeGetCurrent()
    let deltaTime = (currentTime - lastTime)
    lastTime = currentTime
    scene.update(
      deltaTime: Float(deltaTime),
      motorValues: robotWebSocket.latestAction)
    renderer.draw(scene: scene, in: view)
  }
}
