# Mactenna Project Outline

## 1. Project Overview

**Mactenna** is a document-based SwiftUI application targeting macOS (primary) and iPadOS (secondary). It provides a GUI front-end for the OpenNEC antenna modeling library, enabling users to create, edit, and visualize NEC antenna deck files, run calculations, and display radiation patterns in interactive 3D.

---

## 2. Core Technologies

| Component | Technology |
|---|---|
| UI Framework | SwiftUI |
| Document Model | `FileDocument` |
| 3D Visualization | RealityKit |
| OpenNEC Bridge | C ↔ Swift via bridging header (`opennec.h`) + `libonec.a` |
| Build System | Xcode, Swift Package Manager |
| File Formats | `.nec`, `.deck` (plain text) |

---

## 3. Major Subsystems

### 3.1 Document & File Management
- Native document-based app using SwiftUI's `DocumentGroup`
- Open, save, save-as, revert for `.nec` / `.deck` files
- File browser / recents panel
- Import/export support
- Undo/redo stack tied to deck edits

### 3.2 Deck Editor
- Table-based editor mapping directly to NEC card rows
- Each row represents a NEC "card" (GW, EX, FR, RP, etc.)
- Inline validation and error highlighting
- Add, delete, reorder rows
- Card-type picker with per-card field descriptions/tooltips
- Live sync between table rows and the OpenNEC `Deck` object

### 3.3 OpenNEC Bridge
- OpenNEC is a pure C library located at `~/Developer/OpenNEC/`
- Public API entry point: `opennec.h`; pre-built static library: `libonec.a`
- Key C types: `card_t`, `deck_t`, `nec_context_t` (opaque)
- Key C functions:
  - `nec_create_context()` / `nec_destroy_context()` — context lifecycle
  - `read_deck()` — parse an open `FILE*` into a `deck_t`
  - `parse_deck()` — structural analysis, unit conversion, field parsing
  - `evaluate_symbols_in_comments()` / `update_deck_values()` — formula/symbol evaluation via `tinyexpr`
  - `mark_4nec2_cards_invisible()` — 4nec2 compatibility filtering
  - `nec_run_simulation()` — run the NEC engine
  - `write_deck_onec()` — serialize `deck_t` back to a file (preserves formulas, symbols, extensions)
  - `nec_set_log_callback()` — capture log/error messages
- Swift integration via a thin C bridging header (`MactennaOpenNEC.h`)
- **The C library is the sole owner and source of truth for parsed deck data.**
  The C library handles all parsing, unit conversion, formula/symbol evaluation,
  and 4nec2 compatibility — none of this is reimplemented in Swift.
- `NECDeck.swift` — a Swift `ObservableObject` class that owns `deck_t *` and
  `nec_context_t *`; exposes card data to the UI by reading `card_t` fields directly
- `DeckRow.swift` — a lightweight read-only display proxy built from `card_t`
  fields on demand; not a storage model
- `MactennaDocument.swift` — thin `FileDocument` holding only raw text for I/O;
  on open, passes text to `NECDeck`; on save, retrieves text from `NECDeck`

### 3.4 Calculation Engine Interface
- "Run" button triggers calculation via OpenNEC
- Background execution to keep UI responsive
- Progress/status reporting
- Error capture and display
- Results stored per-document

### 3.5 3D Visualization — Radiation Pattern
- Parse radiation pattern (RP card output) from OpenNEC results
- Map gain/pattern data to 3D geometry (sphere-like mesh with gain-scaled vertices)
- Color mapping for gain values (e.g. dBi scale)
- Interactive: rotate, zoom, pan
- Toggle between linear and dB scale
- Overlay cardinal directions / reference sphere

### 3.6 3D Visualization — Antenna Geometry
- **Phase 1:** Use OpenNEC's segmented wire geometry for display
- **Phase 2:** Independent geometry renderer that reads the deck directly
  - Render wires, sources, loads without NEC segmentation artifacts
  - Cleaner visual for editing feedback
  - Real-time update as deck is edited

---

## 4. Development Phases

