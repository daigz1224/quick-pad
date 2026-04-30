import Foundation

/// Shared serial queue for `~/.quickpad/stream.md` reads and writes.
/// One queue keeps every read-modify-write atomic across both
/// `StreamWriter` and `StreamMutator`; off-main keeps the popover
/// responsive when Spotlight or TimeMachine spikes write latency.
enum StreamFileIO {

    /// Serial, user-initiated. Always go through `perform` — never
    /// `queue.sync` from main, that's a deadlock recipe.
    static let queue = DispatchQueue(
        label: "dev.quickpad.stream-io",
        qos: .userInitiated
    )

    /// Cancellation is intentionally not honored once `work` is running:
    /// a partial atomic-write rollback is more risk than benefit at this
    /// op size.
    static func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
