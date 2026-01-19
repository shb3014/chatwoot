# Captain Handoff Confirmation Fix

**Version:** 1.1  
**Date:** December 29, 2025  
**Issue:** Users unable to reach human agents after confirming handoff request

---

## Problem Description

### Observed Behavior

When Captain's validation system detects it cannot help (no documentation found), it offers to connect the user with a human agent:

```
Captain: "I couldn't find that information in the documentation. Would you like to speak with a support agent?"
User: "yes"
```

**Expected:** Hand off to human agent  
**Actual:** Captain continues with more troubleshooting steps

### Root Cause

The **forced search enforcement** system (designed to prevent hallucinations) was intercepting the user's "yes" response:

1. User says "yes" (a continuation signal)
2. `should_force_search?` detects "yes" as continuation signal
3. Forces a documentation search
4. Model responds with more troubleshooting steps
5. **Handoff never happens**

The system didn't have **context awareness** to distinguish between:
- "yes" = continue troubleshooting
- "yes" = confirm handoff request

---

## Solution

### Code Changes

#### 1. Added Handoff Context Detection (`chat_helper.rb`)

**File:** `enterprise/app/helpers/captain/chat_helper.rb`

Added new method to detect when assistant offers handoff:

```ruby
def assistant_just_offered_handoff?
  last_assistant_msg = @messages.reverse.find do |m|
    role = m[:role] || m['role']
    role == 'assistant'
  end
  
  return false unless last_assistant_msg
  
  content = last_assistant_msg[:content] || last_assistant_msg['content']
  
  # Handle JSON-formatted content
  if content.is_a?(String) && content.strip.start_with?('{')
    begin
      parsed = JSON.parse(content)
      content = parsed['response'] || parsed[:response] || content
    rescue JSON::ParserError
      # Use as-is
    end
  end
  
  return false unless content.is_a?(String)
  
  # Check for handoff offer patterns
  handoff_patterns = [
    'would you like to speak with',
    'would you like to talk to',
    'connect you with',
    'transfer you to',
    'speak with a support agent',
    'talk to a human',
    'human agent',
    'support agent',
    'handoff'
  ]
  
  content_lower = content.downcase
  handoff_patterns.any? { |pattern| content_lower.include?(pattern) }
end
```

#### 2. Updated Forced Search Logic (`chat_helper.rb`)

Modified `should_force_search?` to skip forced search when handoff was offered:

```ruby
def should_force_search?
  return false unless @messages.length > 2
  return false unless @tool_registry&.respond_to?(:search_documentation)
  
  last_user_message = (@messages.last&.dig(:content) || @messages.last&.dig('content'))&.strip&.downcase
  return false if last_user_message.nil?
  
  continuation_signals = [
    'yes', 'yep', 'yeah', 'yup', 'ok', 'okay', 'sure',
    'done', 'finished', 'completed', 'ready',
    'next', 'continue', 'go on', 'proceed',
    'i did', "i've done", 'all set'
  ]
  
  is_continuation = continuation_signals.any? { |signal| 
    last_user_message == signal || last_user_message.start_with?(signal) 
  }
  
  if is_continuation
    # NEW: Check if assistant just offered handoff
    if assistant_just_offered_handoff?
      Rails.logger.info "Detected continuation signal '#{last_user_message}' but assistant offered handoff - skipping forced search"
      return false
    end
    
    Rails.logger.info "Detected continuation signal: '#{last_user_message}'"
    return true
  end
  
  false
end
```

#### 3. Enhanced System Prompt (`system_prompts_service.rb`)

**File:** `enterprise/app/services/captain/llm/system_prompts_service.rb`

Updated instructions to be more explicit about handoff confirmation:

```markdown
- If the answer is not provided in the documentation returned by search_documentation, you MUST respond: "I couldn't find that information in the documentation. Would you like to speak with a support agent who can help you further?"
- If the user explicitly requests to chat with another agent (e.g., "connect me with an agent", "I need human help", "talk to support"), return `conversation_handoff` as the response in JSON.
- If you previously offered handoff ("Would you like to speak with a support agent?") and the user confirms with "yes", "sure", "okay" or similar, return `conversation_handoff` as the response. Do NOT provide additional troubleshooting steps.
- NEVER make up information or use your training data. Only use what's in the search_documentation results.
```

---

## How It Works

### Flow with Fix

```
User: "how to do that"
   ↓
Assistant: [searches documentation]
   ↓
Validation: No relevant docs found
   ↓
Assistant: "I couldn't find that information in the documentation. 
           Would you like to speak with a support agent?"
   ↓
User: "yes"
   ↓
should_force_search? checks:
   ✓ Is "yes" a continuation signal? → YES
   ✓ Did assistant offer handoff? → YES
   → SKIP forced search
   ↓
Model processes "yes" naturally:
   - Recognizes handoff context
   - Returns {"response": "conversation_handoff"}
   ↓
ResponseBuilderJob:
   - Detects handoff_requested? → true
   - Calls conversation.bot_handoff!
   ↓
✅ User successfully connected to human agent
```

### Before vs After

