//
//  PreferencesView.swift
//  Mactenna
//
//  The Preferences/settings window for the app.  It presents several tabs that
//  correspond to logical areas of configuration.  This view reads and writes
//  values from `Preferences.shared` using SwiftUI bindings.
//
//  As additional features and phases are added the view can grow new tabs or
//  sections; the underlying `Preferences` singleton should be the canonical
//  source of truth.
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            simulationTab
                .tabItem { Label("Simulation", systemImage: "play.circle") }
            patternTab
                .tabItem { Label("Pattern", systemImage: "waveform.path") }
            geometryPrefsTab
                .tabItem { Label("Geometry", systemImage: "cube") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "hammer") }
        }
        .padding(16)
        .frame(width: 480, height: 360)
    }

    private var generalTab: some View {
        Form {
            Section(header: Text("Deck Editor")) {
                Toggle("Show ignored cards by default", isOn: $prefs.deckShowIgnoredByDefault)
                TextField("Column order", text: $prefs.deckDefaultColumnOrder)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
    }

    private var simulationTab: some View {
        Form {
            Section(header: Text("Pattern computation")) {
                HStack {
                    Slider(value: $prefs.simDefaultStepDegrees,
                           in: 1...30,
                           step: 0.5) {
                        Text("Step (°)")
                    }
                    Text(String(format: "%.1f°", prefs.simDefaultStepDegrees))
                        .frame(width: 50, alignment: .leading)
                }
                Toggle("Enable auto‑recalculate", isOn: $prefs.simAutoRecalcEnabled)
                HStack {
                    Text("Auto‑recalc threshold (s):")
                    TextField("", value: $prefs.simAutoRecalcThreshold, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!prefs.simAutoRecalcEnabled)
                }
            }
        }
        .padding()
    }

    private var patternTab: some View {
        Form {
            Section(header: Text("Visualisation")) {
                Picker("Color map", selection: $prefs.patternColorMap) {
                    Text("Default").tag("default")
                    Text("Spectrum").tag("spectrum")
                    Text("Heat").tag("heat")
                }
                .pickerStyle(.segmented)
                Toggle("Auto‑run pattern on change", isOn: $prefs.patternAutoRun)
            }
        }
        .padding()
    }

    private var geometryPrefsTab: some View {
        Form {
            Section(header: Text("Geometry view")) {
                Toggle("Exaggerate small diameters",
                       isOn: $prefs.geometryExaggerateSmallDiameters)
                HStack {
                    Text("Base radius scale")
                    Slider(value: $prefs.geometryRadiusScale,
                           in: 1...10,
                           step: 0.5)
                    Text(String(format: "%.1fx", prefs.geometryRadiusScale))
                        .frame(width: 50)
                }
                Text("If an element's diameter is \u{003c}1% of its length, show it 5× thicker")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
    }

    private var advancedTab: some View {
        Form {
            Section(header: Text("External engine")) {
                TextField("Engine path", text: $prefs.externalEnginePath)
                    .textFieldStyle(.roundedBorder)
                TextField("Arguments", text: $prefs.externalEngineArgs)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
    }
}

#if DEBUG
struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
#endif
