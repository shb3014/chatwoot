# Captain Response Validation System

This document describes the response validation system that prevents hallucinations in Captain AI assistant responses.

## Overview

The validation system ensures that AI assistant responses only use information retrieved from documentation via the `search_documentation` tool, preventing the model from using its training data or making up information.

## How It Works

### 1. Tool Result Capture
When the assistant calls `search_documentation`, the results are captured and stored by `Captain::ResponseValidatorService`.

### 2. Response Validation
After the model generates a response, the validator checks:
- Whether the response acknowledges when no documentation was found
- If specific numbers/values in the response exist in the documentation
- If the response is suspiciously detailed given sparse documentation
- If the response uses "general knowledge" phrases suggesting training data use

### 3. Response Rejection or Warning
Based on validation results and strictness settings:
- **Reject**: Replace the response with a safe "I don't have that information" message
- **Warn**: Log warning but allow the response
- **Allow**: Response passes validation

## Strictness Levels

Configure via assistant config `validation_strictness`:

### `:strict` (Most Restrictive)
- Rejects responses with confidence < 0.7
- Best for critical applications where accuracy is paramount
- May produce more "I don't know" responses

### `:moderate` (Default, Recommended)
- Rejects responses with confidence < 0.4
- Balanced between accuracy and usability
- Catches obvious hallucinations while allowing reasonable responses

### `:lenient` (Most Permissive)
- Never rejects responses automatically
- Only logs warnings
- Use for testing or when human review is available

## Configuration

### Set Validation Strictness

```ruby
# In Rails console or during assistant setup
assistant = Captain::Assistant.find(YOUR_ASSISTANT_ID)
config = assistant.config || {}
config['validation_strictness'] = 'strict'  # or 'moderate', 'lenient'
assistant.update(config: config)
```

### Set Temperature (Also Important)

Lower temperature reduces creativity/hallucination:

```ruby
config['temperature'] = 0.3  # Range: 0.0 (most factual) to 1.0 (most creative)
assistant.update(config: config)
```

## Validation Indicators

The validator looks for these hallucination patterns:

1. **Specific values not in documentation**
   - Numbers, versions, technical specs mentioned but not in retrieved docs
   - Example: Saying "2000mAh battery" when docs only mention "long battery life"

2. **Excessive detail from sparse docs**
   - Response has 300+ characters when documentation is < 200 characters
   - Suggests model is adding information from training data

3. **General knowledge phrases**
   - "generally", "typically", "usually", "in most cases", "commonly"
   - These often indicate the model is using training data, not documentation

## Monitoring

Check logs for validation results:

```
Response Validation:
Valid: false
Reason: Possible hallucination detected: mentions specific values not in documentation
Confidence: 0.3
Should Reject: true
Strictness: moderate
```

## Best Practices

1. **Start with `:moderate` strictness** - Good balance for most use cases

2. **Monitor logs for warnings** - Review warnings to tune your documentation or strictness

3. **Combine with low temperature** - Use `temperature: 0.2-0.4` for factual responses

4. **Improve documentation coverage** - More comprehensive docs = fewer rejections

5. **Test with edge cases**:
   - Questions with no relevant documentation
   - Questions with partial information
   - Questions with complete documentation

## Troubleshooting

### Too Many Rejections
- Increase strictness to `:lenient` temporarily
- Check if documentation coverage is adequate
- Review rejected responses to see if validation is too aggressive

### Still Getting Hallucinations
- Decrease strictness to `:strict`
- Lower temperature to 0.2
- Review and strengthen system prompts
- Check if search_documentation is returning relevant results

### False Positives
The validator may flag legitimate responses if:
- Documentation uses different terminology than model response
- Numbers in docs are formatted differently (e.g., "2,000 mAh" vs "2000mAh")
- Response summarizes technical content appropriately

Adjust strictness or enhance the validator's pattern detection as needed.

## Code Locations

- **Validator Service**: `enterprise/app/services/captain/response_validator_service.rb`
- **Integration**: `enterprise/app/helpers/captain/chat_helper.rb`
- **System Prompts**: `enterprise/app/services/captain/llm/system_prompts_service.rb`

