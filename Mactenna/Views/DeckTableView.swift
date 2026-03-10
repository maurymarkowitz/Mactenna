//
//  DeckTableView.swift
//  Mactenna
//
//  NSTableView-based deck editor wrapped in NSViewRepresentable.
//  macOS only — the iPadOS target will use a separate List-based view.
//
//  Phase 1: read-only display, all 13 columns (Card, I1–I4, F1–F7, Comment).
//  Phase 2: in-place cell editing, row add/delete/reorder.
//
//  Column identifiers match NEC field names exactly so they can be stored
//  in user preferences for column ordering/visibility later.

#if os(macOS)
import SwiftUI
import AppKit

// MARK: – Column descriptor

private struct Col {
    let id: String
    let title: String
    let minWidth: CGFloat
    let idealWidth: CGFloat
    let maxWidth: CGFloat
    let alignment: NSTextAlignment
}

private let columns: [Col] = [
    Col(id: "rownum",  title: "#",       minWidth: 28,  idealWidth: 32,  maxWidth: 40,   alignment: .right),
    Col(id: "card",    title: "Type",    minWidth: 50,  idealWidth: 50,  maxWidth: 75,   alignment: .left),
    Col(id: "I1",      title: "I1",      minWidth: 36,  idealWidth: 40,  maxWidth: 80,   alignment: .right),
    Col(id: "I2",      title: "I2",      minWidth: 36,  idealWidth: 40,  maxWidth: 80,   alignment: .right),
    Col(id: "I3",      title: "I3",      minWidth: 36,  idealWidth: 40,  maxWidth: 80,   alignment: .right),
    Col(id: "I4",      title: "I4",      minWidth: 36,  idealWidth: 40,  maxWidth: 80,   alignment: .right),
    Col(id: "F1",      title: "F1",      minWidth: 58,  idealWidth: 58,  maxWidth: 200,  alignment: .right),
    Col(id: "F2",      title: "F2",      minWidth: 58,  idealWidth: 58,  maxWidth: 200,  alignment: .right),
    Col(id: "F3",      title: "F3",      minWidth: 58,  idealWidth: 58,  maxWidth: 200,  alignment: .right),
    Col(id: "F4",      title: "F4",      minWidth: 58,  idealWidth: 58,  maxWidth: 200,  alignment: .right),
    Col(id: "F5",      title: "F5",      minWidth: 58,  idealWidth: 58,  maxWidth: 200,  alignment: .right),
    Col(id: "F6",      title: "F6",      minWidth: 58,  idealWidth: 58,  maxWidth: 200,  alignment: .right),
    Col(id: "F7",      title: "F7",      minWidth: 58,  idealWidth: 58,  maxWidth: 200,  alignment: .right),
    // checkbox column: toggles card.ignore state
    Col(id: "ignore",  title: "Ignored", minWidth: 24,  idealWidth: 24,  maxWidth: 30,   alignment: .center),
    // second checkbox column: toggles card.invisible flag
    Col(id: "invisible", title: "Invisible", minWidth: 24, idealWidth: 24, maxWidth: 30, alignment: .center),
    Col(id: "comment", title: "Comment", minWidth: 60,  idealWidth: 200, maxWidth: 500,  alignment: .left),
]

// Internal pasteboard type for deck row drag-reorder.
private let deckRowPBType = NSPasteboard.PasteboardType("com.mactenna.deckRowIndex")

// MARK: – Editable cell subclass

/// NSTextField that remembers which deck row and column it belongs to.
/// This lets the text-field delegate identify the field being edited without
/// additional bookkeeping in the NSTableView data source.
private final class EditableCell: NSTextField {
    var row:   Int    = -1
    var colID: String = ""
}

/// NSPopUpButton that remembers which deck row it belongs to.
/// Used for the Type (card code) column so the user picks from a
/// contextually filtered list rather than typing a raw code.
private final class CardTypePopup: NSPopUpButton {
    var row: Int = -1
}

// MARK: – NSViewRepresentable

struct DeckTableView: NSViewRepresentable {

