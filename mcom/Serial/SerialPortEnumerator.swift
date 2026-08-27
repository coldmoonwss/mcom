//
//  SerialPortEnumerator.swift
//  mcom
//
//  通过 IOKit 枚举系统中的串口设备(/dev/cu.*)。
//

import Foundation
import IOKit
import IOKit.serial

enum SerialPortEnumerator {
    /// 返回所有可用的 callout 设备路径(如 /dev/cu.usbserial-XXXX)。
    static func availablePorts() -> [String] {
        var ports: [String] = []
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOSerialBSDClient"),
            &iterator
        )
        guard result == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let devicePath = IORegistryEntryCreateCFProperty(
                service,
                kIOCalloutDeviceKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String {
                ports.append(devicePath)
            }
        }

        return ports.sorted()
    }
}
