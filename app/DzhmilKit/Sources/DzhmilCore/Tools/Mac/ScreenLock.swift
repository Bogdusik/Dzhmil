import CoreGraphics
import Foundation

enum ScreenLock {
    static let loginFramework = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"

    static func lock() async -> Bool {
        await MainActor.run { requestLock() }
        for _ in 0..<10 {
            if isLocked() { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        _ = await ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"])
        return false
    }

    static func isLocked() -> Bool {
        let info = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (info?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    @MainActor private static func requestLock() {
        guard let handle = dlopen(loginFramework, RTLD_LAZY), let symbol = dlsym(handle, "SACLockScreenImmediate") else { return }
        typealias LockFunction = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: LockFunction.self)()
    }
}
