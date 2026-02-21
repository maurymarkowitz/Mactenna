//
//  ContentView.swift
//  Mactenna
//
//  Created by Maury Markowitz on 2026-02-21.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: MactennaDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(MactennaDocument()))
}
