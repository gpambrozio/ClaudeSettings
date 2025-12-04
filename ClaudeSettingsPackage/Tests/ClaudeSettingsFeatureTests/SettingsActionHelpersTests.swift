import Foundation
import Testing
@testable import ClaudeSettingsFeature

@Suite("SettingsActionHelpers Tests")
struct SettingsActionHelpersTests {
    // MARK: - sourceColor Tests

    @Test("sourceColor returns purple for enterprise managed")
    func sourceColorEnterpriseManaged() {
        let color = SettingsActionHelpers.sourceColor(for: .enterpriseManaged)
        #expect(color == .purple)
    }

    @Test("sourceColor returns blue for global settings")
    func sourceColorGlobalSettings() {
        let colors = [
            SettingsActionHelpers.sourceColor(for: .globalSettings),
            SettingsActionHelpers.sourceColor(for: .globalLocal),
            SettingsActionHelpers.sourceColor(for: .globalMemory),
        ]
        for color in colors {
            #expect(color == .blue)
        }
    }

    @Test("sourceColor returns green for project settings")
    func sourceColorProjectSettings() {
        let colors = [
            SettingsActionHelpers.sourceColor(for: .projectSettings),
            SettingsActionHelpers.sourceColor(for: .projectLocal),
            SettingsActionHelpers.sourceColor(for: .projectMemory),
            SettingsActionHelpers.sourceColor(for: .projectLocalMemory),
        ]
        for color in colors {
            #expect(color == .green)
        }
    }

    // MARK: - sourceLabel Tests

    @Test("sourceLabel returns correct labels for each file type")
    func sourceLabels() {
        #expect(SettingsActionHelpers.sourceLabel(for: .globalSettings) == "Global Settings")
        #expect(SettingsActionHelpers.sourceLabel(for: .globalLocal) == "Global Local")
        #expect(SettingsActionHelpers.sourceLabel(for: .projectSettings) == "Project Settings")
        #expect(SettingsActionHelpers.sourceLabel(for: .projectLocal) == "Project Local")
        #expect(SettingsActionHelpers.sourceLabel(for: .enterpriseManaged) == "Enterprise Managed")
    }

    @Test("sourceLabel returns Memory File for all memory types")
    func sourceLabelMemoryTypes() {
        let memoryTypes: [SettingsFileType] = [
            .globalMemory,
            .projectMemory,
            .projectLocalMemory,
        ]
        for fileType in memoryTypes {
            #expect(SettingsActionHelpers.sourceLabel(for: fileType) == "Memory File")
        }
    }

    // MARK: - availableFileTypes Tests

    @MainActor
    @Test("availableFileTypes returns global files when no project exists")
    func availableFileTypesNoProject() {
        let viewModel = SettingsViewModel(project: nil)
        viewModel.settingItems = [
            SettingItem(
                key: "test.setting",
                value: .string("value"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("value"))]
            ),
        ]

        let available = SettingsActionHelpers.availableFileTypes(for: viewModel)

