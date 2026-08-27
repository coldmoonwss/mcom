//
//  AppSettings.swift
//  mcom
//
//  应用设置:时间显示格式、收发日志落盘(目录可选,安全书签持久化)。
//

import Foundation

@Observable
final class AppSettings {
    /// 交互区时间显示格式
    enum TimestampMode: Int, CaseIterable, Identifiable {
        case none = 0     // 不显示
        case time         // 时间
        case dateTime     // 日期+时间

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .none: return "不显示"
            case .time: return "时间"
            case .dateTime: return "日期+时间"
            }
        }
    }

    /// 交互区收/发标识样式
    enum MarkerStyle: Int, CaseIterable, Identifiable {
        case arrow = 0    // → / ←
        case chinese      // 发 / 收

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .arrow: return "箭头 ← →"
            case .chinese: return "中文 收/发"
            }
        }

        func marker(isTX: Bool) -> String {
            switch self {
            case .arrow: return isTX ? "←" : "→"
            case .chinese: return isTX ? "发" : "收"
            }
        }
    }

    private(set) var timestampMode: TimestampMode
    private(set) var markerStyle: MarkerStyle
    private(set) var logEnabled: Bool
    private(set) var logDirectory: URL

    private let defaults = UserDefaults.standard
    private let timestampModeKey = "timestampMode"
    private let markerStyleKey = "markerStyle"
    private let logEnabledKey = "logEnabled"
    private let logDirectoryBookmarkKey = "logDirectoryBookmark"

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    init() {
        timestampMode = TimestampMode(rawValue: defaults.integer(forKey: timestampModeKey)) ?? .time
        markerStyle = MarkerStyle(rawValue: defaults.integer(forKey: markerStyleKey)) ?? .arrow
        logEnabled = defaults.bool(forKey: logEnabledKey)
        logDirectory = Self.resolveBookmark(defaults: defaults, key: logDirectoryBookmarkKey)
            ?? Self.defaultLogDirectory
    }

    func setTimestampMode(_ mode: TimestampMode) {
        timestampMode = mode
        defaults.set(mode.rawValue, forKey: timestampModeKey)
    }

    func setMarkerStyle(_ style: MarkerStyle) {
        markerStyle = style
        defaults.set(style.rawValue, forKey: markerStyleKey)
    }

    func setLogEnabled(_ enabled: Bool) {
        logEnabled = enabled
        defaults.set(enabled, forKey: logEnabledKey)
    }

    // MARK: - 日志目录

    /// 默认目录:沙盒容器内的 Application Support/mcom/logs
    static var defaultLogDirectory: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 设置用户自选目录,保存安全书签以便重启后仍可访问。
    func setLogDirectory(_ url: URL) {
        logDirectory.stopAccessingSecurityScopedResource()
        if let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmark, forKey: logDirectoryBookmarkKey)
        }
        _ = url.startAccessingSecurityScopedResource()
        logDirectory = url
    }

    /// 恢复为默认目录。
    func resetLogDirectory() {
        logDirectory.stopAccessingSecurityScopedResource()
        defaults.removeObject(forKey: logDirectoryBookmarkKey)
        logDirectory = Self.defaultLogDirectory
    }

    private static func resolveBookmark(defaults: UserDefaults, key: String) -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}
