//
//  QuickCommand.swift
//  mcom
//
//  快捷命令模型与持久化(UserDefaults + JSON),支持分页与按页导入导出。
//

import Foundation
import SwiftUI

struct QuickCommand: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var command: String
}

struct QuickCommandPage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var commands: [QuickCommand]
}

/// 按页导出的文件格式
struct QuickCommandPageExport: Codable {
    var version: Int
    var name: String
    var commands: [QuickCommand]

    static let currentVersion = 1
}

enum QuickCommandImportError: LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "文件格式不正确,请选择 mcom 导出的快捷命令 JSON 文件"
        case .unsupportedVersion(let version):
            return "文件版本(\(version))高于当前应用支持的版本,请升级应用"
        }
    }
}

@Observable
final class QuickCommandStore {
    private(set) var pages: [QuickCommandPage] = []
    private(set) var selectedPageID: UUID?

    private let defaults = UserDefaults.standard
    private let pagesKey = "quickCommandPages"
    private let legacyCommandsKey = "quickCommands"
    private let selectedPageKey = "quickCommandSelectedPage"

    /// 当前选中页(始终非空,至少保留一页)
    var selectedPage: QuickCommandPage {
        pages.first(where: { $0.id == selectedPageID }) ?? pages[0]
    }

    private var selectedPageIndex: Int {
        pages.firstIndex(where: { $0.id == selectedPageID }) ?? 0
    }

    static let defaultCommands: [QuickCommand] = [
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

    // MARK: - 持久化

    private func load() {
        if let data = defaults.data(forKey: pagesKey),
           let decoded = try? JSONDecoder().decode([QuickCommandPage].self, from: data),
           !decoded.isEmpty {
            pages = decoded
        } else if let data = defaults.data(forKey: legacyCommandsKey),
                  let legacy = try? JSONDecoder().decode([QuickCommand].self, from: data) {
            // 旧版单列表数据迁移为「第 1 页」
            pages = [QuickCommandPage(name: "第 1 页", commands: legacy)]
            defaults.removeObject(forKey: legacyCommandsKey)
            save()
        } else {
            pages = [QuickCommandPage(name: "第 1 页", commands: Self.defaultCommands)]
            save()
        }

        if let idString = defaults.string(forKey: selectedPageKey),
           let id = UUID(uuidString: idString),
           pages.contains(where: { $0.id == id }) {
            setSelection(id)
        } else {
            setSelection(pages[0].id)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pages) {
            defaults.set(data, forKey: pagesKey)
        }
    }

    private func setSelection(_ id: UUID?) {
        selectedPageID = id
        defaults.set(id?.uuidString, forKey: selectedPageKey)
    }

    // MARK: - 页操作

    func addPage() {
        let page = QuickCommandPage(name: "第 \(pages.count + 1) 页", commands: [])
        pages.append(page)
        setSelection(page.id)
        save()
    }

    func renamePage(_ page: QuickCommandPage, name: String) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages[index].name = name.isEmpty ? "第 \(index + 1) 页" : name
        save()
    }

    func deletePage(_ page: QuickCommandPage) {
        guard pages.count > 1,
              let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages.remove(at: index)
        if selectedPageID == page.id {
            setSelection(pages[max(index - 1, 0)].id)
        }
        save()
    }

    func selectPage(_ page: QuickCommandPage) {
        setSelection(page.id)
    }

    // MARK: - 当前页命令操作

    func add(_ command: QuickCommand) {
        pages[selectedPageIndex].commands.append(command)
        save()
    }

    func update(_ command: QuickCommand) {
        let pageIndex = selectedPageIndex
        guard let index = pages[pageIndex].commands.firstIndex(where: { $0.id == command.id }) else { return }
        pages[pageIndex].commands[index] = command
        save()
    }

    func delete(_ command: QuickCommand) {
        pages[selectedPageIndex].commands.removeAll { $0.id == command.id }
        save()
    }

    /// 删除当前页最后一条命令。
    func removeLast() {
        guard !pages[selectedPageIndex].commands.isEmpty else { return }
        pages[selectedPageIndex].commands.removeLast()
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        pages[selectedPageIndex].commands.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func moveUp(_ command: QuickCommand) {
        let commands = pages[selectedPageIndex].commands
        guard let index = commands.firstIndex(where: { $0.id == command.id }), index > 0 else { return }
        pages[selectedPageIndex].commands.swapAt(index, index - 1)
        save()
    }

    func moveDown(_ command: QuickCommand) {
        let commands = pages[selectedPageIndex].commands
        guard let index = commands.firstIndex(where: { $0.id == command.id }),
              index < commands.count - 1 else { return }
        pages[selectedPageIndex].commands.swapAt(index, index + 1)
        save()
    }

    /// 拖拽排序:把 draggedID 移动到 targetID 的位置。
    func move(draggedID: UUID, to targetID: UUID) {
        var commands = pages[selectedPageIndex].commands
        guard let from = commands.firstIndex(where: { $0.id == draggedID }),
              let to = commands.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        let item = commands.remove(at: from)
        commands.insert(item, at: to)
        pages[selectedPageIndex].commands = commands
        save()
    }

    // MARK: - 导入导出

    /// 导出指定页为 JSON 数据。
    func exportPage(_ page: QuickCommandPage) -> Data? {
        let payload = QuickCommandPageExport(
            version: QuickCommandPageExport.currentVersion,
            name: page.name,
            commands: page.commands
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(payload)
    }

    /// 从 JSON 数据导入为新页(命令重新分配 id),导入后选中新页。
    /// fallbackName 用于文件内 name 为空时(一般为文件名)。
    @discardableResult
    func importPage(from data: Data, fallbackName: String) throws -> QuickCommandPage {
        guard let payload = try? JSONDecoder().decode(QuickCommandPageExport.self, from: data) else {
            throw QuickCommandImportError.invalidFormat
        }
        guard payload.version <= QuickCommandPageExport.currentVersion else {
            throw QuickCommandImportError.unsupportedVersion(payload.version)
        }
        let name = payload.name.isEmpty ? fallbackName : payload.name
        let page = QuickCommandPage(
            name: name,
            commands: payload.commands.map { QuickCommand(title: $0.title, command: $0.command) }
        )
        pages.append(page)
        setSelection(page.id)
        save()
        return page
    }
}