    @ObservedObject var deck: NECDeck
    @Binding var selectedIndex: Int?

    /// Called when the user commits an edit: (rowIndex, columnID, newStringValue).
    /// The parent view is responsible for writing the value into the model
    /// and registering undo.
    var onCommitEdit: (Int, String, String) -> Void = { _, _, _ in }

    /// Called just before a row drag completes: (srcIndex, dropRow, preMoveSnapshot).
    /// The parent view is responsible for registering undo using the snapshot.
    var onMove: (Int, Int, String) -> Void = { _, _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(deck: deck, selectedIndex: $selectedIndex, onCommitEdit: onCommitEdit, onMove: onMove)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = false
        tableView.allowsMultipleSelection = false
        tableView.rowSizeStyle = .default
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        // the table itself doesn't have an isEditable flag; editing is
        // controlled via the delegate’s `tableView(_:shouldEdit:row:)`
        // implementation (see below).
        // wire up a double-click action so we can explicitly begin editing
        // the cell that was clicked.  Some behaviours (especially when views
        // are borderless) don't reliably provoke the normal text‑editor
        // start sequence, so we'll trigger it ourselves.
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.tableViewDoubleClicked(_:))
        for col in columns {
            let tc = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.id))
            tc.title = col.title
            tc.minWidth = col.minWidth
            tc.width = col.idealWidth
            tc.maxWidth = col.maxWidth
            tc.resizingMask = .userResizingMask

            // Add a tooltip describing the column purpose.  Keep it brief;
            // specific field tooltips are provided by the editable cells themselves.
            // TODO: what is the tip called, if any?
