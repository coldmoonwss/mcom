//
//  QuickCommand.swift
//  mcom
//
//  快捷命令模型与持久化(UserDefaults + JSON)。
//

import Foundation
import SwiftUI

struct QuickCommand: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var command: String
}

@Observable
final class QuickCommandStore {
    private(set) var commands: [QuickCommand] = []

    private let defaultsKey = "quickCommands"

    static let defaults: [QuickCommand] = [
        QuickCommand(title: "AT 测试", command: "AT"),
        QuickCommand(title: "关闭回显", command: "ATE0"),
        QuickCommand(title: "厂商信息", command: "AT+CGMI"),
        QuickCommand(title: "型号信息", command: "AT+CGMM"),
        QuickCommand(title: "信号强度", command: "AT+CSQ"),
        QuickCommand(title: "网络注册", command: "AT+CREG?"),
        QuickCommand(title: "产品信息", command: "ATI"),
    ]

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([QuickCommand].self, from: data)
        else {
            commands = Self.defaults
            save()
            return
        }
        commands = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(commands) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func add(_ command: QuickCommand) {
        commands.append(command)
        save()
    }

    func update(_ command: QuickCommand) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        commands[index] = command
        save()
    }

    func delete(_ command: QuickCommand) {
        commands.removeAll { $0.id == command.id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        commands.move(fromOffsets: source, toOffset: destination)
        save()
    }
}
