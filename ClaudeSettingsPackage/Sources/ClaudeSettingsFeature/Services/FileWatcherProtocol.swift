import Foundation

/// Protocol for file system change monitoring
/// Abstracts file watching implementation to allow for testing and alternative implementations
public protocol FileWatcherProtocol: Actor {
    /// AsyncStream of file change events
    /// Each URL represents a file that was created, modified, or deleted
    var fileChanges: AsyncStream<URL> { get }

    /// Update the paths being watched without recreating the underlying watcher
    /// - Parameters:
    ///   - directories: Directories to watch for file system events
    ///   - filePaths: Specific file paths to monitor (events for other files will be ignored)
    func updateWatchedPaths(directories: [URL], filePaths: [URL]) async

    /// Stop watching for file changes and clean up resources
    func stopWatching() async
}
