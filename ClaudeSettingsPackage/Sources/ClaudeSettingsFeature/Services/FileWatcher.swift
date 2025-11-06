import Foundation
import Logging

/// Watches for file system changes using FSEvents
public actor FileWatcher {
    private let logger = Logger(label: "com.claudesettings.filewatcher")
    private var eventStream: FSEventStreamRef?
    private var isWatching = false
    private let callback: @Sendable (URL) -> Void

    public init(callback: @escaping @Sendable (URL) -> Void) {
        self.callback = callback
    }

    /// Start watching a directory for changes
    public func startWatching(paths: [URL]) {
        guard !isWatching else {
            logger.warning("Already watching files")
            return
        }

        logger.info("Starting file watcher for \(paths.count) paths")

        let pathsToWatch = paths.map { $0.path } as NSArray
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

        logger.info("File watcher stopped")
    }

    /// Handle file system events
    private func handleEvents(paths: [String], flagsArray: [FSEventStreamEventFlags]) {
        for (index, path) in paths.enumerated() {
            guard index < flagsArray.count else { continue }
            let flag = flagsArray[index]

            // Check if this is a modification event
            if
                flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 ||
                flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                let url = URL(fileURLWithPath: path)
                logger.debug("File changed: \(path)")
                callback(url)
            }
        }
    }

    deinit {
        // Note: Cannot access actor-isolated properties from deinit
        // Callers must explicitly call stopWatching() before releasing
        // FSEventStream cleanup requires actor isolation, which deinit doesn't have
    }
}