| Scenario | Before Fix | After Fix |
|----------|-----------|-----------|
| User confirms handoff | Forced search → More troubleshooting | Handoff executed |
| User continues troubleshooting | Forced search → Next steps | Forced search → Next steps |
| User says "yes" after step completion | Forced search → Next steps | Forced search → Next steps |

---

## Testing

### Manual Test

1. **Start conversation with unsolvable issue:**
   ```
   User: "How do I configure the quantum flux capacitor?"
   ```

2. **Captain should offer handoff** (if no docs found):
   ```
   Captain: "I couldn't find that information in the documentation. 
            Would you like to speak with a support agent?"
   ```

3. **Confirm handoff:**
   ```
   User: "yes"
   ```

4. **Expected result:**
   - Conversation status changes to `open`
   - Bot handoff triggered
   - No additional troubleshooting steps

5. **Check logs:**
   ```
   grep "Skipping forced search - assistant offered handoff" logs/production.log
   grep "handoff_requested?" logs/production.log
   ```

### Edge Cases to Test

1. **Handoff confirmation with different words:**
   - "sure", "okay", "yeah", "yep"
   - All should trigger handoff

2. **Similar language but different context:**
   ```
   User: "Will you speak with my manager about this?"
   ```
   - Should NOT trigger handoff detection
   - Pattern must be in assistant's message, not user's

3. **Multiple handoff patterns:**
   - "Would you like to talk to a human?"
   - "I can connect you with a support agent"
   - "Let me transfer you to our team"
   - All should be detected

---

## Configuration

No configuration changes required. The fix works automatically with existing settings.

### Customizing Handoff Patterns

If your organization uses different handoff offer language, add patterns to the `handoff_patterns` array in `assistant_just_offered_handoff?`:

```ruby
handoff_patterns = [
  'would you like to speak with',
  'speak with a support agent',
  'talk to a human',
  # Add your custom patterns:
  'connect you with our team',
  'escalate to a specialist'
]
```

---

## Monitoring

### Key Metrics

1. **Handoff Success Rate:**
   - Count: Handoffs triggered after validation failure
   - Should increase after fix

2. **Forced Search Skip Rate:**
   - Count: Times forced search was skipped due to handoff context
   - Track with: `grep "Skipping forced search - assistant offered handoff"`

3. **False Handoff Blocks:**
   - Times system incorrectly detected handoff offer
   - Should be zero - investigate if pattern matching is too broad

### Log Indicators

**✅ Working Correctly:**
```log
[INFO] Detected continuation signal 'yes' but assistant offered handoff - skipping forced search
[INFO] handoff_requested? true
[INFO] Conversation bot_handoff! triggered
```

**⚠️ Potential Issues:**
```log
[INFO] Detected continuation signal: 'yes'
[WARN] 🔒 FORCED SEARCH: Detected continuation signal
[INFO] Force searching with query: ...
```
(If this happens after handoff offer, the pattern matching may need adjustment)

---

## Troubleshooting

### Issue: Handoff Still Not Working

**Check 1:** Verify handoff offer text matches patterns
```ruby
# In Rails console
last_response = "Your assistant's response text here"
patterns = ['would you like to speak with', 'speak with a support agent', 'talk to a human']
patterns.any? { |p| last_response.downcase.include?(p) }
# Should return true
```

**Check 2:** Ensure response is formatted correctly
```ruby
# Assistant should return:
{
  "response": "conversation_handoff",
  "reasoning": "User confirmed handoff request"
}
```

**Check 3:** Verify system prompt is active
```ruby
# Check that system prompt includes handoff instructions
Captain::Llm::SystemPromptsService.assistant_response_generator('Captain', 'Product', {})
# Should contain: "return `conversation_handoff` as the response"
```

### Issue: False Positives (Wrong Handoff Detection)

If the system incorrectly detects handoff offers, narrow the patterns:

```ruby
# More specific patterns
handoff_patterns = [
  'would you like to speak with a support agent',  # More specific
  'connect you with a human agent'                 # More specific
]

# Instead of:
handoff_patterns = [
  'speak with',  # Too broad
  'agent'        # Too broad
]
```

---

## Related Documentation

- [CAPTAIN_ANTI_HALLUCINATION_SYSTEM.md](./CAPTAIN_ANTI_HALLUCINATION_SYSTEM.md) - Full system documentation
- [CAPTAIN_RESPONSE_VALIDATION.md](./CAPTAIN_RESPONSE_VALIDATION.md) - Validation details
- [CAPTAIN_HALLUCINATION_FIX_TESTING.md](./CAPTAIN_HALLUCINATION_FIX_TESTING.md) - Testing procedures

---

## Impact

### User Experience

- ✅ Users can successfully reach human agents when needed
- ✅ No more infinite loops when documentation is insufficient
- ✅ Clear handoff flow when Captain cannot help

### System Behavior

- ✅ Maintains forced search for genuine troubleshooting continuations
- ✅ Context-aware decision making
- ✅ No performance impact (simple pattern matching)

### Metrics (Expected)

- Handoff success rate: Should approach 100%
- User satisfaction: Should increase (can reach humans)
- Conversation abandonment: Should decrease

---

**End of Document**


