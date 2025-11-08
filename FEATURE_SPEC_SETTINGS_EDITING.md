# Settings Editing System - Feature Specification

## Overview

This document specifies a comprehensive settings editing system for a macOS application that manages hierarchical settings files (similar to VS Code's settings architecture). The system allows users to view, edit, create, move, and delete settings across multiple configuration file types with different precedence levels.

## Background

The application displays settings from multiple JSON files with a precedence system:
- Enterprise settings (read-only, highest precedence)
- User global settings (writable)
- Project/workspace settings (writable)
- Project folder settings (writable, lowest precedence)

Settings can be:
- **Simple values**: strings, numbers, booleans
- **Complex values**: arrays, objects (nested structures)
- **Additive**: where values from multiple files combine (e.g., arrays)
- **Override**: where higher precedence files override lower precedence values

## Core Features

### 1. Transaction-Based Editing Mode

**Problem**: Making live edits to settings files while the app is running can cause conflicts with file watchers and make it hard to batch related changes.

**Solution**: Implement an editing mode that:

- Allows users to toggle the entire settings view into "editing mode"
- Pauses file watching while in editing mode to prevent conflicts
- Tracks all pending changes in memory without immediately writing to disk
- Provides clear "Save All" and "Cancel" actions
- Shows visual indicators for modified settings
- Validates all changes before saving
- Creates backups before writing any changes
- Uses atomic/transactional writes - either all changes succeed or none do
- Rolls back to previous state if any save operation fails

**User Experience**:
- Clear entry/exit from editing mode (toolbar toggle button)
- Visual distinction between editing and viewing modes
- Count of pending edits displayed in the UI
- Confirmation before discarding unsaved changes
- All-or-nothing saves with proper error handling

### 2. Inline Value Editing

**Problem**: Users need to modify settings values directly within the settings list without opening separate dialogs.

**Solution**: Provide inline editors for each value type:

#### String Values
- Direct text field editing
- Real-time validation as user types
- Auto-focus on edit mode entry

#### Numeric Values (Integers and Doubles)
- Specialized number input fields
- Type validation (prevent text in number fields)
- Range validation where applicable
- Proper handling of decimal vs integer types

#### Boolean Values
- Toggle switches for quick true/false changes
- Clear visual state indication

#### Complex Types (Arrays and Objects)
- JSON text editor with syntax awareness
- Real-time JSON validation
- Clear error messages for invalid JSON
- Pretty-printed display when valid
- Type safety - ensure edited JSON matches expected structure

**Change Detection**:
- Only track changes when values actually differ from original
- Automatically remove pending edits if user reverts to original value
- Compare against the source file's value, not the computed merged value

### 3. Multi-File Target Selection

**Problem**: Settings can exist in multiple files with different precedence. Users need to control which file their edits target.

**Solution**:

- Display all sources (file types) that contribute to a setting's value
- Allow users to select which file to edit when modifying a setting
- Default to the highest-precedence writable file
- Show clear indicators of which file will receive the edit
- Support creating new files if the target doesn't exist yet

**User Interface**:
- Dropdown or picker showing available target files
- Visual hierarchy indicating precedence order
- Distinguish between read-only (Enterprise) and writable files
- Show which file currently provides the active value

### 4. Settings Management Operations

#### Copy Settings Between Files

**Purpose**: Duplicate a setting from one file to another (e.g., promote a workspace setting to user global)

**Behavior**:
- Select source and destination file types
- Preserve the exact value structure
- Don't remove from source file
- Validate destination is writable
- Create destination file if it doesn't exist

#### Move Settings Between Files

**Purpose**: Transfer a setting from one file to another

**Behavior**:
- Combines copy + delete operations
- Atomic operation - if either step fails, neither completes
- Show clear feedback about the move
- Update UI to reflect new source

#### Delete Settings

**Purpose**: Remove a setting from a specific file

**Behavior**:
- Select which file to delete from (not all files)
- Show confirmation dialog with details:
  - Setting key being deleted
  - Current value
  - Source file
  - Impact on effective value (if other files still define it)
- Cannot delete from read-only files
- If deleting causes another file's value to become active, show this clearly

### 5. Inspector Panel Integration

**Problem**: Users need detailed information about selected settings and quick access to common operations.

**Solution**: Enhanced inspector panel that shows:

#### Setting Information
- Key (full dotted path)
- Current effective value
- All contributing files and their values
- Override indicators (which values are overridden)
- Color-coding by file type
- Documentation (if available)

#### Quick Actions
When NOT in editing mode:
- **Copy Value**: Copy the formatted value to clipboard
- **Copy to...**: Copy this setting to another file
- **Move to...**: Move this setting to another file
- **Delete**: Delete from specific file (with confirmation)

When in editing mode:
- Actions are disabled (to encourage batch operations)
- User must use inline editing

#### Contribution Display
For each file that contributes to a setting:
- File type indicator with color coding
- The specific value from that file
- Override status (grayed out if overridden)
- Precedence order (top to bottom = low to high)

### 6. Validation and Error Handling

**Real-Time Validation**:
- Validate as users type
- Show inline error messages
- Prevent saving when validation errors exist
- Type-specific validation (e.g., JSON syntax for complex types)

**Type Safety**:
- Ensure edits maintain expected types
- Clear error when trying to set incompatible types
- Special handling for type transitions (e.g., changing string to object)

**Error Messages**:
- Specific, actionable error descriptions
- Indicate which setting has the error
- Show validation errors in the edit interface
- Provide guidance on how to fix errors

**Pre-Save Validation**:
- Check all pending edits before writing
- Block save if any validation errors exist
- Show summary of errors preventing save
- Allow user to fix errors without losing other edits

### 7. Backup and Recovery

**Automatic Backups**:
- Create backup before any write operation
- One backup per file per save operation
- ISO 8601 timestamp in backup filename
- Store in standardized location: `~/Library/Application Support/ClaudeSettings/Backups/`

**Backup Naming**:
- Format: `{timestamp}-{original-filename}`
- Example: `2025-01-15T14:30:45Z-settings.json`

**Recovery Strategy**:
- On save failure, automatic rollback to previous state
- Backups remain available for manual recovery
- No UI for backup browsing (future enhancement)

### 8. File System Integration

**File Watching**:
- Pause file watching when entering editing mode
- Resume file watching after save completes or cancel
- Prevent external file changes from conflicting with pending edits

**File Creation**:
- Automatically create target file if it doesn't exist
- Use proper directory structure for each file type
- Set appropriate permissions

**Atomic Writes**:
- Use write-then-rename pattern for safety
- Ensure file consistency even if app crashes during save
- Proper handling of file system errors

### 9. Visual Design Requirements

**Editing Mode Indicators**:
- Toolbar shows "Edit" button (toggles to "Done"/"Cancel" in editing mode)
- Pending edit count badge
- Visual state change (background color, borders, etc.)
- Modified setting indicators (badges, highlights, or icons)

**Setting Row States**:
- Normal (not modified)
- Modified (has pending edit)
- Error (validation failed)
- Read-only (Enterprise settings)

**Color Coding**:
- Enterprise: Purple/violet
- User: Blue
- Workspace: Orange
- Folder: Green
- Consistent across all UI elements

**Responsive Layout**:
- Inspector panel adjusts to show all information
- Inline editors expand/collapse appropriately
- JSON editors provide adequate space for editing
- Tooltips for truncated content

## Technical Requirements

### State Management

**Editing State**:
- Boolean flag: `isEditingMode`
- Dictionary of pending edits: `[String: PendingEdit]`
- Each pending edit contains:
  - Setting key
  - New value
  - Target file type
  - Validation error (if any)
  - Raw editing text (for complex types being edited)

**Change Tracking**:
- Compare pending value against original value from target file
- Only store edit if value actually changed
- Remove pending edit if user reverts to original

### Data Structures

**Pending Edit Model**:
```
PendingEdit:
- key: String (the setting key, e.g., "editor.fontSize")
- value: SettingValue (the new value)
- targetFileType: SettingsFileType (which file to save to)
- validationError: String? (error message if validation failed)
- rawEditingText: String? (for JSON editing of complex types)
```

**Error Types**:
- File not found
- File is read-only
- Setting not found
- Validation failed (with details)
- Type mismatch (when editing nested values)

### Operations

**Core Operations**:
1. **Start Editing**: Enter editing mode, pause file watching
2. **Update Pending Edit**: Track a change in memory
3. **Cancel Editing**: Discard all pending edits, resume file watching
4. **Save All Edits**:
   - Validate all edits
   - Create backups
   - Write all changes atomically
   - Rollback on failure
   - Resume file watching on success

**File Operations**:
1. **Update Setting**: Modify value in specific file
2. **Delete Setting**: Remove key from specific file
3. **Copy Setting**: Duplicate to another file
4. **Move Setting**: Copy then delete atomically

**Helper Operations**:
- Set nested value (using dot notation for keys like "editor.font.size")
- Remove nested value (properly clean up empty parent objects)
- Validate value (type-specific validation)

### Nested Key Handling

Settings use dot notation for nesting (e.g., `"editor.font.size"`).

**Requirements**:
- Support arbitrary nesting depth
- Create intermediate objects as needed
- Validate type compatibility when traversing path
- Clean up empty parent objects when deleting nested values
- Proper error messages when type conflicts occur (e.g., trying to set `foo.bar` when `foo` is a string)

## User Workflows

### Workflow 1: Edit a Simple Setting

1. User clicks "Edit" button in toolbar
2. App enters editing mode, pauses file watching
3. User clicks on a string setting
4. Inline text field appears with current value
5. User modifies the text
6. App validates in real-time, shows any errors
7. User clicks "Save All"
8. App validates all edits, creates backup, writes file
9. App exits editing mode, resumes file watching
10. UI updates to show new value

### Workflow 2: Edit a Complex Setting (Array/Object)

1. User enters editing mode
2. User clicks on an array or object setting
3. JSON editor appears showing pretty-printed JSON
4. User edits the JSON text
5. App validates JSON syntax in real-time
6. If valid: app parses and stores the structured value
7. If invalid: app shows error message inline
8. User fixes error
9. User saves all edits
10. App writes properly structured data to file

### Workflow 3: Move a Setting to Different File

1. User selects a setting in the list
2. Inspector shows setting details and current file
3. User clicks "Move to..." button
4. Sheet appears with file type picker
5. User selects destination (e.g., move from Workspace to User)
6. Confirmation dialog shows impact
7. User confirms
8. App creates backup of both files
9. App copies value to destination, deletes from source
10. UI updates to show new source

### Workflow 4: Delete a Setting with Multiple Sources

1. User selects setting that exists in multiple files
2. Inspector shows all contributions from different files
3. User clicks delete button on specific contribution
4. Confirmation dialog appears showing:
   - "Delete 'editor.fontSize' from Workspace settings?"
   - "Current value: 14"
   - "After deletion, User settings value (12) will be active"
5. User confirms
6. App creates backup, deletes from specified file
7. UI updates to show the next value in precedence order is now active

### Workflow 5: Batch Edit Multiple Settings

1. User enters editing mode
2. User modifies setting A (string value)
3. User modifies setting B (number value)
4. User edits setting C (complex JSON)
5. Setting C has validation error
6. User attempts to save
7. App shows error: "Cannot save: validation error in setting C"
8. User fixes setting C
9. User saves all
10. App creates backups for all affected files
11. App writes all changes atomically
12. All three settings are updated
13. App exits editing mode

### Workflow 6: Error Recovery

1. User enters editing mode
2. User makes multiple edits
3. User clicks "Save All"
4. App begins saving
5. First file writes successfully
6. Second file write fails (disk full, permissions, etc.)
7. App automatically rolls back:
   - Restores in-memory state to pre-save state
   - First file changes are kept (backup exists)
8. Error message shown to user with specific failure reason
9. User remains in editing mode with all edits intact
10. User can fix issue and try again, or cancel

## Implementation Phases

### Phase 1: Core Infrastructure
- Pending edit state management
- Edit mode toggle
- Basic validation framework
- Backup creation

### Phase 2: Inline Editing
- String, number, boolean editors
- JSON editor for complex types
- Real-time validation
- Change detection

### Phase 3: Multi-File Operations
- Target file selection
- Copy/move/delete operations
- File creation for new targets

### Phase 4: Transaction System
- Atomic save all operation
- Rollback on failure
- File watching pause/resume

### Phase 5: UI Polish
- Visual indicators for modified state
- Error presentation
- Confirmation dialogs
- Loading states

## Edge Cases and Considerations

### Type Conflicts
**Scenario**: Setting `foo` is a string in one file, but user tries to set `foo.bar` in another file.
**Handling**: Detect the conflict, show error message explaining that `foo` must be an object to have nested properties, offer to replace the string with an object.

### Empty Objects After Deletion
**Scenario**: Deleting `editor.font.size` leaves `editor.font` as an empty object.
**Handling**: Automatically clean up empty parent objects after deletion.

### Concurrent External Changes
**Scenario**: User is in editing mode, external process modifies the file.
**Handling**: File watching is paused, so changes aren't detected until after save/cancel. Could detect on save and offer to reload or keep edits.

### Large JSON Values
**Scenario**: Setting contains a very large array or deeply nested object.
**Handling**: JSON editor should handle large content gracefully, possibly with syntax highlighting and scrolling. Consider size limits or warnings.

### Read-Only Enterprise Settings
**Scenario**: User tries to edit an Enterprise setting.
**Handling**: Disable editing UI entirely for Enterprise settings. Show information that they're read-only and why.

### Validation During Editing
**Scenario**: User is typing JSON and it's temporarily invalid.
**Handling**: Don't prevent intermediate invalid states, but clearly show errors and prevent saving until valid.

### Missing Target Files
**Scenario**: User wants to edit in User settings, but file doesn't exist yet.
**Handling**: Automatically create the file in the correct location when saving, show clear indication that file will be created.

## Success Criteria

1. **Data Integrity**: No data loss, corruption, or inconsistent states
2. **User Confidence**: Clear feedback at every step, undo capability, confirmations for destructive actions
3. **Performance**: Editing feels instant, validation doesn't block UI
4. **Reliability**: Automatic backups, rollback on errors, graceful error handling
5. **Usability**: Intuitive workflows, minimal clicks for common operations, inline editing reduces context switching
6. **Consistency**: Visual design matches macOS patterns, behavior matches VS Code settings where applicable

## Future Enhancements (Out of Scope)

- Search/filter while in editing mode
- Diff view comparing file values
- Restore from backup UI
- Bulk operations (edit multiple settings at once)
- Keyboard shortcuts for common operations
- Drag-and-drop to move settings between files
- Undo/redo within editing session
- Setting templates or presets
- Import/export settings
- Conflict resolution UI for concurrent external changes
