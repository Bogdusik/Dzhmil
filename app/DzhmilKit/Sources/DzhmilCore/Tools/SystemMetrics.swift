import Darwin
import Foundation
import IOKit.ps

public struct SystemStatus: Sendable {
    public var batteryPercent: Int?
    public var isCharging: Bool
    public var cpuLoadPercent: Int
    public var memoryUsedGB: Double
    public var memoryTotalGB: Double
    public var diskFreeGB: Double
    public var uptime: TimeInterval

    public var summary: String {
        var lines: [String] = []
        if let b = batteryPercent {
            lines.append("Батарея: \(b)%" + (isCharging ? ", заряжается." : ", от батареи."))
        } else {
            lines.append("Батарея: нет, питание от сети.")
        }
        lines.append("Процессор: загружен на \(cpuLoadPercent)%.")
        lines.append(String(format: "Память: занято %.1f из %.0f ГБ.", memoryUsedGB, memoryTotalGB))
        lines.append(String(format: "Диск: свободно %.0f ГБ.", diskFreeGB))
        let days = Int(uptime) / 86400, hours = (Int(uptime) % 86400) / 3600, minutes = (Int(uptime) % 3600) / 60
        lines.append("Без перезагрузки: \(days) дн \(hours) ч \(minutes) мин.")
        return lines.joined(separator: "\n")
    }
}

public enum SystemMetrics {
    public static func current() async -> SystemStatus {
        let (battery, charging) = batteryInfo()
        let cpu = await cpuLoad()
        let (used, total) = memoryInfo()
        return SystemStatus(batteryPercent: battery, isCharging: charging, cpuLoadPercent: cpu,
                            memoryUsedGB: used, memoryTotalGB: total, diskFreeGB: diskFree(),
                            uptime: ProcessInfo.processInfo.systemUptime)
    }

    public static func battery() -> (percent: Int?, charging: Bool) {
        batteryInfo()
    }

    static func batteryInfo() -> (Int?, Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, false) }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = (d[kIOPSIsChargingKey] as? Bool ?? false) || onAC
            return (Int((Double(current) / Double(max) * 100).rounded()), charging)
        }
        return (nil, false)
    }

    static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    static func cpuLoad() async -> Int {
        guard let a = cpuTicks() else { return 0 }
        try? await Task.sleep(for: .milliseconds(500))
        guard let b = cpuTicks(), b.total > a.total else { return 0 }
        let load = Double(b.busy - a.busy) / Double(b.total - a.total) * 100
        return min(100, max(0, Int(load.rounded())))
    }

    static func memoryInfo() -> (Double, Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = Double(sysconf(_SC_PAGESIZE))
        let used = Double(UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page / 1_073_741_824
        return (used, total)
    }

    static func diskFree() -> Double {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Double(values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000
    }
}
