import Foundation
import Logging

/// Manages file system operations with proper error handling and permissions
public actor FileSystemManager {
    private let fileManager = FileManager.default
    private let logger = Logger(label: "com.claudesettings.filesystem")

    public init() { }

    /// Read the contents of a file as Data
    public func readFile(at url: URL) throws -> Data {
        logger.debug("Reading file at: \(url.path)")
        do {
            return try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read file at \(url.path): \(error)")
            throw FileSystemError.readFailed(url: url, underlyingError: error)
        }
    }

    /// Write data to a file, creating intermediate directories if needed
    public func writeFile(data: Data, to url: URL) throws {
        logger.debug("Writing file to: \(url.path)")

        // Create intermediate directories
        let directory = url.deletingLastPathComponent()
        try createDirectory(at: directory)

        do {
            try data.write(to: url, options: .atomic)
            logger.info("Successfully wrote file to: \(url.path)")
        } catch {
            logger.error("Failed to write file to \(url.path): \(error)")
            throw FileSystemError.writeFailed(url: url, underlyingError: error)
        }
    }

    /// Create a directory at the specified URL
    public func createDirectory(at url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            logger.debug("Created directory at: \(url.path)")
        } catch {
            logger.error("Failed to create directory at \(url.path): \(error)")
            throw FileSystemError.directoryCreationFailed(url: url, underlyingError: error)
        }
    }

    /// Check if a file or directory exists at the given URL
    public func exists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    /// Get the modification date of a file
    public func modificationDate(of url: URL) throws -> Date {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let date = attributes[.modificationDate] as? Date else {
                throw FileSystemError.attributeNotFound(url: url, attribute: "modificationDate")
            }
            return date
        } catch {
            throw FileSystemError.attributeReadFailed(url: url, underlyingError: error)
        }
    }

    /// Check if a file is readable
    public func isReadable(at url: URL) -> Bool {
        fileManager.isReadableFile(atPath: url.path)
    }

    /// Check if a file is writable
    public func isWritable(at url: URL) -> Bool {
        fileManager.isWritableFile(atPath: url.path)
    }

    /// List contents of a directory
    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.error("Failed to list directory contents at \(url.path): \(error)")
            throw FileSystemError.directoryListFailed(url: url, underlyingError: error)
        }
    }

    /// Check if a URL points to a directory
    public func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Delete a file or directory
    public func delete(at url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
            logger.info("Deleted item at: \(url.path)")
        } catch {
            logger.error("Failed to delete item at \(url.path): \(error)")
            throw FileSystemError.deleteFailed(url: url, underlyingError: error)
        }
    }

    /// Copy a file from source to destination
    public func copy(from source: URL, to destination: URL) throws {
        do {
            // Create destination directory if needed
            try createDirectory(at: destination.deletingLastPathComponent())
            try fileManager.copyItem(at: source, to: destination)
            logger.info("Copied file from \(source.path) to \(destination.path)")
        } catch {
            logger.error("Failed to copy file: \(error)")
            throw FileSystemError.copyFailed(source: source, destination: destination, underlyingError: error)
        }
    }
}

/// Errors that can occur during file system operations
public enum FileSystemError: LocalizedError {
    case readFailed(url: URL, underlyingError: Error)
    case writeFailed(url: URL, underlyingError: Error)
    case directoryCreationFailed(url: URL, underlyingError: Error)
    case directoryListFailed(url: URL, underlyingError: Error)
    case deleteFailed(url: URL, underlyingError: Error)
    case copyFailed(source: URL, destination: URL, underlyingError: Error)
    case attributeNotFound(url: URL, attribute: String)
    case attributeReadFailed(url: URL, underlyingError: Error)

    public var errorDescription: String? {
        switch self {
        case let .readFailed(url, error):
            return "Failed to read file at \(url.path): \(error.localizedDescription)"
        case let .writeFailed(url, error):
            return "Failed to write file to \(url.path): \(error.localizedDescription)"
        case let .directoryCreationFailed(url, error):
            return "Failed to create directory at \(url.path): \(error.localizedDescription)"
        case let .directoryListFailed(url, error):
            return "Failed to list directory at \(url.path): \(error.localizedDescription)"
        case let .deleteFailed(url, error):
            return "Failed to delete item at \(url.path): \(error.localizedDescription)"
        case let .copyFailed(source, destination, error):
            return "Failed to copy from \(source.path) to \(destination.path): \(error.localizedDescription)"
        case let .attributeNotFound(url, attribute):
            return "Attribute '\(attribute)' not found for file at \(url.path)"
        case let .attributeReadFailed(url, error):
            return "Failed to read attributes of file at \(url.path): \(error.localizedDescription)"
        }
    }
}
