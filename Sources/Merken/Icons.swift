import SwiftUI

/// Hand-rolled line-art icons in a Carbon/iA Writer spirit:
/// thin uniform strokes, square caps, no fills, 16×16 viewBox.
///
/// Usage:
///   Icon.search.view(size: 12)
///   Icon.plus.view(size: 14, color: C.textDim)

enum Icon: String {
    case search, plus, close, chevronDown, chevronRight
    case bold, italic, strike
    case listBullet, listNumber, checkbox
    case quote, inlineCode, codeBlock, link, wikilink, hr
    case tasks, sparkles, arrow
    case document, message
}

extension Icon {
    func view(size: CGFloat, color: Color = C.textDim, weight: CGFloat = 1.2) -> some View {
        IconShape(kind: self, stroke: weight)
            .stroke(color, style: StrokeStyle(lineWidth: weight, lineCap: .square, lineJoin: .miter))
            .frame(width: size, height: size)
    }
}

/// A single Shape that dispatches on the icon kind.
/// All shapes are drawn inside a normalized 16×16 coordinate system.
private struct IconShape: Shape {
    let kind: Icon
    let stroke: CGFloat

    func path(in rect: CGRect) -> Path {
        // Normalize to 16-unit grid
        let s = min(rect.width, rect.height) / 16.0
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }

        var path = Path()

