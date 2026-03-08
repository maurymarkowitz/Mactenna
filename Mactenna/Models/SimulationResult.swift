//
//  SimulationResult.swift
//  Mactenna
//
//  Immutable value type produced by NECDeck.runSimulation().
//  All data is extracted from the C library before this struct is created,
//  so it is safe to read from any thread once constructed.
//

import Foundation

struct SimulationResult {

    // MARK: – Run metadata

    /// True if nec_run_simulation returned non-zero or an error prevented the run.
    let failed: Bool

    /// Human-readable error string when `failed` is true.
    let errorMessage: String?

    // MARK: – Formatted text report

    /// Text produced by write_nec_output() — the full NEC output file as a string.
    /// This is the traditional NEC output format (frequencies, impedances,
    /// radiation pattern tables, etc.) and is the primary Phase 3 display.
    let outputText: String

    // MARK: – Log lines

    /// Messages captured via nec_set_log_callback during the run.
    /// Level 0 = info, higher = warnings/errors (mirrors C enum).
    let logLines: [String]

    // MARK: – Summary convenience

    /// True if outputText is non-empty (simulation produced printable results).
    var hasOutput: Bool { !outputText.isEmpty }

    /// True if there are any log messages.
    var hasLog: Bool { !logLines.isEmpty }
}
