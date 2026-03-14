//
//  ControlCardEditor.swift
//  Mactenna
//
//  Editor for control cards: FR, EX, LD, GN, GD, NT, TL, EK, NE, NH, KH, XQ, PQ, RP, CP, PT, WB, NX, PL, EN
//
//  Uses the same field layout as geometry cards with type-specific grouping.

import SwiftUI

struct ControlCardEditor: CardEditor {
    let cardType: NECCardType
    let rowIndex: Int

    @State var intFields: [IntFieldValue] = []
    @State var floatFields: [FloatFieldValue] = []
    @State var mode: CardEditorMode = .editing

    var onCommit: (Int, [String]) -> Void
    var onCancel: () -> Void

    init(cardType: NECCardType,
         rowIndex: Int = -1,
         intValues: [String] = [],
         floatValues: [String] = [],
         intValidations: [FieldValidation] = [],
         floatValidations: [FieldValidation] = [],
         onCommit: @escaping (Int, [String]) -> Void,
         onCancel: @escaping () -> Void) {
        self.cardType = cardType
        self.rowIndex = rowIndex
        self.onCommit = onCommit
        self.onCancel = onCancel

        // Initialize int fields from labels and values.
        let labels = cardType.intFieldLabels
        _intFields = State(initialValue: (0..<4).map { i in
            IntFieldValue(
                index: i,
                label: labels[i],
                value: i < intValues.count ? intValues[i] : "",
                validation: i < intValidations.count ? intValidations[i] : .ok
            )
        })

        // Initialize float fields from labels and values.
        let floatLabels = cardType.floatFieldLabels
        _floatFields = State(initialValue: (0..<7).map { i in
            FloatFieldValue(
                index: i,
                label: floatLabels[i],
                value: i < floatValues.count ? floatValues[i] : "",
                validation: i < floatValidations.count ? floatValidations[i] : .ok
            )
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // ── Render fields with appropriate grouping based on card type
                renderFieldGroups()
            }
        }
    }

    /// Renders fields grouped by logical sections based on the card type.
    @ViewBuilder
    private func renderFieldGroups() -> some View {
        switch cardType {
        case .FR:
            // Frequency: Type, Steps
            integerFieldSection(title: "Frequency Settings", intIndices: 0..<2)

        case .EX:
            // Excitation: Type, Tag, Seg, Options
            integerFieldSection(title: "Excitation", intIndices: 0..<4)

        case .LD:
            // Loading: Type, Tag, Seg1, Seg2
            integerFieldSection(title: "Loading", intIndices: 0..<4)

        case .GN:
            // Ground: Type, Radials
            integerFieldSection(title: "Ground Parameters", intIndices: 0..<2)

        case .GD:
            // Advanced Ground: (no int fields)
            fieldSection("Ground Parameters", floatIndices: 0..<4)

        case .NT, .TL:
            // Network / Transmission Line: Tag1, Seg1, Tag2, Seg2
            integerFieldSection(title: "Network", intIndices: 0..<4)

        case .NE, .NH:
            // Near field: Coords, N1, N2, N3
            integerFieldSection(title: "Field Computation", intIndices: 0..<4)

        case .RP:
            // Radiation: Mode, Nθ, Nφ, XNDA
            integerFieldSection(title: "Radiation Pattern", intIndices: 0..<4)

        case .CP:
            // Coupling: Tag1, Seg1, Tag2, Seg2
            integerFieldSection(title: "Coupling", intIndices: 0..<4)

        case .XQ, .PQ, .PT, .WB, .NX, .PL, .EK, .KH, .EN:
            // Other types: render all available int fields
            integerFieldSection(title: "Parameters", intIndices: 0..<4)
            if floatFields.contains(where: { $0.label != nil }) {
                fieldSection("Values", floatIndices: 0..<7)
            }

        default:
            // Generic
            integerFieldSection(title: "Integer Fields", intIndices: 0..<4)
            fieldSection("Float Fields", floatIndices: 0..<7)
        }
    }

    @ViewBuilder
    private func integerFieldSection(title: String, intIndices: Range<Int>) -> some View {
        let activeFields = intIndices.filter { intFields[$0].label != nil }
        if !activeFields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(Array(intIndices), id: \.self) { i in
                    if intFields[i].label != nil {
                        HStack(spacing: 8) {
                            Text(intFields[i].label ?? "")
                                .frame(maxWidth: 100, alignment: .trailing)
                            TextField("I\(i + 1)", text: $intFields[i].value)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 150)
                                .background(colorForIntField(i))
                                .cornerRadius(4)
                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
    }

    @ViewBuilder
    private func fieldSection(_ title: String, floatIndices: Range<Int>) -> some View {
        let activeFields = floatIndices.filter { floatFields[$0].label != nil }
        if !activeFields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(Array(floatIndices), id: \.self) { i in
                    if floatFields[i].label != nil {
                        HStack(spacing: 8) {
                            Text(floatFields[i].label ?? "")
                                .frame(maxWidth: 100, alignment: .trailing)

                            TextField("F\(i + 1)", text: $floatFields[i].value)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 150)
                                .background(colorForFloatField(i))
                                .cornerRadius(4)
                                .help(tooltipForFloatField(i))

                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
    }

    /// Returns a tooltip showing the parsed numeric value of a float field.
    private func tooltipForFloatField(_ index: Int) -> String {
        let value = floatFields[index].value.trimmingCharacters(in: .whitespaces)
        if let doubleVal = Double(value) {
            return String(format: "%.6g", doubleVal)
        }
        return "Enter a number"
    }

    func validate() -> [FieldValidationError] {
        // Fields accept any non-empty value: plain numbers or formulas.
        // Syntax and semantic validation happens in the C library.
        // For now, ControlCardEditor has no client-side validation errors.
        return []
    }

    /// Returns the background color for a float field based on validation severity.
    private func colorForFloatField(_ index: Int) -> Color {
        let validation = floatFields[index].validation
        switch validation.severity {
        case .none:       return .clear
        case .warning:    return Color.yellow.opacity(0.2)
        case .problem:    return Color.orange.opacity(0.2)
        case .fatal:      return Color.red.opacity(0.2)
        }
    }

    /// Returns the background color for an int field based on validation severity.
    private func colorForIntField(_ index: Int) -> Color {
        let validation = intFields[index].validation
        switch validation.severity {
        case .none:       return .clear
        case .warning:    return Color.yellow.opacity(0.2)
        case .problem:    return Color.orange.opacity(0.2)
        case .fatal:      return Color.red.opacity(0.2)
        }
    }

    func collectValues() -> [String] {
        let intVals = intFields.map { $0.value }
        let floatVals = floatFields.map { $0.value }
        return intVals + floatVals
    }
}
