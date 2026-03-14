//
//  CommentCardEditor.swift
//  Mactenna
//
//  Editor for comment cards: CM, CE, !, ', #
//  Comments are simple: just a text field. No I1–I4 or F1–F7 fields.

import SwiftUI

struct CommentCardEditor: CardEditor {
    let cardType: NECCardType
    let rowIndex: Int

    @State var commentText: String = ""
    @State var mode: CardEditorMode = .editing

    var onCommit: (Int, [String]) -> Void
    var onCancel: () -> Void

    init(cardType: NECCardType,
         rowIndex: Int = -1,
         commentText: String = "",
         onCommit: @escaping (Int, [String]) -> Void,
         onCancel: @escaping () -> Void) {
        self.cardType = cardType
        self.rowIndex = rowIndex
        self._commentText = State(initialValue: commentText)
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comment Text")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            TextEditor(text: $commentText)
                .border(Color(.controlBackgroundColor))
                .frame(minHeight: 100)
                .font(.monospaced(.body)())
        }
    }

    func validate() -> [FieldValidationError] {
        // Comments have minimal validation; any text is valid.
        // Could check for NEC line length limits if needed.
        return []
    }

    func collectValues() -> [String] {
        // Comments don't have I/F fields, just the comment text.
        // Return a placeholder structure; the parent will handle
        // writing just the text field.
        return [commentText]
    }
}
