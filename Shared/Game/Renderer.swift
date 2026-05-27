

import MetalKit

// swiftlint:disable implicitly_unwrapped_optional

class Renderer: NSObject {
  static var device: MTLDevice!
  static var commandQueue: MTLCommandQueue!
  static var library: MTLLibrary!
  var options: Options

  var uniforms = Uniforms()
  var params = Params()

  var forwardRenderPass: ForwardRenderPass
  var shadowRenderPass: ShadowRenderPass
  var gBufferRenderPass: GBufferRenderPass
  var lightingRenderPass: LightingRenderPass
  var tiledDeferredRenderPass: TiledDeferredRenderPass?
  var shadowCamera = OrthographicCamera()

  init(metalView: MTKView, options: Options) {
    guard
      let device = MTLCreateSystemDefaultDevice(),
      let commandQueue = device.makeCommandQueue() else {
        fatalError("GPU not available")
    }
    Renderer.device = device
    Renderer.commandQueue = commandQueue
    metalView.device = device
    // sRGB framebuffer: shaders write linear [0,1] (post-ACES) and the hardware
    // applies the sRGB encode on write. Must be set before the render passes
    // build their pipelines (they capture view.colorPixelFormat).
    metalView.colorPixelFormat = .bgra8Unorm_srgb

    // create the shader function library
    let library = device.makeDefaultLibrary()
    Self.library = library
    self.options = options
    forwardRenderPass = ForwardRenderPass(view: metalView)
    shadowRenderPass = ShadowRenderPass(view: metalView)
    gBufferRenderPass = GBufferRenderPass(view: metalView)
    lightingRenderPass = LightingRenderPass(view: metalView)
    options.tiledSupported = device.supportsFamily(.apple3)
    if options.tiledSupported {
      tiledDeferredRenderPass = TiledDeferredRenderPass(view: metalView)
    } else {
      print("WARNING: TBDR features not supported. Reverting to Forward Rendering")
      tiledDeferredRenderPass = nil
      options.renderChoice = .forward
    }
    super.init()
    // Clear color is in linear space because the framebuffer is sRGB-encoded.
    // Values below are sRGB(0.93, 0.97, 1.0) decoded → linear ≈ (0.85, 0.93, 1.0).
    metalView.clearColor = MTLClearColor(
      red: 0.848,
      green: 0.933,
      blue: 1.000,
      alpha: 1.0)
    metalView.depthStencilPixelFormat = .depth32Float
    mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
  }
}

extension Renderer {
  func mtkView(
    _ view: MTKView,
    drawableSizeWillChange size: CGSize
  ) {
    forwardRenderPass.resize(view: view, size: size)
    shadowRenderPass.resize(view: view, size: size)
    gBufferRenderPass.resize(view: view, size: size)
    lightingRenderPass.resize(view: view, size: size)
    tiledDeferredRenderPass?.resize(view: view, size: size)
  }

  func updateUniforms(scene: GameScene) {
    uniforms.viewMatrix = scene.camera.viewMatrix
    uniforms.projectionMatrix = scene.camera.projectionMatrix
    params.lightCount = UInt32(scene.lighting.lights.count)
    params.cameraPosition = scene.camera.position
    let sun = scene.lighting.lights[0]
    shadowCamera = OrthographicCamera.createShadowCamera(
      using: scene.camera,
      lightPosition: sun.position)
    uniforms.shadowProjectionMatrix = shadowCamera.projectionMatrix
    uniforms.shadowViewMatrix = float4x4(
      eye: shadowCamera.position,
      center: shadowCamera.center,
      up: [0, 1, 0])
  }

  func draw(scene: GameScene, in view: MTKView) {
    guard
      let commandBuffer = Renderer.commandQueue.makeCommandBuffer(),
      let descriptor = view.currentRenderPassDescriptor else {
        return
    }

    updateUniforms(scene: scene)

    shadowRenderPass.draw(
      commandBuffer: commandBuffer,
      scene: scene,
      uniforms: uniforms,
      params: params)

    switch options.renderChoice {
    case .tiledDeferred:
      tiledDeferredRenderPass?.shadowTexture = shadowRenderPass.shadowTexture
      tiledDeferredRenderPass?.descriptor = descriptor
      tiledDeferredRenderPass?.draw(
        commandBuffer: commandBuffer,
        scene: scene,
        uniforms: uniforms,
        params: params)
    case .deferred:
      gBufferRenderPass.shadowTexture = shadowRenderPass.shadowTexture
      gBufferRenderPass.draw(
        commandBuffer: commandBuffer,
        scene: scene,
        uniforms: uniforms,
        params: params)
      lightingRenderPass.albedoTexture = gBufferRenderPass.albedoTexture
      lightingRenderPass.normalTexture = gBufferRenderPass.normalTexture
      lightingRenderPass.positionTexture = gBufferRenderPass.positionTexture
      lightingRenderPass.stencilTexture = gBufferRenderPass.depthTexture
      lightingRenderPass.descriptor = descriptor
      lightingRenderPass.draw(
        commandBuffer: commandBuffer,
        scene: scene,
        uniforms: uniforms,
        params: params)
    case .forward:
      forwardRenderPass.descriptor = descriptor
      forwardRenderPass.shadowTexture = shadowRenderPass.shadowTexture
      forwardRenderPass.draw(
        commandBuffer: commandBuffer,
        scene: scene,
        uniforms: uniforms,
        params: params)
    }
    guard let drawable = view.currentDrawable else {
      return
    }
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
}
