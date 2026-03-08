//
//  NECCardType.swift
//  Mactenna
//
//  Enumerates every NEC-2 card mnemonic understood by OpenNEC,
//  plus an .unknown catch-all for unrecognised codes.
//
//  NEC cards are two capital letters, e.g. "GW" or "EX".
//  OpenNEC comment codes (from types.c comment_codes[]): CM, CE, !, ', #
//  OpenNEC extension codes (from types.c onec_codes[]): XT, SY, IT, OP
//
//  Cards fall into four categories:
//    • Comment    — CM, CE, !, ', #
//    • Geometry   — GW, GX, GR, GS, GM, GC, GA, GH, GF, SP, SM, SC, GE
//    • Control    — FR, EX, LD, GN, GD, NT, TL, EK, NE, NH, KH, XQ, PQ,
//                   RP, CP, PT, WB, NX, PL, EN
//    • Extension  — SY (only supported extension currently)
//
//  TODO: XT (eXiT/nec2c), IT (ITerate), OP (OPtimize) are valid onec_codes
//        but their deck semantics are not yet implemented in the UI.
//        PR (Print) and LN (Label) were previously listed here but do not
//        exist in the C library and have been removed.

import Foundation

enum NECCardType: String, CaseIterable, Codable, Hashable {

    // MARK: – Comment cards  (matches comment_codes[] in types.c)
    case CM              // Comment
    case CE              // Comment End (required terminator)
    case bangComment  = "!"  // Inline comment (! prefix)
    case apostComment = "'"  // Inline comment (' prefix)
    case hashComment  = "#"  // Inline comment (# prefix)

    // MARK: – Geometry cards
    case GW  // Wire
    case GX  // Reflection in coordinate planes
    case GR  // Rotate and duplicate structure
    case GS  // Scale structure dimensions (unit conversion)
    case GM  // Move and duplicate structure
    case GC  // Wire radius change (tapered wire)
    case GA  // Arc wire
    case GH  // Helix wire
    case GF  // Read NEC greens file (NGF)
    case SP  // Surface patch
    case SM  // Multiple-patch surface
    case SC  // Continue surface patch
    case GE  // Geometry End (required terminator)

    // MARK: – Control cards
    case FR  // Frequency
    case EX  // Excitation (source)
    case LD  // Loading
    case GN  // Ground parameters
    case GD  // Additional ground
    case NT  // Network
    case TL  // Transmission line
    case EK  // Extended thin-wire kernel
    case NE  // Near electric field computation
    case NH  // Near magnetic field computation
    case KH  // Interaction approximation range
    case XQ  // Execute (no print)
    case PQ  // Print charge densities
    case RP  // Radiation pattern
    case CP  // Couple (coupling between antenna elements)
    case PT  // Print current
    case WB  // Wire surface patch
    case NX  // Next structure
    case PL  // Plot flags
    case EN  // End of run

    // MARK: – OpenNEC extension cards
    case SY  // Symbol (variable assignment) — from onec_codes[]

    // MARK: – Fallback
    case unknown

    // Convenience init that maps a raw string.
    // Note: !, ', # are single-char codes and must NOT be uppercased.
    init(_ code: String) {
        // Try exact match first (preserves !, ', # and two-letter codes).
        if let match = NECCardType(rawValue: code) {
            self = match
        } else if let match = NECCardType(rawValue: code.uppercased()) {
            // Fall back to uppercased for two-letter codes typed in lowercase.
            self = match
        } else {
            self = .unknown
        }
    }

    // –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    // MARK: – Category

    enum Category: String, CaseIterable {
        case comment  = "Comment"
        case geometry = "Geometry"
        case control  = "Control"
        case extension_ = "Extension"
        case unknown  = "Unknown"
    }

    var category: Category {
        switch self {
        case .CM, .CE, .bangComment, .apostComment, .hashComment:
            return .comment
        case .GW, .GX, .GR, .GS, .GM, .GC, .GA, .GH, .GF, .SP, .SM, .SC, .GE:
            return .geometry
        case .FR, .EX, .LD, .GN, .GD, .NT, .TL, .EK, .NE, .NH, .KH,
             .XQ, .PQ, .RP, .CP, .PT, .WB, .NX, .PL, .EN:
            return .control
        case .SY:
            return .extension_
        case .unknown:
            return .unknown
        }
    }

    // –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    // MARK: – Human-readable labels

    var displayName: String {
        switch self {
        case .CM: return "Comment"
        case .CE: return "Comment End"
        case .bangComment:  return "Comment (!)"
        case .apostComment: return "Comment (')"
        case .hashComment:  return "Comment (#)"
        case .GW: return "Wire"
        case .GX: return "Reflect"
        case .GR: return "Rotate & Duplicate"
        case .GS: return "Scale"
        case .GM: return "Move & Duplicate"
        case .GC: return "Tapered Wire"
        case .GA: return "Arc"
        case .GH: return "Helix"
        case .GF: return "Read Geometry File"
        case .SP: return "Surface Patch"
        case .SM: return "Multiple Patch"
        case .SC: return "Continue Patch"
        case .GE: return "Geometry End"
        case .FR: return "Frequency"
        case .EX: return "Excitation"
        case .LD: return "Loading"
        case .GN: return "Ground"
        case .GD: return "Additional Ground"
        case .NT: return "Network"
        case .TL: return "Transmission Line"
        case .EK: return "Extended Kernel"
        case .NE: return "Near E-Field"
        case .NH: return "Near H-Field"
        case .KH: return "Interaction Range"
        case .XQ: return "Execute"
        case .PQ: return "Print Charge"
        case .RP: return "Radiation Pattern"
        case .CP: return "Coupling"
        case .PT: return "Print Current"
        case .WB: return "Wire Surface Patch"
        case .NX: return "Next Structure"
        case .PL: return "Plot Flags"
        case .EN: return "End"
        case .SY: return "Symbol"
        case .unknown: return "Unknown"
        }
    }

