import SwiftUI

// StatusBar.swift — kept as home for ModelSwitcher only.
// TopBar (Tasks toggle) lives in ContentView.swift.

struct ModelSwitcher: View {
    @State private var models:   [String] = []
    @State private var current:  String   = UserDefaults.standard.string(forKey: "ollamaModel") ?? "mistral-nemo"
    @State private var hovered = false

    var body: some View {
        Menu {
            ForEach(models, id: \.self) { model in
                Button {
                    current = model
                    Task { await OllamaClient.shared.setModel(model) }
                } label: {
                    HStack {
                        Text(model)
                        if model == current { Image(systemName: "checkmark") }
                    }
                }
            }
            if models.isEmpty {
                Text("No models found").foregroundColor(C.textDim)
            }
            Divider()
            Button("Refresh") {
                Task { models = await OllamaClient.shared.availableModels() }
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(models.isEmpty ? Color.orange.opacity(0.6) : Color.green.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text(shortName(current))
                    .font(F.syneUI(10))
                    .foregroundColor(hovered ? C.text : C.textDim)
                    .lineLimit(1)
                SmallCaret()
                    .stroke(C.textDim, lineWidth: 1)
                    .frame(width: 6, height: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(C.bgSide)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(C.border, lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovered = $0 }
        .help("Switch Ollama model")
        .task {
            models  = await OllamaClient.shared.availableModels()
            let saved = await OllamaClient.shared.chatModel
            if !saved.isEmpty { current = saved }
        }
    }

    private func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: ":latest", with: "")
    }
}

private struct SmallCaret: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}
