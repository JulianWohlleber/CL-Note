import AppKit

// MARK: – Checkbox attachment

/// Lightweight cell that draws a rounded checkbox glyph.
private final class CheckboxAttachmentCell: NSTextAttachmentCell {
    let checked: Bool
    init(checked: Bool) {
        self.checked = checked
        super.init(textCell: "")
    }
    required init(coder: NSCoder) { fatalError() }

    override func cellSize() -> NSSize { NSSize(width: 14, height: 14) }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -2) }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let s   = min(cellFrame.width, cellFrame.height)
        let box = NSRect(x: cellFrame.minX, y: cellFrame.minY, width: s, height: s)
        let path = NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5)

        if checked {
            NSColor(hex: "#7D78FF").withAlphaComponent(0.18).setFill()
            path.fill()
            NSColor(hex: "#7D78FF").setStroke()
        } else {
            NSColor(hex: "#444444").setStroke()
        }
        path.lineWidth = 1.3
        path.stroke()

        if checked {
            let tick = NSBezierPath()
            tick.move(to:    CGPoint(x: cellFrame.minX + s * 0.22, y: cellFrame.minY + s * 0.50))
            tick.line(to:    CGPoint(x: cellFrame.minX + s * 0.44, y: cellFrame.minY + s * 0.72))
            tick.line(to:    CGPoint(x: cellFrame.minX + s * 0.80, y: cellFrame.minY + s * 0.26))
            tick.lineWidth    = 1.5
            tick.lineCapStyle  = .round
            tick.lineJoinStyle = .round
            NSColor(hex: "#7D78FF").setStroke()
            tick.stroke()
        }
    }
}

/// Custom NSTextStorage that applies live syntax highlighting:
/// headings, **bold**, *italic*, `code`, and [[wikilinks]].
final class WikilinkTextStorage: NSTextStorage {

    // A custom attribute we attach to [[...]] ranges so clicks can navigate.
    static let wikilinkKey = NSAttributedString.Key("com.merken.wikilinkTarget")

    // MARK: – Cursor tracking

    /// Character offset of the cursor — updated by WikilinkTextView so we can
    /// decide which checkbox lines are in "edit mode" (show raw text) vs rendered.
    var cursorLocation: Int = 0 {
        didSet {
            guard cursorLocation != oldValue else { return }
            let text = backing.string
            guard !text.isEmpty else { return }
            applyStyles(range: NSRange(text.startIndex..., in: text))
        }
    }

    // MARK: – Backing store

    private var backing = NSMutableAttributedString()

    override var string: String { backing.string }

    override func attributes(at location: Int,
                             effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        guard location < backing.length else {
            range?.pointee = NSRange(location: backing.length, length: 0)
            return [:]
        }
        return backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        let delta = (str as NSString).length - range.length
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: delta)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        guard range.location + range.length <= backing.length else { return }
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: – Syntax highlighting

    override func processEditing() {
        // Re-style only the paragraph(s) that contain the edited range,
        // then fall through so the layout manager gets notified.
        let text = backing.string
        if !text.isEmpty {
            // Expand edited range to full paragraph boundaries
            let nsText  = text as NSString
            let paraRange = nsText.paragraphRange(for: editedRange)
            // But for patterns that can span multiple lines (e.g. wikilinks near ends)
            // we re-style the whole document only when structure may have changed.
            // Heuristic: if the edit contains [, ], *, #, ` — full pass.
            let edited  = nsText.substring(with: editedRange)
            let needsFull = edited.contains(where: { "[]#*`>=~-_+()".contains($0) })
            applyStyles(range: needsFull ? NSRange(text.startIndex..., in: text) : paraRange)
        }
        super.processEditing()
    }

    private func applyStyles(range: NSRange? = nil) {
        let text = backing.string
        guard !text.isEmpty else { return }
        let full = range ?? NSRange(text.startIndex..., in: text)

        // ── 1. Base reset ──────────────────────────────────────────────────
        // Body text uses IBM Plex Serif for an editorial writing feel.
        // Headings use Syne; code uses IBM Plex Mono.
        let bodyPara = NSMutableParagraphStyle()
        bodyPara.lineSpacing      = 5
        bodyPara.paragraphSpacing = 3
        backing.setAttributes([
            .font:            F.serif(15),
            .foregroundColor: C.textNS,
            .paragraphStyle:  bodyPara
        ], range: full)

        // ── 2. Headings (H1-H6, line-by-line) ──────────────────────────────
        (text as NSString).enumerateSubstrings(in: full, options: .byLines) { sub, range, _, _ in
            guard let sub = sub else { return }
            let font: NSFont
            if      sub.hasPrefix("# ")      { font = F.syne(24, weight: .bold) }
            else if sub.hasPrefix("## ")     { font = F.syne(19, weight: .bold) }
            else if sub.hasPrefix("### ")    { font = F.syne(16, weight: .bold) }
            else if sub.hasPrefix("#### ")   { font = F.syne(14, weight: .bold) }
            else if sub.hasPrefix("##### ")  { font = F.syne(13, weight: .bold) }
            else if sub.hasPrefix("###### ") { font = F.syne(12, weight: .bold) }
            else { return }

            self.backing.addAttribute(.font,            value: font,      range: range)
            self.backing.addAttribute(.foregroundColor, value: C.textNS,  range: range)
            // Fade the #/##/### markers (iA Writer style — barely visible)
            let hashLen   = sub.prefix(while: { $0 == "#" }).count + 1
            let hashRange = NSRange(location: range.location, length: min(hashLen, range.length))
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: hashRange)
        }

