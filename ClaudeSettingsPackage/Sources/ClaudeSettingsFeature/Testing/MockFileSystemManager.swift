import Foundation

/// In-memory file system manager for testing
/// Provides a complete mock of the file system without touching real files
public actor MockFileSystemManager: FileSystemManagerProtocol {
    /// In-memory file storage: URL path -> file data
    private var files: [String: Data] = [:]

    /// In-memory directory tracking: stores paths of directories
    private var directories: Set<String> = []

    /// Modification dates for files
    private var modificationDates: [String: Date] = [:]

    /// Read-only files (for testing read-only scenarios)
    private var readOnlyPaths: Set<String> = []

    /// Unreadable files (for testing permission errors)
    private var unreadablePaths: Set<String> = []

    /// Track calls for verification in tests
    public private(set) var readFileCalls: [URL] = []
    public private(set) var writeFileCalls: [(data: Data, url: URL)] = []
    public private(set) var createDirectoryCalls: [URL] = []
    public private(set) var deleteCalls: [URL] = []
    public private(set) var copyCalls: [(source: URL, destination: URL)] = []
    public private(set) var backupCalls: [(url: URL, backupDirectory: URL)] = []

    /// Errors to inject for testing error handling
    private var _errorToThrowOnRead: Error?
    private var _errorToThrowOnWrite: Error?
    private var _errorToThrowOnDelete: Error?
    private var _errorToThrowOnCopy: Error?

    /// Set an error to throw on read operations
    public func setErrorOnRead(_ error: Error?) {
        _errorToThrowOnRead = error
    }

    /// Set an error to throw on write operations
    public func setErrorOnWrite(_ error: Error?) {
        _errorToThrowOnWrite = error
    }

    /// Set an error to throw on delete operations
    public func setErrorOnDelete(_ error: Error?) {
        _errorToThrowOnDelete = error
    }

    /// Set an error to throw on copy operations
    public func setErrorOnCopy(_ error: Error?) {
        _errorToThrowOnCopy = error
    }

    public init() {
        // Initialize with home directory existing
        directories.insert(FileManager.default.homeDirectoryForCurrentUser.path)
    }

    /// Initialize with pre-populated files for testing
    /// - Parameter initialFiles: Dictionary mapping file paths to their contents
    public init(initialFiles: [URL: Data]) {
        directories.insert(FileManager.default.homeDirectoryForCurrentUser.path)
        for (url, data) in initialFiles {
            files[url.path] = data
            modificationDates[url.path] = Date()
            // Ensure parent directories exist (inlined to avoid actor isolation issues in init)
            var currentURL = url.deletingLastPathComponent()
            while currentURL.path != "/" && currentURL.path != "" {
                directories.insert(currentURL.path)
                currentURL = currentURL.deletingLastPathComponent()
            }
            directories.insert("/")
        }
    }

    // MARK: - FileSystemManagerProtocol Implementation

    public func readFile(at url: URL) throws -> Data {
        readFileCalls.append(url)

        if let error = _errorToThrowOnRead {
            throw error
        }

        if unreadablePaths.contains(url.path) {
            throw FileSystemError.readFailed(url: url, underlyingError: NSError(domain: "MockFileSystem", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"]))
        }

        guard let data = files[url.path] else {
            throw FileSystemError.readFailed(url: url, underlyingError: NSError(domain: "MockFileSystem", code: 2, userInfo: [NSLocalizedDescriptionKey: "No such file"]))
        }

        return data
    }

    public func writeFile(data: Data, to url: URL) throws {
        writeFileCalls.append((data: data, url: url))

        if let error = _errorToThrowOnWrite {
            throw error
        }

        if readOnlyPaths.contains(url.path) {
            throw FileSystemError.writeFailed(url: url, underlyingError: NSError(domain: "MockFileSystem", code: 3, userInfo: [NSLocalizedDescriptionKey: "Read-only file"]))
        }

        // Create parent directories
        try createDirectory(at: url.deletingLastPathComponent())

        files[url.path] = data
        modificationDates[url.path] = Date()
    }

    public func createDirectory(at url: URL) throws {
        createDirectoryCalls.append(url)

        // Create all intermediate directories
        var currentPath = ""
        for component in url.pathComponents {
            if component == "/" {
                currentPath = "/"
            } else {
                currentPath = currentPath == "/" ? "/\(component)" : "\(currentPath)/\(component)"
            }
            directories.insert(currentPath)
        }
    }

    public func exists(at url: URL) -> Bool {
        files[url.path] != nil || directories.contains(url.path)
    }

    public func modificationDate(of url: URL) throws -> Date {
        guard let date = modificationDates[url.path] else {
            throw FileSystemError.attributeNotFound(url: url, attribute: "modificationDate")
        }
        return date
    }

    public func isReadable(at url: URL) -> Bool {
        !unreadablePaths.contains(url.path) && files[url.path] != nil
    }

    public func isWritable(at url: URL) -> Bool {
        !readOnlyPaths.contains(url.path)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        guard directories.contains(url.path) else {
            throw FileSystemError.directoryListFailed(url: url, underlyingError: NSError(domain: "MockFileSystem", code: 4, userInfo: [NSLocalizedDescriptionKey: "Not a directory"]))
        }

        let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
        var contents: [URL] = []

        // Find direct children (files)
        for filePath in files.keys where filePath.hasPrefix(prefix) {
            let relativePath = String(filePath.dropFirst(prefix.count))
            if !relativePath.contains("/") {
                contents.append(URL(fileURLWithPath: filePath))
            }
        }

        // Find direct children (directories)
        for dirPath in directories {
            if dirPath.hasPrefix(prefix) && dirPath != url.path {
                let relativePath = String(dirPath.dropFirst(prefix.count))
                if !relativePath.contains("/") && !relativePath.isEmpty {
                    contents.append(URL(fileURLWithPath: dirPath, isDirectory: true))
                }
            }
        }

        return contents
    }

    public func isDirectory(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    public func delete(at url: URL) throws {
        deleteCalls.append(url)

        if let error = _errorToThrowOnDelete {
            throw error
        }

        if files[url.path] != nil {
            files.removeValue(forKey: url.path)
            modificationDates.removeValue(forKey: url.path)
        } else if directories.contains(url.path) {
            // Remove directory and all contents
            let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
            files = files.filter { !$0.key.hasPrefix(prefix) }
            modificationDates = modificationDates.filter { !$0.key.hasPrefix(prefix) }
            directories = directories.filter { !$0.hasPrefix(prefix) && $0 != url.path }
        } else {
            throw FileSystemError.deleteFailed(url: url, underlyingError: NSError(domain: "MockFileSystem", code: 5, userInfo: [NSLocalizedDescriptionKey: "No such file or directory"]))
        }
    }

    public func copy(from source: URL, to destination: URL) throws {
        copyCalls.append((source: source, destination: destination))

        if let error = _errorToThrowOnCopy {
            throw error
        }

        guard let data = files[source.path] else {
            throw FileSystemError.copyFailed(source: source, destination: destination, underlyingError: NSError(domain: "MockFileSystem", code: 6, userInfo: [NSLocalizedDescriptionKey: "Source file not found"]))
        }

        // Create destination directory
        try createDirectory(at: destination.deletingLastPathComponent())

        files[destination.path] = data
        modificationDates[destination.path] = Date()
    }

    public func createBackup(of url: URL, to backupDirectory: URL) throws -> URL {
        backupCalls.append((url: url, backupDirectory: backupDirectory))

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = url.lastPathComponent
        let backupFilename = "\(timestamp)-\(filename)"
        let backupURL = backupDirectory.appendingPathComponent(backupFilename)

        try copy(from: url, to: backupURL)

        return backupURL
    }

    // MARK: - Test Setup Helpers

    /// Add a file to the mock file system
    public func addFile(at url: URL, content: Data, modificationDate: Date = Date()) {
        files[url.path] = content
        modificationDates[url.path] = modificationDate
        ensureParentDirectoriesExist(for: url)
    }

    /// Add a file with string content
    public func addFile(at url: URL, content: String, modificationDate: Date = Date()) {
        addFile(at: url, content: content.data(using: .utf8) ?? Data(), modificationDate: modificationDate)
    }

    /// Add a JSON file
    public func addJSONFile(at url: URL, content: [String: Any], modificationDate: Date = Date()) throws {
        let data = try JSONSerialization.data(withJSONObject: content, options: .prettyPrinted)
        addFile(at: url, content: data, modificationDate: modificationDate)
    }

    /// Mark a file as read-only
    public func setReadOnly(at url: URL) {
        readOnlyPaths.insert(url.path)
    }

    /// Mark a file as unreadable
    public func setUnreadable(at url: URL) {
        unreadablePaths.insert(url.path)
    }

    /// Create a directory
    public func addDirectory(at url: URL) {
        directories.insert(url.path)
    }

    /// Get all files in the mock file system (for verification)
    public func getAllFiles() -> [String: Data] {
        files
    }

    /// Get file content as string (for verification)
    public func getFileContent(at url: URL) -> String? {
        guard let data = files[url.path] else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Get raw file data (for verification)
    /// Returns Data which is Sendable and can safely cross actor boundaries
    public func getFileData(at url: URL) -> Data? {
        files[url.path]
    }

    /// Reset all tracking data
    public func resetTracking() {
        readFileCalls.removeAll()
        writeFileCalls.removeAll()
        createDirectoryCalls.removeAll()
        deleteCalls.removeAll()
        copyCalls.removeAll()
        backupCalls.removeAll()
    }

    /// Reset the entire mock file system
    public func reset() {
        files.removeAll()
        directories.removeAll()
        modificationDates.removeAll()
        readOnlyPaths.removeAll()
        unreadablePaths.removeAll()
        resetTracking()
        _errorToThrowOnRead = nil
        _errorToThrowOnWrite = nil
        _errorToThrowOnDelete = nil
        _errorToThrowOnCopy = nil
        directories.insert(FileManager.default.homeDirectoryForCurrentUser.path)
    }

    // MARK: - Private Helpers

    private func ensureParentDirectoriesExist(for url: URL) {
        var currentURL = url.deletingLastPathComponent()
        while currentURL.path != "/" && currentURL.path != "" {
            directories.insert(currentURL.path)
            currentURL = currentURL.deletingLastPathComponent()
        }
        directories.insert("/")
    }
}
