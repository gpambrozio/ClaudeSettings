import Foundation
import Logging

/// Watches for file system changes using FSEvents
public actor FileWatcher {
    private let logger = Logger(label: "com.claudesettings.filewatcher")
    private var eventStream: FSEventStreamRef?
    private var isWatching = false
    private let callback: @Sendable (URL) -> Void
    private var watchTask: Task<Void, Never>?
    private var watchedFilePaths: Set<String> = []

    public init(callback: @escaping @Sendable (URL) -> Void) {
        self.callback = callback
    }

    /// Start watching directories for changes to specific files
    /// - Parameters:
    ///   - directories: Directories to watch for file system events
    ///   - filePaths: Specific file paths to monitor (events for other files will be ignored)
    public func startWatching(directories: [URL], filePaths: [URL]) {
        guard !isWatching else {
            logger.warning("Already watching files")
            return
        }

        // Store the file paths we care about for filtering
        watchedFilePaths = Set(filePaths.map(\.path))

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
    public func stopWatching() {
        guard isWatching, let stream = eventStream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        isWatching = false
        watchTask?.cancel()
        watchTask = nil

        logger.info("File watcher stopped")
    }

    /// Handle file system events
    private func handleEvents(paths: [String], flagsArray: [FSEventStreamEventFlags]) {
        for (index, path) in paths.enumerated() {
            guard index < flagsArray.count else { continue }
            let flag = flagsArray[index]

            // Only process events for files we're watching
            guard watchedFilePaths.contains(path) else { continue }

            // Check if this is a modification, creation, or deletion event
            if
                flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 ||
                flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 ||
                flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                let url = URL(fileURLWithPath: path)
                logger.debug("File changed: \(path)")
                callback(url)
            }
        }
    }

    deinit {
        // Note: Cannot directly access actor-isolated properties from deinit
        // The watchTask cancellation handler will trigger stopWatching() to clean up the FSEventStream
        // Callers should explicitly call stopWatching() before releasing if immediate cleanup is needed
        watchTask?.cancel()
    }
}
