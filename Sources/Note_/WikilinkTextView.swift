import AppKit

final class WikilinkTextView: NSTextView {

    // Callbacks wired up by EditorView
    var navigateToNote:  ((String) -> Void)?
    var getNoteTitles:   (() -> [String])?
    var onTextDidChange: (() -> Void)?

    // Picker state
    private var picker:          WikilinkPickerPanel?
    private var isPickerActive   = false
    private var pickerSearchStart: Int = -1   // char offset right after [[

    // MARK: – Click to navigate

    override func mouseDown(with event: NSEvent) {
        let pt       = convert(event.locationInWindow, from: nil)
        let glyphIdx = layoutManager!.glyphIndex(for: pt,
                                                  in: textContainer!,
                                                  fractionOfDistanceThroughGlyph: nil)
        let charIdx  = layoutManager!.characterIndexForGlyph(at: glyphIdx)

        if charIdx < (textStorage?.length ?? 0),
           let target = textStorage?.attribute(WikilinkTextStorage.wikilinkKey,
                                               at: charIdx,
                                               effectiveRange: nil) as? String {
            navigateToNote?(target)
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: – Key handling for picker navigation + shortcuts

    override func keyDown(with event: NSEvent) {
        if isPickerActive {
            switch event.keyCode {
            case 53:         // Esc
                dismissPicker(); return
            case 36:         // Return
                picker?.confirm(); dismissPicker(); return
            case 48:         // Tab
                picker?.confirm(); dismissPicker(); return
            case 125:        // ↓
                picker?.moveDown(); return
            case 126:        // ↑
                picker?.moveUp(); return
            default: break
            }
        }

        // ⌘Return → insert / toggle checkbox on current line
        let cmd = event.modifierFlags.contains(.command)
        if cmd && event.keyCode == 36 {   // 36 = Return
            toggleCheckboxOnCurrentLine()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: – insertText: handles auto-pairing like Obsidian

    /// Characters that auto-pair when typed. Typing the closing char when it's
    /// already there just steps over it instead of inserting a duplicate.
    private static let autoPairs: [String: String] = [
        "(": ")",
        "[": "]",
        "{": "}",
        "\"": "\"",
        "'":  "'",
        "`":  "`",
    ]

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let ts = textStorage else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let full  = ts.string as NSString
        let input: String = (string as? String) ?? ((string as? NSAttributedString)?.string ?? "")
        let sel   = selectedRange()

        // Case 1: skip over matching closing bracket when caret is right before it
        //         (so typing ")" inside "(|)" steps the caret forward).
        if input.count == 1, "})]\"'`".contains(input.first!),
           sel.length == 0, sel.location < full.length {
            let next = full.substring(with: NSRange(location: sel.location, length: 1))
            if next == input {
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                return
            }
        }

        // Case 2: typing the second "[" right after an existing "[" → delegate
        //         to the picker logic (handleTextChange triggers it).
        //         Regular super.insertText handles the character itself.

        // Case 3: auto-pair opening bracket / quote characters
        if input.count == 1, let close = Self.autoPairs[input] {
            // If there is a selection, wrap it instead of pairing empty.
            let replacement = input + (sel.length > 0
                                       ? full.substring(with: sel)
                                       : "") + close
            if shouldChangeText(in: sel, replacementString: replacement) {
                ts.replaceCharacters(in: sel, with: replacement)
                didChangeText()
                // Place caret inside the pair (after opener + optional content)
                let caret = sel.location + 1 + sel.length
                setSelectedRange(NSRange(location: caret, length: 0))
            }
            return
        }

        // Case 4: typing "*" → when selection non-empty, wrap as **bold** or *italic*
        //         Handled by the existing toolbar bold/italic, not here.

        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: – Enter: smart list continuation

    override func insertNewline(_ sender: Any?) {
        guard let ts = textStorage else { super.insertNewline(sender); return }
        let str  = ts.string as NSString
        let sel  = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = str.substring(with: lineRange)
        // Strip the trailing newline (if any) for inspection
        let lineNoNL = line.hasSuffix("\n") ? String(line.dropLast()) : line

        let leadingCount = lineNoNL.prefix(while: { $0 == " " || $0 == "\t" }).count
        let leading      = String(lineNoNL.prefix(leadingCount))
        let rest         = String(lineNoNL.dropFirst(leadingCount))

        // Detect list patterns
        // 1) unchecked / checked task
        if rest.hasPrefix("- [ ] ") || rest.hasPrefix("- [x] ") || rest.hasPrefix("- [X] ") {
            let afterMarker = String(rest.dropFirst(6))
            if afterMarker.isEmpty {
                // Empty task line → break out of the list
                replaceCurrentLine(with: leading)
                return
            }
            insertAtCaret("\n\(leading)- [ ] ")
            return
        }
        // 2) plain bullet - / * / +
        if let marker = rest.first.map(String.init),
           "-*+".contains(marker), rest.hasPrefix("\(marker) ") {
            let afterMarker = String(rest.dropFirst(2))
            if afterMarker.isEmpty {
                replaceCurrentLine(with: leading)
                return
            }
            insertAtCaret("\n\(leading)\(marker) ")
            return
        }
        // 3) numbered list "N. "
        if let match = rest.range(of: #"^(\d+)\. "#, options: .regularExpression) {
            let numStr = String(rest[match].dropLast(2))   // strips ". "
            let afterMarker = String(rest[match.upperBound...])
            if afterMarker.isEmpty {
                replaceCurrentLine(with: leading)
                return
            }
            if let n = Int(numStr) {
                insertAtCaret("\n\(leading)\(n + 1). ")
                return
            }
        }
        // 4) blockquote
        if rest.hasPrefix("> ") {
            let afterMarker = String(rest.dropFirst(2))
            if afterMarker.isEmpty {
                replaceCurrentLine(with: leading)
                return
            }
            insertAtCaret("\n\(leading)> ")
            return
        }

        // Default: plain newline preserving indent
        if !leading.isEmpty {
            insertAtCaret("\n\(leading)")
            return
        }
        super.insertNewline(sender)
    }

    /// Replace the current logical line (including trailing newline if present)
    /// with the given string, placing the caret at the end of the replacement.
    private func replaceCurrentLine(with replacement: String) {
        guard let ts = textStorage else { return }
        let str = ts.string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        if shouldChangeText(in: lineRange, replacementString: replacement) {
            ts.replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
            let caret = lineRange.location + (replacement as NSString).length
            setSelectedRange(NSRange(location: caret, length: 0))
        }
    }

    /// Insert `text` at the current caret and place the caret after it.
    private func insertAtCaret(_ text: String) {
        guard let ts = textStorage else { return }
        let sel = selectedRange()
        if shouldChangeText(in: sel, replacementString: text) {
            ts.replaceCharacters(in: sel, with: text)
            didChangeText()
            let caret = sel.location + (text as NSString).length
            setSelectedRange(NSRange(location: caret, length: 0))
        }
    }

    // MARK: – Tab / Shift+Tab: indent / outdent

    override func insertTab(_ sender: Any?) {
        guard let ts = textStorage else { super.insertTab(sender); return }
        let str = ts.string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: sel)

        // Only indent if this looks like a list line — otherwise behave normally.
        let subs = str.substring(with: lineRange)
        if isListLine(subs) {
            indentLines(lineRange, by: "  ")
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        guard let ts = textStorage else { super.insertBacktab(sender); return }
        let str = ts.string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: sel)
        let subs = str.substring(with: lineRange)
        if isListLine(subs) {
            outdentLines(lineRange)
            return
        }
        super.insertBacktab(sender)
    }

    private func isListLine(_ block: String) -> Bool {
        for line in block.components(separatedBy: "\n") {
            let t = line.drop(while: { $0 == " " || $0 == "\t" })
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") ||
               t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ") ||
               (t.range(of: #"^\d+\. "#, options: .regularExpression) != nil) {
                return true
            }
        }
        return false
    }

    private func indentLines(_ range: NSRange, by pad: String) {
        guard let ts = textStorage else { return }
        let str     = ts.string as NSString
        let block   = str.substring(with: range)
        let padded  = block.components(separatedBy: "\n")
            .enumerated()
            .map { i, line -> String in
                // Don't indent trailing empty line from split
                (line.isEmpty && i == block.components(separatedBy: "\n").count - 1) ? line : pad + line
            }
            .joined(separator: "\n")
        if shouldChangeText(in: range, replacementString: padded) {
            ts.replaceCharacters(in: range, with: padded)
            didChangeText()
            setSelectedRange(NSRange(location: range.location,
                                     length: (padded as NSString).length))
        }
    }

    private func outdentLines(_ range: NSRange) {
        guard let ts = textStorage else { return }
        let str   = ts.string as NSString
        let block = str.substring(with: range)
        let out = block.components(separatedBy: "\n")
            .map { line -> String in
                if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
                if line.hasPrefix("\t") { return String(line.dropFirst(1)) }
                if line.hasPrefix(" ")  { return String(line.dropFirst(1)) }
                return line
            }
            .joined(separator: "\n")
        if shouldChangeText(in: range, replacementString: out) {
            ts.replaceCharacters(in: range, with: out)
            didChangeText()
            setSelectedRange(NSRange(location: range.location,
                                     length: (out as NSString).length))
        }
    }

    // MARK: – Backspace: smart delete of list markers and pairs

    override func deleteBackward(_ sender: Any?) {
        guard let ts = textStorage else { super.deleteBackward(sender); return }
        let str = ts.string as NSString
        let sel = selectedRange()

        // 1) Delete empty auto-pair (e.g. caret between `()` removes both)
        if sel.length == 0, sel.location > 0, sel.location < str.length {
            let prev = str.substring(with: NSRange(location: sel.location - 1, length: 1))
            let next = str.substring(with: NSRange(location: sel.location,     length: 1))
            let pairs: [String: String] = ["(": ")", "[": "]", "{": "}",
                                           "\"": "\"", "'": "'", "`": "`"]
            if let expected = pairs[prev], expected == next {
                let r = NSRange(location: sel.location - 1, length: 2)
                if shouldChangeText(in: r, replacementString: "") {
                    ts.replaceCharacters(in: r, with: "")
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location - 1, length: 0))
                    return
                }
            }
        }

        // 2) Delete list marker at end of empty list item
        if sel.length == 0 {
            let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
            let line = str.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Caret must be at the end of the marker
            let caretInLine = sel.location - lineRange.location
            let markers = ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "+ ", "> "]
            for m in markers where trimmed == String(m.dropLast()) {
                // e.g. "- " with caret at pos 2 of line = user just wants to clear marker
                let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                if caretInLine == leading + m.count {
                    let r = NSRange(location: lineRange.location + leading, length: m.count)
                    if shouldChangeText(in: r, replacementString: "") {
                        ts.replaceCharacters(in: r, with: "")
                        didChangeText()
                        setSelectedRange(NSRange(location: lineRange.location + leading, length: 0))
                        return
                    }
                }
            }
        }

        super.deleteBackward(sender)
    }

    // MARK: – Checkbox toggle on current line (⌘Return)

    private func toggleCheckboxOnCurrentLine() {
        guard let ts = textStorage else { return }
        let str  = ts.string as NSString
        let sel  = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = str.substring(with: lineRange)

        let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let rest    = (line as NSString).substring(from: leading)

        let newLine: String
        if rest.hasPrefix("- [ ] ") {
            newLine = String(line.prefix(leading)) + "- [x] " + rest.dropFirst(6)
        } else if rest.hasPrefix("- [x] ") || rest.hasPrefix("- [X] ") {
            newLine = String(line.prefix(leading)) + "- [ ] " + rest.dropFirst(6)
        } else {
            newLine = String(line.prefix(leading)) + "- [ ] " + rest
        }

        if shouldChangeText(in: lineRange, replacementString: newLine) {
            ts.replaceCharacters(in: lineRange, with: newLine)
            didChangeText()
            let newSel = NSRange(location: lineRange.location + (newLine as NSString).length - 1,
                                 length: 0)
            setSelectedRange(newSel)
        }
    }

    // MARK: – Cursor tracking

    override func setSelectedRange(_ charRange: NSRange,
                                   affinity: NSSelectionAffinity,
                                   stillSelecting flag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        (textStorage as? WikilinkTextStorage)?.cursorLocation = charRange.location
    }

    // MARK: – Called from Coordinator after each text change

    func handleTextChange() {
        let cursorPos = selectedRange().location
        let str       = string as NSString

        // Check if we just typed the second [
        if cursorPos >= 2 {
            let two = str.substring(with: NSRange(location: cursorPos - 2, length: 2))
            if two == "[[" && !isPickerActive {
                showPicker(at: cursorPos)
                return
            }
        }

        // Update picker query while active
        if isPickerActive {
            if cursorPos > pickerSearchStart {
                let query = str.substring(with: NSRange(location: pickerSearchStart,
                                                         length: cursorPos - pickerSearchStart))
                if query.contains("]]") || query.contains("\n") || query.contains("[") {
                    dismissPicker()
                } else {
                    picker?.updateQuery(query)
                    repositionPicker()
                }
            } else {
                dismissPicker()
            }
        }
    }

    // MARK: – Picker lifecycle

    private func showPicker(at startPos: Int) {
        guard let window = window else { return }
        isPickerActive    = true
        pickerSearchStart = startPos

        let titles = getNoteTitles?() ?? []
        picker = WikilinkPickerPanel(titles: titles) { [weak self] title in
            self?.insertWikilink(title)
            self?.dismissPicker()
        }
        picker?.show(near: cursorScreenRect(), in: window)
    }

    private func repositionPicker() {
        picker?.reposition(near: cursorScreenRect())
    }

    private func dismissPicker() {
        isPickerActive    = false
        pickerSearchStart = -1
        picker?.close()
        picker = nil
    }

    private func insertWikilink(_ title: String) {
        let cursorPos   = selectedRange().location
        // Delete from [[ through the query typed so far, replace with [[title]]
        let deleteStart = pickerSearchStart - 2          // position of first [
        guard deleteStart >= 0 else { return }
        let deleteLen   = cursorPos - deleteStart
        guard deleteLen >= 0 else { return }
        let range       = NSRange(location: deleteStart, length: deleteLen)
        insertText("[[\(title)]]", replacementRange: range)
    }

    private func cursorScreenRect() -> NSRect {
        let charRange = selectedRange()
        let rect      = firstRect(forCharacterRange: charRange, actualRange: nil)
        return window?.convertToScreen(rect) ?? rect
    }

    // MARK: – Markdown formatting actions (toolbar + keyboard)

    /// Wrap the current selection with prefix/suffix. If empty selection,
    /// inserts the markers and places cursor between them.
    private func wrapSelection(prefix: String, suffix: String) {
        let sel = selectedRange()
        guard let ts = textStorage else { return }

        let full = ts.string as NSString
        if sel.length > 0 {
            let selected = full.substring(with: sel)
            let new      = prefix + selected + suffix
            if shouldChangeText(in: sel, replacementString: new) {
                ts.replaceCharacters(in: sel, with: new)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + prefix.count,
                                          length: sel.length))
            }
        } else {
            let insert = prefix + suffix
            if shouldChangeText(in: sel, replacementString: insert) {
                ts.replaceCharacters(in: sel, with: insert)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + prefix.count, length: 0))
            }
        }
    }

    /// Prepend a marker to each line in the current selection (or the current line if none).
    private func prefixLines(_ marker: String, toggle: Bool = true) {
        guard let ts = textStorage else { return }
        let str = ts.string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: sel)

        let block = str.substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        // Drop trailing empty piece produced by splitting on the final \n
        let usable = lines.last == "" ? Array(lines.dropLast()) : lines

        // Figure out toggle: only toggle off if every non-empty line already has the marker
        let allHave = toggle && usable.allSatisfy { $0.isEmpty || $0.hasPrefix(marker) }

        let transformed = usable.map { line -> String in
            if line.isEmpty { return line }
            if allHave {
                return String(line.dropFirst(marker.count))
            }
            // Strip other heading markers first so they don't stack
            var stripped = line
            for m in ["# ", "## ", "### ", "- [ ] ", "- [x] ", "- ", "> ", "1. "] {
                if stripped.hasPrefix(m) { stripped = String(stripped.dropFirst(m.count)); break }
            }
            return marker + stripped
        }
        var newBlock = transformed.joined(separator: "\n")
        if lines.last == "" { newBlock += "\n" }

        if shouldChangeText(in: lineRange, replacementString: newBlock) {
            ts.replaceCharacters(in: lineRange, with: newBlock)
            didChangeText()
            let newLen = (newBlock as NSString).length
            setSelectedRange(NSRange(location: lineRange.location, length: newLen))
        }
    }

    private func insertAtCursor(_ text: String, offset: Int? = nil) {
        let sel = selectedRange()
        guard let ts = textStorage,
              shouldChangeText(in: sel, replacementString: text) else { return }
        ts.replaceCharacters(in: sel, with: text)
        didChangeText()
        let caret = sel.location + (offset ?? (text as NSString).length)
        setSelectedRange(NSRange(location: caret, length: 0))
    }

    // Public API the toolbar calls:
    func applyBold()          { wrapSelection(prefix: "**", suffix: "**") }
    func applyItalic()        { wrapSelection(prefix: "*",  suffix: "*") }
    func applyStrikethrough() { wrapSelection(prefix: "~~", suffix: "~~") }
    func applyInlineCode()    { wrapSelection(prefix: "`",  suffix: "`") }
    func applyH1()            { prefixLines("# ") }
    func applyH2()            { prefixLines("## ") }
    func applyH3()            { prefixLines("### ") }
    func applyBulletList()    { prefixLines("- ") }
    func applyNumberList()    { prefixLines("1. ") }
    func applyCheckbox()      { prefixLines("- [ ] ") }
    func applyQuote()         { prefixLines("> ") }
    func applyCodeBlock()     { wrapSelection(prefix: "```\n", suffix: "\n```") }
    func applyHR()            { insertAtCursor("\n\n---\n\n") }
    func applyLink()          {
        let sel = selectedRange()
        guard let ts = textStorage else { return }
        let selected = (ts.string as NSString).substring(with: sel)
        let text = selected.isEmpty ? "[]()" : "[\(selected)](url)"
        insertAtCursor(text, offset: selected.isEmpty ? 1 : text.count - 4)
    }
    func applyWikilink() {
        let sel = selectedRange()
        guard let ts = textStorage else { return }
        let selected = (ts.string as NSString).substring(with: sel)
        if selected.isEmpty {
            insertAtCursor("[[]]", offset: 2)   // caret between brackets
        } else {
            insertAtCursor("[[\(selected)]]")
        }
    }
}
