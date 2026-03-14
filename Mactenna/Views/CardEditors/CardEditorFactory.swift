//
//  CardEditorFactory.swift
//  Mactenna
//
//  Instantiates the correct CardEditor subview for a given card type.
//  Wraps the editor in CardEditorDialog and handles the presentation lifecycle.

import SwiftUI

/// Factory function to create the appropriate editor for a card type.
/// Returns an AnyView wrapping the correct editor + dialog container.
/// Passes both numeric values and formula strings to editors.
func makeCardEditor(
    cardType: NECCardType,
    rowIndex: Int,
    deckRow: DeckRow?,
    onCommit: @escaping (Int, [String]) -> Void,
    onCancel: @escaping () -> Void,
    onDismiss: @escaping () -> Void
) -> AnyView {
    // Prepare int values and formulas: prefer formula if present, otherwise numeric value
    let intVals = (0..<4).map { i -> String in
        if let formula = deckRow?.iFormulas[i] {
            return formula
        }
        return String(deckRow?.i[i] ?? 0)
    }

    // Prepare float values and formulas: prefer formula if present, otherwise numeric value
    let floatVals = (0..<7).map { i -> String in
        if let formula = deckRow?.fFormulas[i] {
            return formula
        }
        return String(deckRow?.f[i] ?? 0.0)
    }

    let commentText = deckRow?.comment ?? ""

    switch cardType.category {
    case .comment:
        let editor = CommentCardEditor(
            cardType: cardType,
            rowIndex: rowIndex,
            commentText: commentText,
            onCommit: onCommit,
            onCancel: onCancel
        )
        return AnyView(CardEditorDialog(editor: editor, onDismiss: onDismiss))

    case .geometry:
        let editor = GeometryCardEditor(
            cardType: cardType,
            rowIndex: rowIndex,
            intValues: intVals,
            floatValues: floatVals,
            intValidations: deckRow?.iValidations ?? [],
            floatValidations: deckRow?.fValidations ?? [],
            onCommit: onCommit,
            onCancel: onCancel
        )
        return AnyView(CardEditorDialog(editor: editor, onDismiss: onDismiss))

    case .control:
        let editor = ControlCardEditor(
            cardType: cardType,
            rowIndex: rowIndex,
            intValues: intVals,
            floatValues: floatVals,
            intValidations: deckRow?.iValidations ?? [],
            floatValidations: deckRow?.fValidations ?? [],
            onCommit: onCommit,
            onCancel: onCancel
        )
        return AnyView(CardEditorDialog(editor: editor, onDismiss: onDismiss))

    case .extension_:
        let editor = SymbolCardEditor(
            cardType: cardType,
            rowIndex: rowIndex,
            symbolText: commentText,
            onCommit: onCommit,
            onCancel: onCancel
        )
        return AnyView(CardEditorDialog(editor: editor, onDismiss: onDismiss))

    case .unknown:
        // Fallback: use generic control editor
        let editor = ControlCardEditor(
            cardType: cardType,
            rowIndex: rowIndex,
            intValues: intVals,
            floatValues: floatVals,
            onCommit: onCommit,
            onCancel: onCancel
        )
        return AnyView(CardEditorDialog(editor: editor, onDismiss: onDismiss))
    }
}
