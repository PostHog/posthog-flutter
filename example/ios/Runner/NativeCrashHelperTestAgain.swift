import Foundation

/// Helper class to trigger a native crash for testing error tracking.
/// Having a dedicated class and method produces a clearer stack trace
/// for verifying symbolication works correctly.
class NativeCrashHelperTestAgain {
    @inline(never) func triggerCrashTestAgain() {
        let array: [Int] = []
        _ = array[99]
    }
}
