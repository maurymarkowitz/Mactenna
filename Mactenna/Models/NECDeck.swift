//
//  NECDeck.swift
//  Mactenna
//
//  Owns the OpenNEC C deck_t and nec_context_t for one document window.
//  This is the live editing model; MactennaDocument is only the I/O wrapper.
//
//  Architecture:
//    • The C library is the sole source of truth for parsed deck data.
//    • All parsing, unit conversion, formula/symbol evaluation, and 4nec2
//      compatibility handling is done by the C library, not re-implemented here.
//    • Swift reads card values out of card_t for display via card(at:).
//    • Phase 2 will write edited values back into card_t fields.

import Foundation
import Combine

// MARK: – NECDeck

final class NECDeck: ObservableObject {

    // MARK: – C pointers

    /// Simulation context (nec_context_t *).  Fully typed now that MactennaOpenNEC.h
    /// includes internals.h and Swift can see the complete struct definition.
    private var ctx: UnsafeMutablePointer<nec_context_t>?
    private var deckPtr: UnsafeMutablePointer<deck_t>?

    // MARK: – Published state

    /// Number of cards currently in the deck — drives NSTableView row count.
    @Published private(set) var cardCount: Int = 0

    /// Parse warnings / errors surfaced to the UI.
    @Published private(set) var parseErrors: [String] = []

    /// Incremented on every field-level edit so ContentView + NSTableView
    /// can react to changes that don't alter cardCount.
    @Published private(set) var editGeneration: Int = 0

    // MARK: – Simulation state (Phase 3)

    /// True while a background simulation run is in progress.
    @Published private(set) var isRunning: Bool = false

    /// The result of the most-recent simulation run, or nil if not yet run.
    @Published private(set) var simulationResult: SimulationResult? = nil

    // MARK: – Default template for new documents

    static let defaultTemplate = """
    CM New antenna deck
    CE
    GW 1 11 0 0 0 0 0 0.25 0.001
    GE 0
    FR 0 1 0 0 299.8 0
    EX 0 1 6 0 1 0
    RP 0 91 1 1000 0 0 1 0
    EN
    """

    // MARK: – Init / deinit

    init(text: String = NECDeck.defaultTemplate) {
        load(text: text)
    }

    deinit {
        tearDown()
    }

    // MARK: – Load

    /// Replace the current deck with a freshly parsed one from `text`.
    /// Writes text to a temp file and passes a FILE* to the C library.
    func load(text: String) {
        tearDown()

        guard let newCtx = nec_create_context() else { return }
        ctx = newCtx

        let newDeck = UnsafeMutablePointer<deck_t>.allocate(capacity: 1)
        newDeck.initialize(to: deck_t())
        deckPtr = newDeck

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".nec")

        do {
            try text.write(to: tmpURL, atomically: true, encoding: .utf8)
        } catch {
            parseErrors = ["Failed to write temp file: \(error.localizedDescription)"]
            return
        }

        guard let fp = fopen(tmpURL.path, "r") else {
            parseErrors = ["Failed to open temp file for read_deck"]
            try? FileManager.default.removeItem(at: tmpURL)
            return
        }

        read_deck(ctx, deckPtr, fp)
        fclose(fp)
        try? FileManager.default.removeItem(at: tmpURL)

        // Let the C library do all structural analysis, unit conversion,
        // formula evaluation, and 4nec2 extension filtering.
        var errors = errors_list_t()
        parse_deck(ctx, deckPtr, &errors)
        mark_4nec2_cards_invisible(ctx, deckPtr)
        update_deck_values(ctx, deckPtr)

        // Surface any parse errors to the UI.
        if errors.num_errors > 0, let list = errors.errors {
            parseErrors = (0..<Int(errors.num_errors)).compactMap { idx in
                list[idx].message.map { String(cString: $0) }
            }
        } else {
            parseErrors = []
        }

