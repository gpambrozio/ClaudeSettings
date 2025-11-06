import Foundation
import Logging

/// Discovers Claude Code projects by scanning the ~/.claude/projects directory
public actor ProjectScanner {
    private let fileSystemManager: FileSystemManager
    private let logger = Logger(label: "com.claudesettings.scanner")

    public init(fileSystemManager: FileSystemManager) {
        self.fileSystemManager = fileSystemManager
    }

    /// Scan for all Claude projects by reading the ~/.claude/projects directory
    public func scanProjects() async throws -> [ClaudeProject] {
        logger.info("Starting project scan")

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let claudeProjectsDir = homeDirectory.appendingPathComponent(".claude/projects")

        guard await fileSystemManager.exists(at: claudeProjectsDir) else {
            logger.warning("Claude projects directory not found at \(claudeProjectsDir.path)")
            return []
        }

        // Get all subdirectories in ~/.claude/projects
        let projectDirs = try await fileSystemManager.contentsOfDirectory(at: claudeProjectsDir)
            .filter { url in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }

        logger.debug("Found \(projectDirs.count) project directories")

        var projects: [ClaudeProject] = []

        for projectDir in projectDirs {
            if let project = await scanProjectDirectory(projectDir) {
                projects.append(project)
            }
        }

        logger.info("Scan complete. Found \(projects.count) valid projects")
        return projects
    }

    /// Scan a single project directory to extract project information
    private func scanProjectDirectory(_ projectDir: URL) async -> ClaudeProject? {
        logger.debug("Scanning project directory: \(projectDir.lastPathComponent)")

        // Find the first JSONL file and extract the cwd
        guard let projectPath = await extractProjectPath(from: projectDir) else {
            logger.warning("Could not find valid project path in \(projectDir.lastPathComponent)")
            return nil
        }

        // Check if the project directory still exists
        guard await fileSystemManager.exists(at: projectPath) else {
            logger.warning("Project path no longer exists: \(projectPath.path)")
            return nil
        }

        // Check for .claude directory
        let claudeDir = projectPath.appendingPathComponent(".claude")
        guard await fileSystemManager.exists(at: claudeDir) else {
            logger.warning("No .claude directory found at \(projectPath.path)")
            return nil
        }

        // Determine what settings files exist
        let settingsJSON = claudeDir.appendingPathComponent("settings.json")
        let settingsLocalJSON = claudeDir.appendingPathComponent("settings.local.json")
        let claudeMd = projectPath.appendingPathComponent("CLAUDE.md")
        let claudeLocalMd = projectPath.appendingPathComponent("CLAUDE.local.md")

        let hasSharedSettings = await fileSystemManager.exists(at: settingsJSON)
        let hasLocalSettings = await fileSystemManager.exists(at: settingsLocalJSON)
        let hasClaudeMd = await fileSystemManager.exists(at: claudeMd)
        let hasLocalClaudeMd = await fileSystemManager.exists(at: claudeLocalMd)

        // Get last modified date
        var lastModified = Date()
        if hasLocalSettings, let date = try? await fileSystemManager.modificationDate(of: settingsLocalJSON) {
            lastModified = date
        } else if hasSharedSettings, let date = try? await fileSystemManager.modificationDate(of: settingsJSON) {
            lastModified = date
        }

        let projectName = projectPath.lastPathComponent

        return ClaudeProject(
            name: projectName,
            path: projectPath,
            claudeDirectory: claudeDir,
            hasLocalSettings: hasLocalSettings,
            hasSharedSettings: hasSharedSettings,
            hasClaudeMd: hasClaudeMd,
            hasLocalClaudeMd: hasLocalClaudeMd,
            lastModified: lastModified
        )
    }

    /// Extract the actual project path from a project directory's JSONL files
    private func extractProjectPath(from projectDir: URL) async -> URL? {
        do {
            let files = try await fileSystemManager.contentsOfDirectory(at: projectDir)
            let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }

            // Try each JSONL file until we find one with a cwd
            for jsonlFile in jsonlFiles {
                if let cwd = await extractCWD(from: jsonlFile) {
                    logger.debug("Found cwd in \(jsonlFile.lastPathComponent): \(cwd)")
                    return URL(fileURLWithPath: cwd)
                }
            }
        } catch {
            logger.error("Failed to read project directory \(projectDir.path): \(error)")
        }

        return nil
    }

    /// Extract the cwd field from a JSONL file
    private func extractCWD(from jsonlFile: URL) async -> String? {
        do {
            let data = try await fileSystemManager.readFile(at: jsonlFile)
            let content = String(data: data, encoding: .utf8) ?? ""

            // Parse each line as JSON
            for line in content.components(separatedBy: .newlines) {
                guard !line.isEmpty else { continue }

                if
                    let jsonData = line.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                    let cwd = json["cwd"] as? String {
                    return cwd
                }
            }
        } catch {
            logger.debug("Failed to parse JSONL file \(jsonlFile.lastPathComponent): \(error)")
        }

        return nil
    }
}
