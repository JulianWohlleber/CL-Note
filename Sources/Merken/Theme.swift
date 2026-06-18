import SwiftUI
import AppKit
import CoreText

// MARK: – Colors (matching design_space exactly)

enum C {
    static let bg        = Color(hex: "#111111")
    static let bgSide    = Color(hex: "#141414")
    static let bgHover   = Color(hex: "#1e1e1e")
    static let bgInput   = Color(hex: "#191919")
    static let border    = Color(hex: "#222222")
    static let text      = Color(hex: "#d4d4d4")
    static let textDim   = Color(hex: "#6b6b6b")
    static let textFaint = Color(hex: "#3a3a3a")
    static let accent    = Color(hex: "#c8c8c8")

    // Primary gradient (accent colour)
    static let primaryStart = Color(hex: "#7D78FF")
    static let primaryEnd   = Color(hex: "#c7dbe8")
    static let primary      = LinearGradient(
        colors: [primaryStart, primaryEnd],
        startPoint: .leading,
        endPoint:   .trailing
    )

    // NSColor versions
    static let bgNS          = NSColor(hex: "#111111")
    static let bgSideNS      = NSColor(hex: "#141414")
    static let textNS        = NSColor(hex: "#d4d4d4")
    static let textDimNS     = NSColor(hex: "#6b6b6b")
    static let textFaintNS   = NSColor(hex: "#3a3a3a")
    static let borderNS      = NSColor(hex: "#222222")
    static let primaryStartNS = NSColor(hex: "#7D78FF")
}

// MARK: – Fonts

enum F {
    static func syne(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name = weight == .bold ? "Syne-Bold" : "Syne-Regular"
        return NSFont(name: name, size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }
    /// IBM Plex Serif — body text font in the editor
    static func serif(_ size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        let name: String
        switch (weight == .bold, italic) {
        case (true,  true):  name = "IBMPlexSerif-BoldItalic"
        case (true,  false): name = "IBMPlexSerif-Bold"
        case (false, true):  name = "IBMPlexSerif-Italic"
        case (false, false): name = "IBMPlexSerif-Regular"
        }
        return NSFont(name: name, size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }
    static func mono(_ size: CGFloat) -> NSFont {
        NSFont(name: "IBMPlexMono-Regular", size: size)
            ?? NSFont(name: "SFMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    static func syneUI(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(weight == .bold ? "Syne-Bold" : "Syne-Regular", size: size)
            .weight(weight)
    }
}

// MARK: – Font loader

func registerFonts() {
    let names = [
        "Syne-Regular.ttf", "Syne-Bold.ttf",
        "IBMPlexMono-Regular.ttf",
        "IBMPlexSerif-Regular.ttf", "IBMPlexSerif-Bold.ttf",
        "IBMPlexSerif-Italic.ttf",  "IBMPlexSerif-BoldItalic.ttf"
    ]
    for name in names {
        // Try Bundle.main first (works in .app), then Bundle.module (SPM)
        let url = Bundle.main.url(forResource: name, withExtension: nil)
            ?? findBundleResource(name)
        if let url = url {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

private func findBundleResource(_ name: String) -> URL? {
    // SPM puts resources in a side-bundle; walk all loaded bundles
    for bundle in Bundle.allBundles + Bundle.allFrameworks {
        if let url = bundle.url(forResource: name, withExtension: nil) { return url }
        // Also check Fonts subdirectory
        if let url = bundle.url(forResource: (name as NSString).deletingPathExtension,
                                withExtension: (name as NSString).pathExtension,
                                subdirectory: "Fonts") { return url }
    }
    return nil
}

// MARK: – Color helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >>  8) & 0xFF) / 255
        let b = CGFloat( int        & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