        // ── 3. Bold **text** ───────────────────────────────────────────────
        regex(#"\*\*(.+?)\*\*"#).enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m = m else { return }
            // Preserve size; switch to bold serif (or bold of whatever font is active)
            let cur  = self.backing.attribute(.font, at: m.range.location, effectiveRange: nil) as? NSFont
                ?? F.serif(15)
            let bold = F.serif(cur.pointSize, weight: .bold)
            self.backing.addAttribute(.font, value: bold, range: m.range)
            // Fade the ** markers
            let openRange  = NSRange(location: m.range.location,        length: 2)
            let closeRange = NSRange(location: m.range.upperBound - 2,  length: 2)
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: openRange)
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: closeRange)
        }

        // ── 4. Italic *text* (not **) ──────────────────────────────────────
        regex(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#).enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m = m else { return }
            let cur    = self.backing.attribute(.font, at: m.range.location, effectiveRange: nil) as? NSFont
                ?? F.serif(15)
            let isBold = cur.fontDescriptor.symbolicTraits.contains(.bold)
            let italic = F.serif(cur.pointSize, weight: isBold ? .bold : .regular, italic: true)
            self.backing.addAttribute(.font, value: italic, range: m.range)
            // Fade the * markers
            let openRange  = NSRange(location: m.range.location,        length: 1)
            let closeRange = NSRange(location: m.range.upperBound - 1,  length: 1)
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: openRange)
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: closeRange)
        }

        // ── 5. Inline code `…` ─────────────────────────────────────────────
        let codeFont = F.mono(13)
        let codeBG   = NSColor.white.withAlphaComponent(0.06)
        regex(#"`([^`\n]+)`"#).enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m = m else { return }
            self.backing.addAttribute(.font,            value: codeFont, range: m.range)
            self.backing.addAttribute(.backgroundColor, value: codeBG,   range: m.range)
        }

        // ── 6. Wikilinks [[NoteName]] or [[NoteName|Alias]] ────────────────
        let wikilinkColor = NSColor(hex: "#7eb3ff")  // visible blue on dark bg
        regex(#"\[\[([^\]\n|]+?)(?:\|([^\]\n]+))?\]\]"#).enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m = m else { return }
            // Visual style on full [[...]]
            self.backing.addAttribute(.foregroundColor, value: wikilinkColor, range: m.range)
            self.backing.addAttribute(.underlineStyle,  value: NSUnderlineStyle.single.rawValue, range: m.range)
            // Navigation target: alias target (group 1)
            if let innerRange = Range(m.range(at: 1), in: text) {
                let target = String(text[innerRange])
                self.backing.addAttribute(WikilinkTextStorage.wikilinkKey, value: target, range: m.range)
            }
            // Dim [[ and ]]
            let open  = NSRange(location: m.range.location, length: 2)
            let close = NSRange(location: m.range.upperBound - 2, length: 2)
            self.backing.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: open)
            self.backing.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: close)
        }

        // ── 7. Blockquote > ────────────────────────────────────────────────
        let quoteColor = C.textDimNS
        (text as NSString).enumerateSubstrings(in: full, options: .byLines) { sub, range, _, _ in
            guard let sub = sub, sub.hasPrefix("> ") else { return }
            self.backing.addAttribute(.foregroundColor, value: quoteColor, range: range)
        }

        // ── 8. Highlight ==text== ──────────────────────────────────────────
        let highlightBG   = NSColor(red: 0.28, green: 0.24, blue: 0.00, alpha: 1) // dark amber
        let highlightText = NSColor(red: 0.95, green: 0.84, blue: 0.30, alpha: 1) // warm yellow
        let markerFade    = NSColor(red: 0.95, green: 0.84, blue: 0.30, alpha: 0.35)
        regex(#"==(.+?)==(?!=)"#).enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m = m else { return }
            self.backing.addAttribute(.backgroundColor,  value: highlightBG,   range: m.range)
            self.backing.addAttribute(.foregroundColor,  value: highlightText, range: m.range)
            // Fade the == markers themselves
            let open  = NSRange(location: m.range.location,       length: 2)
            let close = NSRange(location: m.range.upperBound - 2, length: 2)
            self.backing.addAttribute(.foregroundColor, value: markerFade, range: open)
            self.backing.addAttribute(.foregroundColor, value: markerFade, range: close)
            // Remove background from the markers so only the inner text is highlighted
            self.backing.addAttribute(.backgroundColor, value: NSColor.clear, range: open)
            self.backing.addAttribute(.backgroundColor, value: NSColor.clear, range: close)
        }

        // ── 8b. Strikethrough ~~text~~ ─────────────────────────────────────
        regex(#"~~(.+?)~~"#).enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m = m else { return }
            self.backing.addAttribute(.strikethroughStyle,
                                      value: NSUnderlineStyle.single.rawValue, range: m.range)
            self.backing.addAttribute(.strikethroughColor, value: C.textDimNS, range: m.range)
            let openR  = NSRange(location: m.range.location, length: 2)
            let closeR = NSRange(location: m.range.upperBound - 2, length: 2)
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: openR)
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: closeR)
        }

        // ── 8c. Markdown links [text](url) ─────────────────────────────────
        let linkColor = NSColor(hex: "#7eb3ff")
        regex(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#).enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 3 else { return }
            let textR = m.range(at: 1)
            let urlR  = m.range(at: 2)
            // Style the visible text as a link
            self.backing.addAttribute(.foregroundColor, value: linkColor, range: textR)
            self.backing.addAttribute(.underlineStyle,
                                      value: NSUnderlineStyle.single.rawValue, range: textR)
            // Fade the surrounding syntax [ ] ( url )
            let before = NSRange(location: m.range.location, length: 1) // [
            let mid    = NSRange(location: textR.upperBound, length: 2) // ](
            let after  = NSRange(location: urlR.upperBound,  length: 1) // )
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: before)
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: mid)
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: after)
            self.backing.addAttribute(.foregroundColor, value: C.textDimNS,   range: urlR)
        }

        // ── 8d. Tags #tag (word-start only, not inside headings) ───────────
        let tagColor = NSColor(hex: "#9aa4d6")
        regex(#"(?<=^|[\s(])#([A-Za-z][\w\-/]*)"#).enumerateMatches(in: text, range: full) { m, _, _ in
            guard let m = m else { return }
            // Skip if this hash is actually a heading marker at line start
            let locLine = (text as NSString).lineRange(for: NSRange(location: m.range.location, length: 0))
            let lineText = (text as NSString).substring(with: locLine)
            // Heading lines look like "# ", "## " etc. If the tag would be at
            // the very start of such a line with a following space, skip.
            if lineText.hasPrefix("#"),
               let spaceIdx = lineText.firstIndex(of: " "),
               locLine.location + lineText.distance(from: lineText.startIndex, to: spaceIdx) > m.range.location {
                return
            }
            self.backing.addAttribute(.foregroundColor, value: tagColor, range: m.range)
        }

        // ── 8e. Horizontal rule (--- or *** or ___ alone on a line) ────────
        (text as NSString).enumerateSubstrings(in: full, options: .byLines) { sub, range, _, _ in
            guard let sub = sub else { return }
            let trimmed = sub.trimmingCharacters(in: .whitespaces)
            guard trimmed == "---" || trimmed == "***" || trimmed == "___" else { return }
            self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: range)
            // Add a thin underline to simulate the HR rule
            self.backing.addAttribute(.underlineStyle,
                                      value: NSUnderlineStyle.single.rawValue, range: range)
            self.backing.addAttribute(.underlineColor, value: C.borderNS, range: range)
        }

        // ── 8f. Bullet / numbered list markers ─────────────────────────────
        // Fade the "-", "*", "+", or "1." markers so the content reads cleanly.
        // Skip checkbox lines — those are handled in section 9.
        let bulletRE  = #"^(\s*)([-*+])\s"#
        let numberRE  = #"^(\s*)(\d+\.)\s"#
        (text as NSString).enumerateSubstrings(in: full, options: .byLines) { sub, lineRange, _, _ in
            guard let sub = sub else { return }
            let nsSub = sub as NSString
            let subRange = NSRange(location: 0, length: nsSub.length)

            // Skip checkboxes — handled separately
            let trimmed = sub.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") ||
               trimmed.hasPrefix("- [X] ") { return }

            if let m = (try? NSRegularExpression(pattern: bulletRE))?
                .firstMatch(in: sub, range: subRange),
               m.numberOfRanges >= 3 {
                let markerInSub = m.range(at: 2)
                let globalRange = NSRange(location: lineRange.location + markerInSub.location,
                                          length: markerInSub.length)
                self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: globalRange)
            } else if let m = (try? NSRegularExpression(pattern: numberRE))?
                .firstMatch(in: sub, range: subRange),
               m.numberOfRanges >= 3 {
                let markerInSub = m.range(at: 2)
                let globalRange = NSRange(location: lineRange.location + markerInSub.location,
                                          length: markerInSub.length)
                self.backing.addAttribute(.foregroundColor, value: C.textFaintNS, range: globalRange)
            }
        }

        // ── 9. Checkboxes - [ ] and - [x] ─────────────────────────────────
        // Lines where the cursor rests show the raw markdown (edit mode).
        // All other checkbox lines render a graphical checkbox attachment.
        let checkDoneColor    = NSColor(hex: "#7D78FF")
        let checkDoneBG       = NSColor(hex: "#7D78FF").withAlphaComponent(0.12)
        let checkTextDone     = C.textDimNS
        let checkboxFont      = F.mono(13)
        let cursorLine        = cursorLocation   // snapshot — avoids re-entrancy

        (text as NSString).enumerateSubstrings(in: full, options: .byLines) { sub, lineRange, _, _ in
            guard let sub = sub else { return }
            let trimmed = sub.trimmingCharacters(in: .whitespaces)

            let isDone: Bool
            let markerStr: String
            if trimmed.hasPrefix("- [ ] ") {
                isDone = false; markerStr = "- [ ] "
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                isDone = true;  markerStr = trimmed.hasPrefix("- [x] ") ? "- [x] " : "- [X] "
            } else {
                return
            }

            let leadingSpaces = sub.prefix(while: { $0 == " " || $0 == "\t" }).count
            let markerStart   = lineRange.location + leadingSpaces
            let markerLen     = markerStr.count          // "- [ ] " = 6 chars
            let textStart     = markerStart + markerLen
            let textLen       = lineRange.length - leadingSpaces - markerLen
            guard textLen > 0, textStart + textLen <= (text as NSString).length else { return }
            let textRange     = NSRange(location: textStart, length: textLen)

            let cursorOnLine  = cursorLine >= lineRange.location &&
                                cursorLine <= lineRange.location + lineRange.length

            if cursorOnLine {
                // ── Edit mode: show raw markdown, styled ──────────────────
                // Dim the "- " dash prefix
                let dashRange  = NSRange(location: markerStart, length: 2)
                // Bracket span [ ] or [x]
                let bracketLen  = 3
                let dashOffset  = 2   // after "- "
                let bracketRange = NSRange(location: markerStart + dashOffset, length: bracketLen)

                self.backing.addAttribute(.font,            value: checkboxFont,   range: NSRange(location: markerStart, length: markerLen))
                self.backing.addAttribute(.foregroundColor, value: C.textFaintNS,  range: dashRange)
                if isDone {
                    self.backing.addAttribute(.foregroundColor, value: checkDoneColor, range: bracketRange)
                    self.backing.addAttribute(.backgroundColor, value: checkDoneBG,    range: bracketRange)
                    self.backing.addAttribute(.foregroundColor, value: checkTextDone,  range: textRange)
                    self.backing.addAttribute(.strikethroughStyle,  value: NSUnderlineStyle.single.rawValue, range: textRange)
                    self.backing.addAttribute(.strikethroughColor,  value: checkTextDone, range: textRange)
                } else {
                    self.backing.addAttribute(.foregroundColor, value: NSColor(hex: "#555555"), range: bracketRange)
                }

            } else {
                // ── Rendered mode: hide "- [ ] " and show graphic checkbox ─
                // Make the whole "- [ ] " span invisible except for the checkbox glyph.
                // We replace the visual representation of the leading "- " with nothing
                // by setting foreground = clear, and we draw the attachment at the "["
                // position.

                // Hide "- " prefix
                let hideRange = NSRange(location: markerStart, length: markerLen)
                self.backing.addAttribute(.foregroundColor, value: NSColor.clear, range: hideRange)

                // Draw a checkbox attachment at the bracket position (offset 2 = after "- ")
                let att = NSTextAttachment()
                att.attachmentCell = CheckboxAttachmentCell(checked: isDone)
                // We set the attachment attribute on the "[" character so the layout
                // manager renders the attachment cell there instead of the bracket glyph.
                let bracketPos = NSRange(location: markerStart + 2, length: 1)
                self.backing.addAttribute(.attachment, value: att, range: bracketPos)

                // Style the text part
                if isDone {
                    self.backing.addAttribute(.foregroundColor, value: checkTextDone, range: textRange)
                    self.backing.addAttribute(.strikethroughStyle,  value: NSUnderlineStyle.single.rawValue, range: textRange)
                    self.backing.addAttribute(.strikethroughColor,  value: checkTextDone, range: textRange)
                }
                // (undone text keeps default body color)
            }
        }
    }

    // MARK: – Helpers

    private func regex(_ pattern: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
        (try? NSRegularExpression(pattern: pattern, options: opts)) ?? NSRegularExpression()
    }
}
