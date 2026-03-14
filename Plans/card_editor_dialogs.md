# Plan: Card Editor Dialogs

## TL;DR

Offer another UI for data entry instead of inline table-cell editing with dedicated dialog windows for each NEC card type. When the user double-clicks a card's row number or uses "Add Card," a type-appropriate dialog appears for creating or editing that card. An "Add" menu in the top menu bar shows all available card types grouped by section (Comments, Geometry, Control), matching the existing popup structure in the deck table.

---

## Design Principles

1. **Type-specific forms**: Each card type (GW, GA, GH, SP, GN, EX, etc.) gets a focused dialog with labeled fields for I1–I4 and F1–F7, plus card-specific metadata.
2. **Consistent UX**: All dialogs follow a common template and interaction model (OK/Cancel, live validation, undo support).
3. **Grouped Add menu**: The top menu bar includes an "Add" menu that mirrors the section structure from the table (Comments, Geometry, Control, etc.), allowing quick card insertion.
4. **Double-click activation**: Double-clicking the row number (or card type cell) opens the editor for that card without entering inline-edit mode.
5. **Write-back to deck**: Dialog commits write through `onCommitEdit` callback, triggering undo registration in the parent controller.

---

## Section Grouping

The Add menu is organized by the same sections used in the deck table:

| Section | Card Types |
|---------|-----------|
| **Comments** | CM, CE, !, ', # |
| **Geometry** | GW, GX, GR, GS, GM, GC, GA, GH, GF, SP, SM, SC, GE |
| **Control** | FR, EX, LD, GN, GD, NT, TL, EK, NE, NH, KH, XQ, PQ, RP, CP, PT, WB, NX, PL, EN |
| **Extensions** | SY |

---

## Dialog Components

### Common Elements (all dialogs)

- **Header**: Card type name (e.g. "Wire (GW)") and code selector (hidden or disabled for edit mode, shown for add-new mode)
- **Field Grid**: Two columns (I1–I4, F1–F7) with labels and input fields
- **Validation Status**: Live feedback for each field (OK, warning, error)
- **Comment Field**: Full-row text input for inline comments (if card has one)
- **Buttons**: OK, Cancel, Delete (for edit mode), Apply (stays open)

### Card-Type-Specific Views

#### Comment Cards (CM, CE, !, ', #)

- **Text Input**: Large text area for comment body
- **No numeric fields**: Gray out / hide I1–I4, F1–F7 sections

#### Geometry Cards (GW, GA, GH, SP, SM, SC, GC, GR, GS, GM, GX, GF)

- **Interactive 3D Preview** (optional, Phase 2): Small OpenGL/SceneKit view showing the geometry being edited
- **Fields Grid**: All 11 fields with labels from NECCardType
- **Context Labels**: Show human-readable descriptions (e.g. "GW: Start X, Y, Z; End X, Y, Z; Radius")

#### Control Cards (FR, EX, LD, GN, etc.)

- **Fields Grid**: Standard I1–I4, F1–F7 with type-specific labels
- **Field Grouping** (optional Phase 2): Visually group related fields with dividers (e.g. EX "Source type" section, "Position" section, "Value" section)

#### Symbol Cards (SY)

- **Key-Value Table**: Two columns (Variable Name, Value expression)
- **Add/Remove Row Buttons**: Manage the assignment list
- **Live Formula Evaluation** (optional): Show numeric result next to each expression

---

## Interaction Model

### Opening the Editor

**Double-click row number (or card type cell)**:
1. Table view detects double-click on "rownum" or "card" column
2. Locate the card at that row index
3. Determine card type
4. Open the editor dialog (modal or sheet-style)
5. Pre-populate fields from the card's data

**"Add Card" function**:
1. User selects a menu item from "Add" → (Section) → (Card Type)
2. Create a new blank card of that type
3. Open the editor dialog (modal or sheet-style)
4. Dialog starts in "add mode" (shows type selector, "Insert" button instead of "OK")

### Dialog Lifecycle

