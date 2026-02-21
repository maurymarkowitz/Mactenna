//
//  MactennaApp.swift
//  Mactenna
//
//  Created by Maury Markowitz on 2026-02-21.
//

import SwiftUI

@main
struct MactennaApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MactennaDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
