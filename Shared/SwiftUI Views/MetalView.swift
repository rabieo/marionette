

import SwiftUI
import MetalKit

struct MetalView: View {
  let options: Options
  @State private var metalView = MTKView()
  @State private var gameController: GameController?

  var body: some View {
    VStack {
      MetalViewRepresentable(
        gameController: gameController,
        metalView: $metalView,
        options: options)
        .onAppear {
          gameController = GameController(
            metalView: metalView,
            options: options)
        }
        .gesture(DragGesture(minimumDistance: 0)
          .onChanged { value in
            InputController.shared.touchLocation = value.location
            // if the user drags, cancel the tap touch
            if abs(value.translation.width) > 1 ||
              abs(value.translation.height) > 1 {
              InputController.shared.touchLocation = nil
            }
          })
    }
  }
}

#if os(macOS)
typealias ViewRepresentable = NSViewRepresentable
#elseif os(iOS)
typealias ViewRepresentable = UIViewRepresentable
#endif

struct MetalViewRepresentable: ViewRepresentable {
  let gameController: GameController?
  @Binding var metalView: MTKView
  let options: Options

  #if os(macOS)
  func makeNSView(context: Context) -> some NSView {
    return metalView
  }
  func updateNSView(_ uiView: NSViewType, context: Context) {
    updateMetalView()
  }
  #elseif os(iOS)
  func makeUIView(context: Context) -> MTKView {
    metalView
  }

  func updateUIView(_ uiView: MTKView, context: Context) {
    updateMetalView()
  }
  #endif

  func updateMetalView() {
    gameController?.options = options
  }
}

struct MetalView_Previews: PreviewProvider {
  static var previews: some View {
    VStack {
      MetalView(options: Options())
      Text("Metal View")
    }
  }
}