### Phase 1 — Foundation ✅
- [x] Xcode project setup, macOS target (iOS target pending)
- [x] `OpenNEC.xcconfig` — `HEADER_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS`, `OTHER_LDFLAGS = -lonec`, bridging header path
- [x] `Mactenna/Bridge/MactennaOpenNEC.h` — C bridging header importing `opennec.h`
- [x] `Info.plist` — UTType `net.maury.mactenna.nec-deck` declared for `.nec` / `.deck`
- [x] `MactennaDocument.swift` — thin `FileDocument`; holds raw text only; passes to `NECDeck` on open, reads back on save
- [x] `Models/NECCardType.swift` — enum of all NEC card mnemonics with category, `displayName`, and per-card int/float field labels
- [x] `Models/DeckRow.swift` — read-only display proxy; values copied from `card_t.i` / `card_t.f` on demand; comments come from `card_t.comment` or `card_t.extn_str` (SY cards now show comment in comment column); also records `isIgnored` for commented‑out cards

- [x] `Models/NECDeck.swift` — Swift `ObservableObject` owning `deck_t *` and `nec_context_t *`; calls `read_deck`, `parse_deck`, `update_deck_values`; exposes `card(at:)` and `text()`
- [x] `Views/DeckTableView.swift` — `NSViewRepresentable` wrapping `NSTableView`; reads card data from `NECDeck`; 13 columns; comment rows span I1 column; category colour coding
- [x] `ContentView.swift` — `HSplitView`; creates `@StateObject NECDeck` from document text; syncs back on change

### Phase 2 — Editing ✅
- [x] `EditableCell: NSTextField` subclass stores row + colID for delegate identification
- [x] `DeckTableView.onCommitEdit` callback — wired to `ContentView.handleCellEdit`
- [x] In-place editing enabled for all columns except "card" (I1–I4, F1–F7, comment, CM/CE text)
- [x] `NSTextFieldDelegate.controlTextDidEndEditing` in Coordinator — fires `onCommitEdit`
- [x] `NECDeck.setIntField(row:field:value:)` — writes to `card_t.i`, marks `edited`, bumps `editGeneration`
- [x] `NECDeck.setFloatField(row:field:value:)` — writes to `card_t.f`, marks `edited`, bumps `editGeneration`
- [x] `NECDeck.setComment(row:text:)` — frees old `char*`, `strdup` new value, marks `edited`
- [x] `NECDeck.addCard(_:after:)` — text-roundtrip insert (avoids off-by-one bug in C `insert_card`), returns snapshot
- [x] `NECDeck.deleteCard(at:)` — text-roundtrip delete, returns snapshot
- [x] `NECDeck.restore(text:)` — undo target; calls `load(text:)`
- [x] `NECDeck.editGeneration` — `@Published` int bumped on field edits; drives dirty sync
- [x] `ContentView` + / − toolbar buttons (navigation placement) with UndoManager registration
- [x] `ContentView.applyEdit` — parses string value, skips no-op edits, calls appropriate setter
- [x] Undo/redo for all edits (field edits + insert + delete) via `UndoManager` text snapshots
- [x] extern declarations for `new_card`, `append_card`, `remove_card` in bridging header

### Phase 3 — Calculation ✅
- [x] Wire up OpenNEC calculation engine via bridge
- [x] Background task execution (`DispatchQueue.global` + `nec_run_simulation` on separate context)
- [x] `SimulationResult` — immutable value type holding log lines + `write_nec_output` text
- [x] `NECDeck.runSimulation()` — creates fresh sim context, captures log via `nec_set_log_callback`, calls `nec_run_simulation`, captures text via `write_nec_output`, publishes `SimulationResult` on main thread
- [x] `ResultsView` — replaces right-pane placeholder; shows Output / Log tabs with monospace `NSTextView`
- [x] Run toolbar button enabled (▶ play.fill) with progress spinner while running
- [x] `OpenNEC.xcconfig` — added `-framework Accelerate` for LAPACK `zgetrf` (pulled in by matrix solver)

### Phase 4 — 3D Radiation Pattern
- [x] Begin Phase 4 work: add SceneKit-based view scaffold (PatternView.swift)
- [x] Allow viewer to compute full‑sphere pattern on demand (5° steps) without
      modifying deck RP cards
- [x] Parse RP output data (radiation pattern tables in outputText or context)
- [x] Build 3D pattern mesh from theta/phi/gain values
- [x] Interactive SceneKit view
- [x] Color mapping and legend

### Phase 5 — 3D Geometry Viewer
- [ ] Phase 1: geometry from OpenNEC segmented data
- [ ] Phase 2: native deck-to-geometry renderer (no segmentation)
- [ ] Real-time geometry preview during editing

