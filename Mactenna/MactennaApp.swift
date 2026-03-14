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
    @FocusedValue(\.addCard)         private var addCard
    @FocusedValue(\.deleteCard)      private var deleteCard
    @FocusedValue(\.canDeleteCard)   private var canDeleteCard
    @FocusedValue(\.addCardOfType)   private var addCardOfType

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

            // ── Add menu ────────────────────────────────────────────────────
            CommandMenu("Add") {
                // Comments
                Menu("Comments") {
                    Button("Comment (CM)") { addCardOfType?(.CM) }
                    Button("Comment (#)") { addCardOfType?(.hashComment) }
                    Button("Comment (!)") { addCardOfType?(.bangComment) }
                    Button("Comment (')") { addCardOfType?(.apostComment) }
                    Button("Comment End (CE)") { addCardOfType?(.CE) }
                }

                // Extensions
                Menu("Extensions") {
                    Button("Symbol (SY)") { addCardOfType?(.SY) }
                }

                Divider()

                // Geometry
                Menu("Geometry") {
                    Menu("Primary") {
                        Button("Wire (GW)") { addCardOfType?(.GW) }
                        Button("Arc (GA)") { addCardOfType?(.GA) }
                        Button("Helix (GH)") { addCardOfType?(.GH) }
                        Button("Surface Patch (SP)") { addCardOfType?(.SP) }
                        Button("Multiple Patch (SM)") { addCardOfType?(.SM) }
                        Button("Continue Patch (SC)") { addCardOfType?(.SC) }
                    }
                    Divider()
                    Menu("Transformations") {
                        Button("Reflect (GX)") { addCardOfType?(.GX) }
                        Button("Rotate (GR)") { addCardOfType?(.GR) }
                        Button("Scale (GS)") { addCardOfType?(.GS) }
                        Button("Move (GM)") { addCardOfType?(.GM) }
                    }
                    Divider()
                    Menu("Advanced") {
                        Button("Tapered Wire (GC)") { addCardOfType?(.GC) }
                        Button("Read File (GF)") { addCardOfType?(.GF) }
                    }
                    Divider()
                    Button("Geometry End (GE)") { addCardOfType?(.GE) }
                }

                Divider()

                // Control
                Menu("Control") {
                    Menu("Simulation") {
                        Button("Frequency (FR)") { addCardOfType?(.FR) }
                        Button("Execute (XQ)") { addCardOfType?(.XQ) }
                    }
                    Divider()
                    Menu("Excitation & Loading") {
                        Button("Excitation (EX)") { addCardOfType?(.EX) }
                        Button("Loading (LD)") { addCardOfType?(.LD) }
                    }
                    Divider()
                    Menu("Ground") {
                        Button("Ground (GN)") { addCardOfType?(.GN) }
                        Button("Adv. Ground (GD)") { addCardOfType?(.GD) }
                    }
                    Divider()
                    Menu("Networks & Lines") {
                        Button("Network (NT)") { addCardOfType?(.NT) }
                        Button("Transmission Line (TL)") { addCardOfType?(.TL) }
                    }
                    Divider()
                    Menu("Field Computation") {
                        Button("Extended Kernel (EK)") { addCardOfType?(.EK) }
                        Button("Near E-Field (NE)") { addCardOfType?(.NE) }
                        Button("Near H-Field (NH)") { addCardOfType?(.NH) }
                        Button("Interaction (KH)") { addCardOfType?(.KH) }
                    }
                    Divider()
                    Menu("Output") {
                        Button("Radiation (RP)") { addCardOfType?(.RP) }
                        Button("Coupling (CP)") { addCardOfType?(.CP) }
                        Button("Print Current (PT)") { addCardOfType?(.PT) }
                        Button("Print Charge (PQ)") { addCardOfType?(.PQ) }
                    }
                    Divider()
                    Menu("Structure") {
                        Button("Patch Wire (WB)") { addCardOfType?(.WB) }
                        Button("Next Structure (NX)") { addCardOfType?(.NX) }
                        Button("Plot Flags (PL)") { addCardOfType?(.PL) }
                    }
                    Divider()
                    Button("End (EN)") { addCardOfType?(.EN) }
                }
            }

            // Note: Writing Tools appears in the Edit menu when a text field
            // has focus on macOS 15+. Apple does not provide a public API to
            // remove it from the menu bar; it can only be suppressed per-view.
        }
    }
}