        switch kind {

        case .search:
            // Circle + short diagonal handle
            let c   = CGPoint(x: rect.minX + 6.5 * s, y: rect.minY + 6.5 * s)
            let r   = 4 * s
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2*r, height: 2*r))
            path.move(to:    p(10, 10))
            path.addLine(to: p(14, 14))

        case .plus:
            path.move(to:    p(8,  3))
            path.addLine(to: p(8,  13))
            path.move(to:    p(3,  8))
            path.addLine(to: p(13, 8))

        case .close:
            path.move(to:    p(3,  3))
            path.addLine(to: p(13, 13))
            path.move(to:    p(13, 3))
            path.addLine(to: p(3,  13))

        case .chevronDown:
            path.move(to:    p(3,  6))
            path.addLine(to: p(8,  11))
            path.addLine(to: p(13, 6))

        case .chevronRight:
            path.move(to:    p(6,  3))
            path.addLine(to: p(11, 8))
            path.addLine(to: p(6,  13))

        case .bold:
            // Capital B in two stacked arcs (approx with lines)
            path.move(to:    p(4,  2))
            path.addLine(to: p(4,  14))
            path.addLine(to: p(10, 14))
            path.move(to:    p(4,  8))
            path.addLine(to: p(10, 8))
            path.move(to:    p(4,  2))
            path.addLine(to: p(10, 2))
            // Add a second "fatness" stroke for bold feel
            path.move(to:    p(5,  2))
            path.addLine(to: p(5,  14))

        case .italic:
            path.move(to:    p(6,  2))
            path.addLine(to: p(11, 2))
            path.move(to:    p(5,  14))
            path.addLine(to: p(10, 14))
            path.move(to:    p(9,  2))
            path.addLine(to: p(7,  14))

        case .strike:
            path.move(to:    p(2,  8))
            path.addLine(to: p(14, 8))
            path.move(to:    p(5,  3))
            path.addLine(to: p(11, 3))
            path.move(to:    p(5,  13))
            path.addLine(to: p(11, 13))

        case .listBullet:
            // Three dots + three lines
            let dotR: CGFloat = 0.9 * s
            for y in [4.0, 8.0, 12.0] as [CGFloat] {
                let c = p(3, y)
                path.addEllipse(in: CGRect(x: c.x - dotR, y: c.y - dotR,
                                           width: 2*dotR, height: 2*dotR))
            }
            path.move(to:    p(6,  4));  path.addLine(to: p(14, 4))
            path.move(to:    p(6,  8));  path.addLine(to: p(14, 8))
            path.move(to:    p(6,  12)); path.addLine(to: p(14, 12))

        case .listNumber:
            // "1." "2." "3." on the left + 3 lines
            // Too detailed for pure vectors — just draw three short left markers
            path.move(to:    p(2,  2));  path.addLine(to: p(2,  6))
            path.move(to:    p(2,  10)); path.addLine(to: p(4,  14))
            path.addLine(to: p(2,  14))
            path.move(to:    p(6,  4));  path.addLine(to: p(14, 4))
            path.move(to:    p(6,  8));  path.addLine(to: p(14, 8))
            path.move(to:    p(6,  12)); path.addLine(to: p(14, 12))

        case .checkbox:
            // Box with a tick + one line
            path.addRect(CGRect(x: rect.minX + 2*s, y: rect.minY + 3*s,
                                width: 5*s, height: 5*s))
            path.move(to:    p(3,  5.5))
            path.addLine(to: p(4,  6.5))
            path.addLine(to: p(6,  4.5))
            // second empty box
            path.addRect(CGRect(x: rect.minX + 2*s, y: rect.minY + 9.5*s,
                                width: 5*s, height: 5*s))
            path.move(to:    p(9,  5.5)); path.addLine(to: p(14, 5.5))
            path.move(to:    p(9,  12));  path.addLine(to: p(14, 12))

        case .quote:
            // Left bar + two horizontal strokes
            path.move(to:    p(3,  3));  path.addLine(to: p(3,  13))
            path.move(to:    p(6,  5));  path.addLine(to: p(13, 5))
            path.move(to:    p(6,  9));  path.addLine(to: p(13, 9))
            path.move(to:    p(6,  13)); path.addLine(to: p(11, 13))

        case .inlineCode:
            // </>
            path.move(to:    p(5,  4))
            path.addLine(to: p(2,  8))
            path.addLine(to: p(5,  12))
            path.move(to:    p(11, 4))
            path.addLine(to: p(14, 8))
            path.addLine(to: p(11, 12))

        case .codeBlock:
            // { … }
            path.move(to:    p(6,  3))
            path.addLine(to: p(4,  3))
            path.addLine(to: p(4,  8))
            path.addLine(to: p(2,  8))
            path.addLine(to: p(4,  8))
            path.addLine(to: p(4,  13))
            path.addLine(to: p(6,  13))
            path.move(to:    p(10, 3))
            path.addLine(to: p(12, 3))
            path.addLine(to: p(12, 8))
            path.addLine(to: p(14, 8))
            path.addLine(to: p(12, 8))
            path.addLine(to: p(12, 13))
            path.addLine(to: p(10, 13))

        case .link:
            // Two linked rounded rects
            path.addRoundedRect(
                in: CGRect(x: rect.minX + 2*s, y: rect.minY + 6*s,
                           width: 6*s, height: 4*s),
                cornerSize: CGSize(width: 1.5*s, height: 1.5*s))
            path.addRoundedRect(
                in: CGRect(x: rect.minX + 8*s, y: rect.minY + 6*s,
                           width: 6*s, height: 4*s),
                cornerSize: CGSize(width: 1.5*s, height: 1.5*s))
            path.move(to:    p(6,  8))
            path.addLine(to: p(10, 8))

        case .wikilink:
            // [[ text ]]
            path.move(to:    p(3,  3))
            path.addLine(to: p(2,  3))
            path.addLine(to: p(2,  13))
            path.addLine(to: p(3,  13))
            path.move(to:    p(5,  3))
            path.addLine(to: p(4,  3))
            path.addLine(to: p(4,  13))
            path.addLine(to: p(5,  13))
            path.move(to:    p(11, 3))
            path.addLine(to: p(12, 3))
            path.addLine(to: p(12, 13))
            path.addLine(to: p(11, 13))
            path.move(to:    p(13, 3))
            path.addLine(to: p(14, 3))
            path.addLine(to: p(14, 13))
            path.addLine(to: p(13, 13))

        case .hr:
            path.move(to:    p(2,  8))
            path.addLine(to: p(14, 8))

        case .tasks:
            // Checklist: small box with tick + 2 lines
            path.addRect(CGRect(x: rect.minX + 2*s, y: rect.minY + 3*s,
                                width: 4*s, height: 4*s))
            path.move(to:    p(8,  5)); path.addLine(to: p(14, 5))
            path.addRect(CGRect(x: rect.minX + 2*s, y: rect.minY + 9*s,
                                width: 4*s, height: 4*s))
            path.move(to:    p(8,  11)); path.addLine(to: p(14, 11))

        case .sparkles:
            // A plus and a small plus (no fills)
            path.move(to:    p(5,  1)); path.addLine(to: p(5,  9))
            path.move(to:    p(1,  5)); path.addLine(to: p(9,  5))
            path.move(to:    p(12, 9)); path.addLine(to: p(12, 15))
            path.move(to:    p(9,  12)); path.addLine(to: p(15, 12))

        case .arrow:
            // Right-pointing arrow
            path.move(to:    p(2,  8)); path.addLine(to: p(13, 8))
            path.move(to:    p(9,  4)); path.addLine(to: p(13, 8))
            path.addLine(to: p(9,  12))

        case .document:
            // Page with folded corner + 3 lines
            path.move(to:    p(3,  2))
            path.addLine(to: p(10, 2))
            path.addLine(to: p(13, 5))
            path.addLine(to: p(13, 14))
            path.addLine(to: p(3,  14))
            path.closeSubpath()
            path.move(to:    p(10, 2)); path.addLine(to: p(10, 5))
            path.addLine(to: p(13, 5))
            path.move(to:    p(5,  8)); path.addLine(to: p(11, 8))
            path.move(to:    p(5,  10.5)); path.addLine(to: p(11, 10.5))

        case .message:
            // Speech bubble
            path.addRoundedRect(
                in: CGRect(x: rect.minX + 2*s, y: rect.minY + 3*s,
                           width: 12*s, height: 8*s),
                cornerSize: CGSize(width: 1.5*s, height: 1.5*s))
            path.move(to:    p(5,  11))
            path.addLine(to: p(5,  14))
            path.addLine(to: p(8,  11))
        }

        return path
    }
}
