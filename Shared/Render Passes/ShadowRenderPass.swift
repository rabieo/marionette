

import MetalKit

struct ShadowRenderPass: RenderPass {
  let label: String = "Shadow Render Pass"
  var descriptor: MTLRenderPassDescriptor?
    = MTLRenderPassDescriptor()
  var depthStencilState: MTLDepthStencilState?
    = Self.buildDepthStencilState()
  var pipelineState: MTLRenderPipelineState
  var shadowTexture: MTLTexture?

  init(view: MTKView) {
    pipelineState = PipelineStates.createShadowPSO()
    shadowTexture = Self.makeTexture(
      size: CGSize(
        width: 4096,
        height: 4096),
      pixelFormat: .depth32Float,
      label: "Shadow Depth Texture")
  }

  mutating func resize(view: MTKView, size: CGSize) {
  }

  func draw(
    commandBuffer: MTLCommandBuffer,
    scene: GameScene,
    uniforms: Uniforms,
    params: Params
  ) {
    guard let descriptor = descriptor else { return }
    descriptor.depthAttachment.texture = shadowTexture
    descriptor.depthAttachment.loadAction = .clear
    descriptor.depthAttachment.storeAction = .store

    guard let renderEncoder =
      commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
      return
    }
    renderEncoder.label = "Shadow Encoder"
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setRenderPipelineState(pipelineState)
    for model in scene.models {
      model.render(
        encoder: renderEncoder,
        uniforms: uniforms,
        params: params)
    }
    renderEncoder.endEncoding()
  }
}
