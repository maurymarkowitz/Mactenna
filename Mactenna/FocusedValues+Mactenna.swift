//
//  FocusedValues+Mactenna.swift
//  Mactenna
//
//  FocusedValues keys that let MactennaApp Commands reach the currently
//  focused document window's ContentView without tight coupling.
//

import SwiftUI

extension FocusedValues {
    /// Closure to insert a new card after the selected row (or at end of deck).
    @Entry var addCard: (() -> Void)? = nil

    /// Closure to delete the currently selected card row.
    @Entry var deleteCard: (() -> Void)? = nil

    /// Whether a card is currently selected (determines Delete Card enabled state).
    /// Must be Optional — the @Entry macro requires Optional values on FocusedValues.
    @Entry var canDeleteCard: Bool? = nil
}
