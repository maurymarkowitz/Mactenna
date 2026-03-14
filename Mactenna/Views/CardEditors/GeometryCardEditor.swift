//
//  GeometryCardEditor.swift
//  Mactenna
//
//  Editor for geometry cards: GW, GA, GH, SP, SM, SC, GC, GR, GS, GM, GX, GF, GE
//
//  Handles the standard I1–I4 and F1–F7 field layout with type-specific labels.
//  Includes field grouping based on card type and hover tooltips for calculated values.

import SwiftUI

struct GeometryCardEditor: CardEditor {
    let cardType: NECCardType
    let rowIndex: Int

    @State var intFields: [IntFieldValue] = []
    @State var floatFields: [FloatFieldValue] = []
    @State var mode: CardEditorMode = .editing

    // For GW cards: alternate input mode using wire length instead of end point XYZ
    @State var wireLength: String = ""
    @State var useLengthMode: Bool = false

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
        var intValsOrDefaults = intValues
        // Provide defaults for new GW cards
        if rowIndex == -1 && cardType == .GW && intValues.isEmpty {
            intValsOrDefaults = ["1", "10", "", ""]  // Tag=1, Segments=10
        }
        _intFields = State(initialValue: (0..<4).map { i in
            IntFieldValue(
                index: i,
                label: labels[i],
                value: i < intValsOrDefaults.count ? intValsOrDefaults[i] : "",
                validation: i < intValidations.count ? intValidations[i] : .ok
            )
        })

