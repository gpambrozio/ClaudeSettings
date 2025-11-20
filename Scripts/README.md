# Release Scripts

Scripts for building, packaging, and releasing ClaudeSettings.

## Prerequisites

### 1. GitHub CLI

Install and authenticate the GitHub CLI:

```bash
brew install gh
gh auth login
```

### 2. Claude CLI

Ensure the Claude CLI is installed and available in your PATH.

### 3. create-dmg

Install the create-dmg tool for creating DMG packages:

```bash
brew install create-dmg
```

### 4. Developer ID Certificate

You need a valid "Developer ID Application" certificate in your Keychain. This is required for distributing macOS apps outside the App Store.

### 5. Notarytool Credentials

Set up notarytool to authenticate with Apple's notary service:

```bash
xcrun notarytool store-credentials notarytool-profile \
    --apple-id YOUR_APPLE_ID \
    --team-id YOUR_TEAM_ID
```

Replace:
- `YOUR_APPLE_ID` with your Apple ID email
- `YOUR_TEAM_ID` with your Apple Developer Team ID (found in your Apple Developer account)

When prompted for a password, you'll need an **app-specific password**:

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID
3. Navigate to **Sign-In and Security** > **App-Specific Passwords**
4. Click **+** to generate a new password
5. Label it something like "notarytool"
6. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)
7. Paste it into the terminal prompt

**Note:** You can use a different profile name if desired. Just pass `--notarytool-profile <name>` to the release script.

## Usage

### Full Release

Run the complete release process:

```bash
./Scripts/release.sh
```

This will:
1. Build and archive the app with the current version
2. Export with Developer ID signing
3. Notarize the app with Apple
4. Create a DMG package
5. Generate release notes using Claude
6. Create a GitHub release with the DMG
7. Bump the version by 0.1 and commit (no push)

### Command Line Flags

The release script supports several flags to customize the build process:

#### `--skip-notarize`

Skip the notarization process entirely. Useful for testing builds without waiting for Apple's notary service.

```bash
./Scripts/release.sh --skip-notarize
```

**Note:** Apps built with `--skip-notarize` will trigger Gatekeeper warnings when users try to open them.

#### `--local-signing`

Build with ad-hoc/local signing instead of Developer ID signing. This automatically skips notarization and produces a build suitable for local testing only.

```bash
./Scripts/release.sh --local-signing
```

**Use case:** Quick builds for local testing without needing valid Developer ID certificates.

#### `--notarytool-profile <name>`

Specify a custom notarytool keychain profile name. Defaults to `notarytool-profile` if not specified.

```bash
./Scripts/release.sh --notarytool-profile my-custom-profile
```

**Use case:** Multiple developers or different Apple IDs using different keychain profiles.

#### `--team-id <id>`

Specify a custom Apple Team ID. Defaults to `XG2WG7U93U` if not specified.

```bash
./Scripts/release.sh --team-id ABC123XYZ
```

**Use case:** Building with a different Apple Developer account or team.

### Combining Flags

Multiple flags can be combined:

```bash
# Custom team and profile
./Scripts/release.sh --team-id ABC123XYZ --notarytool-profile my-profile

# Local build for testing
./Scripts/release.sh --local-signing

# Skip notarization with custom team
./Scripts/release.sh --skip-notarize --team-id ABC123XYZ
```

## What the Script Does

### Build Process
- Cleans the build directory
- Creates an Xcode archive with Release configuration
- Exports the archive with Developer ID signing

### Notarization
- Submits the app to Apple's notary service
- Waits for approval (typically 1-5 minutes)
- Staples the notarization ticket to the app

### Packaging
- Creates a DMG with the app and Applications symlink
- Names it `ClaudeSettings-{version}.dmg`

### Release Notes
- Finds the previous release tag
- Analyzes commits since that tag
- Uses Claude to generate user-friendly release notes
- You can review and confirm before publishing

### Version Bump
- Increments `MARKETING_VERSION` by 0.1 (e.g., 1.0 → 1.1)
- Increments `CURRENT_PROJECT_VERSION` by 1
- Commits the change but does not push

## Troubleshooting

### "GitHub CLI is not authenticated"
Run `gh auth login` and follow the prompts.

### "Notarization failed"
- Verify your notarytool credentials: `xcrun notarytool store-credentials`
- Check that your Developer ID certificate is valid
- Ensure hardened runtime is enabled (default in Release builds)

### "Git working directory is not clean"
Commit or stash your changes before running the release script.

### "Archive build failed"
- Check that your Developer ID Application certificate is in the Keychain
- Verify the certificate hasn't expired
- Try building manually in Xcode first to see detailed errors