1. **Open**: Dialog loads field values from the card (or defaults for new card)
2. **Edit**: User modifies fields; live validation runs on each field change
3. **Commit**: User clicks OK
   - Validate all fields
   - If valid, call `onCommitEdit(row, "card", newCardText)` for each changed field (or single call with all-fields snapshot)
   - Close dialog
4. **Cancel**: Discard changes, close dialog (no undo snapshot yet since nothing was committed)

---

## Add Menu Placement & Structure

**Menu bar**: Top-level "Add" menu (or integrate into existing "File" menu if Mactenna uses one)

```
Add
├─ Comments
│  ├ Comment (CM)
│  ├ Comment (#)
│  ├ Comment (!)
│  ├ Comment (')
│  └ Comment End (CE)
└─ Extensions
│  └ Symbol (SY)
├─ Geometry
│  ├ Wire (GW)
│  ├ Arc (GA)
│  ├ Helix (GH)
│  ├ Surface Patch (SP)
│  ├ Multiple Patch (SM)
│  ├ Continue Patch (SC)
│  ├ ─────────────────
│  ├ Reflect (GX)
│  ├ Rotate (GR)
│  ├ Scale (GS)
│  ├ Move (GM)
│  ├ Tapered Wire (GC)
│  ├ Read File (GF)
│  └ Geometry End (GE)
├─ Control
│  ├ Frequency (FR)
│  ├ Excitation (EX)
│  ├ Loading (LD)
│  ├ ─────────────────
│  ├ Ground (GN)
│  ├ Adv. Ground (GD)
│  ├ Network (NT)
│  ├ Transmission Line (TL)
│  ├ ─────────────────
│  ├ Extended Kernel (EK)
│  ├ Near E-Field (NE)
│  ├ Near H-Field (NH)
│  ├ Interaction (KH)
│  ├ ─────────────────
│  ├ Execute (XQ)
│  ├ Print Charge (PQ)
│  ├ Radiation (RP)
│  ├ Coupling (CP)
│  ├ Print Current (PT)
│  ├ Patch Wire (WB)
│  ├ Next Structure (NX)
│  ├ Plot Flags (PL)
│  └ End (EN)

```

---

## Implementation Phases

### Phase 1: Foundation & Dialog Scaffold

1. **New file**: `CardEditorDialog.swift` — Base dialog class/struct
   - Common layout (header, field grid, buttons)
   - Delegate protocol for commit/cancel callbacks
   - Field validation framework

2. **New file**: `Views/CardEditors/` folder with subclasses for each category
   - `CardEditorBase.swift` — Abstract template
   - `CommentCardEditor.swift` — CM/CE/!/'/#
   - `GeometryCardEditor.swift` — GW, GA, GH, SP, SM, SC (primary focus)
   - `ControlCardEditor.swift` — FR, EX, LD, GN, etc.
   - `SymbolCardEditor.swift` — SY

3. **Menu setup** in `MactennaApp.swift` or `ContentView.swift`:
   - Register "Add" menu commands
   - Each menu item has an action that calls `addCard(type:)` on the document
   - Use `.presentationDetents` or `.sheet` to show the dialog

4. **Double-click handling** in `DeckTableView.Coordinator`:
   - Override or hook `tableView(_:mouseDownInHeaderOfTableColumn:)` or intercept `tableViewDoubleClicked(_:)`
   - Detect if click is on "rownum" column
   - Call `editCard(at: rowIndex)` instead of entering inline-edit mode

---

### Phase 2: Enhanced UX & Add Menu

1. **Add menu** in MactennaApp's menu bar with all card types grouped by section
2. **Add-new flow**: Dialog appears in "add mode" when user selects from menu; on commit, inserts card and applies values
3. **Field Grouping**: Sub-headers within dialogs to organize related controls (e.g. EX "Source type" section)
4. **Formula Tooltips**: Hover on F1–F7 to see evaluated numeric value
5. **Snap & Default Suggestions**: When adding GW, pre-populate from nearby geometry
6. **Custom Validators**: Move validation logic into dialog so errors appear before commit

---

### Phase 3: Interactive 3D Preview (optional, defer if time-constrained)