    // Integer field labels (NEC uses I1–I4).
    // nil means the field is unused/blank for this card type.
    var intFieldLabels: [String?] {
        switch self {
        // Comment
        case .CM, .CE,
             .bangComment, .apostComment, .hashComment: return [nil, nil, nil, nil]
        // Geometry
        case .GW, .GA:          return ["Tag", "Segs", nil, nil]
        case .GH:               return ["Tag", "Segs", nil, nil]
        case .GC:               return [nil, nil, nil, nil]
        case .GX:               return ["TagInc", "Planes", nil, nil]
        case .GR:               return ["TagInc", "TotalN", nil, nil]
        case .GS:               return [nil, nil, nil, nil]
        case .GM:               return ["TagInc", "Reps", nil, nil]
        case .GE:               return ["GndFlag", nil, nil, nil]
        case .GF:               return [nil, nil, nil, nil]
        case .SP:               return [nil, "Shape", nil, nil]
        case .SM:               return ["NX", "NY", nil, nil]
        case .SC:               return [nil, "Shape", nil, nil]
        // Control
        case .FR:               return ["Type", "Steps", nil, nil]
        case .EX:               return ["Type", "Tag", "Seg", "Options"]
        case .LD:               return ["Type", "Tag", "Seg1", "Seg2"]
        case .GN:               return ["Type", "Radials", nil, nil]
        case .GD:               return [nil, nil, nil, nil]
        case .NT, .TL:          return ["Tag1", "Seg1", "Tag2", "Seg2"]
        case .NE, .NH:          return ["Coords", "N1", "N2", "N3"]
        case .RP:               return ["Mode", "Nθ", "Nφ", "XNDA"]
        case .EK:               return ["Mode", nil, nil, nil]
        case .KH:               return [nil, nil, nil, nil]
        case .XQ:               return ["Pattern", nil, nil, nil]
        case .PQ:               return ["Flag", "Tag", "Seg1", "Seg2"]
        case .PT:               return ["Flag", "Tag", "Seg1", "Seg2"]
        case .CP:               return ["Tag1", "Seg1", "Tag2", "Seg2"]
        case .WB, .NX, .PL, .EN: return [nil, nil, nil, nil]
        // Extensions
        case .SY:               return [nil, nil, nil, nil]
        case .unknown:          return [nil, nil, nil, nil]
        }
    }

    // Float field labels (NEC uses F1–F7).
    // nil means the field is unused/blank for this card type.
    var floatFieldLabels: [String?] {
        switch self {
        case .CM, .CE,
             .bangComment, .apostComment, .hashComment: return [nil, nil, nil, nil, nil, nil, nil]
        case .GW:               return ["X1", "Y1", "Z1", "X2", "Y2", "Z2", "Radius"]
        case .GA:               return ["ArcRad", "Ang1°", "Ang2°", "WireR", nil, nil, nil]
        case .GH:               return ["Spacing", "Length", "RadX1", "RadY1", "RadX2", "RadY2", "WireR"]
        case .GC:               return ["RDel", "Rad1", "Rad2", nil, nil, nil, nil]
        case .GX, .GR:          return [nil, nil, nil, nil, nil, nil, nil]
        case .GS:               return ["Factor", nil, nil, nil, nil, nil, nil]
        case .GM:               return ["RotX°", "RotY°", "RotZ°", "Δx", "Δy", "Δz", "TagEnd"]
        case .GE, .GF:          return [nil, nil, nil, nil, nil, nil, nil]
        case .SP:               return ["X1", "Y1", "Z1", "X2", "Y2", "Z2", nil]
        case .SM:               return ["X1", "Y1", "Z1", "X2", "Y2", "Z2", nil]
        case .SC:               return ["X3", "Y3", "Z3", "X4", "Y4", "Z4", nil]
        case .FR:               return ["Freq MHz", "Step", nil, nil, nil, nil, nil]
        case .EX:               return ["V Real", "V Imag", "Norm", "ΔTheta", "ΔPhi", "Axial R", nil]
        case .LD:               return ["R Ω", "L H", "C F", nil, nil, nil, nil]
        case .GN:               return ["εr", "σ S/m", nil, nil, nil, nil, nil]
        case .GD:               return ["εr2", "σ2 S/m", "CLT m", "CHT m", nil, nil, nil]
        case .NT:               return ["Y11R", "Y11I", "Y12R", "Y12I", "Y22R", "Y22I", nil]
        case .TL:               return ["Z0 Ω", "Len m", "Y1R", "Y1I", "Y2R", "Y2I", nil]
        case .NE, .NH:          return ["X/R", "Y/φ°", "Z/θ°", "ΔX/ΔR", "ΔY/Δφ", "ΔZ/Δθ", nil]
        case .RP:               return ["Theta0°", "Phi0°", "dTheta°", "dPhi°", "R m", "GNorm", nil]
        case .EK:               return [nil, nil, nil, nil, nil, nil, nil]
        case .KH:               return ["RKH λ", nil, nil, nil, nil, nil, nil]
        case .XQ, .PQ, .PT, .CP, .WB, .NX, .PL, .EN:
                                return [nil, nil, nil, nil, nil, nil, nil]
        case .SY:               return [nil, nil, nil, nil, nil, nil, nil]
        case .unknown:          return [nil, nil, nil, nil, nil, nil, nil]
        }
    }
}
