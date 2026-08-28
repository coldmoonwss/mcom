//
//  SerialManager.swift
//  mcom
//
//  串口状态中心:开关串口、收发数据、选项开关、日志与字节统计。
//

import Foundation

/// 一条日志:带时间戳与收发方向。
struct LogEntry: Identifiable {
    enum Direction {
        case rx, tx
    }

    let id = UUID()
    let timestamp: Date
    let direction: Direction
    var text: String
}

@Observable
@MainActor
final class SerialManager {
    // MARK: - 端口与参数
    var availablePorts: [String] = []
    private(set) var selectedPort: String
    private(set) var selectedBaud: Int
    private(set) var isOpen = false

    // MARK: - 统计
    private(set) var txBytes = 0
    private(set) var rxBytes = 0

    // MARK: - 选项(全部持久化)
    private(set) var rtsEnabled: Bool
    private(set) var dtrEnabled: Bool
    private(set) var hexDisplay: Bool
    private(set) var hexSend: Bool
    private(set) var appendCRLF: Bool
    private(set) var replaceInvisible: Bool
    private(set) var paused: Bool

    // MARK: - 日志
    private(set) var entries: [LogEntry] = []
    private let maxEntries = 5000

    // MARK: - 错误提示
    var errorMessage: String?

    let baudRates = SerialPort.standardBaudRates
    private let port = SerialPort()
    private let settings: AppSettings
    private let defaults = UserDefaults.standard

    // 持久化 key
    private enum Key {
        static let port = "serial.port"
        static let baud = "serial.baud"
        static let rts = "serial.rts"
        static let dtr = "serial.dtr"
        static let hexDisplay = "serial.hexDisplay"
        static let hexSend = "serial.hexSend"
        static let appendCRLF = "serial.appendCRLF"
        static let replaceInvisible = "serial.replaceInvisible"
        static let paused = "serial.paused"
    }

    // 日志文件状态
    private var logFileHandle: FileHandle?
    private var logFileKey: String = "" // "目录|日期",变化时重开文件

    private static let logDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    init(settings: AppSettings) {
        self.settings = settings
        // 恢复上次的选项(注意区分"未设置过"和"设置为 false")
        rtsEnabled = defaults.bool(forKey: Key.rts)
        dtrEnabled = defaults.bool(forKey: Key.dtr)
        hexDisplay = defaults.bool(forKey: Key.hexDisplay)
        hexSend = defaults.bool(forKey: Key.hexSend)
        appendCRLF = defaults.object(forKey: Key.appendCRLF) as? Bool ?? true
        replaceInvisible = defaults.object(forKey: Key.replaceInvisible) as? Bool ?? true
        paused = defaults.bool(forKey: Key.paused)
        selectedBaud = defaults.object(forKey: Key.baud) as? Int ?? 115_200
        selectedPort = defaults.string(forKey: Key.port) ?? ""
        refreshPorts()
    }

    // MARK: - 选项变更(即时持久化)

    func setHexDisplay(_ value: Bool) { hexDisplay = value; defaults.set(value, forKey: Key.hexDisplay) }
    func setHexSend(_ value: Bool) { hexSend = value; defaults.set(value, forKey: Key.hexSend) }
    func setAppendCRLF(_ value: Bool) { appendCRLF = value; defaults.set(value, forKey: Key.appendCRLF) }
    func setReplaceInvisible(_ value: Bool) { replaceInvisible = value; defaults.set(value, forKey: Key.replaceInvisible) }
    func setPaused(_ value: Bool) { paused = value; defaults.set(value, forKey: Key.paused) }
    func setSelectedBaud(_ value: Int) { selectedBaud = value; defaults.set(value, forKey: Key.baud) }
    func setSelectedPort(_ value: String) { selectedPort = value; defaults.set(value, forKey: Key.port) }

    // MARK: - 端口管理

    func refreshPorts() {
        availablePorts = SerialPortEnumerator.availablePorts()
        if !availablePorts.contains(selectedPort) {
            selectedPort = availablePorts.first ?? ""
        }
    }

    func toggleConnection() {
        isOpen ? closePort() : openPort()
    }

