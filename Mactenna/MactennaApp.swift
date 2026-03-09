//
//  MactennaApp.swift
//  Mactenna
//
//  Created by Maury Markowitz on 2026-02-21.
//

import SwiftUI

@main
struct MactennaApp: App {

    // Focused-value bindings: populated by the active document window's
    // ContentView so menu commands can reach the correct deck.
    @FocusedValue(\.addCard)       private var addCard
    @FocusedValue(\.deleteCard)    private var deleteCard
    @FocusedValue(\.canDeleteCard) private var canDeleteCard

    var body: some Scene {
        DocumentGroup(newDocument: MactennaDocument()) { file in
            ContentView(document: file.$document)
        }
        Settings {
            PreferencesView()
        }
        .commands {
            // ── File menu additions ────────────────────────────────────────
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Show in Finder") {
                    #if os(macOS)
                    if let url = NSDocumentController.shared.currentDocument?.fileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    #endif
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
            }

            // ── Card menu ─────────────────────────────────────────────────
            CommandMenu("Card") {
                Button("Add Card") { addCard?() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(addCard == nil)

                Button("Delete Card") { deleteCard?() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(deleteCard == nil || canDeleteCard != true)
            }
            // Note: Writing Tools appears in the Edit menu when a text field
            // has focus on macOS 15+. Apple does not provide a public API to
            // remove it from the menu bar; it can only be suppressed per-view.
        }
    }
}
