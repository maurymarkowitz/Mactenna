//
//  Preferences.swift
//  Mactenna
//
//  Centralised model for application preferences.  The values are backed by
//  UserDefaults via the @AppStorage property wrapper, which means they are
//  persisted automatically and can be read and written from anywhere in the
//  app.
//
//  New preferences should be added here along with sensible defaults; the UI
//  in `PreferencesView` binds directly to these properties.
//

import Foundation
import SwiftUI
import Combine

/// Singleton object exposing user-configurable settings.
///
/// The instance is intentionally light-weight and may be replaced by a more
/// sophisticated store (e.g. using Combine) later.
final class Preferences: ObservableObject {
    // ObservableObject requirement
    let objectWillChange = ObservableObjectPublisher()

    static let shared = Preferences()

    private init() {} // enforce singleton

    // MARK: – General
    @AppStorage("deckDefaultColumnOrder") var deckDefaultColumnOrder: String = "rownum,card,I1,I2,I3,I4,F1,F2,F3,F4,F5,F6,F7,ignore,invisible,comment"
    @AppStorage("deckShowIgnoredByDefault") var deckShowIgnoredByDefault: Bool = true

    // MARK: – Simulation
    @AppStorage("simDefaultStepDegrees") var simDefaultStepDegrees: Double = 5.0
    @AppStorage("simAutoRecalcEnabled") var simAutoRecalcEnabled: Bool = true
    @AppStorage("simAutoRecalcThreshold") var simAutoRecalcThreshold: Double = 1e9

    // MARK: – Logging
    @AppStorage("logVerbosity") var logVerbosity: Int = 0

    // MARK: – Pattern view
    @AppStorage("patternColorMap") var patternColorMap: String = "default" // placeholder
    @AppStorage("patternAutoRun") var patternAutoRun: Bool = true

    // MARK: – Geometry display
    @AppStorage("geometryExaggerateSmallDiameters") var geometryExaggerateSmallDiameters: Bool = true // default to on as per user request
    @AppStorage("geometryRadiusScale") var geometryRadiusScale: Double = 5.0

    // MARK: – Deck table
    @AppStorage("deckShowSectionLabels") var deckShowSectionLabels: Bool = true

    // MARK: – External engine
    @AppStorage("externalEnginePath") var externalEnginePath: String = ""
    @AppStorage("externalEngineArgs") var externalEngineArgs: String = ""
}