    private func openPort() {
        guard !selectedPort.isEmpty else {
            errorMessage = "请先选择串口"
            return
        }
        do {
            try port.open(path: selectedPort, baudRate: selectedBaud) { [weak self] data in
                Task { @MainActor in self?.handleReceive(data) }
            }
            isOpen = true
            port.setRTS(rtsEnabled)
            port.setDTR(dtrEnabled)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func closePort() {
        port.close()
        isOpen = false
    }

    /// 串口被外部断开(如 USB 拔出)时同步 UI 状态。
    func syncOpenState() {
        if !port.isOpen { isOpen = false }
    }

    // MARK: - RTS / DTR

    func setRTS(_ enabled: Bool) {
        rtsEnabled = enabled
        defaults.set(enabled, forKey: Key.rts)
        port.setRTS(enabled)
    }

    func setDTR(_ enabled: Bool) {
        dtrEnabled = enabled
        defaults.set(enabled, forKey: Key.dtr)
        port.setDTR(enabled)
    }

    // MARK: - 发送

    func send(_ input: String) {
        guard isOpen else {
            errorMessage = "串口未打开,无法发送"
            return
        }
        var data: Data
        if hexSend {
            switch Self.parseHex(input) {
            case .success(let parsed):
                data = parsed
            case .failure(let error):
                errorMessage = error.localizedDescription
                return
            }
        } else {
            data = Data(input.utf8)
            if appendCRLF {
                data.append(contentsOf: [0x0D, 0x0A])
            }
        }
        guard !data.isEmpty else { return }
        let entry = LogEntry(timestamp: Date(), direction: .tx, text: formatForLog(data))
        appendEntry(entry)
        writeLogToFile(entry)
        txBytes += data.count
        port.writeAsync(data) { [weak self] result in
            if case .failure(let error) = result {
                Task { @MainActor in self?.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - 接收

    private func handleReceive(_ data: Data) {
        rxBytes += data.count
        syncOpenState()
        let text = formatForLog(data)
        writeLogToFile(LogEntry(timestamp: Date(), direction: .rx, text: text)) // 停止打印只影响显示,文件照常记录
        guard !paused else { return }
        appendRX(text)
    }

    // MARK: - 日志

    func clearLog() {
        entries.removeAll()
        txBytes = 0
        rxBytes = 0
    }

    private func appendEntry(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    /// 接收数据并入日志:串口数据是分包到达的,同方向的连续数据合并到同一条,
    /// 避免包边界显示成莫名换行;遇到发送记录或清空后重新开始一条。
    private func appendRX(_ text: String) {
        if let last = entries.last, last.direction == .rx {
            entries[entries.count - 1].text += text
        } else {
            appendEntry(LogEntry(timestamp: Date(), direction: .rx, text: text))
        }
    }

    /// 追加写入日志文件(mcom-yyyyMMdd.log),目录或日期变化时自动重开。
    private func writeLogToFile(_ entry: LogEntry) {
        guard settings.logEnabled else { return }
        let day = Self.logDayFormatter.string(from: entry.timestamp)
        let key = "\(settings.logDirectory.path)|\(day)"
        if key != logFileKey {
            logFileHandle?.closeFile()
            logFileHandle = nil
            let url = settings.logDirectory.appendingPathComponent("mcom-\(day).log")
            try? FileManager.default.createDirectory(
                at: settings.logDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            logFileHandle = try? FileHandle(forWritingTo: url)
            logFileHandle?.seekToEndOfFile()
            logFileKey = key
        }
        let timestamp = AppSettings.dateTimeFormatter.string(from: entry.timestamp)
        let tag = entry.direction == .tx ? "TX" : "RX"
        let line = "[\(timestamp)] [\(tag)] \(entry.text)\n"
        if let data = line.data(using: .utf8) {
            logFileHandle?.write(data)
        }
    }

    private func formatForLog(_ data: Data) -> String {
        if hexDisplay {
            return data.map { String(format: "%02X ", $0) }.joined()
        }
        if replaceInvisible {
            // 规则:\r\n 连在一起算一次换行(显示 ␍␊),单独的 \r 或 \n 各换一次行,
            // \t 显示 ␉,其余不可见字符显示 \xNN
            var result = ""
            result.reserveCapacity(data.count * 2)
            var i = data.startIndex
            while i < data.endIndex {
                let byte = data[i]
                switch byte {
                case 0x0D:
                    let next = data.index(after: i)
                    if next < data.endIndex, data[next] == 0x0A {
                        result += "␍␊\n"
                        i = data.index(after: next)
                    } else {
                        result += "␍\n"
                        i = next
                    }
                case 0x0A:
                    result += "␊\n"
                    i = data.index(after: i)
                case 0x09:
                    result += "␉\t"
                    i = data.index(after: i)
                case 0x20...0x7E:
                    result.append(UnicodeScalar(byte).description)
                    i = data.index(after: i)
                default:
                    result += String(format: "\\x%02X", byte)
                    i = data.index(after: i)
                }
            }
            return result
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - HEX 解析

    enum HexParseError: LocalizedError {
        case invalidCharacter(String)
        case oddLength

        var errorDescription: String? {
            switch self {
            case .invalidCharacter(let s):
                return "HEX 内容包含非法字符:\"\(s)\",仅支持 0-9 A-F、空格、逗号、0x 前缀"
            case .oddLength:
                return "HEX 字节数不正确:十六进制字符数量必须为偶数"
            }
        }
    }

    /// 支持 "41 54 0D 0A"、"41540D0A"、"0x41,0x54" 等写法。
    nonisolated static func parseHex(_ input: String) -> Result<Data, HexParseError> {
        let cleaned = input
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard !cleaned.isEmpty else { return .success(Data()) }
        let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard cleaned.unicodeScalars.allSatisfy({ hexSet.contains($0) }) else {
            let bad = String(cleaned.unicodeScalars.filter { !hexSet.contains($0) })
            return .failure(.invalidCharacter(bad))
        }
        guard cleaned.count % 2 == 0 else { return .failure(.oddLength) }

        var data = Data()
        data.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            if let byte = UInt8(cleaned[index..<next], radix: 16) {
                data.append(byte)
            }
            index = next
        }
        return .success(data)
    }
}
