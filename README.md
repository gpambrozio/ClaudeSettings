# ClaudeSettings

A native macOS app for visually managing your Claude Code settings.

## Why ClaudeSettings?

Claude Code stores its configuration in JSON files scattered across multiple locations—global settings, project settings, local overrides, enterprise policies. Managing these files means:

- Hunting through directories to find the right file
- Remembering which settings override which
- Manually editing JSON without validation
- No easy way to see the "effective" configuration

ClaudeSettings gives you a visual interface to manage all of this in one place.

## Built with Claude Code

This app was vibe coded ([vibe engineered?](https://simonwillison.net/2025/Oct/7/vibe-engineering/)) almost entirely using [Claude Code](https://claude.ai/claude-code). It serves as both a useful tool and a demonstration of what's possible with AI-assisted development.

Contributions are welcome! See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture details, build instructions, and development guidelines.

## Disclaimer

As this is a side project mostly build with Claude Code it probably contains bugs. Feel free to open an issue if you find one or, better yet, fix and submit a pull request. The app does backup every file it touches to `~/Library/Application Support/ClaudeSettings/Backups`.

## Features

### See Everything in One View

Browse all your Claude Code projects and their settings in a unified three-panel interface. The sidebar shows your projects, the list shows available settings organized by category, and the inspector shows details and lets you edit values.

### Understand Setting Precedence

Settings can be defined at multiple levels—enterprise, project, global—and they override each other in specific ways. ClaudeSettings shows you exactly where each value comes from and what's being overridden.

### Edit with Confidence

- **Validation**: The app validates your changes before saving
- **Backups**: Automatic backups before any modification
- **Rollback**: If something goes wrong, your original settings are restored
- **Batch editing**: Change multiple settings at once

### Drag and Drop

Move or copy settings between projects by dragging them in the sidebar. Reorganize your configuration without manual file copying.

### Stay in Sync

ClaudeSettings watches for external changes to your settings files. If you edit a file in your text editor or Claude Code updates something, the app reflects those changes automatically.

### Built-in Documentation

Every setting includes documentation from the official Claude Code schema, so you know what each option does without leaving the app.

## Installation

### Requirements

- macOS 15.0 (Sequoia) or later

### Download

Download the latest release from the [Releases](https://github.com/gpambrozio/ClaudeSettings/releases) page.

### Build from Source

1. Clone the repository
2. Open `ClaudeSettings.xcworkspace` in Xcode 16 or later
3. Build and run

## Usage

1. **Launch the app** — It automatically scans for Claude Code projects on your system
2. **Select a project** — Click on a project in the sidebar to view its settings
3. **Browse settings** — Settings are organized by category in the list view
4. **Edit values** — Click "Edit" to enter edit mode, make changes, then save
5. **See overrides** — The inspector shows which file defines each setting and what it overrides

### Settings Locations

ClaudeSettings manages these configuration files:

| Scope | File | Description |
|-------|------|-------------|
| Global | `~/.claude/settings.json` | Your personal defaults |
| Global Local | `~/.claude/settings.local.json` | Personal settings not synced |
| Project | `.claude/settings.json` | Shared project settings |
| Project Local | `.claude/settings.local.json` | Your local project overrides |
| Enterprise | (managed) | Organization policies |

## Contributing

Interested in contributing? See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture details, build instructions, and development guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.
