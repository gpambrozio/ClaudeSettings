Synchronize the settings documentation JSON file with the official Claude Code settings schema from schemastore.org.

## Process

1. **Fetch the latest schema**:
   - Fetch from https://www.schemastore.org/claude-code-settings.json
   - Parse and analyze the schema structure

2. **Look at the documentation**:
   - Look at https://code.claude.com/docs/en/settings for the official documentation and examples

2. **Update existing fields** in `ClaudeSettingsPackage/Sources/ClaudeSettingsFeature/Resources/settings-documentation.json`:
   - Compare descriptions - use schema or documentation version if clearer
   - Compare examples - use schema  or documentation examples if better
   - Add `enumValues` for fields with `enum` constraints (enables dropdown UI)
   - Add validation constraints: `minLength`, `minimum`, `uniqueItems`, `itemMinLength`
   - Update type definitions (e.g., `number` → `integer`)
   - Mark deprecated fields with `deprecated: true`

3. **Add missing fields**:
   - Identify fields present in schema but missing from our documentation
   - Add them to the appropriate category with description and examples
   - Generate UUIDs for example IDs
   - Add missing fields in a way that reduces the diff to make it easier to review

4. **Validate the result**:
   - Ensure JSON is valid
   - Verify all schema fields are documented

## Key Schema Properties to Extract

When synchronizing, extract these properties from the official schema:

- `type` - Data type (string, boolean, integer, object, array)
- `description` - Human-readable description
- `enum` - Allowed values (becomes `enumValues` in our JSON)
- `const` - Single allowed value
- `minLength`, `minimum` - Validation constraints
- `uniqueItems` - Array uniqueness constraint
- `itemMinLength` - Minimum length for array items
- `format` - Special formats (uuid, etc.)
- `default` - Default value (becomes `defaultValue`)
- `examples` - Usage examples
- `deprecated` - Deprecation status
- `required` - Required properties for objects
- `properties` - Object property definitions

## Expected Outcome

The settings-documentation.json file should be fully synchronized with the official schema, ready to commit.
