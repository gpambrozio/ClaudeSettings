import Foundation
import Logging

/// Watches for file system changes using FSEvents
public actor FileWatcher: FileWatcherProtocol {
    private let logger = Logger(label: "com.claudesettings.filewatcher")
    private var eventStream: FSEventStreamRef?
    private var isWatching = false
    private var watchTask: Task<Void, Never>?
    private var watchedFilePaths: Set<String> = []

    // AsyncStream for publishing file change events
    public let fileChanges: AsyncStream<URL>
    private let continuation: AsyncStream<URL>.Continuation

    public init() {
        // Create the AsyncStream and store the continuation for yielding values
        let (stream, continuation) = AsyncStream<URL>.makeStream()
        self.fileChanges = stream
        self.continuation = continuation
    }

    /// Update the paths being watched without recreating the underlying watcher
    /// - Parameters:
    ///   - directories: Directories to watch for file system events
    ///   - filePaths: Specific file paths to monitor (events for other files will be ignored)
    public func updateWatchedPaths(directories: [URL], filePaths: [URL]) async {
        // Store the file paths we care about for filtering
        watchedFilePaths = Set(filePaths.map(\.path))

        // If already watching, stop the current watcher before starting a new one
        if isWatching {
            await stopWatching()
        }

        logger.info("Starting file watcher for \(directories.count) directories watching \(filePaths.count) files")

        let pathsToWatch = directories.map(\.path) as NSArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let eventCallback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, eventFlags, _ in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()

            // Safely cast eventPaths to string array
            let pathsArray = unsafeBitCast(eventPaths, to: NSArray.self)
            guard let paths = pathsArray as? [String] else { return }

            // Copy values to avoid data races
            let count = numEvents
            let pathsCopy = paths
            let flagsBuffer = UnsafeBufferPointer(start: eventFlags, count: count)
            let flagsArray = Array(flagsBuffer)

            Task {
                await watcher.handleEvents(paths: pathsCopy, flagsArray: flagsArray)
            }
        }

        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            eventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1, // Latency in seconds
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream = eventStream else {
            logger.error("Failed to create FSEventStream")
            return
        }

        let queue = DispatchQueue(label: "com.claudesettings.filewatcher", qos: .background)
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        isWatching = true

        // Create a task with cancellation handler to ensure cleanup
        watchTask = Task {
            await withTaskCancellationHandler {
                // Keep the task alive while watching
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                }
            } onCancel: {
                Task {
                    await self.stopWatching()
                }
            }
        }

        logger.info("File watcher started")
    }

    /// Stop watching for file changes
    public func stopWatching() async {
        guard isWatching, let stream = eventStream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        isWatching = false
        watchTask?.cancel()
        // Wait for it to finish cancelling as cancellation call `stopWatching` again
        // and it needs to happen before we proceed with a possible `updateWatchedPaths`
        _ = await watchTask?.result
        watchTask = nil

        logger.info("File watcher stopped")
    }

    /// Handle file system events
    private func handleEvents(paths: [String], flagsArray: [FSEventStreamEventFlags]) {
        for (index, path) in paths.enumerated() {
            guard index < flagsArray.count else { continue }
            let flag = flagsArray[index]

            // For deletion events, FSEvents might report the parent directory instead of the file
            // So we need to check if the path matches exactly OR if it's a directory containing watched files
            let isWatchedFile = watchedFilePaths.contains(path)
            let isWatchedDirectory = watchedFilePaths.contains { watchedPath in
                watchedPath.hasPrefix(path + "/")
            }

            guard isWatchedFile || isWatchedDirectory else {
                continue
            }

            // Check if this is a modification, creation, or deletion event
            if
                flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 ||
                flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 ||
                flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {

                // If event is on a directory, notify about all watched files in that directory
                if isWatchedDirectory && !isWatchedFile {
                    logger.debug("Directory changed: \(path), checking watched files")
                    for watchedPath in watchedFilePaths where watchedPath.hasPrefix(path + "/") {
                        let url = URL(fileURLWithPath: watchedPath)
                        logger.debug("File potentially changed: \(watchedPath)")
                        continuation.yield(url)
                    }
                } else {
                    let url = URL(fileURLWithPath: path)
                    logger.debug("File changed: \(path)")
                    continuation.yield(url)
                }
            }
        }
    }

    deinit {
        // Note: Cannot directly access actor-isolated properties from deinit
        // The watchTask cancellation handler will trigger stopWatching() to clean up the FSEventStream
        // Callers should explicitly call stopWatching() before releasing if immediate cleanup is needed
        watchTask?.cancel()
        continuation.finish()
    }
}
