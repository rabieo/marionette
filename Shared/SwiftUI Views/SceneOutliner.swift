import SwiftUI

private struct OutlinerNode: Identifiable {
  let id: AppState.OutlinerItem
  let title: String
  let symbol: String
  var children: [OutlinerNode]? = nil
}

struct SceneOutliner: View {
  @ObservedObject var appState: AppState

  private var tree: [OutlinerNode] {
    [
      OutlinerNode(
        id: .world, title: "World", symbol: "globe",
        children: [
          OutlinerNode(id: .sunLight, title: "Sun", symbol: "sun.max.fill"),
          OutlinerNode(id: .pointLights, title: "Point Lights", symbol: "lightbulb.fill"),
          OutlinerNode(id: .mainCamera, title: "Main Camera", symbol: "camera.fill"),
          OutlinerNode(id: .ground, title: "Ground", symbol: "square.fill"),
          OutlinerNode(id: .trees, title: "Trees", symbol: "tree.fill"),
        ]),
      OutlinerNode(
        id: .robot, title: "SO-101", symbol: "figure.arms.open",
        children: [
          OutlinerNode(id: .robotLink("base_link"),       title: "base_link",       symbol: "square.dashed"),
          OutlinerNode(id: .robotLink("shoulder_link"),   title: "shoulder_link",   symbol: "square.dashed"),
          OutlinerNode(id: .robotLink("upper_arm_link"),  title: "upper_arm_link",  symbol: "square.dashed"),
          OutlinerNode(id: .robotLink("lower_arm_link"),  title: "lower_arm_link",  symbol: "square.dashed"),
          OutlinerNode(id: .robotLink("wrist_link"),      title: "wrist_link",      symbol: "square.dashed"),
          OutlinerNode(id: .robotLink("gripper_link"),    title: "gripper_link",    symbol: "square.dashed"),
          OutlinerNode(id: .robotLink("moving_jaw_link"), title: "moving_jaw_link", symbol: "square.dashed"),
        ]),
    ]
  }

  var body: some View {
    VStack(spacing: 0) {
      SidebarHeader(title: "Scene", trailing: {
        Button {} label: { Image(systemName: "plus") }
          .buttonStyle(.borderless)
      })

      List(selection: $appState.selectedItem) {
        ForEach(tree) { node in
          OutlinerRowView(node: node)
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
    }
    .background(.regularMaterial)
  }
}

private struct OutlinerRowView: View {
  let node: OutlinerNode
  @State private var expanded: Bool = true

  var body: some View {
    if let children = node.children {
      DisclosureGroup(isExpanded: $expanded) {
        ForEach(children) { child in
          OutlinerRowView(node: child)
        }
      } label: {
        OutlinerLabel(symbol: node.symbol, title: node.title, bold: true)
      }
      .tag(node.id)
    } else {
      OutlinerLabel(symbol: node.symbol, title: node.title, bold: false)
        .tag(node.id)
    }
  }
}

private struct OutlinerLabel: View {
  let symbol: String
  let title: String
  let bold: Bool

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: 14)
      Text(title)
        .font(.system(size: 12, weight: bold ? .semibold : .regular))
      Spacer(minLength: 0)
      Image(systemName: "eye")
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }
  }
}

struct SidebarHeader<Trailing: View>: View {
  let title: String
  @ViewBuilder let trailing: () -> Trailing

  var body: some View {
    HStack {
      Text(title.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .tracking(0.6)
      Spacer()
      trailing()
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .frame(height: 28)
    .background(.bar)
    .overlay(Divider(), alignment: .bottom)
  }
}