1. **3D Preview**: SceneKit viewlet in Geometry dialogs showing live geometry update while editing
2. Integration with GeometryView for real-time visualization

---

## Relevant Files

- **Mactenna/Views/DeckTableView.swift** — Detect double-click; call editor dialog
- **Mactenna/Models/NECDeck.swift** — Query valid types for a row; write fields via `setFloatField()`, `setIntField()`
- **Mactenna/Models/NECCardType.swift** — Field labels and metadata; used by dialogs
- **Mactenna/Models/DeckRow.swift** — Data structure holding card fields & validation results
- **Mactenna/MactennaDocument.swift** — Parent controller; handles undo for commits
- **Mactenna/MactennaApp.swift** or **Mactenna/ContentView.swift** — Register "Add" menu commands
- **MactennaOpenNEC.h** / **.c** — C API for reading/writing deck cards

---

## Validation Strategy

1. **Per-field**: Each dialog field validates on every change (debounced ~200ms)
2. **On commit**: Full card validation using OpenNEC's `validate_card_all_fields(card_t*)`
3. **Error display**: Show inline error message below the field, or in a summary bar
4. **Undo integration**: Dialog commits call `onCommitEdit`, which routes to document's undo mechanism

---

## Future Enhancements

1. Keyboard shortcuts for "Add Card" (⌘N for new, ⌘E for edit?)
2. Drag-and-drop within Add menu to reorder favorite card types
3. Card templates / quick-add presets (e.g. "Add Standard Dipole" → GW + GE cards)
4. Batch card editor: Edit multiple cards at once (multi-select in table → single dialog with all rows)

---

## Success Criteria

- ✅ All card types have a dedicated editor dialog
- ✅ Dialogs open on double-click of row number
- ✅ "Add" menu lists all types, grouped by section
- ✅ Fields validate in real-time
- ✅ Commits write back to deck and register undo
- ✅ Geometry cards show live field validation
- ✅ No inline cell editing needed for card content (only table reordering/deletion via row ops)

---

## Phase 2 Completion

- ✅ **Add menu** in MactennaApp with all card types grouped by section (Comments, Extensions, Geometry, Control)
- ✅ **Add-new flow**: Dialog shows in "add mode" (rowIndex == -1); on commit, inserts card at appropriate location
- ✅ **Field Grouping**: Geometry and Control editors organize fields by logical sections (e.g. GW: "Start Point", "End Point", "Wire Parameters")
- ✅ **Formula Tooltips**: Hover on F1–F7 fields shows parsed numeric value or formula text
- ✅ **Default Suggestions**: GW cards pre-populate with sensible defaults when adding (1m vertical wire, tag 1, 10 segments, 0.5mm radius)
- ✅ **Formula Support**: All numeric fields (I1–I4, F1–F7) accept plain numbers or formula strings (e.g., "lambda/4", "pi*2"))
  - Formulas are preserved when editing existing cards
  - Editor fields display formulas as-is in text input
  - Tooltips show formula text (e.g., "Formula: lambda/4") for non-numeric entries
  - Syntax validation deferred to C library at save/commit time
  - Factory initializes editors with formula values from deck (prefers formula over numeric if present)
- ✅ **Validation Color-Coding**: Fields get background colors based on C library validation results
  - Yellow (0.2 opacity): Warning-level issues (suspicious but simulation likely to proceed)
  - Orange (0.2 opacity): Problem-level issues (likely to cause incorrect results)
  - Red (0.2 opacity): Fatal-level issues (will definitely fail)
  - Clear: No validation issues (none severity)
- ✅ **Unit Picker Support**: Length and position fields in geometry cards show unit dropdown
  - Supported length units: m, cm, mm, in, ft
  - Wire radius fields also support AWG (American Wire Gauge) notation (#6, #12, etc.)
  - User selects unit and field value is automatically formatted (e.g., "0.5" + "m" → "0.5m", "6" + "AWG" → "#6")
  - Existing units in field values are parsed and displayed in the correct picker selection
  - UnitsHelper utility provides parsing, formatting, and validation for unit support
