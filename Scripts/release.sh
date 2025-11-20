#!/bin/bash

# ClaudeSettings Release Script
# Builds, notarizes, packages, and releases the app to GitHub

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE="$PROJECT_ROOT/ClaudeSettings.xcworkspace"
SCHEME="ClaudeSettings"
CONFIG_FILE="$PROJECT_ROOT/Config/Shared.xcconfig"
EXPORT_OPTIONS="$SCRIPT_DIR/export-options.plist"
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/ClaudeSettings.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_NAME="ClaudeSettings"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
SKIP_NOTARIZE=false
NOTARYTOOL_PROFILE="notarytool-profile"
TEAM_ID="XG2WG7U93U"
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --notarytool-profile)
            NOTARYTOOL_PROFILE="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            ;;
    esac
done

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Get version from xcconfig
get_version() {
    grep "^MARKETING_VERSION" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' '
}

get_build_number() {
    grep "^CURRENT_PROJECT_VERSION" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' '
}

# Increment version by 0.1
increment_version() {
    local version=$1
    local major minor
    major=$(echo "$version" | cut -d'.' -f1)
    minor=$(echo "$version" | cut -d'.' -f2)
    minor=$((minor + 1))
    echo "$major.$minor"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check for gh CLI
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed. Install with: brew install gh"
    fi

    # Check gh auth
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI is not authenticated. Run: gh auth login"
    fi

    # Check for claude CLI
    if ! command -v claude &> /dev/null; then
        log_error "Claude CLI is not installed."
    fi

    # Check for create-dmg
    if ! command -v create-dmg &> /dev/null; then
        log_error "create-dmg is not installed. Install with: brew install create-dmg"
    fi

    # Check for notarytool (part of Xcode)
    if ! command -v xcrun &> /dev/null; then
        log_error "Xcode command line tools are not installed."
    fi

    # Check for clean git state
    if [[ -n $(git -C "$PROJECT_ROOT" status --porcelain) ]]; then
        log_warning "Git working directory has uncommitted changes."
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Release cancelled. Please commit or stash changes first."
        fi
    fi

    log_success "All prerequisites satisfied"
}

# Clean and build
build_archive() {
    log_info "Building archive..."

    # Clean build directory
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # Build archive
    # Note: Don't override CODE_SIGN_IDENTITY here - let automatic signing work
    # The export phase will re-sign with Developer ID using export-options.plist
    xcodebuild archive \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        -quiet \
        || log_error "Archive build failed"

    log_success "Archive built successfully"
}

# Export archive
export_archive() {
    log_info "Exporting archive with Developer ID signing..."

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        -exportPath "$EXPORT_PATH" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        -quiet \
        || log_error "Archive export failed"

    log_success "Archive exported successfully"
}

# Notarize the app
notarize_app() {
    if [ "$SKIP_NOTARIZE" = true ]; then
        log_warning "Skipping notarization (--skip-notarize flag set)"
        return
    fi

    log_info "Notarizing app (this may take a few minutes)..."

    local app_path="$EXPORT_PATH/$APP_NAME.app"
    local zip_path="$BUILD_DIR/$APP_NAME-notarize.zip"

    # Create zip for notarization
    ditto -c -k --keepParent "$app_path" "$zip_path"

    # Submit for notarization
    xcrun notarytool submit "$zip_path" \
        --keychain-profile "$NOTARYTOOL_PROFILE" \
        --wait \
        || log_error "Notarization failed. Make sure you have set up notarytool credentials with: xcrun notarytool store-credentials $NOTARYTOOL_PROFILE --apple-id YOUR_APPLE_ID --team-id $TEAM_ID"

    # Staple the notarization ticket
    xcrun stapler staple "$app_path" \
        || log_error "Stapling failed"

    # Clean up
    rm "$zip_path"

    log_success "App notarized and stapled successfully"
}

# Create DMG
create_dmg() {
    local version=$1
    local dmg_name="$APP_NAME-$version.dmg"
    local dmg_path="$BUILD_DIR/$dmg_name"
    local app_path="$EXPORT_PATH/$APP_NAME.app"

    # Use stderr for log messages so they don't get captured in output
    log_info "Creating DMG: $dmg_name..." >&2

    # Remove any existing DMG
    rm -f "$dmg_path"

    # Build create-dmg arguments
    local dmg_args=(
        --volname "$APP_NAME"
        --window-pos 200 120
        --window-size 600 400
        --icon-size 100
        --icon "$APP_NAME.app" 150 150
        --hide-extension "$APP_NAME.app"
        --app-drop-link 450 150
        --no-internet-enable
    )

    # Add notarization only if not skipped
    if [ "$SKIP_NOTARIZE" != true ]; then
        dmg_args+=(--notarize "$NOTARYTOOL_PROFILE")
    fi

    # Create DMG using create-dmg tool (redirect output to stderr)
    # This tool properly handles the Applications folder icon and layout
    create-dmg \
        "${dmg_args[@]}" \
        "$dmg_path" \
        "$app_path" >&2 \
        || log_error "DMG creation failed"

    log_success "DMG created: $dmg_path" >&2
    echo "$dmg_path"
}

