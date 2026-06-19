import Foundation

/// One entry in the curated list of models shown in the first-run wizard.
/// Tags & sizes verified against ollama.com/library on 2026-06-19.
struct CuratedModel: Identifiable, Hashable {
    let id = UUID()
    let tag: String
    let displayName: String
    let sizeOnDiskGB: Double
    let recommendedRamGB: Int
    let justification: String
    let isDefault: Bool
}

enum CuratedModels {
    static let all: [CuratedModel] = [
        CuratedModel(tag: "llama3.2:1b",
                     displayName: "Llama 3.2 1B",
                     sizeOnDiskGB: 1.3, recommendedRamGB: 4,
                     justification: "Tiniest viable option; fast on 8GB Macs, decent at extractive Q&A.",
                     isDefault: false),
        CuratedModel(tag: "llama3.2:3b",
                     displayName: "Llama 3.2 3B",
                     sizeOnDiskGB: 2.0, recommendedRamGB: 8,
                     justification: "Best quality-per-GB at the tiny tier; strong instruction following.",
                     isDefault: false),
        CuratedModel(tag: "phi3.5",
                     displayName: "Phi 3.5 Mini (3.8B)",
                     sizeOnDiskGB: 2.2, recommendedRamGB: 8,
                     justification: "Reasoning-tuned small model; punches above its weight on extraction.",
                     isDefault: false),
        CuratedModel(tag: "qwen2.5:7b",
                     displayName: "Qwen 2.5 7B",
                     sizeOnDiskGB: 4.7, recommendedRamGB: 16,
                     justification: "Excellent multilingual recall; strong at citing passages verbatim.",
                     isDefault: false),
        CuratedModel(tag: "gemma2:9b",
                     displayName: "Gemma 2 9B",
                     sizeOnDiskGB: 5.4, recommendedRamGB: 16,
                     justification: "Conversational tone; reliable refusal when context is missing.",
                     isDefault: false),
        CuratedModel(tag: "mistral-nemo",
                     displayName: "Mistral Nemo 12B",
                     sizeOnDiskGB: 7.1, recommendedRamGB: 16,
                     justification: "128k context fits long note threads in one shot; balanced reasoning.",
                     isDefault: true),
        CuratedModel(tag: "phi4",
                     displayName: "Phi-4 14B",
                     sizeOnDiskGB: 9.1, recommendedRamGB: 32,
                     justification: "Sharpest synthesis across many retrieved notes when RAM allows.",
                     isDefault: false),
    ]

    static var defaultModel: CuratedModel {
        all.first(where: { $0.isDefault }) ?? all[5]
    }
}
