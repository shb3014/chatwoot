# Captain Installation Config Setup

This document describes the global Captain configuration options available in the Super Admin panel.

## Accessing Settings

1. Log in as Super Admin
2. Navigate to: **Super Admin → App Configs → Captain**

## New Settings Added

### CAPTAIN_VALIDATION_STRICTNESS

**Description**: Sets the default validation strictness for all assistants (can be overridden per-assistant).

**Valid Values**:
- `strict` - Most restrictive, rejects responses with confidence < 0.7
- `moderate` - Balanced approach, rejects responses with confidence < 0.4 (recommended)
- `lenient` - Only logs warnings, never rejects responses

**Default**: `moderate`

**Recommendation**: Start with `moderate`. If you experience too many "I don't know" responses, switch to `lenient`. If hallucinations persist, use `strict`.

### CAPTAIN_DEFAULT_TEMPERATURE

**Description**: Sets the default temperature for LLM responses across all assistants (can be overridden per-assistant).

**Valid Values**: `0.0` to `1.0`
- `0.0` - Most factual and deterministic
- `0.3` - **Recommended for documentation-based assistants**
- `0.7` - Balanced creativity and accuracy
- `1.0` - Most creative and varied

**Default**: `1.0`

**Recommendation**: Set to `0.3` for factual, documentation-based responses.

## Setting Up via Rails Console

If you prefer to set these via Rails console instead of the UI:

```ruby
# Set validation strictness
InstallationConfig.find_or_create_by(name: 'CAPTAIN_VALIDATION_STRICTNESS') do |config|
  config.value = 'moderate'  # or 'strict', 'lenient'
  config.locked = false
end

# Set default temperature
InstallationConfig.find_or_create_by(name: 'CAPTAIN_DEFAULT_TEMPERATURE') do |config|
  config.value = '0.3'
  config.locked = false
end
```

## Priority / Override Behavior

The system follows this priority order:

1. **Per-Assistant Config** (set in Assistant Settings)
2. **Global InstallationConfig** (set in Super Admin → App Configs → Captain)
3. **Hardcoded Defaults** (moderate for strictness, 1.0 for temperature)

### Example:

```
Assistant A:
  - Has validation_strictness: 'strict' in config
  - Uses: STRICT (from assistant config)

Assistant B:
  - Has no validation_strictness in config
  - Global CAPTAIN_VALIDATION_STRICTNESS = 'moderate'
  - Uses: MODERATE (from global config)

Assistant C:
  - Has no validation_strictness in config
  - No global CAPTAIN_VALIDATION_STRICTNESS set
  - Uses: MODERATE (hardcoded default)
```

## Recommended Initial Setup

After deployment, configure these globally:

1. **Go to**: Super Admin → App Configs → Captain
2. **Add**:
   - `CAPTAIN_VALIDATION_STRICTNESS` = `moderate`
   - `CAPTAIN_DEFAULT_TEMPERATURE` = `0.3`
3. **Save**

Then test with your assistants. Adjust per-assistant if needed in:
- Captain → Assistants → [Your Assistant] → System Settings

## Verification

Check current settings:

```ruby
# In Rails console
puts "Validation Strictness: #{InstallationConfig.find_by(name: 'CAPTAIN_VALIDATION_STRICTNESS')&.value || 'not set (using default: moderate)'}"
puts "Default Temperature: #{InstallationConfig.find_by(name: 'CAPTAIN_DEFAULT_TEMPERATURE')&.value || 'not set (using default: 1.0)'}"

# Check what an assistant will actually use
assistant = Captain::Assistant.first
strictness = assistant.config['validation_strictness'] ||
             InstallationConfig.find_by(name: 'CAPTAIN_VALIDATION_STRICTNESS')&.value ||
             'moderate'
temperature = assistant.config['temperature'] ||
              InstallationConfig.find_by(name: 'CAPTAIN_DEFAULT_TEMPERATURE')&.value&.to_f ||
              1.0

puts "Assistant '#{assistant.name}' will use:"
puts "  Validation Strictness: #{strictness}"
puts "  Temperature: #{temperature}"
```

## Troubleshooting

### Settings Not Appearing in UI

1. Make sure you're logged in as Super Admin
2. Check that you're on an Enterprise plan (these are enterprise features)
3. Try clearing cache and reloading
4. Check logs for any errors

### Settings Not Taking Effect

1. Verify the InstallationConfig record exists: `InstallationConfig.find_by(name: 'CAPTAIN_VALIDATION_STRICTNESS')`
2. Check the value is valid: should be 'strict', 'moderate', or 'lenient'
3. Restart workers: `sudo systemctl restart chatwoot-worker`
4. Check logs for validation messages during assistant responses

### Still Getting Hallucinations

If validation is set but still seeing hallucinations:

1. **Increase strictness**: Change to `strict`
2. **Lower temperature**: Set to `0.2` or `0.3`
3. **Check documentation coverage**: Ensure relevant docs are indexed
4. **Review logs**: Look for "VALIDATION WARNING" messages
5. **Per-assistant override**: Set stricter settings on specific assistants

## Migration Notes

These settings were added in the anti-hallucination update. Existing installations should:

1. Add the new config options to Super Admin → Captain
2. Set recommended values (moderate, 0.3)
3. Test with various questions
4. Adjust based on your specific needs

