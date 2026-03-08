//
//  DeckRow.swift
//  Mactenna
//
//  Read-only display proxy for a single NEC card.
//  Values are copied from card_t fields by NECDeck.card(at:) on demand.
//
//  This struct is NOT a storage model — the C library owns the data via
//  deck_t / card_t.  DeckRow exists only to ferry values to the table view
//  without exposing raw C pointers to the UI layer.

import Foundation

// MARK: – FieldValidation

/// Pure-Swift mirror of field_validation_t from card_validation.h.
/// Severity maps to error_level: NONE=0, WARNING=1, PROBLEM=2, FATAL=3.
struct FieldValidation {
    enum Severity {
        case none       // OK or no validation rule defined for this field
        case warning    // Suspicious; simulation will likely proceed
        case problem    // Likely to cause incorrect results
        case fatal      // Will definitely fail
    }
    let severity: Severity
    let message: String

    static let ok = FieldValidation(severity: .none, message: "")
}

// MARK: – DeckRow

struct DeckRow: Identifiable {
    /// Row index in the parent deck_t — used as the stable identity.
    let id: Int

    let cardCode: String
    let i: [Int]          // 4 elements: i[1]..i[4] (calculated values)
    let f: [Double]       // 7 elements: f[1]..f[7] (calculated values)
    let comment: String  // may come from card_t.comment or, for inline
                       // comments on geometry/control cards, card_t.extn_str

    /// Formula strings for integer fields I1–I4 (nil if the field is a plain number).
    let iFormulas: [String?]  // 4 elements, indexed 0–3 matching i[]
    /// Formula strings for float fields F1–F7 (nil if the field is a plain number).
    let fFormulas: [String?]  // 7 elements, indexed 0–6 matching f[]

    /// For SY cards: all symbol assignments joined as "key=value, …".
    /// Empty for all other card types.
    let symbols: String

    /// Per-field validation results from validate_card_all_fields().
    let iValidations: [FieldValidation]  // 4 elements: I1–I4
    let fValidations: [FieldValidation]  // 7 elements: F1–F7

    /// True if the card was commented-out/ignored (`card_t.ignore`).
    /// Such rows are rendered grey and are not editable.
    let isIgnored: Bool

    /// True if the card has been marked invisible (`card_t.invisible`).
    /// This flag currently has no UI effect beyond the checkbox column.
    let isInvisible: Bool

    var cardType: NECCardType { NECCardType(cardCode) }
}

