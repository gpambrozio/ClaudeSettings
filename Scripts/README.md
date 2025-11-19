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

### 3. Developer ID Certificate

You need a valid "Developer ID Application" certificate in your Keychain. This is required for distributing macOS apps outside the App Store.

### 4. Notarytool Credentials

Set up notarytool to authenticate with Apple's notary service:

```bash
xcrun notarytool store-credentials notarytool-profile \
    --apple-id YOUR_APPLE_ID \
    --team-id XG2WG7U93U
```

When prompted for a password, you'll need an **app-specific password**:

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID
3. Navigate to **Sign-In and Security** > **App-Specific Passwords**
4. Click **+** to generate a new password
5. Label it something like "notarytool"
6. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)
7. Paste it into the terminal prompt

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

### Testing (Skip Notarization)

For testing the build process without waiting for notarization:

```bash
./Scripts/release.sh --skip-notarize
```

Note: Apps built with `--skip-notarize` will trigger Gatekeeper warnings when users try to open them.

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
