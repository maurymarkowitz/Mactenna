//
//  UnitsHelper.swift
//  Mactenna
//
//  Unit parsing, formatting, and conversion for NEC card fields.
//  Supports length units (m, cm, mm, in, ft) and wire size (AWG).

import Foundation

struct UnitsHelper {

    // MARK: – Unit Definitions

    enum LengthUnit: String, CaseIterable {
        case none = ""
        case meter = "m"
        case centimeter = "cm"
        case millimeter = "mm"
        case inch = "in"
        case foot = "ft"

        var displayName: String {
            switch self {
            case .none: return "—"
            case .meter: return "m"
            case .centimeter: return "cm"
            case .millimeter: return "mm"
            case .inch: return "in"
            case .foot: return "ft"
            }
        }
    }

    enum WireUnit: String, CaseIterable {
        case awg = "AWG"

        var displayName: String { "AWG" }
    }

    // MARK: – Parsing

    /// Parse a field value string and extract numeric value and unit.
    /// Examples:
    ///   "0.5" → (0.5, .none)
    ///   "0.5m" → (0.5, .meter)
    ///   "10mm" → (10.0, .millimeter)
    ///   "#6" → (6, .awg)
    static func parseFieldValue(_ str: String) -> (Double, LengthUnit, Bool) {
        let trimmed = str.trimmingCharacters(in: .whitespaces)

        // Check for AWG notation: #6, #12, etc.
        if trimmed.starts(with: "#") {
            let numStr = String(trimmed.dropFirst())
            if let val = Double(numStr) {
                return (val, .none, true)  // true = is AWG
            }
        }

        // Try to extract numeric + unit
        var numericStr = ""
        var unitStr = ""
        var inUnit = false

        for char in trimmed {
            if char.isNumber || char == "." || char == "-" {
                if !inUnit {
                    numericStr.append(char)
                }
            } else if char.isLetter {
                inUnit = true
                unitStr.append(char)
            }
        }

        guard let value = Double(numericStr) else {
            return (0.0, .none, false)
        }

        let unit = LengthUnit(rawValue: unitStr) ?? .none
        return (value, unit, false)
    }

    /// Format a numeric value with a unit into a field string.
    /// Examples:
    ///   (0.5, .meter) → "0.5m"
    ///   (10, .millimeter) → "10mm"
    ///   (6, isAWG: true) → "#6"
    static func formatFieldValue(_ value: Double, unit: LengthUnit, isAWG: Bool = false) -> String {
        if isAWG {
            return "#\(Int(value))"
        }
        if unit == .none {
            return String(value)
        }
        return "\(value)\(unit.rawValue)"
    }

    /// Format a numeric value with a wire unit.
    static func formatFieldValueAWG(_ value: Double) -> String {
        return "#\(Int(value))"
    }

    // MARK: – Field Metadata

    /// Returns true if the card type and field index should have a length unit picker.
    static func shouldShowLengthUnit(cardType: NECCardType, fieldIndex: Int) -> Bool {
        switch cardType {
        case .GW:
            // F1-F6 are coordinates, F7 is radius
            return fieldIndex >= 0 && fieldIndex < 7  // All float fields for GW
        case .GA:
            // Arc: F1-F3 start, F4-F6 end, F7 radius
            return fieldIndex >= 0 && fieldIndex < 7
        case .GH:
            // Helix: all are length/angle fields
            return fieldIndex >= 0 && fieldIndex < 7
        case .SP, .SM, .SC:
            // Patch cards: coordinates
            return fieldIndex >= 0 && fieldIndex < 7
        case .GC:
            // Tapered wire: coordinates and radius
            return fieldIndex >= 0 && fieldIndex < 7
        default:
            return false
        }
    }

    /// Returns true if the wire size (AWG) notation should be available for this field.
    static func supportsWireSize(cardType: NECCardType, fieldIndex: Int) -> Bool {
        switch cardType {
        case .GW, .GC:
            // Only the radius field (F7, index 6) supports AWG
            return fieldIndex == 6
        default:
            return false
        }
    }
}
