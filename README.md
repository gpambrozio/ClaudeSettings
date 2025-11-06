# ClaudeSettings - macOS App

A modern macOS application using a **workspace + SPM package** architecture for clean separation between app shell and feature code.

## Project Architecture

```
ClaudeSettings/
├── ClaudeSettings.xcworkspace/              # Open this file in Xcode
├── ClaudeSettings.xcodeproj/                # App shell project
├── ClaudeSettings/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── ClaudeSettingsApp.swift              # App entry point
│   ├── ClaudeSettings.entitlements          # App sandbox settings
│   └── ClaudeSettings.xctestplan            # Test configuration
├── ClaudeSettingsPackage/                   # 🚀 Primary development area
│   ├── Package.swift                   # Package configuration
│   ├── Sources/ClaudeSettingsFeature/       # Your feature code
│   └── Tests/ClaudeSettingsFeatureTests/    # Unit tests
└── ClaudeSettingsUITests/                   # UI automation tests
```

## Key Architecture Points

### Workspace + SPM Structure
- **App Shell**: `ClaudeSettings/` contains minimal app lifecycle code
- **Feature Code**: `ClaudeSettingsPackage/Sources/ClaudeSettingsFeature/` is where most development happens
- **Separation**: Business logic lives in the SPM package, app target just imports and displays it

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

### App Sandbox
The app is sandboxed by default with basic file access permissions. Modify `ClaudeSettings.entitlements` to add capabilities as needed.

## Development Notes

### Code Organization
Most development happens in `ClaudeSettingsPackage/Sources/ClaudeSettingsFeature/` - organize your code as you prefer.

### Public API Requirements
Types exposed to the app target need `public` access:
```swift
public struct SettingsView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit `ClaudeSettingsPackage/Package.swift` to add SPM dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "ClaudeSettingsFeature",
        dependencies: ["SomePackage"]
    ),
]
```

### Test Structure
- **Unit Tests**: `ClaudeSettingsPackage/Tests/ClaudeSettingsFeatureTests/` (Swift Testing framework)
- **UI Tests**: `ClaudeSettingsUITests/` (XCUITest framework)
- **Test Plan**: `ClaudeSettings.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### App Sandbox & Entitlements
The app is sandboxed by default with basic file access. Edit `ClaudeSettings/ClaudeSettings.entitlements` to add capabilities:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<!-- Add other entitlements as needed -->
```

## macOS-Specific Features

### Window Management
Add multiple windows and settings panels:
```swift
@main
struct ClaudeSettingsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        Settings {
            SettingsView()
        }
    }
}
```

### SF Symbols Usage

This project uses the [SFSymbolsMacro](https://github.com/lukepistrol/SFSymbolsMacro) library for type-safe SF Symbol management:

#### Using Symbols

- **Never use string literals** for SF Symbols (enforced by SwiftLint rule)
- **Always use the `Symbols` enum** from `MacVoiceHooksPackage/Sources/MacVoiceHooksFeature/Symbols.swift`
- Symbols are kept in **alphabetical order** within the enum

#### Examples

```swift
// ✅ Correct - Use Symbols enum
Label("Settings", symbol: .gearshape)
Symbols.micFill.image
stateMachine.state.icon.image

// ❌ Wrong - Don't use string literals
Label("Settings", systemImage: "gearshape")
Image(systemName: "mic.fill")
```

#### Adding New Symbols

1. Add the new case to `Symbols` enum in alphabetical order
2. Use camelCase for the case name
3. Specify raw value only if different from case name
4. Make sure to keep the enum `public` for cross-module access

```swift
@SFSymbol
public enum Symbols: String {
    case micFill = "mic.fill"  // Raw value needed
    case terminal             // Raw value same as case name
}
```

### Asset Management
- **App-Level Assets**: `ClaudeSettings/Assets.xcassets/` (app icon with multiple sizes, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in your feature package:
```swift
.target(
    name: "ClaudeSettingsFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

## Notes

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted macOS development workflows.