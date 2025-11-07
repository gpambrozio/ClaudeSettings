# Claude Code Settings Documentation

A comprehensive guide to configuring Claude Code through various settings files, environment variables, and extension mechanisms.

---

## Table of Contents

1. [Settings File Hierarchy](#settings-file-hierarchy)
2. [Core Settings](#core-settings)
   - [Model & Behavior](#model--behavior)
   - [Authentication](#authentication)
   - [Workspace Management](#workspace-management)
   - [Tool Integration](#tool-integration)
3. [Permission System](#permission-system)
4. [Sandbox Configuration](#sandbox-configuration)
5. [MCP Server Configuration](#mcp-server-configuration)
6. [Subagent Configuration](#subagent-configuration)
7. [Plugin System](#plugin-system)
8. [Sensitive Data Protection](#sensitive-data-protection)
9. [Environment Variables](#environment-variables)
10. [Available Tools](#available-tools)

---

## Settings File Hierarchy

Claude Code uses a multi-level configuration system with the following precedence order (highest to lowest):

| Priority | Location | Purpose | Override Behavior |
|----------|----------|---------|-------------------|
| 1 | `managed-settings.json` | Enterprise managed policies | **Cannot be overridden** |
| 2 | Command line arguments | Temporary session overrides | Session-specific |
| 3 | `.claude/settings.local.json` | Local project settings | Personal, gitignored |
| 4 | `.claude/settings.json` | Shared project settings | Team-shared, version controlled |
| 5 | `~/.claude/settings.json` | User global settings | Personal defaults |

### Enterprise Deployment Locations

Enterprise policies are stored at system-level paths:

- **macOS**: `/Library/Application Support/Claude/managed-settings.json`
- **Linux/WSL**: `/etc/claude/managed-settings.json`
- **Windows**: `%ProgramData%\Claude\managed-settings.json`

---

## Core Settings

### Model & Behavior

#### `model`
**Type**: `string`
**Default**: Auto-selected based on availability
**Description**: Override the default Claude model for all sessions.

**Example**:
```json
{
  "model": "claude-sonnet-4-5-20250929"
}
```

#### `outputStyle`
**Type**: `string`
**Description**: Adjust system prompt behavior and response formatting.

#### `statusLine`
**Type**: `object`
**Description**: Configure custom context information displayed in the status line.

**Example**:
```json
{
  "statusLine": {
    "enabled": true,
    "format": "custom"
  }
}
```

#### `forceLoginMethod`
**Type**: `"claudeai" | "console"`
**Description**: Restrict authentication to specific account types.

**Example**:
```json
{
  "forceLoginMethod": "console"
}
```

---

### Authentication

#### `apiKeyHelper`
**Type**: `string` (path to script)
**Description**: Custom script that generates authentication credentials. The script should output credentials to stdout.

**Related Environment Variable**:
- `CLAUDE_CODE_API_KEY_HELPER_TTL_MS`: Cache duration for credentials (default: refreshes as needed)

**Example**:
```json
{
  "apiKeyHelper": "/usr/local/bin/get-claude-token.sh"
}
```

#### `forceLoginOrgUUID`
**Type**: `string` (UUID)
**Description**: Automatically select a specific organization during login.

**Example**:
```json
{
  "forceLoginOrgUUID": "12345678-1234-1234-1234-123456789abc"
}
```

---

### Workspace Management

#### `cleanupPeriodDays`
**Type**: `number`
**Default**: `30`
**Description**: Retention period (in days) for chat transcripts before automatic cleanup.

**Example**:
```json
{
  "cleanupPeriodDays": 60
}
```

#### `includeCoAuthoredBy`
**Type**: `boolean`
**Default**: `true`
**Description**: Include co-author byline in Git commits made by Claude Code.

**Example**:
```json
{
  "includeCoAuthoredBy": false
}
```

#### `env`
**Type**: `object`
**Description**: Environment variables applied to every Claude Code session.

**Example**:
```json
{
  "env": {
    "NODE_ENV": "development",
    "DEBUG": "true"
  }
}
```

#### `companyAnnouncements`
**Type**: `array<string>`
**Description**: Startup messages displayed to users, rotated randomly.

**Example**:
```json
{
  "companyAnnouncements": [
    "Welcome to Acme Corp development environment!",
    "Remember to run tests before committing!",
    "Check the wiki for coding standards."
  ]
}
```

---

### Tool Integration

#### `hooks`
**Type**: `object`
**Description**: Custom commands executed before/after tool execution.

**Hook Types**:
- `preToolExecution`: Run before any tool executes
- `postToolExecution`: Run after any tool completes
- `preRead`: Run before file read operations
- `postWrite`: Run after file write operations
- And many more...

**Example**:
```json
{
  "hooks": {
    "postWrite": "echo 'File written: ${FILE_PATH}'",
    "preToolExecution": "timestamp.sh"
  }
}
```

#### `disableAllHooks`
**Type**: `boolean`
**Default**: `false`
**Description**: Disable all hook functionality globally.

**Example**:
```json
{
  "disableAllHooks": true
}
```

---

## Permission System

The `permissions` object controls tool access through three arrays:

### Permission Arrays

#### `allow`
**Type**: `array<string>`
**Description**: Grant explicit tool use permissions without prompting.

**Syntax**:
- Tool permissions: `"ToolName"` or `"ToolName(pattern)"`
- Bash commands: `"Bash(command:*)"` (prefix matching)
- File operations: `"Read(glob/pattern/**)"` (glob patterns)

**Example**:
```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Read(src/**/*.js)",
      "Edit(src/**/*.js)",
      "WebFetch(domain:github.com)"
    ]
  }
}
```

#### `ask`
**Type**: `array<string>`
**Description**: Request user confirmation before allowing tool use.

**Example**:
```json
{
  "permissions": {
    "ask": [
      "Bash(rm:*)",
      "Bash(docker:*)",
      "Write(.env)"
    ]
  }
}
```

#### `deny`
**Type**: `array<string>`
**Description**: Block specific tools or file patterns completely.

**Example**:
```json
{
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(.env.*)",
      "Read(secrets/**)",
      "Bash(curl:*)",
      "WebFetch(domain:internal-api.example.com)"
    ]
  }
}
```

---

### Additional Permission Settings

#### `additionalDirectories`
**Type**: `array<string>`
**Description**: Expand Claude's working directory access beyond the current project.

**Example**:
```json
{
  "permissions": {
    "additionalDirectories": [
      "/usr/local/lib/my-company-tools",
      "~/shared-configs"
    ]
  }
}
```

#### `defaultMode`
**Type**: `string`
**Description**: Permission mode to use on startup (e.g., `"acceptEdits"`).

**Example**:
```json
{
  "permissions": {
    "defaultMode": "acceptEdits"
  }
}
```

#### `disableBypassPermissionsMode`
**Type**: `"disable"`
**Description**: Prevent users from bypassing permission restrictions.

**Example**:
```json
{
  "permissions": {
    "disableBypassPermissionsMode": "disable"
  }
}
```

---

### Permission Rule Syntax

**Important Notes**:
- Bash command patterns use **prefix matching** (not regex)
- File patterns support **glob syntax** (`*`, `**`, `?`)
- Permission rules are evaluated in order: `deny` → `allow` → `ask`

**Examples**:

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",                    // All git commands
      "Bash(npm install:*)",            // npm install variations
      "Read(src/**/*.{js,ts})",         // JS/TS files in src/
      "Edit(tests/**)",                 // All files in tests/
      "WebFetch(domain:*.github.com)"   // GitHub subdomains
    ],
    "deny": [
      "Bash(git push --force:*)",       // Prevent force push
      "Read(.env*)",                    // Block environment files
      "Write(/etc/**)",                 // Block system files
      "WebFetch(domain:malicious.com)"  // Block specific domain
    ]
  }
}
```

---

## Sandbox Configuration

Sandboxing isolates Bash commands from the filesystem and network. **Only available on macOS and Linux** (disabled by default).

### Core Sandbox Settings

#### `sandbox.enabled`
**Type**: `boolean`
**Default**: `false`
**Description**: Activate command sandboxing.

#### `sandbox.autoAllowBashIfSandboxed`
**Type**: `boolean`
**Default**: `true`
**Description**: Automatically approve Bash commands when they run in the sandbox.

#### `sandbox.allowUnsandboxedCommands`
**Type**: `boolean`
**Default**: `true`
**Description**: Allow commands to escape the sandbox when necessary. Set to `false` for strict enterprise policies.

#### `sandbox.excludedCommands`
**Type**: `array<string>`
**Description**: Commands that always run outside the sandbox (prefix matching).

**Example**:
```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "allowUnsandboxedCommands": false,
    "excludedCommands": [
      "git",
      "docker",
      "npm"
    ]
  }
}
```

---

### Network Sandbox Options

#### `sandbox.network.allowUnixSockets`
**Type**: `array<string>`
**Description**: Unix socket paths accessible within the sandbox.

**Example**:
```json
{
  "sandbox": {
    "network": {
      "allowUnixSockets": [
        "/var/run/docker.sock",
        "/tmp/my-app.sock"
      ]
    }
  }
}
```

#### `sandbox.network.allowLocalBinding`
**Type**: `boolean`
**Default**: `false`
**macOS only**
**Description**: Allow binding to localhost ports within the sandbox.

#### `sandbox.network.httpProxyPort`
**Type**: `number`
**Description**: Custom HTTP proxy port for sandbox network requests.

#### `sandbox.network.socksProxyPort`
**Type**: `number`
**Description**: Custom SOCKS proxy port for sandbox network requests.

**Example**:
```json
{
  "sandbox": {
    "network": {
      "allowLocalBinding": true,
      "httpProxyPort": 8888,
      "socksProxyPort": 1080
    }
  }
}
```

#### `sandbox.enableWeakerNestedSandbox`
**Type**: `boolean`
**Default**: `false`
**Description**: Reduce sandbox security for Docker/container environments where full isolation causes issues.

---

### Sandbox Access Control

- **Filesystem**: Controlled via `permissions.allow` and `permissions.deny` for `Read`/`Edit`/`Write` tools
- **Network**: Controlled via `permissions.allow` and `permissions.deny` for `WebFetch` tool

**Example Complete Sandbox Configuration**:
```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "allowUnsandboxedCommands": false,
    "excludedCommands": ["git", "npm"],
    "network": {
      "allowUnixSockets": ["/var/run/docker.sock"],
      "allowLocalBinding": true
    }
  },
  "permissions": {
    "allow": [
      "Read(src/**)",
      "Edit(src/**)",
      "Bash(npm test:*)",
      "WebFetch(domain:github.com)"
    ],
    "deny": [
      "Read(.env)",
      "Write(/etc/**)",
      "WebFetch(domain:internal.corp)"
    ]
  }
}
```

---

## MCP Server Configuration

Model Context Protocol (MCP) servers extend Claude Code with additional capabilities. Configuration controls which servers are available.

### MCP Settings

#### `enableAllProjectMcpServers`
**Type**: `boolean`
**Default**: `false`
**Description**: Automatically approve all MCP servers defined in project-level configuration.

#### `enabledMcpjsonServers`
**Type**: `array<string>`
**Description**: List of specific MCP servers to approve/enable.

#### `disabledMcpjsonServers`
**Type**: `array<string>`
**Description**: List of specific MCP servers to reject/disable.

**Example**:
```json
{
  "enableAllProjectMcpServers": false,
  "enabledMcpjsonServers": [
    "github-mcp",
    "sqlite-mcp"
  ],
  "disabledMcpjsonServers": [
    "experimental-mcp"
  ]
}
```

---

### Enterprise MCP Management

#### `allowedMcpServers`
**Type**: `array<string>`
**Default**: `undefined` (no restrictions)
**Description**: Enterprise allowlist. Only listed servers can be used.

#### `deniedMcpServers`
**Type**: `array<string>`
**Description**: Enterprise denylist. Listed servers are blocked. **Takes precedence over allowlist**.

**Example**:
```json
{
  "allowedMcpServers": [
    "approved-internal-mcp",
    "github-mcp"
  ],
  "deniedMcpServers": [
    "unapproved-external-mcp",
    "experimental-*"
  ]
}
```

---

### Managed MCP Configuration

Enterprise deployments can define managed MCP servers via `managed-mcp.json` at system-level paths:

- **macOS**: `/Library/Application Support/Claude/managed-mcp.json`
- **Linux/WSL**: `/etc/claude/managed-mcp.json`
- **Windows**: `%ProgramData%\Claude\managed-mcp.json`

---

## Subagent Configuration

Subagents are custom AI assistants with specialized prompts and tool permissions. They are stored as Markdown files with YAML frontmatter.

### Subagent Locations

| Location | Scope | Purpose |
|----------|-------|---------|
| `~/.claude/agents/` | User-level | Available across all projects for personal use |
| `.claude/agents/` | Project-level | Shared with team, version controlled |

### Subagent File Format

**File naming**: `agent-name.md`

**Structure**:
```markdown
---
name: Agent Name
description: Brief description of what this agent does
tools:
  allow:
    - ToolName
    - Bash(command:*)
  deny:
    - Write(.env)
model: claude-sonnet-4-5-20250929
---

# Agent Prompt

Your detailed instructions for this subagent go here.

## Behavior

Describe how the agent should behave...

## Examples

Provide examples of how to use this agent...
```

---

### Subagent YAML Frontmatter

#### `name`
**Type**: `string` (required)
**Description**: Display name for the subagent.

#### `description`
**Type**: `string` (required)
**Description**: Brief summary of the subagent's purpose.

#### `tools`
**Type**: `object`
**Description**: Tool permissions specific to this subagent.

**Subfields**:
- `allow`: Array of allowed tools
- `deny`: Array of denied tools

#### `model`
**Type**: `string`
**Description**: Override the Claude model for this specific subagent.

---

### Example Subagent

**File**: `.claude/agents/code-reviewer.md`

```markdown
---
name: Code Reviewer
description: Reviews code for best practices, security issues, and maintainability
tools:
  allow:
    - Read(**/*.{js,ts,jsx,tsx})
    - Grep
    - Bash(git diff:*)
  deny:
    - Edit
    - Write
    - Bash(git push:*)
model: claude-sonnet-4-5-20250929
---

# Code Reviewer Agent

You are a specialized code reviewer focusing on:

## Review Areas

1. **Security**: Look for common vulnerabilities (XSS, SQL injection, etc.)
2. **Best Practices**: Ensure code follows team conventions
3. **Performance**: Identify potential performance bottlenecks
4. **Maintainability**: Check for code clarity and documentation

## Output Format

Provide feedback in this structure:

### Critical Issues
- Issue 1
- Issue 2

### Suggestions
- Suggestion 1
- Suggestion 2

### Positive Observations
- What was done well
```

---

### Using Subagents

Invoke subagents via the Task tool:
```javascript
// Claude Code will automatically discover agents in:
// - ~/.claude/agents/
// - .claude/agents/

// Usage in prompts:
"Use the code-reviewer subagent to review the changes in src/"
```

---

## Plugin System

Plugins extend Claude Code with additional features, commands, and integrations. They are distributed via marketplaces.

### Plugin Settings

#### `enabledPlugins`
**Type**: `array<string>`
**Format**: `"plugin-name@marketplace-name"`
**Description**: Control which plugins are enabled.

**Example**:
```json
{
  "enabledPlugins": [
    "swift-dev@official",
    "custom-linter@company-marketplace"
  ]
}
```

#### `extraKnownMarketplaces`
**Type**: `array<object>`
**Description**: Define additional plugin sources beyond the official marketplace.

**Marketplace Types**:
- GitHub repositories
- Git URLs
- Local directories

**Example**:
```json
{
  "extraKnownMarketplaces": [
    {
      "name": "company-marketplace",
      "type": "github",
      "url": "https://github.com/company/claude-plugins"
    },
    {
      "name": "local-dev",
      "type": "local",
      "path": "/Users/dev/my-plugins"
    }
  ]
}
```

---

### Plugin Configuration Scope

Plugin settings respect scope inheritance:

1. **User settings** (`~/.claude/settings.json`): Global plugin defaults
2. **Project settings** (`.claude/settings.json`): Team-shared plugin configuration
3. **Local settings** (`.claude/settings.local.json`): Personal project overrides

**Example Multi-level Configuration**:

**User** (`~/.claude/settings.json`):
```json
{
  "enabledPlugins": [
    "swift-dev@official",
    "git-tools@official"
  ]
}
```

**Project** (`.claude/settings.json`):
```json
{
  "enabledPlugins": [
    "project-specific@company"
  ]
}
```

**Result**: All three plugins are enabled (merged across scopes).

---

### Plugin Management

Use the `/plugin` command for interactive plugin management:

```bash
/plugin list              # List available plugins
/plugin enable <name>     # Enable a plugin
/plugin disable <name>    # Disable a plugin
/plugin info <name>       # Show plugin details
```

---

## Sensitive Data Protection

Protect sensitive files from Claude Code access using `permissions.deny` rules.

### Recommended Deny Patterns

```json
{
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(.env.*)",
      "Read(*.env)",
      "Read(secrets/**)",
      "Read(**/*secret*)",
      "Read(**/*password*)",
      "Read(**/*token*)",
      "Read(.aws/**)",
      "Read(.ssh/**)",
      "Read(*.key)",
      "Read(*.pem)",
      "Read(credentials.json)",
      "Write(.env)",
      "Write(secrets/**)"
    ]
  }
}
```

### Migration from `ignorePatterns`

The deprecated `ignorePatterns` configuration has been replaced by `permissions.deny`:

**Old** (deprecated):
```json
{
  "ignorePatterns": [".env", "secrets/"]
}
```

**New** (current):
```json
{
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(secrets/**)"
    ]
  }
}
```

---

## Environment Variables

Claude Code respects over 50 environment variables for configuration. These can be set via:
- System environment
- `settings.json` via the `env` field (for team-wide rollout)

### Authentication

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Direct API key for Claude |
| `AWS_ACCESS_KEY_ID` | AWS Bedrock access key |
| `AWS_SECRET_ACCESS_KEY` | AWS Bedrock secret key |
| `AWS_REGION` | AWS Bedrock region |
| `GOOGLE_APPLICATION_CREDENTIALS` | Google Vertex AI credentials path |
| `CLAUDE_CODE_MTLS_CERT` | mTLS client certificate path |
| `CLAUDE_CODE_MTLS_KEY` | mTLS private key path |

---

### Model Configuration

| Variable | Description |
|----------|-------------|
| `CLAUDE_CODE_DEFAULT_MODEL` | Override default model selection |
| `CLAUDE_CODE_TOKEN_LIMIT` | Maximum tokens per request |
| `CLAUDE_CODE_THINKING_BUDGET` | Token budget for reasoning |
| `CLAUDE_CODE_PROMPT_CACHING` | Enable/disable prompt caching |

---

### Bash Execution

| Variable | Description |
|----------|-------------|
| `CLAUDE_CODE_BASH_TIMEOUT` | Command timeout (milliseconds) |
| `CLAUDE_CODE_BASH_OUTPUT_LIMIT` | Max output size (bytes) |

---

### Proxy & Network

| Variable | Description |
|----------|-------------|
| `HTTP_PROXY` | HTTP proxy URL |
| `HTTPS_PROXY` | HTTPS proxy URL |
| `SOCKS_PROXY` | SOCKS proxy URL |
| `CLAUDE_CODE_CUSTOM_HEADERS` | Custom HTTP headers (JSON) |

---

### Features

| Variable | Description |
|----------|-------------|
| `CLAUDE_CODE_TELEMETRY` | Enable/disable telemetry |
| `CLAUDE_CODE_AUTO_UPDATE` | Enable/disable auto-updates |
| `CLAUDE_CODE_COST_WARNING` | Show cost warnings |
| `CLAUDE_CODE_EXPERIMENTAL_FEATURES` | Enable experimental features |

---

### Tool Behavior

| Variable | Description |
|----------|-------------|
| `CLAUDE_CODE_MCP_TIMEOUT` | MCP server timeout (milliseconds) |
| `CLAUDE_CODE_WEBSEARCH_DOMAINS` | Domain filtering for WebSearch |
| `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` | API key helper cache duration |

---

### Setting Environment Variables via `settings.json`

**Example**:
```json
{
  "env": {
    "CLAUDE_CODE_DEFAULT_MODEL": "claude-sonnet-4-5-20250929",
    "CLAUDE_CODE_BASH_TIMEOUT": "300000",
    "CLAUDE_CODE_TELEMETRY": "false",
    "HTTP_PROXY": "http://proxy.company.com:8080"
  }
}
```

This approach enables team-wide environment configuration through version-controlled settings.

---

## Available Tools

Claude Code provides 12 core tools for various operations. Some require explicit permission.

### Tool Reference

| Tool | Permission Required | Description |
|------|---------------------|-------------|
| **Bash** | ✅ Yes | Execute shell commands |
| **Edit** | ✅ Yes | Modify existing files |
| **Write** | ✅ Yes | Create new files or overwrite existing ones |
| **Read** | ❌ No | Read file contents |
| **Glob** | ❌ No | Find files by pattern matching |
| **Grep** | ❌ No | Search file contents by regex |
| **NotebookEdit** | ✅ Yes | Edit Jupyter notebook cells |
| **NotebookRead** | ❌ No | Read Jupyter notebooks |
| **WebFetch** | ✅ Yes | Fetch content from URLs |
| **WebSearch** | ✅ Yes | Search the web |
| **SlashCommand** | ✅ Yes | Execute custom slash commands |
| **Task** | ❌ No | Delegate work to specialized subagents |
| **TodoWrite** | ❌ No | Manage task lists |

---

### Tool Permission Configuration

Control tool access via `permissions.allow`, `permissions.ask`, and `permissions.deny`:

**Example**:
```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(npm:*)",
      "Edit(src/**)",
      "Write(tests/**)",
      "WebFetch(domain:github.com)",
      "WebSearch"
    ],
    "ask": [
      "Bash(rm:*)",
      "Bash(docker:*)",
      "Write(.github/**)"
    ],
    "deny": [
      "Bash(curl:*)",
      "Edit(.env)",
      "Write(node_modules/**)",
      "WebFetch(domain:internal.corp)"
    ]
  }
}
```

---

### Tool Hook Integration

Tools can be customized with pre/post-execution hooks:

**Example**:
```json
{
  "hooks": {
    "preRead": "echo 'Reading ${FILE_PATH}'",
    "postEdit": "./scripts/format-on-save.sh ${FILE_PATH}",
    "preBash": "echo 'Executing: ${COMMAND}'",
    "postWebFetch": "log-network-access.sh ${URL}"
  }
}
```

**Available Hook Points**:
- `preToolExecution` / `postToolExecution`: All tools
- `preBash` / `postBash`: Shell commands
- `preRead` / `postRead`: File reads
- `preEdit` / `postEdit`: File edits
- `preWrite` / `postWrite`: File writes
- `preWebFetch` / `postWebFetch`: Network requests
- And many more...

---

## Best Practices

### 1. Use Layered Configuration

- **User settings**: Personal preferences and global defaults
- **Project settings**: Team-shared conventions
- **Local settings**: Personal project overrides (gitignored)
- **Managed settings**: Enterprise policies (cannot be overridden)

### 2. Protect Sensitive Data

Always deny access to sensitive files:
```json
{
  "permissions": {
    "deny": [
      "Read(.env*)",
      "Read(secrets/**)",
      "Read(*.key)",
      "Read(.ssh/**)"
    ]
  }
}
```

### 3. Use Specific Permissions

Prefer specific permissions over wildcards:
```json
{
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)"
    ]
  }
}
```

Avoid overly broad permissions like `"Bash(*)"`.

### 4. Enable Sandboxing for Security

For environments requiring isolation:
```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "allowUnsandboxedCommands": false
  }
}
```

### 5. Document Project-Level Settings

Add comments to `.claude/settings.json`:
```json
{
  "// Description": "Team settings for Project X",
  "permissions": {
    "allow": [
      "// Git operations are auto-approved",
      "Bash(git:*)"
    ]
  }
}
```

(Note: JSON doesn't officially support comments, but Claude Code tolerates them)

### 6. Version Control Considerations

**Commit** (`.claude/settings.json`):
- Team-shared permissions
- Project-specific plugins
- Shared MCP servers
- Hooks that benefit the team

**Gitignore** (`.claude/settings.local.json`):
- Personal API keys
- Local development preferences
- Machine-specific paths

---

## Troubleshooting

### Permission Issues

**Problem**: Claude Code asks for permission repeatedly.

**Solution**: Add explicit `allow` rules:
```json
{
  "permissions": {
    "allow": [
      "Bash(npm:*)",
      "Read(src/**)",
      "Edit(src/**)"
    ]
  }
}
```

---

### Sandbox Conflicts

**Problem**: Commands fail in sandbox mode.

**Solution**: Either exclude the command or allow unsandboxed execution:
```json
{
  "sandbox": {
    "enabled": true,
    "excludedCommands": ["docker", "git"],
    "allowUnsandboxedCommands": true
  }
}
```

---

### MCP Server Not Loading

**Problem**: MCP server defined in project but not available.

**Solution**: Enable project MCP servers:
```json
{
  "enableAllProjectMcpServers": true
}
```

Or enable specific servers:
```json
{
  "enabledMcpjsonServers": ["my-mcp-server"]
}
```

---

### Plugin Conflicts

**Problem**: Multiple plugins provide similar functionality.

**Solution**: Explicitly disable conflicting plugins:
```json
{
  "enabledPlugins": [
    "preferred-plugin@official"
  ],
  "disabledPlugins": [
    "conflicting-plugin@marketplace"
  ]
}
```

---

## Additional Resources

- **Official Documentation**: https://code.claude.com/docs/en/settings
- **MCP Protocol**: https://modelcontextprotocol.io/
- **Plugin Development**: https://code.claude.com/docs/en/plugins
- **Subagent Creation**: https://code.claude.com/docs/en/subagents

---

## Version History

- **2025-11**: Comprehensive documentation compiled from official sources
- Settings system continues to evolve with new features
