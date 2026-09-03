import SwiftUI

struct DiffPaneRepresentable: NSViewRepresentable {
    let side: Side
    let model: AppModel

    func makeNSView(context: Context) -> DiffPaneView {
        let view = DiffPaneView(side: side, model: model)
        if side == .left {
            model.leftPane = view
        } else {
            model.rightPane = view
        }
        return view
    }

    func updateNSView(_ nsView: DiffPaneView, context: Context) {
        nsView.applyModelUpdates()
    }
}

struct MinimapRepresentable: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> MinimapView {
        let view = MinimapView(model: model)
        model.minimap = view
        return view
    }

    func updateNSView(_ nsView: MinimapView, context: Context) {
        nsView.needsDisplay = true
    }
}

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                pane(.left)
                MinimapRepresentable(model: model)
                    .frame(width: 36)
                    .accessibilityLabel("Diff preview")
                pane(.right)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle("Diff")
        .toolbar { toolbar }
        .onAppear {
            model.restoreIfNeeded()
            DispatchQueue.main.async {
                model.refreshViews()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button(action: model.prevHunk) {
                Label("Previous change", systemImage: "chevron.up")
            }
            .disabled(!model.hasDiff)
            .help("Previous change (⌘↑)")
            Button(action: model.nextHunk) {
                Label("Next change", systemImage: "chevron.down")
            }
            .disabled(!model.hasDiff)
            .help("Next change (⌘↓)")
        }
        ToolbarItem(placement: .automatic) {
            Button("Clear") {
                model.clear(side: .left)
                model.clear(side: .right)
            }
            .help("Clear both sides")
        }
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 6) {
                Text("Ignore whitespace")
                    .font(.system(size: 12))
                Toggle("Ignore whitespace", isOn: $model.ignoreWhitespace)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel("Ignore whitespace")
            }
            .help("Treat whitespace-only changes as equal")
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func pane(_ side: Side) -> some View {
        DiffPaneRepresentable(side: side, model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(side == .left ? "Left text" : "Right text")
    }
}