# Generate release notes using Claude
generate_release_notes() {
    local version=$1
    # Use stderr for log messages so they don't get captured in output
    log_info "Generating release notes with Claude..." >&2

    # Get the previous tag
    local previous_tag
    previous_tag=$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null || echo "")

    local commit_range
    if [ -n "$previous_tag" ]; then
        commit_range="$previous_tag..HEAD"
        log_info "Analyzing commits from $previous_tag to HEAD" >&2
    else
        commit_range="HEAD~20..HEAD"
        log_info "No previous tag found, analyzing last 20 commits" >&2
    fi

    # Get commit history
    local commits
    commits=$(git -C "$PROJECT_ROOT" log "$commit_range" --pretty=format:"- %s (%h)" 2>/dev/null || echo "Initial release")

    # Use Claude to generate release notes
    local prompt="You are a technical writer creating release notes for a software product.

Generate professional release notes for version $version of ClaudeSettings, a macOS app for managing Claude Code settings.

IMPORTANT: This is an independent open source project. It is NOT affiliated with or built by Anthropic.

Here are the commits since the last release:
$commits

Requirements:
- Group changes by category (Features, Improvements, Bug Fixes) if applicable
- Explain what each change means for users (not just the technical details)
- Keep it concise but informative
- Use markdown formatting
- Maintain a professional, neutral tone throughout
- Do NOT include any commentary, opinions, jokes, or meta-text
- Do NOT include any preamble like 'Here are the release notes'
- Do NOT add any URLs or links
- Do NOT add 'for more information' sections or footer content
- Do NOT assume or mention who built the app
- Output ONLY the release notes content itself"

    local release_notes
    release_notes=$(claude -p "$prompt" 2>/dev/null) || {
        log_warning "Claude failed to generate release notes, using commit list instead"
        release_notes="## Changes

$commits"
    }

    echo "$release_notes"
}

# Create GitHub release
create_github_release() {
    local version=$1
    local dmg_path=$2
    local release_notes=$3
    local tag="v$version"

    log_info "Creating GitHub release $tag..."

    # Create release with notes and upload DMG
    gh release create "$tag" \
        --title "ClaudeSettings $version" \
        --notes "$release_notes" \
        "$dmg_path" \
        || log_error "GitHub release creation failed"

    log_success "GitHub release created: $tag"
}

# Bump version for next release
bump_version() {
    local current_version=$1
    local new_version
    new_version=$(increment_version "$current_version")

    local current_build
    current_build=$(get_build_number)
    local new_build=$((current_build + 1))

    log_info "Bumping version: $current_version -> $new_version (build $new_build)"

    # Update MARKETING_VERSION
    sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $new_version/" "$CONFIG_FILE"

    # Update CURRENT_PROJECT_VERSION
    sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $new_build/" "$CONFIG_FILE"

    # Commit the change
    git -C "$PROJECT_ROOT" add "$CONFIG_FILE"
    git -C "$PROJECT_ROOT" commit -m "Bump version to $new_version"

    log_success "Version bumped to $new_version (build $new_build)"
    log_warning "Remember to push the commit when ready: git push"
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  ClaudeSettings Release Script"
    echo "=========================================="
    echo ""

    # Check prerequisites
    check_prerequisites

    # Get current version
    local version
    version=$(get_version)
    log_info "Current version: $version"

    # Confirm with user
    echo ""
    read -p "Release version $version? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Release cancelled"
        exit 0
    fi

    # Build
    build_archive

    # Export
    export_archive

    # Notarize
    notarize_app

    # Create DMG
    local dmg_path
    dmg_path=$(create_dmg "$version")

    # Generate release notes
    local release_notes
    release_notes=$(generate_release_notes "$version")

    echo ""
    echo "Generated release notes:"
    echo "----------------------------------------"
    echo "$release_notes"
    echo "----------------------------------------"
    echo ""

    read -p "Proceed with GitHub release? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "GitHub release cancelled. DMG is available at: $dmg_path"
        exit 0
    fi

    # Create GitHub release
    create_github_release "$version" "$dmg_path" "$release_notes"

    # Bump version for next release
    bump_version "$version"

    # Clean up build folder
    log_info "Cleaning up build folder..."
    rm -rf "$BUILD_DIR"

    echo ""
    echo "=========================================="
    echo "  Release Complete!"
    echo "=========================================="
    echo ""
    echo "Released: ClaudeSettings $version"
    echo ""
    echo "Next steps:"
    echo "  - Review and push the version bump commit: git push"
    echo ""
}

# Run main
main
