import Foundation
import Logging

/// Discovers Claude Code projects by scanning the ~/.claude/projects directory
public actor ProjectScanner {
    private let fileSystemManager: FileSystemManager
    private let logger = Logger(label: "com.claudesettings.scanner")

    public init(fileSystemManager: FileSystemManager) {
        self.fileSystemManager = fileSystemManager
    }

    /// Scan for all Claude projects by reading the ~/.claude.json file
    public func scanProjects() async throws -> [ClaudeProject] {
        logger.info("Starting project scan")

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let claudeConfigFile = homeDirectory.appendingPathComponent(".claude.json")

        guard await fileSystemManager.exists(at: claudeConfigFile) else {
            logger.warning("Claude config file not found at \(claudeConfigFile.path)")
            return []
        }

        // Read and parse the JSON file
        let data = try await fileSystemManager.readFile(at: claudeConfigFile)

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let projectsDict = json["projects"] as? [String: Any] else {
            logger.error("Failed to parse projects from \(claudeConfigFile.path)")
            return []
        }

        logger.debug("Found \(projectsDict.count) projects in config")

        var projects: [ClaudeProject] = []

        for (projectPath, _) in projectsDict {
            let projectURL = URL(fileURLWithPath: projectPath)
            if let project = await scanProjectDirectory(projectURL) {
                projects.append(project)
            }
        }

        logger.info("Scan complete. Found \(projects.count) valid projects")
        return projects
    }

    /// Scan a single project directory to extract project information
    private func scanProjectDirectory(_ projectPath: URL) async -> ClaudeProject? {
        logger.debug("Scanning project directory: \(projectPath.lastPathComponent)")

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
        let settingsJSON = SettingsFileType.projectSettings.path(in: projectPath)
        let settingsLocalJSON = SettingsFileType.projectLocal.path(in: projectPath)
        let claudeMd = SettingsFileType.projectMemory.path(in: projectPath)
        let claudeLocalMd = SettingsFileType.projectLocalMemory.path(in: projectPath)

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
}
