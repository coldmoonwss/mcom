//
//  mcomApp.swift
//  mcom
//
//  Created by coldmoon on 2026/8/27.
//

import SwiftUI

@main
struct mcomApp: App {
    @State private var settings: AppSettings
    @State private var serial: SerialManager
    @State private var commandStore = QuickCommandStore()

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _serial = State(initialValue: SerialManager(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(serial)
                .environment(commandStore)
                .frame(minWidth: 980, idealWidth: 1100,
                       minHeight: 620, idealHeight: 700)
        }
        .windowResizability(.contentMinSize)
    }
}