        // Initialize float fields from labels and values.
        let floatLabels = cardType.floatFieldLabels
        var floatValsOrDefaults = floatValues
        // Provide defaults for new GW cards (simple vertical antenna)
        if rowIndex == -1 && cardType == .GW && floatValues.isEmpty {
            floatValsOrDefaults = ["0", "0", "0", "0", "0", "10", "0.5"]  // vertical wire, 10m high, 0.5m radius
        }
        _floatFields = State(initialValue: (0..<7).map { i in
            FloatFieldValue(
                index: i,
                label: floatLabels[i],
                value: i < floatValsOrDefaults.count ? floatValsOrDefaults[i] : "",
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
        case .GW:
            // Wire: Start (I/F), End (I/F) or Length, Radius
            integerFieldSection()
            coordinateFieldSection("Start Point", indices: 0..<3)
            gwEndPointSection()
            fieldSection("Wire Parameters", floatIndices: 6..<7)

        case .GA:
            // Arc: radius, angles, radius
            integerFieldSection()
            fieldSection("Arc Parameters", floatIndices: 0..<4)

        case .GH:
            // Helix: spacing, length, radii, wire radius
            integerFieldSection()
            fieldSection("Helix Parameters", floatIndices: 0..<7)

        case .SP, .SM, .SC:
            // Patches: coordinates
            integerFieldSection()
            fieldSection("Patch Coordinates", floatIndices: 0..<7)

        case .GC:
            // Tapered wire: delta radius, radii
            integerFieldSection()
            fieldSection("Wire Taper", floatIndices: 0..<3)

        case .GX, .GR, .GS, .GM:
            // Transformations
            integerFieldSection()
            fieldSection("Parameters", floatIndices: 0..<7)

        case .GF, .GE:
            // Simple types
            integerFieldSection()
            if floatFields.contains(where: { $0.label != nil }) {
                fieldSection("Parameters", floatIndices: 0..<7)
            }

        default:
            // Generic
            integerFieldSection()
            fieldSection("Float Fields", floatIndices: 0..<7)
        }
    }

    @ViewBuilder
    private func integerFieldSection() -> some View {
        let activeFields = intFields.filter { $0.label != nil }
        if !activeFields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags & Segments")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach($intFields, id: \.index) { $field in
                    if let label = field.label {
                        HStack(spacing: 8) {
                            Text(label)
                                .frame(maxWidth: 100, alignment: .trailing)
                            TextField("I\(field.index + 1)", text: $field.value)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 150)
                                .background(colorForIntField(field.index))
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

    /// Renders coordinate fields (X, Y, Z) stacked vertically.
    @ViewBuilder
    private func coordinateFieldSection(_ title: String, indices: Range<Int>) -> some View {
        let activeFields = indices.filter { floatFields[$0].label != nil }
        if !activeFields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ForEach(Array(indices), id: \.self) { i in
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
                                .onChange(of: floatFields[i].value) { _, newValue in
                                    let (numVal, unit, isAwg) = UnitsHelper.parseFieldValue(newValue)
                                    floatFields[i].displayValue = String(numVal)
                                    floatFields[i].displayUnit = unit
                                    floatFields[i].isAWG = isAwg
                                }

                            if UnitsHelper.shouldShowLengthUnit(cardType: cardType, fieldIndex: i) {
                                Picker("", selection: Binding(
                                    get: { floatFields[i].displayUnit.rawValue },
                                    set: { newSelection in
                                        updateFieldUnit(fieldIndex: i, unitString: newSelection)
                                    }
                                )) {
                                    Text("—").tag("")
                                    Text("m").tag("m")
                                    Text("cm").tag("cm")
                                    Text("mm").tag("mm")
                                    Text("in").tag("in")
                                    Text("ft").tag("ft")
                                }
                                .frame(maxWidth: 70)
                            }

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
                                .onChange(of: floatFields[i].value) { _, newValue in
                                    // Re-parse the field to update display value and unit
                                    let (numVal, unit, isAwg) = UnitsHelper.parseFieldValue(newValue)
                                    floatFields[i].displayValue = String(numVal)
                                    floatFields[i].displayUnit = unit
                                    floatFields[i].isAWG = isAwg
                                }

                            // Unit picker for length/position fields
                            if UnitsHelper.shouldShowLengthUnit(cardType: cardType, fieldIndex: i) {
                                if UnitsHelper.supportsWireSize(cardType: cardType, fieldIndex: i) {
                                    // Wire size field: show AWG and length units
                                    Picker("", selection: Binding(
                                        get: { floatFields[i].isAWG ? "AWG" : floatFields[i].displayUnit.rawValue },
                                        set: { newSelection in
                                            updateFieldUnit(fieldIndex: i, unitString: newSelection)
                                        }
                                    )) {
                                        Text("—").tag("")
                                        Text("m").tag("m")
                                        Text("cm").tag("cm")
                                        Text("mm").tag("mm")
                                        Text("in").tag("in")
                                        Text("ft").tag("ft")
                                        Text("AWG").tag("AWG")
                                    }
                                    .frame(maxWidth: 70)
                                } else {
                                    // Regular length field
                                    Picker("", selection: Binding(
                                        get: { floatFields[i].displayUnit.rawValue },
                                        set: { newSelection in
                                            updateFieldUnit(fieldIndex: i, unitString: newSelection)
                                        }
                                    )) {
                                        Text("—").tag("")
                                        Text("m").tag("m")
                                        Text("cm").tag("cm")
                                        Text("mm").tag("mm")
                                        Text("in").tag("in")
                                        Text("ft").tag("ft")
                                    }
                                    .frame(maxWidth: 70)
                                }
                            }

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
        } else if !value.isEmpty {
            return "Formula: \(value)"
        }
        return "Enter a number or formula"
    }

    /// Renders the end point section for GW cards with two input modes:
    /// 1. Direct X, Y, Z coordinates
    /// 2. Length (extends/contracts wire along current direction)
    @ViewBuilder
    private func gwEndPointSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(useLengthMode ? "Wire Length" : "End Point")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { useLengthMode.toggle() }) {
                    Text(useLengthMode ? "Switch to XYZ" : "Switch to Length")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
            }

            if useLengthMode {
                // Length mode: show single field for wire length
                HStack(spacing: 8) {
                    Text("Length (m)")
                        .frame(maxWidth: 100, alignment: .trailing)

                    TextField("Wire length", text: $wireLength)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150)
                        .onChange(of: wireLength) { oldVal, newVal in
                            updateEndPointFromLength(newVal)
                        }
                        .help(tooltipForLength())

                    Spacer()
                }
            } else {
                // Direct XYZ mode: show end point fields
                ForEach(Array(3..<6), id: \.self) { i in
                    if floatFields[i].label != nil {
                        HStack(spacing: 8) {
                            Text(floatFields[i].label ?? "")
                                .frame(maxWidth: 100, alignment: .trailing)

                            TextField("F\(i + 1)", text: $floatFields[i].value)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 150)
                                .background(colorForFloatField(i))
                                .cornerRadius(4)
                                .onChange(of: floatFields[i].value) { _, _ in
                                    updateLengthFromEndPoint()
                                }
                                .help(tooltipForFloatField(i))

                            if UnitsHelper.shouldShowLengthUnit(cardType: cardType, fieldIndex: i) {
                                Picker("", selection: Binding(
                                    get: { floatFields[i].displayUnit.rawValue },
                                    set: { newSelection in
                                        updateFieldUnit(fieldIndex: i, unitString: newSelection)
                                    }
                                )) {
                                    Text("—").tag("")
                                    Text("m").tag("m")
                                    Text("cm").tag("cm")
                                    Text("mm").tag("mm")
                                    Text("in").tag("in")
                                    Text("ft").tag("ft")
                                }
                                .frame(maxWidth: 70)
                            }

                            Spacer()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
        .onAppear {
            // Initialize wireLength from current end point on first appearance
            updateLengthFromEndPoint()
        }
    }

    /// Updates the end point (F4, F5, F6) based on wire length and current direction.
    /// Maintains the angle of the wire (direction from start to current end).
    private func updateEndPointFromLength(_ newLengthStr: String) {
        guard let newLength = Double(newLengthStr), newLength > 0 else { return }

        // Get start point (F1, F2, F3)
        let x1 = Double(floatFields[0].value) ?? 0
        let y1 = Double(floatFields[1].value) ?? 0
        let z1 = Double(floatFields[2].value) ?? 0

        // Get current end point (F4, F5, F6)
        let x2 = Double(floatFields[3].value) ?? 0
        let y2 = Double(floatFields[4].value) ?? 0
        let z2 = Double(floatFields[5].value) ?? 0

        // Direction vector: end - start
        let dx = x2 - x1
        let dy = y2 - y1
        let dz = z2 - z1

        // Current length
        let currentLength = sqrt(dx * dx + dy * dy + dz * dz)
        guard currentLength > 0 else {
            // If start == end, assume vertical wire going up
            floatFields[3].value = String(format: "%.6g", x1)
            floatFields[4].value = String(format: "%.6g", y1)
            floatFields[5].value = String(format: "%.6g", z1 + newLength)
            return
        }

        // Normalize direction and scale by new length
        let scale = newLength / currentLength
        let newX2 = x1 + dx * scale
        let newY2 = y1 + dy * scale
        let newZ2 = z1 + dz * scale

        floatFields[3].value = String(format: "%.6g", newX2)
        floatFields[4].value = String(format: "%.6g", newY2)
        floatFields[5].value = String(format: "%.6g", newZ2)
    }

    /// Updates the wireLength field based on current start and end points.
    private func updateLengthFromEndPoint() {
        let x1 = Double(floatFields[0].value) ?? 0
        let y1 = Double(floatFields[1].value) ?? 0
        let z1 = Double(floatFields[2].value) ?? 0

        let x2 = Double(floatFields[3].value) ?? 0
        let y2 = Double(floatFields[4].value) ?? 0
        let z2 = Double(floatFields[5].value) ?? 0

        let dx = x2 - x1
        let dy = y2 - y1
        let dz = z2 - z1

        let length = sqrt(dx * dx + dy * dy + dz * dz)
        wireLength = String(format: "%.6g", length)
    }

    /// Returns a tooltip showing the current wire length.
    private func tooltipForLength() -> String {
        if let length = Double(wireLength), length > 0 {
            return String(format: "%.6g meters", length)
        }
        return "Enter wire length in meters"
    }

    func validate() -> [FieldValidationError] {
        // Fields accept any non-empty value: plain numbers or formulas.
        // Syntax and semantic validation happens in the C library.
        // For now, GeometryCardEditor has no client-side validation errors.
        return []
    }

    /// Returns the background color for a field based on validation severity.
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

    /// Updates a field when the user selects a unit in the picker.
    /// Takes the current display value and appends the selected unit.
    private func updateFieldUnit(fieldIndex: Int, unitString: String) {
        guard fieldIndex >= 0, fieldIndex < floatFields.count else { return }

        // Parse the current value to get the numeric part
        let currentValue = floatFields[fieldIndex].value.trimmingCharacters(in: .whitespaces)
        let (numVal, _, _) = UnitsHelper.parseFieldValue(currentValue)

        if unitString == "AWG" {
            // Format as AWG: #6
            floatFields[fieldIndex].value = UnitsHelper.formatFieldValueAWG(numVal)
            floatFields[fieldIndex].isAWG = true
            floatFields[fieldIndex].displayUnit = .none
        } else if unitString.isEmpty {
            // No unit: just the numeric value
            floatFields[fieldIndex].value = String(numVal)
            floatFields[fieldIndex].isAWG = false
            floatFields[fieldIndex].displayUnit = .none
        } else if let unit = UnitsHelper.LengthUnit(rawValue: unitString) {
            // Length unit: 0.5m, 10mm, etc.
            floatFields[fieldIndex].value = UnitsHelper.formatFieldValue(numVal, unit: unit, isAWG: false)
            floatFields[fieldIndex].isAWG = false
            floatFields[fieldIndex].displayUnit = unit
        }
    }

    func collectValues() -> [String] {
        let intVals = intFields.map { $0.value }
        let floatVals = floatFields.map { $0.value }
        return intVals + floatVals
    }
}

