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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 mcom") {
                    openWindow(id: "about")
                }
            }
        }

        Window("关于 mcom", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    @Environment(\.openWindow) private var openWindow
}

/// 关于窗口:图标、版本、构建号、版权、仓库链接。
struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 10) {
            Image("AboutIcon")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text("mcom")
                .font(.title)
                .fontWeight(.semibold)

            Text("版本 \(version)(\(build))")
                .foregroundStyle(.secondary)

            Text("macOS 串口调试工具,快捷发送 AT 命令")
                .font(.callout)
                .foregroundStyle(.secondary)

            Link("GitHub 仓库", destination: URL(string: "https://github.com/coldmoonwss/mcom")!)
                .font(.callout)

            if !copyright.isEmpty {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(minWidth: 300)
    }
}
