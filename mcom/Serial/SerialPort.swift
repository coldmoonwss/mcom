//
//  SerialPort.swift
//  mcom
//
//  POSIX termios 串口封装:打开/配置/读写/关闭,RTS/DTR 控制。
//

import Foundation

enum SerialError: LocalizedError {
    case openFailed(path: String, errno: Int32)
    case configureFailed(errno: Int32)
    case notOpen
    case writeFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let code):
            return "无法打开串口 \(path):\(String(cString: strerror(code)))"
        case .configureFailed(let code):
            return "配置串口参数失败:\(String(cString: strerror(code)))"
        case .notOpen:
            return "串口未打开"
        case .writeFailed(let code):
            return "写入串口失败:\(String(cString: strerror(code)))"
        }
    }
}

final class SerialPort: @unchecked Sendable {
    // sys/ttycom.h 中的 ioctl 常量(宏未导入 Swift,手工展开)
    private static let TIOCMGET: UInt = 0x4004_746B   // _IOR('t', 107, int)
    private static let TIOCMSET: UInt = 0x8004_746D   // _IOW('t', 109, int)
    private static let TIOCM_RTS: Int32 = 0x004
    private static let TIOCM_DTR: Int32 = 0x002
    private static let IOSSIOSPEED: UInt = 0x8008_5402 // _IOW('T', 2, speed_t)

    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let writeQueue = DispatchQueue(label: "mcom.serial.write")

    /// 收到数据时的回调,在后台队列触发,调用方需自行切线程。
    var onReceive: ((Data) -> Void)?

    private(set) var isOpen = false
    private(set) var path = ""

    /// 常用波特率列表
    static let standardBaudRates = [
        300, 1200, 2400, 4800, 9600, 19200, 38400, 57600,
        115200, 230400, 460800, 576000, 921600, 1_000_000, 1_500_000, 2_000_000,
    ]

    /// 打开并配置串口:8N1、无流控、raw 模式。
    func open(path: String, baudRate: Int, onReceive: @escaping (Data) -> Void) throws {
        close()

        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw SerialError.openFailed(path: path, errno: errno) }

        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw SerialError.configureFailed(errno: code)
        }

        cfmakeraw(&options)
        // 8 数据位、无校验、1 停止位、无硬件流控
        options.c_cflag = tcflag_t(CLOCAL | CREAD | CS8)
        options.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        // 全部清掉输入/输出/本地处理
        options.c_iflag = 0
        options.c_oflag = 0
        options.c_lflag = 0
        // 非阻塞读:立即返回
        withUnsafeMutableBytes(of: &options.c_cc) { ptr in
            ptr[Int(VMIN)] = 0
            ptr[Int(VTIME)] = 1
        }

        // 标准波特率用 cfsetspeed(Darwin 上 B 常量数值等于波特率)
        cfsetispeed(&options, speed_t(baudRate))
        cfsetospeed(&options, speed_t(baudRate))

        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw SerialError.configureFailed(errno: code)
        }

        // 非标准波特率回退到 IOSSIOSPEED
        if !Self.standardBaudRates.contains(baudRate) {
            var speed = speed_t(baudRate)
            _ = ioctl(fd, Self.IOSSIOSPEED, &speed)
        }

        // 配置完成后清掉 O_NONBLOCK 写标志,读由 DispatchSource 驱动
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)

        self.fileDescriptor = fd
        self.path = path
        self.isOpen = true
        self.onReceive = onReceive

        let source = DispatchSource.makeReadSource(fileDescriptor: fd,
                                                   queue: DispatchQueue.global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(self.fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                self.onReceive?(Data(buffer[0..<count]))
            } else if count == 0 {
                // 对端断开(如 USB 拔出)
                DispatchQueue.main.async { self.close() }
            }
        }
        source.setCancelHandler { [fd] in
            Darwin.close(fd)
        }
        source.resume()
        readSource = source
    }

    func write(_ data: Data) throws {
        guard isOpen, fileDescriptor >= 0 else { throw SerialError.notOpen }
        try data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            guard let base = ptr.baseAddress, !data.isEmpty else { return }
            var sent = 0
            while sent < data.count {
                let n = Darwin.write(fileDescriptor, base + sent, data.count - sent)
                if n < 0 {
                    if errno == EAGAIN || errno == EINTR { continue }
                    throw SerialError.writeFailed(errno: errno)
                }
                sent += n
            }
        }
    }

    /// 异步写入,避免阻塞 UI。
    func writeAsync(_ data: Data, completion: ((Result<Int, Error>) -> Void)? = nil) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.write(data)
                completion?(.success(data.count))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    func setRTS(_ enabled: Bool) {
        setModemBit(Self.TIOCM_RTS, enabled: enabled)
    }

    func setDTR(_ enabled: Bool) {
        setModemBit(Self.TIOCM_DTR, enabled: enabled)
    }

    private func setModemBit(_ bit: Int32, enabled: Bool) {
        guard isOpen, fileDescriptor >= 0 else { return }
        var status: Int32 = 0
        guard ioctl(fileDescriptor, Self.TIOCMGET, &status) == 0 else { return }
        if enabled { status |= bit } else { status &= ~bit }
        _ = ioctl(fileDescriptor, Self.TIOCMSET, &status)
    }

    func close() {
        readSource?.cancel()
        readSource = nil
        fileDescriptor = -1
        isOpen = false
    }

    deinit { close() }
}
