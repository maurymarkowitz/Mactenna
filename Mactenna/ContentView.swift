//
//  ContentView.swift
//  Mactenna
//
//  Root view for a Mactenna document window.
//
//  Owns the NECDeck for this window — the live C-library editing model.
//  MactennaDocument holds only the raw text for FileDocument I/O.
//
//  Phase 1 layout:
//    • Left pane  — DeckTableView driven by NECDeck
//    • Right pane — placeholder for 3D visualisation (Phase 4/5)
//
//  Phase 2 additions:
//    • Cell editing via onCommitEdit  →  handleCellEdit
//    • +/− toolbar buttons with UndoManager registration
//    • editGeneration observer keeps document dirty on field edits

import SwiftUI

struct ContentView: View {

    @Binding var document: MactennaDocument

    /// The live editing model — owns deck_t* and nec_context_t*.
    /// Created once per window from document.text; changes are synced back
    /// to document.text (which marks the document dirty for autosave).
    @StateObject private var deck: NECDeck

    @State private var selectedIndex: Int? = nil

    @Environment(\.undoManager) private var undoManager

    init(document: Binding<MactennaDocument>) {
        _document = document
        _deck = StateObject(wrappedValue: NECDeck(text: document.wrappedValue.text))
    }

    var body: some View {
        HSplitView {
            // ── Deck editor pane ──────────────────────────────────────────
            DeckTableView(deck: deck,
                          selectedIndex: $selectedIndex,
                          onCommitEdit: handleCellEdit,
                          onMove: { src, dst, snapshot in
                              undoManager?.registerUndo(withTarget: deck) { d in
                                  d.restore(text: snapshot)
                              }
                              undoManager?.setActionName("Move Card")
                          })
                .frame(minWidth: 600)

            // ── Results pane ──────────────────────────────────────────────
            ResultsView(deck: deck, selectedIndex: $selectedIndex)
                .frame(minWidth: 300)
        }
        // ensure the window opens large enough that the comment column is visible
        .frame(minWidth: 1000, minHeight: 600)
        .toolbar {
            // ― Add / delete card row ――――――――――――――――――――――――――――――――――――――――
            // Note: .navigation placement is silently dropped in DocumentGroup
            // windows (no NavigationStack).  .automatic places items in the
            // leading toolbar area where + / − conventionally belong.
            ToolbarItemGroup(placement: .automatic) {
                Button(action: addCardRow) {
                    Label("Add Card", systemImage: "plus")
                }
                .help("Insert a new card after the selected row (⌘+)")

                Button(action: deleteCardRow) {
                    Label("Delete Card", systemImage: "minus")
                }
                .disabled(selectedIndex == nil)
                .help("Delete the selected card row (⌘⌫)")
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { deck.runSimulation() }) {
                    if deck.isRunning {
                        Label("Running…", systemImage: "stop.fill")
                    } else {
                        Label("Run", systemImage: "play.fill")
                    }
                }
                .disabled(deck.isRunning)
                .help(deck.isRunning ? "Simulation in progress" : "Run NEC simulation (Phase 3)")
            }

            #if DEBUG
            ToolbarItem(placement: .automatic) {
                Button(action: { deck.debugDumpCard(at: 8) }) {
                    Label("Debug Card 9", systemImage: "stethoscope")
                }
                .help("Dump raw C fields for card 9 (index 8) → Log tab")
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { document.text = deck.text() }) {
                    Label("Sync & Save", systemImage: "square.and.arrow.down")
                }
                .help("DEBUG: sync current deck state to document and trigger save")
            }
            #endif
        }
        // Expose card actions to MactennaApp's CommandMenu("Card").
        .focusedValue(\.addCard,      addCardRow)
        .focusedValue(\.deleteCard,   deleteCardRow)
        .focusedValue(\.canDeleteCard, selectedIndex != nil)
        // Sync serialised deck text back to MactennaDocument on any change.
        // In DEBUG builds autosave is suppressed — use the "Sync & Save"
        // toolbar button to write the current deck state to disk explicitly.
        // TODO: remove #if !DEBUG guard before shipping to production
        #if !DEBUG
        .onChange(of: deck.cardCount)      { document.text = deck.text() }
        .onChange(of: deck.editGeneration) { document.text = deck.text() }
        #endif
    }

    // MARK: – Cell edit handler

    /// Called by DeckTableView.Coordinator when a cell finishes editing.
    /// Snapshots the deck BEFORE applying the change so the undo action can
    /// restore exactly the pre-edit state.
    private func handleCellEdit(row: Int, colID: String, newValue: String) {
        let snapshot = deck.text()
        guard applyEdit(row: row, colID: colID, value: newValue) else { return }
        undoManager?.registerUndo(withTarget: deck) { d in
            d.restore(text: snapshot)
        }
        undoManager?.setActionName("Edit \(colID)")
    }

    /// Parse `value` and write it into the appropriate card field.
    /// Returns `true` if the value was actually changed.
    @discardableResult
    private func applyEdit(row: Int, colID: String, value: String) -> Bool {
        guard let deckRow = deck.card(at: row) else { return false }
        let isComment = ["CM", "CE", "!", "'", "#"].contains(deckRow.cardCode)

        switch colID {
        case "card":
            guard value != deckRow.cardCode else { return false }
            deck.setCardCode(row: row, code: value)
            return true
        case "I1":
            if isComment {
                guard value != deckRow.comment else { return false }
                deck.setComment(row: row, text: value)
                return true
            }
            let v = Int(value) ?? 0
            guard v != deckRow.i[0] else { return false }
            deck.setIntField(row: row, field: 1, value: v)
            return true
        case "I2", "I3", "I4":
            let fn = Int(colID.dropFirst())!
            let v  = Int(value) ?? 0
            guard v != deckRow.i[fn - 1] else { return false }
            deck.setIntField(row: row, field: fn, value: v)
            return true
        case "F1", "F2", "F3", "F4", "F5", "F6", "F7":
            let fn = Int(colID.dropFirst())!
            let v  = Double(value) ?? 0.0
            guard v != deckRow.f[fn - 1] else { return false }
            deck.setFloatField(row: row, field: fn, value: v)
            return true
        case "comment":
            guard value != deckRow.comment else { return false }
            deck.setComment(row: row, text: value)
            return true
        default:
            return false
        }
    }

    // MARK: – Add / delete rows

    private func addCardRow() {
        // Insert after selected row; if nothing selected, insert before the last
        // card (typically EN, which should stay at the bottom).
        let afterIndex = selectedIndex ?? max(deck.cardCount - 2, 0)
        let snapshot   = deck.addCard("GW", after: afterIndex)
        undoManager?.registerUndo(withTarget: deck) { d in
            d.restore(text: snapshot)
        }
        undoManager?.setActionName("Add Card")
        selectedIndex = afterIndex + 1
    }

    private func deleteCardRow() {
        guard let idx = selectedIndex else { return }
        let snapshot = deck.deleteCard(at: idx)
        undoManager?.registerUndo(withTarget: deck) { d in
            d.restore(text: snapshot)
        }
        undoManager?.setActionName("Delete Card")
        selectedIndex = idx > 0 ? idx - 1 : (deck.cardCount > 0 ? 0 : nil)
    }
}

#Preview {
    ContentView(document: .constant(MactennaDocument()))
}


