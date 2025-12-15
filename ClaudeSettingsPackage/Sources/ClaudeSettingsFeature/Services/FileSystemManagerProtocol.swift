import Foundation

/// Protocol for file system operations
/// Abstracts file system access to allow for testing and alternative implementations
public protocol FileSystemManagerProtocol: Actor, Sendable {
    /// Read the contents of a file as Data
    func readFile(at url: URL) throws -> Data

    /// Write data to a file, creating intermediate directories if needed
    func writeFile(data: Data, to url: URL) throws

    /// Create a directory at the specified URL
    func createDirectory(at url: URL) throws

    /// Check if a file or directory exists at the given URL
    func exists(at url: URL) -> Bool

    /// Get the modification date of a file
    func modificationDate(of url: URL) throws -> Date

    /// Check if a file is readable
    func isReadable(at url: URL) -> Bool

    /// Check if a file is writable
    func isWritable(at url: URL) -> Bool

    /// List contents of a directory
    func contentsOfDirectory(at url: URL) throws -> [URL]

    /// Delete a file or directory
    func delete(at url: URL) throws

    /// Copy a file from source to destination
    func copy(from source: URL, to destination: URL) throws

    /// Create a backup of a file
    /// - Parameters:
    ///   - url: The file to backup
    ///   - backupDirectory: The directory to store the backup in
    /// - Returns: The URL of the created backup file
    func createBackup(of url: URL, to backupDirectory: URL) throws -> URL
}

/// Default backup directory for settings backups
public enum FileSystemDefaults {
    public static var defaultBackupDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeSettings/Backups")
    }
}

// MARK: - FileSystemManager Protocol Conformance

extension FileSystemManager: FileSystemManagerProtocol {
    /// Create a backup with the default backup directory
    public func createBackup(of url: URL, to backupDirectory: URL) throws -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = url.lastPathComponent
        let backupFilename = "\(timestamp)-\(filename)"
        let backupURL = backupDirectory.appendingPathComponent(backupFilename)

        try copy(from: url, to: backupURL)

        return backupURL
    }
}
