//
//  CardEditorBase.swift
//  Mactenna
//
//  Base protocol and common infrastructure for card editor dialogs.
//  Each card type (GW, GA, CM, etc.) implements CardEditor to provide
//  type-specific field layout and validation.
//
//  Formula Support:
//  - All numeric fields (I1–I4, F1–F7) accept either plain numbers or formula strings
//  - Formulas can reference NEC variables (e.g., "lambda/4", "pi*2") or perform calculations
//  - Formula syntax validation is deferred to the C library at commit time
//  - Client-side validation only checks that fields are non-empty (if required)
//

import SwiftUI

// MARK: – Field Value Representation

/// Represents a single integer field (I1–I4).
/// Can contain either a plain number or a formula string.
struct IntFieldValue {
    let index: Int  // 0–3 for I1–I4
    let label: String?
    var value: String = ""  // Can be "42" or "lambda/2" or "pi*3"
    var isValid: Bool = true
    var validationMessage: String = ""
    var validation: FieldValidation = .ok  // Severity: none, warning, problem, fatal

    init(index: Int, label: String?, value: String = "", validation: FieldValidation = .ok) {
        self.index = index
        self.label = label
        self.value = value
        self.validation = validation
    }

    /// Returns true if the value is a formula (contains non-numeric characters after trimming).
    func isFormula() -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && Int(trimmed) == nil
    }

    /// Returns a display string showing formula or value.
    func displayString() -> String {
        return value
    }
}

/// Represents a single float field (F1–F7).
/// Can contain either a plain number or a formula string.
/// Supports unit annotations (e.g., "0.5m", "10mm", "#6" for AWG).
struct FloatFieldValue {
    let index: Int  // 0–6 for F1–F7
    let label: String?
    var value: String = ""  // Can be "3.14", "0.5m", "lambda/4", "#6" (AWG), etc.
    var isValid: Bool = true
    var validationMessage: String = ""
    var validation: FieldValidation = .ok  // Severity: none, warning, problem, fatal
    var displayValue: String = ""  // Numeric part extracted from value (for unit UI)
    var displayUnit: UnitsHelper.LengthUnit = .none  // Unit part extracted from value
    var isAWG: Bool = false  // True if value uses AWG notation (e.g., "#6")

    init(index: Int, label: String?, value: String = "", validation: FieldValidation = .ok) {
        self.index = index
        self.label = label
        self.value = value
        self.validation = validation

        // Parse initial value to extract display value and unit
        let (numVal, unit, isAwg) = UnitsHelper.parseFieldValue(value)
        self.displayValue = String(numVal)
        self.displayUnit = unit
        self.isAWG = isAwg
    }

    /// Returns true if the value is a formula (contains non-numeric characters after trimming).
    func isFormula() -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        // Allow scientific notation, decimal points, signs, but anything with letters is a formula
        return !trimmed.isEmpty && Double(trimmed) == nil
    }

    /// Returns a display string showing formula or value.
    func displayString() -> String {
        return value
    }
}

// MARK: – Validation Error

struct FieldValidationError: Identifiable {
    let id = UUID()
    let fieldLabel: String
    let message: String
}

// MARK: – Card Editor Protocol

/// Protocol that all card editor views must implement.
/// Provides common interface for opening/closing dialogs and validating/committing fields.
protocol CardEditor: View {
    associatedtype EditMode: Equatable

    /// The NECCardType being edited.
    var cardType: NECCardType { get }

    /// The card row index being edited (-1 for new card).
    var rowIndex: Int { get }

    /// Current edit mode: .adding, .editing, etc.
    var mode: EditMode { get set }

    /// Called when user commits changes: (rowIndex, fieldValues).
    /// For a new card (rowIndex == -1), the parent inserts a new row.
    var onCommit: (Int, [String]) -> Void { get }

    /// Called when user cancels the dialog.
    var onCancel: () -> Void { get }

    /// Validate all fields and return any errors.
    /// Returns empty array if all fields are valid.
    /// Formulas are accepted as-is; only plain numeric values are type-checked.
    func validate() -> [FieldValidationError]

    /// Collect all field values as a flat array of strings suitable for
    /// onCommit callback. Values can be plain numbers or formula strings.
    /// Order: I1, I2, I3, I4, F1, F2, F3, F4, F5, F6, F7.
    func collectValues() -> [String]
}

// MARK: – Base Dialog Container

/// Container view that wraps any CardEditor implementation.
/// Handles common UI layout: header, field grid, buttons, validation message.
///
/// Usage:
/// ```
/// CardEditorDialog(
///     editor: CommentCardEditor(rowIndex: 5, ...),
///     onDismiss: { }
/// )
/// ```
struct CardEditorDialog<E: CardEditor>: View {
    @State private var editor: E
    @State private var validationErrors: [FieldValidationError] = []
    var onDismiss: () -> Void

    init(editor: E, onDismiss: @escaping () -> Void) {
        _editor = State(initialValue: editor)
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 16) {
            // ── Header ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("\(editor.cardType.displayName) (\(editor.cardType.rawValue))")
                    .font(.headline)
                if editor.rowIndex >= 0 {
                    Text("Card #\(editor.rowIndex + 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("New card")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.controlBackgroundColor))

            // ── Validation errors (if any) ──────────────────────────
            if !validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Validation Errors", systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    ForEach(validationErrors) { error in
                        VStack(alignment: .leading) {
                            Text(error.fieldLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(error.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.controlBackgroundColor))
            }

            // ── Editor content (delegated to concrete editor) ────────
            editor
                .padding()

            // ── Buttons ─────────────────────────────────────────────
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    editor.onCancel()
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(editor.rowIndex >= 0 ? "Update" : "Insert") {
                    validationErrors = editor.validate()
                    guard validationErrors.isEmpty else { return }

                    let values = editor.collectValues()
                    editor.onCommit(editor.rowIndex, values)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Spacer()
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: – Editor Mode Types (can be common or per-editor)

enum CardEditorMode: Equatable {
    case adding
    case editing
}