        cardCount = Int(deckPtr?.pointee.num_cards ?? 0)
    }

    // MARK: – Serialise

    /// Serialize the current deck_t state to a String using write_deck_onec.
    /// Preserves formulas, symbols, and OpenNEC extensions.
    func text() -> String {
        guard let ctx, let deckPtr else { return "" }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".nec")

        guard let fp = fopen(tmpURL.path, "w") else { return "" }
        write_deck_onec(ctx, deckPtr, fp)
        fclose(fp)

        let result = (try? String(contentsOf: tmpURL, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: tmpURL)
        return result
    }

    // MARK: – Card access

    /// Returns the card types that are contextually valid for the row at `rowIndex`,
    /// based on which section of the deck it falls in.
    ///
    /// Sections are derived from the `deck_t` structural indices set by `parse_deck`:
    ///   • Comment section  (row ≤ comment_end)           → CM, CE + extensions
    ///   • Geometry section (geometry_start … geometry_end) → geometry cards + CM/CE + extensions
    ///   • Control section  (geometry_end+1 … deck_end-1) → control cards + extensions
    ///   • EN card          (row == deck_end)              → EN only
    func validCardTypes(for rowIndex: Int) -> [NECCardType] {
        // Extension cards that can appear anywhere in the deck.
        // PR and LN are NOT real OpenNEC codes (not in onec_codes[]).
        // XT (eXiT), IT (ITerate), OP (OPtimize) exist but are not yet
        // implemented in the UI — revisit when their field semantics are
        // understood.
        let ext: [NECCardType] = [.SY]

        guard let dp = deckPtr else {
            return NECCardType.allCases.filter { $0 != .unknown }
        }
        let d            = dp.pointee
        let commentEnd   = Int(d.comment_end)
        let geoStart     = Int(d.geometry_start)
        let geoEnd       = Int(d.geometry_end)
        let deckEnd      = Int(d.deck_end)

        var types: [NECCardType]

        // Comment header section
        if commentEnd >= 0 && rowIndex <= commentEnd {
            types = [.CM, .CE, .bangComment, .apostComment, .hashComment] + ext
        }
        // Geometry section
        else if geoStart >= 0 && geoEnd >= 0 && rowIndex >= geoStart && rowIndex <= geoEnd {
            let geo = NECCardType.allCases.filter { $0.category == .geometry }
            types = geo + [.CM, .CE, .bangComment, .apostComment, .hashComment] + ext
        }
        // EN terminator
        else if deckEnd >= 0 && rowIndex >= deckEnd {
            types = [.EN]
        }
        // Control section (or gap between sections)
        else {
            let ctrl = NECCardType.allCases.filter { $0.category == .control && $0 != .EN }
            types = ctrl + ext
        }

        // Safety: always include the current card’s own type so the popup
        // never falls back to item 0 (avoids SY → FR mis-display).
        if let currentCode = card(at: rowIndex)?.cardCode,
           let currentType = NECCardType(rawValue: currentCode),
           currentType != .unknown,
           !types.contains(currentType) {
            types.insert(currentType, at: 0)
        }

        return types
    }

    /// Build a DeckRow display proxy for the card at `index`.
    /// Returns nil if the index is out of range.
    func card(at index: Int) -> DeckRow? {
        guard let deckPtr,
              index >= 0,
              index < Int(deckPtr.pointee.num_cards),
              let cards = deckPtr.pointee.cards
        else { return nil }

        // Work with a pointer to avoid copying the card when calling lookup_formula.
        let cardPtr = cards.advanced(by: index)
        let c = cardPtr.pointee

        // card_code is char card_code[3] — a C fixed array, seen as a tuple in Swift.
        let code = withUnsafeBytes(of: c.card_code) { raw -> String in
            let bytes = raw.prefix(while: { $0 != 0 })
            return String(bytes: bytes, encoding: .utf8) ?? "??"
        }

        // i is int i[5], 1-based (i[0] unused). These values are the
        // post-evaluation results after any formulas have been applied.
        let iFields: [Int] = withUnsafeBytes(of: c.i) { raw -> [Int] in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CInt.self)
            return (1...4).map { Int(ptr[$0]) }
        }

        // f is double f[8], 1-based (f[0] unused); these are the
        // evaluated float fields (after formulas/units).
        let fFields: [Double] = withUnsafeBytes(of: c.f) { raw -> [Double] in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: Double.self)
            return (1...7).map { ptr[$0] }
        }

        // comment is char * — an optional C string pointer.
        let comment: String = c.comment.map { String(cString: $0) } ?? ""

        // Formula strings for I1–I4 and F1–F7.  lookup_formula returns nil when
        // the field is a plain numeric literal rather than a formula expression.
        let iFormulas: [String?] = (1...4).map { idx -> String? in
            guard let cStr = lookup_formula(cardPtr, "I\(idx)") else { return nil }
            return String(cString: cStr)
        }
        let fFormulas: [String?] = (1...7).map { idx -> String? in
            guard let cStr = lookup_formula(cardPtr, "F\(idx)") else { return nil }
            return String(cString: cStr)
        }

        // For SY cards, build a human-readable list of symbol assignments from
        // the card's `formulas` linked list: "lambda=0.3, gain=2.5"
        var symbols = ""
        if code == "SY" {
            var parts: [String] = []
            var node = cardPtr.pointee.formulas
            while let n = node {
                let key = n.pointee.key.map { String(cString: $0) } ?? ""
                let val = n.pointee.value.map { String(cString: $0) } ?? ""
                let sep: String
                if n.pointee.separator != 0 {
                    sep = String(bytes: [UInt8(bitPattern: n.pointee.separator)], encoding: .ascii) ?? "="
                } else {
                    sep = "="
                }
                if !key.isEmpty { parts.append("\(key)\(sep)\(val)") }
                node = n.pointee.next
            }
            symbols = parts.joined(separator: ", ")
        }

        // Validate all 11 fields via card_validation.h.
        // results[0..3] = I1..I4, results[4..10] = F1..F7 (per validate_card_all_fields docs).
        var vResults = [field_validation_t](repeating: field_validation_t(), count: 11)
        vResults.withUnsafeMutableBufferPointer { buf in
            validate_card_all_fields(cardPtr, buf.baseAddress!)
        }
        let iValidations = (0..<4).map  { makeFieldValidation(vResults[$0]) }
        let fValidations = (4..<11).map { makeFieldValidation(vResults[$0]) }

        return DeckRow(id: index,
                       cardCode: code,
                       i: iFields,
                       f: fFields,
                       comment: comment,
                       iFormulas: iFormulas,
                       fFormulas: fFormulas,
                       symbols: symbols,
                       iValidations: iValidations,
                       fValidations: fValidations)
    }

    // MARK: – Private helpers

    /// Convert a C field_validation_t to a Swift FieldValidation.
    private func makeFieldValidation(_ r: field_validation_t) -> FieldValidation {
        let sev: FieldValidation.Severity
        switch r.severity.rawValue {
        case 1:  sev = .warning
        case 2:  sev = .problem
        case 3:  sev = .fatal
        default: sev = .none
        }
        let msg = withUnsafeBytes(of: r.message) { raw -> String in
            let bytes = raw.prefix(while: { $0 != 0 })
            return String(bytes: bytes, encoding: .utf8) ?? ""
        }
        return FieldValidation(severity: sev, message: msg)
    }

    // MARK: – Field mutation (Phase 2)

    /// Write an integer value into card_t.i[field] (1-based).
    /// field must be 1…4.  Marks the card edited and bumps editGeneration.
    func setIntField(row: Int, field: Int, value: Int) {
        guard !isRunning else { return }
        guard let deckPtr,
              row   >= 0, row   < Int(deckPtr.pointee.num_cards),
              field >= 1, field <= 4,
              let cards = deckPtr.pointee.cards else { return }
        var card = cards[row]
        withUnsafeMutableBytes(of: &card.i) { raw in
            raw.storeBytes(of: CInt(value),
                           toByteOffset: field * MemoryLayout<CInt>.stride,
                           as: CInt.self)
        }
        card.edited = true
        cards[row] = card
        editGeneration &+= 1
        objectWillChange.send()
    }

    /// Write a floating-point value into card_t.f[field] (1-based).
    /// field must be 1…7.  Marks the card edited and bumps editGeneration.
    func setFloatField(row: Int, field: Int, value: Double) {
        guard !isRunning else { return }
        guard let deckPtr,
              row   >= 0, row   < Int(deckPtr.pointee.num_cards),
              field >= 1, field <= 7,
              let cards = deckPtr.pointee.cards else { return }
        var card = cards[row]
        withUnsafeMutableBytes(of: &card.f) { raw in
            raw.storeBytes(of: value,
                           toByteOffset: field * MemoryLayout<Double>.stride,
                           as: Double.self)
        }
        card.edited = true
        cards[row] = card
        editGeneration &+= 1
        objectWillChange.send()
    }

    /// Replace the comment field of a card (any card, including CM/CE).
    /// Frees the old C string and allocates a fresh one via strdup.
    func setComment(row: Int, text: String) {
        guard !isRunning else { return }
        guard let deckPtr,
              row >= 0, row < Int(deckPtr.pointee.num_cards),
              let cards = deckPtr.pointee.cards else { return }
        var card = cards[row]
        // Free the old C-heap string before overwriting the pointer.
        if let old = card.comment {
            free(UnsafeMutableRawPointer(mutating: old))
        }
        card.comment = text.withCString { strdup($0) }
        card.edited  = true
        cards[row]   = card
        editGeneration &+= 1
        objectWillChange.send()
    }

    /// Change the two-letter card code for the card at `row` (e.g. "GW" → "GA").
    /// Writes directly into card_t.card_code; does NOT reset field values so the
    /// caller should follow up with field edits if needed.
    func setCardCode(row: Int, code: String) {
        guard !isRunning else { return }
        guard let deckPtr,
              row >= 0, row < Int(deckPtr.pointee.num_cards),
              let cards = deckPtr.pointee.cards else { return }
        var card = cards[row]
        // card_code is char[3] — a Swift tuple (CChar, CChar, CChar).
        let bytes = Array(code.uppercased().utf8.prefix(2))
        card.card_code.0 = bytes.count > 0 ? CChar(bitPattern: bytes[0]) : 0
        card.card_code.1 = bytes.count > 1 ? CChar(bitPattern: bytes[1]) : 0
        card.card_code.2 = 0
        card.edited  = true
        cards[row]   = card
        editGeneration &+= 1
        objectWillChange.send()
    }

    // MARK: – Structural edits via C API (Phase 2)
    //
    // insert_card() and remove_card() are now declared in deck.h and exposed
    // through opennec.h → MactennaOpenNEC.h.  Both bugs have been fixed.
    //
    // Each method returns a pre-change text snapshot so the caller can register
    // an undo action via NECDeck.restore(text:).

    /// Insert a blank card of `cardCode` at position `afterIndex + 1`.
    /// Returns the pre-change serialised text for undo registration.
    @discardableResult
    func addCard(_ cardCode: String, after afterIndex: Int) -> String {
        guard !isRunning else { return text() }
        guard let deckPtr, let ctx else { return text() }
        let snapshot = text()

        // Build a zero-initialised card_t and stamp the two-letter card code.
        // insert_card copies by value, so a Swift stack allocation is fine.
        var card = card_t()
        withUnsafeMutableBytes(of: &card.card_code) { raw in
            let bytes = Array(cardCode.utf8.prefix(2))
            if bytes.count > 0 { raw[0] = bytes[0] }
            if bytes.count > 1 { raw[1] = bytes[1] }
        }
        card.edited = true

        let location = CInt(min(afterIndex + 1, Int(deckPtr.pointee.num_cards)))
        insert_card(deckPtr, &card, location)
        update_deck_values(ctx, deckPtr)

        cardCount = Int(deckPtr.pointee.num_cards)
        editGeneration &+= 1
        objectWillChange.send()
        return snapshot
    }

    /// Remove the card at `index`.
    /// Returns the pre-change serialised text for undo registration.
    @discardableResult
    func deleteCard(at index: Int) -> String {
        guard !isRunning else { return text() }
        guard let deckPtr, let ctx else { return text() }
        let snapshot = text()
        guard index >= 0, index < Int(deckPtr.pointee.num_cards) else { return snapshot }

        remove_card(deckPtr, CInt(index))
        update_deck_values(ctx, deckPtr)

        cardCount = Int(deckPtr.pointee.num_cards)
        editGeneration &+= 1
        objectWillChange.send()
        return snapshot
    }

    /// Returns the closed range of valid row positions for the card at `index`.
    /// Returns nil if the card cannot be dragged (GE, EN, out-of-range, or
    /// a section with only one card).
    /// Used by DeckTableView to constrain row drag-drop to the card's own section.
    func allowedMoveRange(forCardAt index: Int) -> ClosedRange<Int>? {
        guard let dp = deckPtr else { return nil }
        let d        = dp.pointee
        let n        = Int(d.num_cards)
        let cmtEnd   = Int(d.comment_end)
        let symStart = Int(d.symbol_start)
        let symEnd   = Int(d.symbol_end)
        let geoStart = Int(d.geometry_start)
        let geoEnd   = Int(d.geometry_end)
        let deckEnd  = Int(d.deck_end)
        guard index >= 0, index < n else { return nil }

        // GE, EN, and anything past EN are structural anchors — not draggable
        if geoEnd  >= 0, index == geoEnd  { return nil }
        if deckEnd >= 0, index >= deckEnd  { return nil }

        // Comment header section (CM/CE)
        if cmtEnd >= 0, index <= cmtEnd {
            let r = 0...cmtEnd
            return r.count > 1 ? r : nil
        }

        // Symbol section (SY cards between CE and geometry)
        if symStart >= 0, symEnd >= symStart, index >= symStart, index <= symEnd {
            let r = symStart...symEnd
            return r.count > 1 ? r : nil
        }

        // Geometry section (up to but NOT including GE)
        if geoStart >= 0, geoEnd > geoStart, index >= geoStart, index < geoEnd {
            let r = geoStart...(geoEnd - 1)
            return r.count > 1 ? r : nil
        }

        // Control section (after GE, before EN)
        if geoEnd >= 0, deckEnd > geoEnd + 1, index > geoEnd, index < deckEnd {
            let r = (geoEnd + 1)...(deckEnd - 1)
            return r.count > 1 ? r : nil
        }

        return nil
    }

    /// Move the card at `src` to insert-before position `dst` (original-array coords).
    /// Validate against `allowedMoveRange` before calling.
    func moveCard(from src: Int, to dst: Int) {
        guard !isRunning else { return }
        guard let deckPtr, let ctx else { return }
        guard src >= 0, src < Int(deckPtr.pointee.num_cards) else { return }
        guard dst >= 0, dst <= Int(deckPtr.pointee.num_cards) else { return }
        guard dst != src, dst != src + 1 else { return }

        move_card(deckPtr, CInt(src), CInt(dst))
        update_deck_values(ctx, deckPtr)

        cardCount = Int(deckPtr.pointee.num_cards)
        editGeneration &+= 1
        objectWillChange.send()
    }

    /// Restore the deck from a serialised snapshot — used as the undo target.
    func restore(text snapshot: String) {
        guard !isRunning else { return }
        load(text: snapshot)
    }

    // MARK: – Debug diagnostics

    /// Dump raw C struct contents for card at row `index` into `simulationResult`
    /// so they appear in the Log window.  Call from a Debug toolbar button only.
    func debugDumpCard(at index: Int) {
        guard let deckPtr,
              index >= 0,
              index < Int(deckPtr.pointee.num_cards),
              let cards = deckPtr.pointee.cards
        else {
            simulationResult = SimulationResult(failed: true,
                errorMessage: "Card \(index) out of range (deck has \(cardCount) cards)",
                outputText: "", logLines: [])
            return
        }

        let cardPtr = cards.advanced(by: index)
        let c = cardPtr.pointee

        let code = withUnsafeBytes(of: c.card_code) { raw -> String in
            let bytes = raw.prefix(while: { $0 != 0 })
            return String(bytes: bytes, encoding: .utf8) ?? "??"
        }

        var lines: [String] = []
        lines.append("── Card \(index + 1) (\(code)) raw C fields ────────────────────────")
        lines.append("")

        // ── f[] raw input floats (1-based) ──────────────────────────────
        lines.append("f[] raw input (as parsed, before formula eval):")
        withUnsafeBytes(of: c.f) { raw in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: Double.self)
            for i in 1...7 {
                lines.append(String(format: "  f[%d] = %g", i, ptr[i]))
            }
        }
        lines.append("")

        // ── f[] evaluated floats (after formula/unit substitution) ───────
        lines.append("f[] evaluated (after formula/unit substitution):")
        withUnsafeBytes(of: c.f) { raw in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: Double.self)
            for i in 1...7 {
                lines.append(String(format: "  f[%d] = %g", i, ptr[i]))
            }
        }
        lines.append("")

        // ── flt_form_inline[] flags (1-based) ───────────────────────────
        lines.append("flt_form_inline[] — true if field was an inline formula:")
        withUnsafeBytes(of: c.flt_form_inline) { raw in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CBool.self)
            for i in 1...7 {
                lines.append("  flt_form_inline[\(i)] = \(ptr[i])")
            }
        }
        lines.append("")

        // ── i[] raw input ints (1-based) ────────────────────────────────
        lines.append("i[] raw input integers:")
        withUnsafeBytes(of: c.i) { raw in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CInt.self)
            for i in 1...4 {
                lines.append("  i[\(i)] = \(ptr[i])")
            }
        }
        lines.append("")

        // ── i[] evaluated integers (after formula/unit substitution) ───────
        lines.append("i[] evaluated integers:")
        withUnsafeBytes(of: c.i) { raw in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CInt.self)
            for i in 1...4 {
                lines.append("  i[\(i)] = \(ptr[i])")
            }
        }
        lines.append("")

        // ── formulas linked list ─────────────────────────────────────────
        lines.append("card->formulas linked list (key=value pairs):")
        var node = c.formulas
        var count = 0
        while let n = node {
            let key = n.pointee.key.map { String(cString: $0) } ?? "(nil)"
            let val = n.pointee.value.map { String(cString: $0) } ?? "(nil)"
            let fv  = n.pointee.fv
            let sep = n.pointee.separator != 0
                ? String(UnicodeScalar(UInt8(bitPattern: n.pointee.separator)))
                : "?"
            lines.append(String(format: "  [%d] key='%@' sep='%@' value='%@' fv=%g",
                                count, key, sep, val, fv))
            node = n.pointee.next
            count += 1
        }
        if count == 0 { lines.append("  (empty)") }
        lines.append("")

        // ── lookup_formula results for F1–F7 ────────────────────────────
        lines.append("lookup_formula() results for F1–F7:")
        for i in 1...7 {
            if let cStr = lookup_formula(cardPtr, "F\(i)") {
                lines.append("  F\(i) → '\(String(cString: cStr))'")
            } else {
                lines.append("  F\(i) → nil (no formula)")
            }
        }

        simulationResult = SimulationResult(failed: false, errorMessage: nil,
                                            outputText: lines.joined(separator: "\n"),
                                            logLines: [])
    }

    // MARK: – Simulation (Phase 3)

    /// Run the NEC simulation in a background queue.
    ///
    /// Creates a fresh simulation context (separate from the editing context)
    /// so results don't overwrite the UI ctx.  The live deck_t is passed
    /// directly — no write_deck_onec / file I/O round-trip.
    /// isRunning guards all mutation methods above, so the deck is stable
    /// for the duration of the background run.
    func runSimulation() {
        guard !isRunning else { return }
        guard let deckPtr else { return }

        isRunning = true
        simulationResult = nil

        // Retain a LogCapture object; the C callback uses it via raw pointer.
        let capture = LogCapture()
        let rawCapture = Unmanaged.passRetained(capture).toOpaque()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                Unmanaged<LogCapture>.fromOpaque(rawCapture).release()
                return
            }

            // ── Create a fresh context for this run ──────────────────────
            guard let simCtx = nec_create_context() else {
                Unmanaged<LogCapture>.fromOpaque(rawCapture).release()
                DispatchQueue.main.async {
                    self.simulationResult = SimulationResult(
                        failed: true, errorMessage: "Could not create simulation context",
                        outputText: "", logLines: [])
                    self.isRunning = false
                }
                return
            }

            // ── Pre-run diagnostics ───────────────────────────────────────
            capture.lines.append("── PRE-RUN DIAGNOSTICS ─────────────────────────────────────")
            capture.lines.append("deck_t structural fields:")
            capture.lines.append("  num_cards      = \(deckPtr.pointee.num_cards)")
            capture.lines.append("  geometry_start = \(deckPtr.pointee.geometry_start)")
            capture.lines.append("  geometry_end   = \(deckPtr.pointee.geometry_end)")
            capture.lines.append("  deck_end       = \(deckPtr.pointee.deck_end)")
            capture.lines.append("  comment_end    = \(deckPtr.pointee.comment_end)")
            capture.lines.append("")
            capture.lines.append("Card codes in deck:")
            if let cards = deckPtr.pointee.cards {
                for i in 0..<Int(deckPtr.pointee.num_cards) {
                    let c = cards[i]
                    let code = withUnsafeBytes(of: c.card_code) { raw -> String in
                        let bytes = raw.prefix(while: { $0 != 0 })
                        return String(bytes: bytes, encoding: .utf8) ?? "??"
                    }
                    let ign = c.ignore ? " [IGNORED]" : ""
                    let cmt = c.comment.map { "  → \(String(cString: $0))" } ?? ""
                    capture.lines.append("  [\(i)] \(code)\(ign)\(cmt)")
                }
            }
            capture.lines.append("")
            capture.lines.append("────────────────────────────────────────────────────────────")

            // ── Wire log callback ─────────────────────────────────────────
            // The closure below captures nothing from the outer scope so
            // Swift can convert it to a @convention(c) function pointer.
            nec_set_log_callback(simCtx, { userData, _, msgPtr in
                guard let rawPtr = userData, let msg = msgPtr else { return }
                Unmanaged<LogCapture>.fromOpaque(rawPtr)
                    .takeUnretainedValue()
                    .lines.append(String(cString: msg))
            }, rawCapture)

            // ── Run ───────────────────────────────────────────────────────
            let runStart = Date()
            let rc = nec_run_simulation(simCtx, deckPtr)
            let elapsed = Date().timeIntervalSince(runStart)

            // ── Read results directly from the context structs ─────────────
            let outputText = NECDeck.formatResults(ctx: simCtx, elapsed: elapsed,
                                                   failed: rc != 0)

            // ── Cleanup ───────────────────────────────────────────────────
            let logLines = capture.lines
            Unmanaged<LogCapture>.fromOpaque(rawCapture).release()
            nec_destroy_context(simCtx)

            let result = SimulationResult(
                failed: rc != 0,
                errorMessage: rc != 0 ? "nec_run_simulation returned \(rc)" : nil,
                outputText: outputText,
                logLines: logLines)

            DispatchQueue.main.async {
                self.simulationResult = result
                self.isRunning = false
            }
        }
    }

    // MARK: – Private

    // Reads results directly from nec_context_t internals after a simulation
    // run and formats them as a human-readable string.
    private static func formatResults(ctx: UnsafeMutablePointer<nec_context_t>, elapsed: Double, failed: Bool) -> String {
        var out = ""

        // ── Header ──────────────────────────────────────────────────────
        let status = failed ? "FAILED" : "complete"
        out += String(format: "── Run \(status) (%.3f s) ──────────────────────────────────────\n", elapsed)

        // XT-terminated decks produce no output by design.
        if nec_result_xt_terminated(ctx) {
            out += "Simulation halted by XT card — no output expected.\n"
            return out
        }

        // ── Frequency ───────────────────────────────────────────────────
        let freqMHz = nec_result_freq_mhz(ctx)
        out += String(format: "Frequency: %.6g MHz\n", freqMHz)

        // ── Antenna inputs ───────────────────────────────────────────────
        let ninp = Int(nec_result_ninp(ctx))
        if ninp > 0 {
            out += "\n"
            out += String(format: "ANTENNA INPUTS  (%d source%@)\n", ninp, ninp == 1 ? "" : "s")
            out += "  #   Tag  Seg        R (Ω)        X (Ω)        Y_r (S)        Y_i (S)     Power (W)\n"
            out += "  ─   ───  ───  ───────────  ───────────  ─────────────  ─────────────  ────────────\n"
            for i in 0..<ninp {
                let tag  = nec_result_inp_tag(ctx, Int32(i))
                let seg  = nec_result_inp_seg(ctx, Int32(i))
                let zr   = nec_result_inp_z_r(ctx, Int32(i))
                let zi   = nec_result_inp_z_i(ctx, Int32(i))
                let yr   = nec_result_inp_y_r(ctx, Int32(i))
                let yi   = nec_result_inp_y_i(ctx, Int32(i))
                let pwr  = nec_result_inp_pwr(ctx, Int32(i))
                out += String(format: "  %d  %4d  %3d  %11.4f  %11.4f  %13.4e  %13.4e  %12.5e\n",
                              i + 1, tag, seg, zr, zi, yr, yi, pwr)
            }
            let pin = nec_result_pin(ctx)
            out += String(format: "\n  Total input power:  %.5e W\n", pin)
        }

        // ── Radiation pattern ────────────────────────────────────────────
        let nrp = Int(nec_result_rpat_npoints(ctx))
        if nrp > 0 {
            let gmax = nec_result_rpat_gmax(ctx)
            let pint = nec_result_rpat_pint(ctx)
            out += "\n"
            out += String(format: "RADIATION PATTERN  (%d point%@)\n", nrp, nrp == 1 ? "" : "s")
            out += String(format: "  Max gain:   %.2f dBi\n", gmax)
            out += String(format: "  Avg power:  %.5e W\n\n", pint)
            out += "  theta     phi    dBi(total)  dBi(H)    dBi(V)    dBi(major)\n"
            out += "  ─────  ──────  ──────────  ────────  ────────  ──────────\n"
            for i in 0..<nrp {
                let theta = nec_result_rpat_theta(ctx, Int32(i))
                let phi   = nec_result_rpat_phi(ctx,   Int32(i))
                let gtot  = nec_result_rpat_gtot(ctx,  Int32(i))
                let gnh   = nec_result_rpat_gnh(ctx,   Int32(i))
                let gnv   = nec_result_rpat_gnv(ctx,   Int32(i))
                let gnmj  = nec_result_rpat_gnmj(ctx,  Int32(i))
                out += String(format: "  %5.1f  %6.1f  %10.2f  %8.2f  %8.2f  %10.2f\n",
                              theta, phi, gtot, gnh, gnv, gnmj)
            }
        }

        // ── Ctx output messages ──────────────────────────────────────────
        let nmsg = Int(nec_result_num_messages(ctx))
        if nmsg > 0 {
            out += "\n"
            out += "OUTPUT MESSAGES\n"
            for i in 0..<nmsg {
                if let ptr = nec_result_message(ctx, Int32(i)) {
                    out += "  " + String(cString: ptr) + "\n"
                }
            }
        }

        // ── Ctx errors ───────────────────────────────────────────────────
        let nerr = Int(nec_result_num_errors(ctx))
        if nerr > 0 {
            out += "\n"
            out += "ERRORS / WARNINGS\n"
            for i in 0..<nerr {
                if let ptr = nec_result_error_msg(ctx, Int32(i)) {
                    out += "  " + String(cString: ptr) + "\n"
                }
            }
        }

        if out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (ninp == 0 && nrp == 0) {
            out += "\n(No structured results found — deck may lack EX/RP cards.)\n"
        }

        return out
    }

    private func tearDown() {
        if let ptr = deckPtr {
            free_deck(ptr)
            ptr.deallocate()
            deckPtr = nil
        }
        if let c = ctx {
            nec_destroy_context(c)
            ctx = nil
        }
        cardCount = 0
    }
}

// MARK: – LogCapture

/// Reference-type accumulator for log lines produced by the C log callback.
/// Passed as `user_data` via an Unmanaged raw pointer so that a @convention(c)
/// closure (which cannot capture context) can still append to it.
private final class LogCapture {
    var lines: [String] = []
}
