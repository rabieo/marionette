import SwiftUI

@main
struct ShadowsApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .navigationTitle("Robot Sim")
        #if os(macOS)
        .frame(minWidth: 1100, minHeight: 700)
        #endif
    }
    #if os(macOS)
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unified(showsTitle: true))
    .commands {
      CommandGroup(replacing: .newItem) { }
    }
    #endif
  }
}
