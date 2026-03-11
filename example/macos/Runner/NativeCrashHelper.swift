import Foundation

/// Helper class to trigger a native crash for testing error tracking.
/// Having a dedicated class and method produces a clearer stack trace
/// for verifying symbolication works correctly.
class NativeCrashHelper {
    func triggerCrash() {
        let array: [Int] = []
        _ = array[99]
    }
}
