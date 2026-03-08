# Mactenna — Editor To-Do (Ad-hoc)

Items collected here are future implementation tasks that don't yet have a scheduled phase.
Move items to `project_outline.md` when they are scoped and ready to implement.

---

## Deck Editor

- **Formula cell tooltip** — cells showing a formula expression (e.g. `lambda/4`) should display the evaluated numeric value as a tooltip on hover (`NSView.toolTip`). Requires passing `i`/`f` alongside `iFormulas`/`fFormulas` in `DeckRow` and setting `toolTip` on the `EditableCell` in `tableView(_:viewFor:row:)`.

- **Card type popup width** — the Type column popup is slightly narrow on some card codes; revisit ideal/max width once real decks are tested.

- **XT / IT / OP extension cards** — `onec_codes[]` in the C library contains `XT` (eXiT), `IT` (ITerate), and `OP` (OPtimize) in addition to `SY`. Their field semantics are not yet understood; add them to `NECCardType` and the popup lists once documented.

- **Card type change side-effects** — when the user changes a card's type via the popup, field values from the old type may be meaningless for the new type. Consider zeroing fields or prompting the user on type change.

- **Drag-to-reorder rows** — `NSTableView` supports drag-and-drop reordering; wire `tableView(_:pasteboardWriterForRow:)` and `tableView(_:acceptDrop:row:dropOperation:)`.

- **Card type picker on Add Row** — the + button always inserts a `GW` card. Show a picker (popover or sheet) so the user can choose the card type before inserting.

- **Inline validation / error highlighting** — highlight cells with out-of-range or type-mismatched values in red; show tooltip with the error message.

- **Column visibility toggle** — let the user hide unused columns (e.g. hide F5–F7 when no card in the deck uses them).

---

## General / Future

- **XT / IT / OP UI** — once the semantics of these OpenNEC extension cards are documented, implement spanning display and editing similar to SY.

- **iOS / iPadOS DeckTableView** — `List`-based counterpart behind `#if !os(macOS)` / `#else`; column layout TBD.
