//
//  MactennaDocument.swift
//  Mactenna
//
//  Thin FileDocument wrapper for .nec / .deck files.
//  Responsibility: read raw text from disk, write raw text to disk.
//  All parsing and editing logic lives in NECDeck (the C library wrapper).

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// NEC antenna deck file (.nec / .deck).
    nonisolated static let necDeck = UTType(importedAs: "net.maury.mactenna.nec-deck")
}

nonisolated struct MactennaDocument: FileDocument {

    // MARK: – Content

    /// Raw text of the deck file.
    /// On open: populated from disk.
    /// On save: populated from NECDeck.text() by ContentView before FileDocument writes.
    var text: String

    // MARK: – FileDocument conformance

    nonisolated static let readableContentTypes: [UTType] = [.necDeck, .plainText]
    nonisolated static let writableContentTypes: [UTType] = [.necDeck]

    // MARK: – Init

    init(text: String = NECDeck.defaultTemplate) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard
            let data   = configuration.file.regularFileContents,
            let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}


