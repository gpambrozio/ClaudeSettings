import Foundation
import Testing
@testable import ClaudeSettingsFeature

/// Tests for the Debouncer utility
@Suite("Debouncer Tests")
struct DebouncerTests {
    /// Test that debouncer cancels previous operations
    @Test("Debouncer cancels previous operations")
    @MainActor
    func debouncerCancelsPreviousOperations() async throws {
        // Given: A debouncer and a counter
        let debouncer = Debouncer()
        let counter = Counter()

        // When: Multiple rapid debounce calls
        await debouncer.debounce(milliseconds: 100) {
            counter.increment() // Should be cancelled
        }

        await debouncer.debounce(milliseconds: 100) {
            counter.increment() // Should be cancelled
        }

        await debouncer.debounce(milliseconds: 100) {
            counter.increment() // This one should execute
        }

        // Wait for debounce to complete
        try await Task.sleep(for: .milliseconds(150))

        // Then: Only the last operation should execute
        #expect(counter.value == 1, "Only the last debounced operation should execute")
    }

    /// Test that debouncer delays execution
    @Test("Debouncer delays execution")
    @MainActor
    func debouncerDelaysExecution() async throws {
        // Given: A debouncer and a counter
        let debouncer = Debouncer()
        let counter = Counter()

        // When: Debouncing with 100ms delay
        await debouncer.debounce(milliseconds: 100) {
            counter.increment()
        }

        // Immediately check - should not have executed yet
        #expect(counter.value == 0, "Should not execute immediately")

        // Wait for debounce to complete
        try await Task.sleep(for: .milliseconds(150))

        // Then: Should have executed after delay
        #expect(counter.value == 1, "Should execute after delay")
    }

    /// Test that cancel stops pending operations
    @Test("Cancel stops pending operations")
    @MainActor
    func cancelStopsPendingOperations() async throws {
        // Given: A debouncer and a counter
        let debouncer = Debouncer()
        let counter = Counter()

        // When: Debouncing then canceling
        await debouncer.debounce(milliseconds: 100) {
            counter.increment()
        }

        await debouncer.cancel()

        // Wait longer than the debounce delay
        try await Task.sleep(for: .milliseconds(150))

        // Then: Operation should not have executed
        #expect(counter.value == 0, "Cancelled operation should not execute")
    }

    /// Test rapid successive debounce calls
    @Test("Rapid successive debounce calls")
    @MainActor
    func rapidSuccessiveDebounceCalls() async throws {
        // Given: A debouncer and a counter
        let debouncer = Debouncer()
        let counter = Counter()

        // When: 10 rapid debounce calls with longer debounce interval
        // Using 100ms debounce and 2ms between calls ensures calls are well within the debounce window
        for _ in 0..<10 {
            await debouncer.debounce(milliseconds: 100) {
                counter.increment()
            }
            // Very small delay between calls (well within debounce window)
            try await Task.sleep(for: .milliseconds(2))
        }

        // Wait for debounce to complete (100ms debounce + buffer)
        try await Task.sleep(for: .milliseconds(200))

        // Then: Only one operation should execute
        #expect(counter.value == 1, "Only the final operation should execute after rapid calls")
    }
}

/// Helper class for testing concurrent operations
@MainActor
private class Counter {
    var value = 0

    func increment() {
        value += 1
    }
}
