//
//  SymbolCardEditor.swift
//  Mactenna
//
//  Editor for symbol cards (SY) containing variable assignments.
//  SY cards have: I1 (unused), I2 (unused), I3 (unused), I4 (unused),
//  F1–F7 (all unused), and instead a comment field containing "key=value, key=value, ..."
//
//  This editor presents a key-value table UI with add/remove rows.

import SwiftUI

struct SymbolCardEditor: CardEditor {
    let cardType: NECCardType
    let rowIndex: Int

    @State var symbols: [SymbolAssignment] = []
    @State var mode: CardEditorMode = .editing

    var onCommit: (Int, [String]) -> Void
    var onCancel: () -> Void

    struct SymbolAssignment: Identifiable {
        let id = UUID()
        var key: String = ""
        var value: String = ""
    }

    init(cardType: NECCardType = .SY,
         rowIndex: Int = -1,
         symbolText: String = "",
         onCommit: @escaping (Int, [String]) -> Void,
         onCancel: @escaping () -> Void) {
        self.cardType = cardType
        self.rowIndex = rowIndex
        self.onCommit = onCommit
        self.onCancel = onCancel

        // Parse symbolText into key-value pairs.
        // Format: "key1=val1, key2=val2, ..."
        let pairs = symbolText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var assignments: [SymbolAssignment] = []
        for pair in pairs {
            if let eqIndex = pair.firstIndex(of: "=") {
                let key = pair[..<eqIndex].trimmingCharacters(in: .whitespaces)
                let val = pair[pair.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
                assignments.append(SymbolAssignment(key: key, value: val))
            }
        }
        if assignments.isEmpty {
            // Start with one empty row
            assignments.append(SymbolAssignment())
        }
        _symbols = State(initialValue: assignments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Symbol Assignments")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                // Header row
                HStack(spacing: 12) {
                    Text("Variable")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 150, alignment: .leading)
                    Text("Value")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("")
                        .frame(width: 24)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

                // Assignment rows
                ForEach($symbols, id: \.id) { $assignment in
                    HStack(spacing: 12) {
                        TextField("Variable", text: $assignment.key)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 150)

                        TextField("Value", text: $assignment.value)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)

                        Button(action: {
                            symbols.removeAll { $0.id == assignment.id }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 24)
                    }
                }

                // Add button
                Button(action: {
                    symbols.append(SymbolAssignment())
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Symbol")
                    }
                    .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
    }

    func validate() -> [FieldValidationError] {
        var errors: [FieldValidationError] = []

        // Each assigned key must be non-empty and not contain spaces.
        // Each value must be non-empty.
        for (idx, assignment) in symbols.enumerated() {
            let key = assignment.key.trimmingCharacters(in: .whitespaces)
            let val = assignment.value.trimmingCharacters(in: .whitespaces)

            if !key.isEmpty && !val.isEmpty {
                // Both present, valid.
                continue
            } else if key.isEmpty && val.isEmpty {
                // Both empty, skip this row (allowed).
                continue
            } else if !key.isEmpty && val.isEmpty {
                errors.append(FieldValidationError(
                    fieldLabel: "Symbol \(idx + 1)",
                    message: "Value cannot be empty"
                ))
            } else {
                errors.append(FieldValidationError(
                    fieldLabel: "Symbol \(idx + 1)",
                    message: "Key cannot be empty"
                ))
            }
        }

        return errors
    }

    func collectValues() -> [String] {
        // SY cards serialize as a single comment string: "key=val, key=val, ..."
        let pairs = symbols
            .filter { !$0.key.isEmpty && !$0.value.isEmpty }
            .map { "\($0.key)=\($0.value)" }
        let commentText = pairs.joined(separator: ", ")
        return [commentText]
    }
}
