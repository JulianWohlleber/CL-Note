import SwiftUI
import AppKit

/// First-run setup sheet: vault → Ollama → model pick → download → done.
struct SetupWizardView: View {
    @EnvironmentObject var store: NoteStore
    @Binding var isPresented: Bool
    @Binding var didCompleteSetup: Bool

    enum Step { case welcome, vault, ollama, model, pulling, done }

    @State private var step: Step = .welcome
    @State private var ollamaVersion: String?
    @State private var checkingOllama = false
    @State private var pollTask: Task<Void, Never>?
    @State private var pullTask: Task<Void, Never>?
    @State private var selectedModel: CuratedModel = CuratedModels.defaultModel
    @State private var pullStatus: String = "Preparing…"
    @State private var pullFraction: Double = 0
    @State private var pulling = false
    @State private var pullDidSucceed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
        .frame(width: 580, height: 560)
        .background(C.bg)
        .preferredColorScheme(.dark)
        .onAppear { startPolling() }
        .onDisappear {
            pollTask?.cancel()
            pullTask?.cancel()
        }
    }

    // MARK: – Header

    private var header: some View {
        HStack {
            Text("MERKEN · SETUP")
                .font(F.syneUI(9))
                .tracking(1.4)
                .foregroundColor(C.textFaint)
            Spacer()
            Text(stepLabel)
                .font(F.syneUI(9))
                .tracking(1.2)
                .foregroundColor(C.textFaint)
            // Always-available exit so the user is never trapped.
            if step != .done {
                Button {
                    pullTask?.cancel()
                    isPresented = false
                } label: {
                    Text("Skip")
                        .font(F.syneUI(9))
                        .tracking(1.2)
                        .foregroundColor(C.textFaint)
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var stepLabel: String {
        switch step {
        case .welcome: return "1 / 5"
        case .vault:   return "2 / 5"
        case .ollama:  return "3 / 5"
        case .model:   return "4 / 5"
        case .pulling: return "4 / 5"
        case .done:    return "5 / 5"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .vault:   vaultStep
        case .ollama:  ollamaStep
        case .model:   modelStep
        case .pulling: pullStep
        case .done:    doneStep
        }
    }

    // MARK: – Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("Set up Merken")
            subtitle("Three small things and you're ready to write.")
            VStack(alignment: .leading, spacing: 10) {
                bullet("Pick a folder for your notes.")
                bullet("Set up Ollama — runs the AI locally on your Mac.")
                bullet("Pick a model — we'll download it in the background.")
            }
            Spacer()
            footer(primary: "Continue") { step = .vault }
        }
    }

    private var vaultStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("Choose a vault folder")
            subtitle("Where your notes live as plain Markdown files. You can change it later.")

            if let url = store.vaultURL {
                vaultRow(url: url)
            } else {
                pickerButton(label: "Choose folder…") { store.pickVault() }
            }

            Spacer()
            footer(primary: "Continue",
                   primaryDisabled: store.vaultURL == nil) {
                step = .ollama
            }
        }
    }

    private func vaultRow(url: URL) -> some View {
        HStack(spacing: 10) {
            Text(url.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(C.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button { store.pickVault() } label: {
                Text("Change…")
                    .font(F.syneUI(11))
                    .foregroundColor(C.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(C.bgInput)
    }

    private var ollamaStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Set up Ollama")
            subtitle("Merken runs Ollama locally so your notes never leave your Mac. We just need to start it up.")

            HStack(spacing: 10) {
                Circle()
                    .fill(ollamaVersion != nil ? Color.green : C.textFaint)
                    .frame(width: 8, height: 8)
                if let v = ollamaVersion {
                    Text("Ollama \(v) is running.")
                        .font(F.syneUI(12))
                        .foregroundColor(C.text)
                } else if checkingOllama {
                    Text("Looking for Ollama…")
                        .font(F.syneUI(12))
                        .foregroundColor(C.textDim)
                } else {
                    Text("Ollama isn't running yet.")
                        .font(F.syneUI(12))
                        .foregroundColor(C.textDim)
                }
            }

            if ollamaVersion == nil {
                HStack(spacing: 10) {
                    pickerButton(label: OllamaInstaller.appIsInstalled() ? "Start Ollama" : "Download Ollama") {
                        OllamaInstaller.launchOrInstall()
                    }
                    Button {
                        Task {
                            await MainActor.run { checkingOllama = true }
                            let v = await OllamaInstaller.daemonVersion()
                            await MainActor.run {
                                ollamaVersion = v
                                checkingOllama = false
                            }
                        }
                    } label: {
                        Text("Recheck")
                            .font(F.syneUI(12))
                            .foregroundColor(C.textDim)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(checkingOllama)
                }
                Text("Ollama is a small menu-bar app. After installing, open it once so the daemon starts — Merken will pick it up automatically.")
                    .font(F.syneUI(10))
                    .foregroundColor(C.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            footer(primary: "Continue",
                   primaryDisabled: ollamaVersion == nil) {
                step = .model
            }
        }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Pick a model")
            subtitle("Pick by your Mac's memory. The recommended choice fits 16GB and handles long notes well.")

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(CuratedModels.all) { model in
                        modelRow(model)
                    }
                }
            }
            footer(primary: "Download & install") {
                step = .pulling
                pullTask?.cancel()
                pullTask = Task { await runPull() }
            }
        }
    }

    private func modelRow(_ model: CuratedModel) -> some View {
        let selected = model.id == selectedModel.id
        return Button {
            selectedModel = model
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(selected ? C.primaryStart : Color.clear)
                    .frame(width: 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(F.syneUI(12, weight: .bold))
                            .foregroundColor(C.text)
                        if model.isDefault {
                            Text("RECOMMENDED")
                                .font(F.syneUI(8))
                                .tracking(1.2)
                                .foregroundColor(C.primaryStart)
                        }
                        Spacer()
                        Text("\(sizeLabel(model.sizeOnDiskGB)) GB · \(model.recommendedRamGB) GB RAM")
                            .font(F.syneUI(10))
                            .foregroundColor(C.textFaint)
                    }
                    Text(model.justification)
                        .font(F.syneUI(11))
                        .foregroundColor(C.textDim)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? C.bgHover : C.bgInput.opacity(0.35))
        }
        .buttonStyle(.plain)
    }

    private var pullStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("Downloading \(selectedModel.displayName)")
            Text(pullStatus)
                .font(F.syneUI(12))
                .foregroundColor(C.textDim)
                .lineLimit(1)
                .truncationMode(.middle)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(C.bgInput)
                        .frame(height: 3)
                    LinearGradient(colors: [C.primaryStart, C.primaryEnd],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(0, geo.size.width * pullFraction), height: 3)
                }
            }
            .frame(height: 3)

            Text("\(Int(pullFraction * 100))%")
                .font(F.syneUI(10))
                .foregroundColor(C.textFaint)

            Spacer()
            HStack(spacing: 10) {
                Spacer()
                if !pulling {
                    Button { step = .model } label: {
                        Text(pullDidSucceed ? "Pick another model" : "Try again")
                            .font(F.syneUI(12))
                            .foregroundColor(C.textDim)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if pullDidSucceed {
                        Button { step = .done } label: {
                            Text("Continue")
                                .font(F.syneUI(12, weight: .bold))
                                .foregroundColor(C.text)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(C.bgHover)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("You're set")
            subtitle("Merken is ready. Notes go in your vault, chat hits \(selectedModel.displayName) locally — no cloud.")
            Spacer()
            HStack {
                Spacer()
                Button {
                    UserDefaults.standard.set(selectedModel.tag, forKey: "ollamaModel")
                    didCompleteSetup = true
                    isPresented = false
                } label: {
                    Text("Open Merken")
                        .font(F.syneUI(12, weight: .bold))
                        .foregroundColor(C.text)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(C.bgHover)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: – Small building blocks

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 26, weight: .regular, design: .serif))
            .foregroundColor(C.text)
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(F.syneUI(13))
            .foregroundColor(C.textDim)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("·")
                .font(F.syneUI(13))
                .foregroundColor(C.textFaint)
            Text(text)
                .font(F.syneUI(13))
                .foregroundColor(C.text)
        }
    }

    private func pickerButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(F.syneUI(12))
                .foregroundColor(C.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(C.bgInput)
        }
        .buttonStyle(.plain)
    }

    private func footer(primary: String,
                        primaryDisabled: Bool = false,
                        action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(action: action) {
                Text(primary)
                    .font(F.syneUI(12, weight: .bold))
                    .foregroundColor(primaryDisabled ? C.textFaint : C.text)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(primaryDisabled ? C.bgInput : C.bgHover)
            }
            .buttonStyle(.plain)
            .disabled(primaryDisabled)
        }
    }

    private func sizeLabel(_ gb: Double) -> String {
        String(format: gb == floor(gb) ? "%.0f" : "%.1f", gb)
    }

    // MARK: – Async glue

    private func startPolling() {
        pollTask?.cancel()
        checkingOllama = true
        pollTask = Task {
            while !Task.isCancelled {
                if let v = await OllamaInstaller.daemonVersion() {
                    await MainActor.run {
                        ollamaVersion = v
                        checkingOllama = false
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func runPull() async {
        await MainActor.run {
            pulling = true
            pullDidSucceed = false
            pullFraction = 0
            pullStatus = "Contacting Ollama…"
        }
        let ok = await ModelInstaller.pull(model: selectedModel.tag) { progress in
            pullStatus   = humanStatus(progress.status)
            pullFraction = progress.fraction
        }
        // Don't mutate UI state or persist anything if the view is gone.
        if Task.isCancelled { return }
        await MainActor.run {
            pulling = false
            pullDidSucceed = ok
            if ok {
                UserDefaults.standard.set(selectedModel.tag, forKey: "ollamaModel")
                step = .done
            }
        }
    }

    private func humanStatus(_ s: String) -> String {
        if s.hasPrefix("pulling sha256:")  { return "Downloading…" }
        if s == "pulling manifest"         { return "Reading manifest…" }
        if s == "verifying sha256 digest"  { return "Verifying…" }
        if s == "writing manifest"         { return "Finalising…" }
        if s == "removing any unused layers" { return "Cleaning up…" }
        if s == "success"                  { return "Done." }
        return s.isEmpty ? "Working…" : s
    }
}