//            let tip: String
//            switch col.id {
//            case "rownum":     tip = "Row number (1‑based)"
//            case "ignore":     tip = "Check to comment out (ignore) the card"
//            case "invisible":  tip = "Mark card invisible (no other effect)"
//            case "card":       tip = "NEC card type (two-letter code)"
//            case "comment":    tip = "Comment text attached to the card"
//            default:
//                if col.id.hasPrefix("I") {
//                    tip = "Integer field \(col.id.dropFirst())"
//                } else if col.id.hasPrefix("F") {
//                    tip = "Float field \(col.id.dropFirst())"
//                } else {
//                    tip = col.title
//                }
//            }
//            tc.headerCell.toolTip = tip

            if col.alignment == .right {
                let header = NSTableHeaderCell()
                header.title = col.title
                header.alignment = .right
                //header.toolTip = tip
                tc.headerCell = header
            }
            tableView.addTableColumn(tc)
        }

        tableView.dataSource = context.coordinator
        tableView.delegate   = context.coordinator
        context.coordinator.tableView = tableView

        tableView.registerForDraggedTypes([deckRowPBType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        // add overlay labels for sections (may be disabled by pref)
        let showLabels = Preferences.shared.deckShowSectionLabels
        let labels: [NSTextField] = ["Comments", "Symbols", "Geometry", "Control"].map { title in
            let lbl = NSTextField(labelWithString: title)
            lbl.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            lbl.textColor = .secondaryLabelColor
            lbl.backgroundColor = .clear
            lbl.isBordered = false
            lbl.isEditable = false
            lbl.isSelectable = false
            lbl.alignment = .left
            lbl.isHidden = !showLabels
            scroll.addSubview(lbl)
            return lbl
        }
        context.coordinator.sectionLabels = labels
        // listen for scrolling or resizing to reposition labels
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(Coordinator.scrollViewDidScroll(_:)),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scroll.contentView)
        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(Coordinator.scrollViewDidScroll(_:)),
                                               name: NSView.frameDidChangeNotification,
                                               object: scroll.contentView)
        // also watch for live scrolling (wheel or trackpad) to ensure labels track
        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(Coordinator.scrollViewDidScroll(_:)),
                                               name: NSScrollView.didLiveScrollNotification,
                                               object: scroll)

        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.deck          = deck
        context.coordinator.onCommitEdit  = onCommitEdit   // keep closure fresh
        context.coordinator.onMove        = onMove          // keep closure fresh
        // don't reload while the user is actively editing; doing so will
        // terminate the editor and make it impossible to type.  `currentEditor`
        // returns the field editor if one is active.
        if tableView.currentEditor() == nil {
            tableView.reloadData()
        }

        // Refresh column headers for the current selection.
        if let idx = selectedIndex, let row = deck.card(at: idx) {
            context.coordinator.updateColumnHeaders(for: row.cardType)
        } else {
            context.coordinator.updateColumnHeaders(for: .unknown)
        }

        // Sync external selection → table
        if let idx = selectedIndex {
            if tableView.selectedRow != idx {
                tableView.selectRowIndexes(IndexSet(integer: idx),
                                           byExtendingSelection: false)
            }
        } else {
            tableView.deselectAll(nil)
        }

        // ensure labels are positioned initially or after updates
        context.coordinator.repositionSectionLabels()
    }

    // MARK: – Coordinator

    class SectionRowView: NSTableRowView {
        var hasThickBottom: Bool = false
        override func drawBackground(in dirtyRect: NSRect) {
            super.drawBackground(in: dirtyRect)
            if hasThickBottom {
                // draw line along bottom edge instead of top
                let y = bounds.height - 1
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 0, y: y))
                line.line(to: NSPoint(x: bounds.width, y: y))
                NSColor.separatorColor.setStroke()
                line.lineWidth = 3  // slightly thicker
                line.stroke()
            }
        }
    }

    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

        var deck: NECDeck
        var selectedIndex: Binding<Int?>
        var onCommitEdit: (Int, String, String) -> Void
        var onMove: (Int, Int, String) -> Void
        weak var tableView: NSTableView?
        // labels overlayed in the scrollview
        var sectionLabels: [NSTextField] = []

        init(deck: NECDeck,
             selectedIndex: Binding<Int?>,
             onCommitEdit: @escaping (Int, String, String) -> Void,
             onMove: @escaping (Int, Int, String) -> Void) {
            self.deck          = deck
            self.selectedIndex = selectedIndex
            self.onCommitEdit  = onCommitEdit
            self.onMove        = onMove
        }

        // MARK: NSTextFieldDelegate – commit edit

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let cell = notification.object as? EditableCell,
                  cell.row >= 0 else { return }
            onCommitEdit(cell.row, cell.colID, cell.stringValue)
        }

        // MARK: NSPopUpButton action – card type changed

        @objc func cardTypePopupChanged(_ sender: NSPopUpButton) {
            guard let popup = sender as? CardTypePopup,
                  popup.row >= 0,
                  let code = popup.selectedItem?.representedObject as? String
            else { return }
            onCommitEdit(popup.row, "card", code)
        }

        // MARK: Ignore checkbox action
        @objc func ignoreCheckboxToggled(_ sender: NSButton) {
            let row = sender.tag
            let shouldIgnore = (sender.state == .on)
            deck.setIgnored(row: row, ignore: shouldIgnore)
            tableView?.reloadData()
        }

        // MARK: Invisible checkbox action
        @objc func invisibleCheckboxToggled(_ sender: NSButton) {
            let row = sender.tag
            let shouldBeInvisible = (sender.state == .on)
            deck.setInvisible(row: row, invisible: shouldBeInvisible)
            // no visual change required, but update the cell in case external
            // code reads the property for some reason.
            tableView?.reloadData()
        }

        // MARK: NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            deck.cardCount
        }

        // MARK: NSTableViewDataSource – row drag and drop

        func tableView(_ tableView: NSTableView,
                       pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard deck.allowedMoveRange(forCardAt: row) != nil else { return nil }
            let item = NSPasteboardItem()
            item.setString(String(row), forType: deckRowPBType)
            return item
        }

        func tableView(_ tableView: NSTableView,
                       validateDrop info: NSDraggingInfo,
                       proposedRow row: Int,
                       proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
            guard let srcStr = info.draggingPasteboard.string(forType: deckRowPBType),
                  let src = Int(srcStr),
                  let range = deck.allowedMoveRange(forCardAt: src)
            else { return [] }

            // Validate range BEFORE calling setDropRow — calling setDropRow and
            // then returning [] confuses AppKit into accepting the drop anyway.
            let lo = range.lowerBound
            let hi = range.upperBound + 1          // +1: allow inserting after last in section
            guard row >= lo, row <= hi,
                  row != src, row != src + 1        // these two positions are no-ops
            else { return [] }

            // Only tell NSTableView where to show the indicator once we're sure it's valid.
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }

        func tableView(_ tableView: NSTableView,
                       acceptDrop info: NSDraggingInfo,
                       row: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
            guard let srcStr = info.draggingPasteboard.string(forType: deckRowPBType),
                  let src = Int(srcStr),
                  let range = deck.allowedMoveRange(forCardAt: src)
            else { return false }

            // Second-line-of-defence: reject cross-section drops even if validateDrop
            // somehow passed them through.
            let lo = range.lowerBound
            let hi = range.upperBound + 1
            guard row >= lo, row <= hi else { return false }

            let snapshot = deck.text()
            onMove(src, row, snapshot)
            deck.moveCard(from: src, to: row)
            tableView.reloadData()

            // Select the card at its new visual position.
            let newRow = row > src ? row - 1 : row
            tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
            selectedIndex.wrappedValue = newRow
            return true
        }

        // MARK: NSTableViewDelegate – cell views

        func tableView(_ tableView: NSTableView,
                       viewFor tableColumn: NSTableColumn?,
                       row: Int) -> NSView? {
            guard let deckRow = deck.card(at: row),
                  let colID = tableColumn?.identifier.rawValue else { return nil }

            // ── Row number column — always read-only ─────────────────────
            if colID == "ignore" {
                let cellID = NSUserInterfaceItemIdentifier("cell.ignore")
                let button: NSButton
                if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSButton {
                    button = reused
                } else {
                    button = NSButton(checkboxWithTitle: "", target: self, action: #selector(ignoreCheckboxToggled(_:)))
                    button.identifier = cellID
                }
                button.tag = row
                button.state = deckRow.isIgnored ? .on : .off
                button.isEnabled = true
                return button
            }
            if colID == "invisible" {
                let cellID = NSUserInterfaceItemIdentifier("cell.invisible")
                let button: NSButton
                if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSButton {
                    button = reused
                } else {
                    button = NSButton(checkboxWithTitle: "", target: self, action: #selector(invisibleCheckboxToggled(_:)))
                    button.identifier = cellID
                }
                button.tag = row
                button.state = deckRow.isInvisible ? .on : .off
                button.isEnabled = true
                return button
            }
            if colID == "rownum" {
                let cellID = NSUserInterfaceItemIdentifier("cell.rownum")
                let cell: NSTextField
                if let reused = tableView.makeView(withIdentifier: cellID, owner: nil)
                                    as? NSTextField {
                    cell = reused
                } else {
                    cell = NSTextField(labelWithString: "")
                    cell.identifier       = cellID
                    cell.font             = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                    cell.isEditable       = false
                    cell.alignment        = .right
                    cell.textColor        = .tertiaryLabelColor
                    cell.lineBreakMode    = .byClipping
                }
                cell.stringValue = String(row + 1)
                return cell
            }

            // ── Type (card code) column — popup picker ────────────────────
            if colID == "card" {
                let popupID = NSUserInterfaceItemIdentifier("cell.card")
                let popup: CardTypePopup
                if let reused = tableView.makeView(withIdentifier: popupID, owner: nil)
                                    as? CardTypePopup {
                    popup = reused
                } else {
                    popup = CardTypePopup(frame: .zero, pullsDown: false)
                    popup.identifier    = popupID
                    popup.isBordered    = false
                    popup.font          = font(forColumn: "card")
                    popup.target        = self
                    popup.action        = #selector(cardTypePopupChanged(_:))
                }
                popup.row = row

                // Rebuild the menu with contextually valid card types.
                popup.removeAllItems()
                let validTypes = deck.validCardTypes(for: row)
                for ct in validTypes {
                    let item = NSMenuItem()
                    item.title             = ct.rawValue          // two-letter code
                    item.toolTip           = ct.displayName       // shown on hover
                    item.representedObject = ct.rawValue
                    popup.menu?.addItem(item)
                }
                // Select the current code; fall back to first item if unrecognised.
                if popup.item(withTitle: deckRow.cardCode) != nil {
                    popup.selectItem(withTitle: deckRow.cardCode)
                } else {
                    popup.selectItem(at: 0)
                }
                // Tint the button title to match the category colour.
                if let cell = popup.cell as? NSPopUpButtonCell {
                    let attr = NSAttributedString(
                        string: deckRow.cardCode,
                        attributes: [.foregroundColor: categoryColor(deckRow.cardType.category),
                                     .font: font(forColumn: "card")])
                    cell.attributedTitle = attr
                }
                return popup
            }

            // Comment cards (CM, CE, !, ', #) and SY span the full row.
            let isTextCard = ["CM", "CE", "!", "'", "#"].contains(deckRow.cardCode)
            let isSYCard   = deckRow.cardCode == "SY"
            let isSpanning = isTextCard || isSYCard

            // For spanning cards every column except "rownum", "card", and "I1"
            // is empty, **with one exception**: SY cards still render the comment
            // column.  Returning nil leaves those cells undrawn so the spanning
            // label can paint over them without obstruction.
            if isSpanning && colID != "rownum" && colID != "card" && colID != "I1" && !(isSYCard && colID == "comment") {
                return nil
            }

            // ── Spanning card I1: full-row label ─────────────────────────
            // NSTableView sizes each cell view to exactly the column width, so
            // a plain NSTextField in the I1 column (~52 pt) clips the text there.
            // The workaround: wrap the label in a plain NSView container whose
            // *subview* is 2000 pt wide.  NSView does not clip its subviews by
            // default, so the label paints rightward over the empty adjacent
            // cells without any complicated overlay or row-view math.
            if isSpanning && colID == "I1" {
                let spanID = NSUserInterfaceItemIdentifier("cell.commentSpan")
                let container: NSView
                let label: EditableCell

                if let reused = tableView.makeView(withIdentifier: spanID, owner: nil),
                   let existing = reused.subviews.first as? EditableCell {
                    container = reused
                    label     = existing
                } else {
                    container            = NSView()
                    container.identifier = spanID
                    label                = EditableCell(string: "")
                    label.isBordered     = false
                    label.drawsBackground = false
                    label.focusRingType  = .none
                    label.font           = font(forColumn: "I1")
                    container.addSubview(label)
                }

                label.row       = row
                label.colID     = "I1"
                label.delegate  = self
                label.alignment = .left
                label.lineBreakMode = .byClipping
                // Height matches the row; width overflows into empty neighbour cells.
                label.frame = NSRect(x: 0, y: 0, width: 2000, height: 18)

                if isSYCard {
                    // SY: show symbol assignments only; comment will appear in its
                    // own column so the user may edit it if desired.
                    label.stringValue  = deckRow.symbols
                    label.textColor    = .systemPurple
                    label.isEditable   = false
                } else {
                    // CM / CE: show comment text; user-editable
                    label.stringValue  = deckRow.comment
                    label.textColor    = .secondaryLabelColor
                    label.isEditable   = true
                }
                return container
            }

            // ── Normal cell ───────────────────────────────────────────────
            let text  = cellText(for: colID, row: deckRow)
            var color = cellColor(for: colID, row: deckRow)
            let align = columns.first { $0.id == colID }?.alignment ?? .left
            // override for ignored cards
            if deckRow.isIgnored {
                color = .tertiaryLabelColor
            }

            // "card" column is never editable; everything else is.
            let isEditable = colID != "card"

            let cellID = NSUserInterfaceItemIdentifier("cell.\(colID)")
            let cell: EditableCell

            if let reused = tableView.makeView(withIdentifier: cellID, owner: nil)
                                as? EditableCell {
                cell = reused
            } else {
                cell = EditableCell(string: "")
                cell.identifier      = cellID
                cell.isBordered      = false
                cell.drawsBackground = false
                cell.focusRingType   = .none
                cell.isSelectable    = true
                cell.font            = font(forColumn: colID)
            }

            cell.row            = row
            cell.colID          = colID
            // prevent editing commented-out rows
            cell.isEditable     = (isEditable && !deckRow.isIgnored)
            cell.delegate       = cell.isEditable ? self : nil
            cell.lineBreakMode  = .byTruncatingTail
            cell.stringValue    = text
            cell.textColor      = color
            // Comment column content is always left-aligned.
            cell.alignment      = (colID == "comment") ? .left : align
            // Validation border and tooltip.
            applyValidationBorder(to: cell, colID: colID, deckRow: deckRow)
            return cell
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            18
        }
        // MARK: – Validation border

        /// Apply a coloured border (and tooltip) to a cell based on its field’s
        /// validation severity.  No border is drawn for NONE (OK / no rule).
        private func applyValidationBorder(to cell: EditableCell,
                                           colID: String,
                                           deckRow: DeckRow) {
            let validation: FieldValidation
            switch colID {
            case "I1": validation = deckRow.iValidations[0]
            case "I2": validation = deckRow.iValidations[1]
            case "I3": validation = deckRow.iValidations[2]
            case "I4": validation = deckRow.iValidations[3]
            case "F1": validation = deckRow.fValidations[0]
            case "F2": validation = deckRow.fValidations[1]
            case "F3": validation = deckRow.fValidations[2]
            case "F4": validation = deckRow.fValidations[3]
            case "F5": validation = deckRow.fValidations[4]
            case "F6": validation = deckRow.fValidations[5]
            case "F7": validation = deckRow.fValidations[6]
            default:   return   // card column, comment column, spanning rows
            }

            cell.wantsLayer = true
            cell.layer?.cornerRadius = 2
            cell.toolTip = validation.severity != .none ? validation.message : nil

            switch validation.severity {
            case .none:
                cell.layer?.borderWidth = 0
                cell.layer?.borderColor = nil
            case .warning:
                cell.layer?.borderWidth = 1.0
                cell.layer?.borderColor = NSColor.systemYellow.cgColor
            case .problem:
                cell.layer?.borderWidth = 1.5
                cell.layer?.borderColor = NSColor.systemOrange.cgColor
            case .fatal:
                cell.layer?.borderWidth = 1.5
                cell.layer?.borderColor = NSColor.systemRed.cgColor
            }
        }


        // MARK: – Editing support

        /// NSTableViewDelegate hook called when the user tries to start an edit
        /// (click/double‑click) in a view‑based table.  The default implementation
        /// returns `false`, so we need to explicitly permit edits on eligible
        /// cells.
        func tableView(_ tableView: NSTableView,
                       shouldEdit tableColumn: NSTableColumn?,
                       row: Int) -> Bool {
            guard let colID = tableColumn?.identifier.rawValue,
                  let deckRow = deck.card(at: row) else {
                return false
            }
            // only the "card" column is never editable; rows marked ignored
            // are also read‑only.
            if colID == "card" || deckRow.isIgnored {
                return false
            }
            return true
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTableView else { return }
            let idx = tv.selectedRow
            let newSel = idx >= 0 && idx < deck.cardCount ? idx : nil
            selectedIndex.wrappedValue = newSel
            if let sel = newSel, let row = deck.card(at: sel) {
                updateColumnHeaders(for: row.cardType)
            } else {
                updateColumnHeaders(for: .unknown)
            }
        }

        // provide custom row views so we can draw thicker separators
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rv = SectionRowView()
            if let end = deck.commentSectionEnd, row == end {
                rv.hasThickBottom = true
            } else if let end = deck.symbolSectionEnd, row == end {
                rv.hasThickBottom = true
            } else if let end = deck.geometrySectionEnd, row == end {
                rv.hasThickBottom = true
            }
            return rv
        }

        @objc func scrollViewDidScroll(_ note: Notification) {
            repositionSectionLabels()
        }

        func repositionSectionLabels() {
            guard let tv = tableView, let scroll = tv.enclosingScrollView else { return }
            let visRect = scroll.contentView.bounds
            // compute start rows for each section if present
            let sections: [(String, Int?)] = [
                ("Comments", deck.commentSectionEnd.map { _ in 0 }),
                // symbols start at symbolSectionEnd - there is no separate start
                ("Symbols", deck.symbolSectionEnd.flatMap { end in
                    end > (deck.commentSectionEnd ?? -1) ? end : nil
                }),
                // geometry label at section start if available
                ("Geometry", deck.geometrySectionStart),
                ("Control", deck.geometrySectionEnd.flatMap { end in
                    end + 1 < deck.cardCount ? end + 1 : nil
                })
            ]
            guard Preferences.shared.deckShowSectionLabels else {
                // hide all if pref disabled
                sectionLabels.forEach { $0.isHidden = true }
                return
            }
            for (idx, (_, optRow)) in sections.enumerated() {
                let lbl = sectionLabels[idx]
                if let row = optRow {
                    lbl.isHidden = false
                    // convert row rect into contentView coordinates (accounts for scrolling)
                    let rowRect = tv.rect(ofRow: row)
                    let rowInContent = tv.convert(rowRect, to: scroll.contentView)
                    let contentOrigin = scroll.contentView.bounds.origin
                    // compute y relative to visible area, clamp at header bottom
                    let headerHeight = tv.headerView?.frame.height ?? 0
                    let y = max(rowInContent.minY - contentOrigin.y, headerHeight)
                    // shift left with a larger margin to avoid clipping
                    let margin: CGFloat = 16
                    // ensure label has correct size first
                    lbl.sizeToFit()
                    let x = visRect.maxX - lbl.frame.width - margin
                    lbl.frame = CGRect(x: x, y: y, width: lbl.frame.width, height: lbl.frame.height)
                } else {
                    lbl.isHidden = true
                }
            }
        }

        // Called when the user double-clicks a row.  Attempt to begin editing
        // whichever column they clicked, provided the cell is allowed to edit.
        @objc func tableViewDoubleClicked(_ sender: Any?) {
            guard let tv = sender as? NSTableView else { return }
            let col = tv.clickedColumn
            let row = tv.clickedRow
            guard col >= 0, row >= 0,
                  let colID = tv.tableColumns[col].identifier.rawValue as String?,
                  let deckRow = deck.card(at: row) else { return }
            // only allow editing if our delegate would allow it
            if colID != "card" && !deckRow.isIgnored {
                tv.editColumn(col, row: row, with: nil, select: true)
            }
        }

        // MARK: – Column header update

        /// Update the 11 numeric column header titles to match the field labels
        /// for `cardType`.  Unused fields (nil label) fall back to the column ID.
        /// Called whenever the selection changes so the user always knows what
        /// each field means for the currently selected card.
        func updateColumnHeaders(for cardType: NECCardType) {
            guard let tableView else { return }

            let intLbls   = cardType.intFieldLabels    // [String?] × 4, 1-based
            let floatLbls = cardType.floatFieldLabels  // [String?] × 7, 1-based

            for column in tableView.tableColumns {
                let id = column.identifier.rawValue
                let newTitle: String
                switch id {
                case "I1": newTitle = intLbls[0]   ?? ""
                case "I2": newTitle = intLbls[1]   ?? ""
                case "I3": newTitle = intLbls[2]   ?? ""
                case "I4": newTitle = intLbls[3]   ?? ""
                case "F1": newTitle = floatLbls[0] ?? ""
                case "F2": newTitle = floatLbls[1] ?? ""
                case "F3": newTitle = floatLbls[2] ?? ""
                case "F4": newTitle = floatLbls[3] ?? ""
                case "F5": newTitle = floatLbls[4] ?? ""
                case "F6": newTitle = floatLbls[5] ?? ""
                case "F7": newTitle = floatLbls[6] ?? ""
                case "comment": newTitle = (cardType.category == .comment || cardType.category == .extension_) ? "" : "Comment"
                default:   continue
                }
                column.headerCell.title = newTitle
                // Comment/extension columns and any I1 used to display spanning text
                // are left-aligned; all other numeric columns are right-aligned.
                let isSpanningContent = id == "comment" ||
                    (id == "I1" && (cardType.category == .comment || cardType.category == .extension_))
                column.headerCell.alignment = isSpanningContent ? .left : .right
            }
            tableView.headerView?.setNeedsDisplay(tableView.headerView?.bounds ?? .zero)
        }

        // MARK: – Helpers

        private func cellText(for colID: String, row: DeckRow) -> String {
            let isTextCard = ["CM", "CE", "!", "'", "#"].contains(row.cardCode)
            switch colID {
            case "card":
                return row.cardCode
            case "I1":
                // Comment cards: full comment text spans from here rightward.
                if isTextCard { return row.comment }
                if let formula = row.iFormulas[0] { return formula }
                let v = row.i[0]
                return v == 0 ? "–" : String(v)
            case "I2", "I3", "I4":
                if isTextCard { return "" }     // caller already returns nil
                let idx = Int(colID.dropFirst())! - 1
                if let formula = row.iFormulas[idx] { return formula }
                let v   = row.i[idx]
                return v == 0 ? "–" : String(v)
            case "F1", "F2", "F3", "F4", "F5", "F6", "F7":
                if isTextCard { return "" }     // caller already returns nil
                let idx = Int(colID.dropFirst())! - 1
                if let formula = row.fFormulas[idx] { return formula }
                let v   = row.f[idx]
                return v == 0.0 ? "–" : String(format: "%g", v)
            case "comment":
                if isTextCard { return "" }     // caller already returns nil
                return row.comment
            default:
                return ""
            }
        }

        private func cellColor(for colID: String, row: DeckRow) -> NSColor {
            let isTextCard = ["CM", "CE", "!", "'", "#"].contains(row.cardCode)
            let isSYCard   = row.cardCode == "SY"
            // grey out entire row if ignored
            if row.isIgnored { return .tertiaryLabelColor }
            if colID == "card"    { return categoryColor(row.cardType.category) }
            // Spanning I1 gets the card-appropriate text colour
            if isSYCard   && colID == "I1" { return .systemPurple }
            if isTextCard && colID == "I1" { return .secondaryLabelColor }
            if colID == "comment" { return .secondaryLabelColor }
            switch colID {
            case "I1", "I2", "I3", "I4":
                let idx = Int(colID.dropFirst())! - 1
                return row.i[idx] == 0 ? .tertiaryLabelColor : .labelColor
            case "F1", "F2", "F3", "F4", "F5", "F6", "F7":
                let idx = Int(colID.dropFirst())! - 1
                return row.f[idx] == 0.0 ? .tertiaryLabelColor : .labelColor
            default:
                return .labelColor
            }
        }

        private func categoryColor(_ category: NECCardType.Category) -> NSColor {
            switch category {
            case .comment:    return .secondaryLabelColor
            case .geometry:   return .systemBlue
            case .control:    return .labelColor
            case .extension_: return .systemPurple
            case .unknown:    return .systemRed
            }
        }

        private func font(forColumn colID: String) -> NSFont {
            let size = NSFont.systemFontSize - 1
            return colID == "comment"
                ? .systemFont(ofSize: size)
                : .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}

// MARK: – Preview

#Preview {
    @Previewable @State var sel: Int? = nil
    let sample = """
    CM Half-wave dipole at 300 MHz
    CE
    GW 1 11 0 0 0 0 0 0.25 0.001
    GE 0
    FR 0 1 0 0 299.8 0
    EX 0 1 6 0 1 0
    RP 0 91 1 1000 0 0 1 0
    EN
    """
    let deck = NECDeck(text: sample)
    return DeckTableView(deck: deck, selectedIndex: $sel)
        .frame(minWidth: 900, minHeight: 260)
}

#endif // os(macOS)