### Phase 6 — Polish & iOS
- [ ] iPad layout and navigation
- [ ] Keyboard shortcuts (macOS)
- [ ] Toolbar customization
- [ ] Accessibility
- [ ] Help documentation

### Phase 7 — Integrate other engines
- [ ] Export current deck to a temporary file
- [ ] Invoke external NEC engine (e.g. `nec2c`) with that file
- [ ] Read and parse resulting `.out` output into SimulationResult
- [ ] Fall back to direct OneC calls when external engine unavailable

(Useful for supporting alternate solver binaries in future; not
required while OneC is called directly.)

### Phase 8 — Preferences panel
- [x] Create central preferences UI (e.g. `Settings` window / sidebar)
- [x] Add generic framework for registering per-phase preferences
- [x] Phase‑1 settings: deck‑editing defaults (column order, visibility) and auto‑recalc toggle/threshold
- [ ] Phase‑2 settings: simulation options, default step size
- [ ] Phase‑3 settings: log verbosity, output formatting preferences
- [ ] Phase‑4 settings: pattern colour map, default view angle, auto‑run
- [ ] Phase‑7 settings: external engine path and command‑line flags

(Preferences panel will evolve as each phase introduces new tunables; this
section may remain a checklist of ongoing work rather than a single milestone.)

---

## 5. Key Data Flow

```
.nec file on disk
      │
      ▼  read_deck() + parse_deck()   ← C library owns all parsing,
deck_t *                                 unit conversion, formula eval
  (in NECDeck)                           4nec2 compat, symbol table
      │
      ├──── card(at:) ────▶  DeckRow (display proxy, values copied
      │                       from card_t.i / card_t.f on demand)
      │                              │
      │                       NSTableView displays
      │                              │
      │                       user edits cell  (Phase 2)
      │                              │
      │                       write back to card_t fields
      │                       card_t.edited = true
      │
      ├──── write_deck_onec() ────▶  .nec file on disk  (save)
      │
      └──── nec_run_simulation() ────▶  nec_context_t results
                                               │
                                    ┌──────────┴──────────┐
                                    ▼                     ▼
                            3D Pattern              Text/Table
                             Renderer                Results
```

---

## 6. Open Questions / Decisions Needed

1. **SceneKit vs RealityKit** for 3D — SceneKit has broader macOS/iOS parity and more mature tooling; RealityKit is more modern. Recommendation: **SceneKit** initially.
2. **OpenNEC integration** ✅ — `libonec.a` linked via `OpenNEC.xcconfig`; `~/Developer/OpenNEC` is a read-only reference, not copied into the repo.
3. **Deck row schema** ✅ — `NECCardType` enum covers all mnemonics with per-card field labels; `DeckRow` is a lightweight display proxy only. The C library owns all parsed data in `deck_t`.
4. **Table implementation** ✅ — `NSTableView` via `NSViewRepresentable` on macOS (no column limit, native editing in Phase 2); iPadOS will use a `List`-based equivalent behind `#if os(macOS)` / `#else`.
5. **Undo architecture** ✅ — `UndoManager` via `@Environment(\.undoManager)` in `ContentView`; all edits use text snapshots via `NECDeck.restore(text:)` as the undo target.

---

## 7. Suggested Next Steps

1. ✅ Phase 1 complete — document opens `.nec` files, table displays correctly
2. ✅ Phase 2 complete — in-place editing, add/delete rows, full undo/redo
3. **Phase 3** — Wire `nec_run_simulation()`: background `Task`, capture log via `nec_set_log_callback`, enable Run toolbar button, show results pane
4. **Phase 2 enhancement** — Card type picker when inserting rows (currently always inserts `GW`); drag-to-reorder rows
5. **Phase 2 enhancement** — Formula cell tooltip: cells that display a formula expression (e.g. `lambda/4`) should show the calculated numeric value as a tooltip on hover (`NSView.toolTip`); requires passing `i`/`f` alongside `iFormulas`/`fFormulas` in `DeckRow` and setting `toolTip` on the `EditableCell` in `tableView(_:viewFor:row:)`.  Commented‑out cards are greyed and non‑editable.
6. **Phase 2 enhancement** — Add checkbox columns to toggle `card.ignore` and `card.invisible`.  The "Ignored" column behaves as before (greyed, non‑editable).  The new "Invisible" column simply flips the invisible flag with no other effect.
7. Add iOS target and `List`-based `DeckTableView` counterpart behind `#if os(macOS)` / `#else`