        #expect(available.contains(.globalSettings))
        #expect(available.contains(.globalLocal))
        #expect(!available.contains(.projectSettings))
        #expect(!available.contains(.projectLocal))
    }

    @MainActor
    @Test("availableFileTypes includes project files when viewing a project")
    func availableFileTypesWithProject() {
        let project = ClaudeProject(
            name: "Test Project",
            path: URL(fileURLWithPath: "/test/project"),
            claudeDirectory: URL(fileURLWithPath: "/test/project/.claude")
        )
        let viewModel = SettingsViewModel(project: project)

        let available = SettingsActionHelpers.availableFileTypes(for: viewModel)

        #expect(available.contains(.globalSettings))
        #expect(available.contains(.globalLocal))
        #expect(available.contains(.projectSettings))
        #expect(available.contains(.projectLocal))
    }

    @MainActor
    @Test("availableFileTypes includes project files even with no project settings")
    func availableFileTypesWithProjectNoSettings() {
        let project = ClaudeProject(
            name: "Test Project",
            path: URL(fileURLWithPath: "/test/project"),
            claudeDirectory: URL(fileURLWithPath: "/test/project/.claude")
        )
        let viewModel = SettingsViewModel(project: project)
        viewModel.settingItems = [] // No settings at all

        let available = SettingsActionHelpers.availableFileTypes(for: viewModel)

        // Project files should still be available for adding new settings
        #expect(available.contains(.projectSettings))
        #expect(available.contains(.projectLocal))
    }

    @MainActor
    @Test("availableFileTypes excludes project files when project is nil despite project-sourced data")
    func availableFileTypesNoProjectWithProjectData() {
        let viewModel = SettingsViewModel(project: nil)
        // Even if we somehow have project-sourced settings, project files should not be available
        viewModel.settingItems = [
            SettingItem(
                key: "test.setting",
                value: .string("value"),
                source: .projectSettings,
                contributions: [SourceContribution(source: .projectSettings, value: .string("value"))]
            ),
        ]

        let available = SettingsActionHelpers.availableFileTypes(for: viewModel)

        #expect(available.contains(.globalSettings))
        #expect(available.contains(.globalLocal))
        #expect(!available.contains(.projectSettings))
        #expect(!available.contains(.projectLocal))
    }

    @MainActor
    @Test("availableFileTypes filters out read-only files")
    func availableFileTypesFiltersReadOnly() {
        let viewModel = SettingsViewModel(project: nil)
        viewModel.settingsFiles = [
            SettingsFile(
                type: .globalSettings,
                path: URL(fileURLWithPath: "/test/path"),
                isReadOnly: true
            ),
        ]

        let available = SettingsActionHelpers.availableFileTypes(for: viewModel)

        #expect(!available.contains(.globalSettings))
    }

    // MARK: - isReadOnly Tests

    @MainActor
    @Test("isReadOnly returns true for read-only files")
    func isReadOnlyTrue() {
        let viewModel = SettingsViewModel(project: nil)
        viewModel.settingsFiles = [
            SettingsFile(
                type: .enterpriseManaged,
                path: URL(fileURLWithPath: "/test/path"),
                isReadOnly: true
            ),
        ]

        let result = SettingsActionHelpers.isReadOnly(fileType: .enterpriseManaged, in: viewModel)
        #expect(result == true)
    }

    @MainActor
    @Test("isReadOnly returns false for writable files")
    func isReadOnlyFalse() {
        let viewModel = SettingsViewModel(project: nil)
        viewModel.settingsFiles = [
            SettingsFile(
                type: .globalSettings,
                path: URL(fileURLWithPath: "/test/path"),
                isReadOnly: false
            ),
        ]

        let result = SettingsActionHelpers.isReadOnly(fileType: .globalSettings, in: viewModel)
        #expect(result == false)
    }

    @MainActor
    @Test("isReadOnly returns false for non-existent files")
    func isReadOnlyNonExistent() {
        let viewModel = SettingsViewModel(project: nil)
        viewModel.settingsFiles = []

        let result = SettingsActionHelpers.isReadOnly(fileType: .globalSettings, in: viewModel)
        #expect(result == false)
    }

    // MARK: - contributingFileTypes Tests

    @MainActor
    @Test("contributingFileTypes returns all sources for parent node")
    func testContributingFileTypes() {
        let viewModel = SettingsViewModel(project: nil)
        viewModel.settingItems = [
            SettingItem(
                key: "editor.fontSize",
                value: .int(12),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .int(12))]
            ),
            SettingItem(
                key: "editor.tabSize",
                value: .int(4),
                source: .projectSettings,
                contributions: [SourceContribution(source: .projectSettings, value: .int(4))]
            ),
        ]

        let contributing = SettingsActionHelpers.contributingFileTypes(for: "editor", in: viewModel)

        #expect(contributing.contains(.globalSettings))
        #expect(contributing.contains(.projectSettings))
        #expect(contributing.count == 2)
    }

    @MainActor
    @Test("contributingFileTypes returns empty for non-existent parent")
    func contributingFileTypesNonExistent() {
        let viewModel = SettingsViewModel(project: nil)
        viewModel.settingItems = []

        let contributing = SettingsActionHelpers.contributingFileTypes(for: "nonexistent", in: viewModel)

        #expect(contributing.isEmpty)
    }

    @MainActor
    @Test("contributingFileTypes includes node itself if it has contributions")
    func contributingFileTypesIncludesNodeItself() {
        let viewModel = SettingsViewModel(project: nil)
        viewModel.settingItems = [
            SettingItem(
                key: "editor",
                value: .object([:]),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .object([:]))]
            ),
            SettingItem(
                key: "editor.fontSize",
                value: .int(12),
                source: .projectSettings,
                contributions: [SourceContribution(source: .projectSettings, value: .int(12))]
            ),
        ]

        let contributing = SettingsActionHelpers.contributingFileTypes(for: "editor", in: viewModel)

        #expect(contributing.contains(.globalSettings))
        #expect(contributing.contains(.projectSettings))
    }
}
