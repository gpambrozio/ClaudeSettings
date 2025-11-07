import Foundation

/// A reusable debouncer for delaying operation execution until a quiet period
///
/// Typical usage:
/// ```swift
/// private let debouncer = Debouncer()
///
/// func onValueChange() {
///     debouncer.debounce(milliseconds: 200) {
///         await self.performExpensiveOperation()
///     }
/// }
/// ```
public actor Debouncer {
    private var task: Task<Void, Never>?

    public init() { }

    /// Debounce an operation by canceling any pending execution and scheduling a new one
    ///
    /// - Parameters:
    ///   - milliseconds: Delay in milliseconds before executing the operation
    ///   - operation: The MainActor-isolated operation to execute after the delay
    public func debounce(milliseconds: Int, operation: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    /// Cancel any pending debounced operation
    public func cancel() {
        task?.cancel()
        task = nil
    }
}
