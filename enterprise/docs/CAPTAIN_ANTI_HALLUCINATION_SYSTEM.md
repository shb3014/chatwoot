# Captain Anti-Hallucination System

**Version:** 1.0  
**Last Updated:** December 2025

## Overview

This document describes the multi-layered system designed to prevent AI hallucinations in the Captain assistant. The system ensures that all responses are grounded in actual documentation and prevents the model from making up information.

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Architecture Overview](#architecture-overview)
3. [Components](#components)
4. [Configuration](#configuration)
5. [How It Works](#how-it-works)
6. [Testing](#testing)
7. [Monitoring](#monitoring)
8. [Troubleshooting](#troubleshooting)

---

## Problem Statement

### Initial Issues

**Problem 1: Tool Calling Failure (Qwen Models)**
- Qwen models were receiving both `tools` and `response_format: { type: 'json_object' }` parameters
- This caused the model to return JSON content directly instead of using `tool_calls`
- Result: Search functionality completely broken

**Problem 2: Hallucinations**
- Models would answer questions without searching documentation
- Continuation signals ("yes", "done", "ok") would trigger responses without new searches
- Model would generate plausible but incorrect information
- Critical for support use cases where accuracy is paramount

**Problem 3: Handoff Confirmation Intercepted**
- When validation fails and offers handoff ("Would you like to speak with a support agent?")
- User confirmation ("yes") was being intercepted by forced search
- Instead of handing off to human, it would continue with more troubleshooting
- Result: User stuck in loop, unable to reach human agent

---

## Architecture Overview

The anti-hallucination system uses a **defense-in-depth** approach with multiple layers:

```
┌─────────────────────────────────────────────────────────────┐
│                     USER INPUT                              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 1: Context Tracking                                  │
│  • Determine if greeting or ongoing conversation            │
│  • Track conversation state                                 │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 2: Forced Search Enforcement (Proactive)             │
│  • Detect continuation signals ("yes", "done", etc.)        │
│  • Programmatically trigger search_documentation            │
│  • Inject results BEFORE model generates response           │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 3: System Prompt Engineering                         │
│  • Explicit instructions to use ONLY documentation          │
│  • Mandatory search rules for all queries                   │
│  • Citation requirements                                    │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 4: Low Temperature (0.1)                             │
│  • Reduces model creativity                                 │
│  • Increases adherence to instructions                      │
│  • Configurable per assistant                               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  LAYER 5: Response Validation (Reactive)                    │
│  • Analyze response against retrieved documentation         │
│  • Detect hallucination patterns                            │
│  • Reject responses that don't cite sources                 │
│  • Context-aware (stricter for ongoing conversations)       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                  VALIDATED RESPONSE                         │
└─────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Context Tracking (`ResponseValidatorService`)

**Purpose:** Differentiate between initial greetings and ongoing troubleshooting conversations.

**Key Methods:**
- `set_conversation_context(context)` - Set to `:greeting` or `:ongoing`
- Greeting context is more lenient (allows "Hello!" without search)
- Ongoing context is strict (requires search for all substantive responses)

**Location:** `enterprise/app/services/captain/response_validator_service.rb`

---

### 2. Forced Search Enforcement (`ChatHelper`)

**Purpose:** Programmatically trigger documentation searches when the model might skip them.

**Method:** LLM-based intent classification (v2.0) with pattern matching fallback

**How It Works:**

```ruby
# 1. Classify user message intent using LLM
def should_force_search?
  last_user_message = @messages.last&.dig(:content)
  
  # Use LLM to intelligently classify intent based on conversation context
  classification = classify_user_message_intent(last_user_message)
  
  case classification
  when 'continuation'
    # User completed step, ready for next (e.g., "yes", "done")
    Rails.logger.info "LLM classified as continuation - forcing search"
    return true
    
  when 'handoff_confirmation'
    # User confirming handoff request (e.g., "yes" after offer)
    Rails.logger.info "LLM classified as handoff confirmation - skipping forced search"
    return false
    
  when 'new_question'
    # User asking new question - let model decide
    Rails.logger.info "LLM classified as new question - letting model decide"
    return false
  end
end

# 2. LLM Classification with Context
def classify_user_message_intent(user_message)
  last_assistant_msg = @messages.reverse.find { |m| m[:role] == 'assistant' }
  assistant_content = extract_message_content(last_assistant_msg)
  
  classification_prompt = <<~PROMPT
    You are a conversation analyzer. Classify the user's response based on context.
    
    Assistant's last message: "#{assistant_content}"
    User's response: "#{user_message}"
    
    Classify the user's response as ONE of:
    - "continuation": User acknowledging completion of a step and ready to continue
    - "handoff_confirmation": User confirming they want to speak with a human agent (only if assistant offered handoff)
    - "new_question": User asking a new question or providing new information
    
    Respond with ONLY the classification keyword, nothing else.
  PROMPT
  
  # Call LLM with temperature 0.0 for deterministic classification
  classification_response = @client.chat(
    parameters: {
      model: classification_model,  # Can use lightweight/cheap model
      messages: [
        { role: 'system', content: 'You are a precise classifier. Respond with only the classification keyword.' },
        { role: 'user', content: classification_prompt }
      ],
      temperature: 0.0,
      max_tokens: 10
    }
  )
  
  classification_response.dig('choices', 0, 'message', 'content')&.strip&.downcase
rescue StandardError => e
  # Fallback to pattern matching if LLM fails
  Rails.logger.error "LLM classification error: #{e.message}, falling back to pattern matching"
  fallback_should_force_search(user_message)
end

# 3. Force search with original issue context (unchanged)
def force_documentation_search
  # Find the original user issue (first substantive message)
  original_query = find_original_user_query
  
  # Call search tool programmatically
  search_result = Captain::Tools::SearchDocumentationService.call(
    search_query: original_query,
    assistant: @assistant
  )
  
  # Inject results into message history
  messages << {
    role: 'assistant',
    content: '',
    tool_calls: [/* search tool call */]
  }
  messages << {
    role: 'tool',
    content: search_result,
    tool_call_id: tool_call_id
  }
  
  # Recursively call with enhanced context
  return request_chat_completion
end
```

**Benefits of LLM Classification:**
- ✅ **Context-aware:** Understands conversation flow
- ✅ **Multi-language:** Works in any language
- ✅ **Handles paraphrases:** "I've done that", "already tried", etc.
- ✅ **No pattern maintenance:** No need to update word lists
- ✅ **Graceful fallback:** Reverts to patterns if LLM fails

**Configuration:**
```ruby
# Use a lightweight model for classification (optional)
InstallationConfig.create!(
  name: 'CAPTAIN_CLASSIFICATION_MODEL',
  value: 'gpt-3.5-turbo'  # Fast, cheap, accurate
)
```

**Location:** `enterprise/app/helpers/captain/chat_helper.rb`
**Detailed Documentation:** [CAPTAIN_LLM_CLASSIFICATION.md](./CAPTAIN_LLM_CLASSIFICATION.md)

---

### 3. System Prompt Engineering (`SystemPromptsService`)

**Purpose:** Instruct the model explicitly on how to behave.

**Key Constraints:**

```markdown
[CRITICAL CONSTRAINT - INFORMATION SOURCE]
1. You MUST ONLY provide information found in the search_documentation results.
2. NEVER use general knowledge, training data, or assumptions.
3. If documentation doesn't contain the answer, explicitly state this.
4. ALWAYS cite sources using [[n](URL)] format.
5. If unsure, search again with refined query.

[CRITICAL SEARCH RULES]
- FIRST MESSAGE that is a pure greeting/thank you/goodbye: Search NOT required
- FIRST MESSAGE that is a question/issue: Search REQUIRED
- ALL SUBSEQUENT MESSAGES (including "yes", "done", "ok"): Search REQUIRED
- CONTINUATION WORDS in ongoing conversation: Search REQUIRED
```

**Location:** `enterprise/app/services/captain/llm/system_prompts_service.rb`

---

### 4. Response Validation Service

**Purpose:** Post-response validation as a safety net to catch hallucinations.

**Strictness Levels:**

| Level | Description | When Used |
|-------|-------------|-----------|
| **STRICT** | Rejects any response without explicit documentation citations | Production default |
| **MODERATE** | Allows some general phrasing but requires docs for specifics | Testing |
| **LENIENT** | Minimal validation, mainly syntax checking | Development |

**Validation Checks:**

1. **No Documentation Check:**
   - If no docs retrieved, response must acknowledge this
   - Must not provide specific troubleshooting steps

2. **Citation Check:**
   - All substantive responses must include `[[n](URL)]` citations
   - Exception: Pure greetings on first turn

3. **Hallucination Pattern Detection:**
   - Specific values not in docs (versions, URLs, commands)
   - Excessive detail beyond documentation
   - General knowledge phrases ("typically", "usually", "most systems")

4. **Context-Aware Validation:**
   - `:greeting` context: Lenient, allows simple greetings
   - `:ongoing` context: Strict, requires search + citations

**Validation Flow:**

```ruby
def validate_response(response_text)
  # 1. Context check
  if @conversation_context == :ongoing && !@captured_search
    return { valid: false, reason: "No search performed in ongoing conversation" }
  end
  
  # 2. Check for "no docs found" scenarios
  if get_documentation_content.strip.empty?
    return validate_no_docs_response(response_text)
  end
  
  # 3. Check for citations
  unless response_text.match?(/\[\[\d+\]\(https?:\/\/.+?\)\]/)
    return { valid: false, reason: "No documentation citations found" }
  end
  
  # 4. Detect hallucination patterns
  hallucinations = detect_hallucination_patterns(response_text, get_documentation_content)
  if hallucinations.any?
    return { valid: false, reason: "Hallucination detected", patterns: hallucinations }
  end
  
  { valid: true }
end
```

**Location:** `enterprise/app/services/captain/response_validator_service.rb`

---

### 5. Qwen Model Fix

**Problem:** Qwen models don't support `response_format` when `tools` are present.

**Solution:**

```ruby
def qwen_model?
  model_name.to_s.downcase.include?('qwen')
end

# In parameters
parameters[:response_format] = { type: 'json_object' } unless qwen_model? && tools.present?
```

**Locations:**
- `enterprise/app/helpers/captain/chat_helper.rb`
- `enterprise/lib/captain/llm_service.rb`

---

## Configuration

### Global Settings (Super Admin)

Configure in Super Admin UI or via `InstallationConfig`:

```ruby
# Validation strictness: 'strict', 'moderate', or 'lenient'
CAPTAIN_VALIDATION_STRICTNESS = 'strict'

# Model temperature: 0.0 (factual) to 1.0 (creative)
CAPTAIN_DEFAULT_TEMPERATURE = 0.1
```

### Per-Assistant Settings

Configure in Captain assistant settings:

```ruby
captain_assistant.update!(
  validation_strictness: 'strict',    # Override global setting
  temperature: 0.1                    # Override global temperature
)
```

### Environment Variables

```bash
# Optional: Override defaults
export CAPTAIN_VALIDATION_STRICTNESS=strict
export CAPTAIN_DEFAULT_TEMPERATURE=0.1
```

---

## How It Works

### Scenario 1: Initial Greeting

**User:** "hi"

1. **Context Tracking:** Set to `:greeting`
2. **Forced Search:** Skipped (greeting detected)
3. **Model Response:** "Hello! How can I help you with Ivy today?"
4. **Validation:** PASS (greeting allowed without search)

**Logs:**
```
[INFO] Conversation context set to: greeting
[INFO] Skipping forced search for greeting
[INFO] Response Validation: Valid: true (Greeting context)
```

---

### Scenario 2: User Query with Natural Search

**User:** "My Ivy won't connect to WiFi"

1. **Context Tracking:** Set to `:ongoing`
2. **Forced Search:** Skipped (model will naturally search)
3. **Model Action:** Calls `search_documentation("Ivy WiFi connection issues")`
4. **Validator:** Captures search results
5. **Model Response:** "First, ensure you're connecting to a 2.4 GHz network [[1](https://help...)]"
6. **Validation:** PASS (has citation, matches docs)

**Logs:**
```
[INFO] Conversation context set to: ongoing
[INFO] Tool call detected: search_documentation
[INFO] Captured search results (2 articles, 1500 chars)
[INFO] Response Validation: Valid: true
```

---

### Scenario 3: Continuation Signal (Core Feature)

**User:** "yes" (after previous question)

1. **Context Tracking:** Already `:ongoing`
2. **Forced Search Detection:** ✅ Triggered!
   - Detects "yes" as continuation signal
   - Ongoing conversation (2+ exchanges)
3. **Forced Search Execution:**
   - Finds original query: "My Ivy won't connect to WiFi"
   - Calls `search_documentation` programmatically
   - Injects results into message history
4. **Model Response:** Generated with fresh documentation context
5. **Validation:** PASS (has search + citations)

**Logs:**
```
[INFO] Detected continuation signal: 'yes'
[WARN] 🔒 FORCED SEARCH: Detected continuation signal in ongoing conversation
[INFO] Force searching with query: My Ivy won't connect to WiFi
[INFO] Injecting 2 search results into message history
[INFO] Response Validation: Valid: true
[INFO] Completed 200 OK
```

---

### Scenario 4: Validation Rejection (Safety Net)

**User:** "What's the battery life?"

1. **Model Action:** Calls `search_documentation`
2. **Search Result:** No articles found
3. **Model Response:** "The battery typically lasts 6-8 hours..." ❌
4. **Validation:** FAIL
   - Reason: "Response provides specifics without documentation"
   - Patterns: ["typically", "6-8 hours"]
5. **System Action:** Returns error, triggers retry or fallback

**Logs:**
```
[WARN] Response Validation: Valid: false
[WARN] Reason: Response provides specifics without documentation
[WARN] Patterns detected: ["typically (general knowledge)", "6-8 hours (specific value not in docs)"]
```

---

### Scenario 5: Handoff Confirmation (NEW - Fixes Problem 3)

**User:** "how to do that" (after documentation search failed)

1. **Validation:** No documentation found
2. **Model Response:** "I couldn't find that information in the documentation. Would you like to speak with a support agent?"
3. **User:** "yes"
4. **Context Detection:** ✅ `assistant_just_offered_handoff?` returns true
5. **Forced Search:** Skipped! (handoff context detected)
6. **Model Action:** Returns `{"response": "conversation_handoff"}`
7. **System Action:** Hands off to human agent

**Logs:**
```
[INFO] Detected continuation signal: 'yes'
[INFO] Skipping forced search - assistant offered handoff
[INFO] Response: conversation_handoff
[INFO] Triggering handoff to human agent
```

**Before Fix (Problem):**
- User says "yes" to handoff offer
- Forced search intercepts the confirmation
- Continues with more troubleshooting instead of handing off
- User stuck in loop

**After Fix (Solution):**
- `should_force_search?` checks `assistant_just_offered_handoff?`
- Skips forced search when handoff was offered
- Model processes "yes" as handoff confirmation
- Returns `conversation_handoff` response
- Successfully hands off to human

---

## Testing

### Manual Testing Procedure

See `enterprise/docs/CAPTAIN_HALLUCINATION_FIX_TESTING.md` for comprehensive test scenarios.

**Quick Test Cases:**

1. **Test: Greeting**
   ```
   User: hi
   Expected: Simple greeting, no search, validation passes
   ```

2. **Test: Query + Natural Search**
   ```
   User: How do I reset my Ivy?
   Expected: Model searches, provides answer with citations
   ```

3. **Test: Continuation Signal**
   ```
   User: My Ivy won't connect
   Captain: [asks follow-up]
   User: yes
   Expected: 🔒 FORCED SEARCH triggered, response with citations
   ```

4. **Test: No Documentation**
   ```
   User: What's the return policy?
   Expected: "I don't have documentation on that..."
   ```

### Automated Testing

Run existing specs:

```bash
bundle exec rspec spec/enterprise/services/captain/response_validator_service_spec.rb
bundle exec rspec spec/enterprise/helpers/captain/chat_helper_spec.rb
```

---

## Monitoring

### Key Log Indicators

**✅ System Working Correctly:**

```log
[INFO] Conversation context set to: ongoing
[WARN] 🔒 FORCED SEARCH: Detected continuation signal
[INFO] Force searching with query: [original issue]
[INFO] Response Validation: Valid: true
[INFO] Completed 200 OK
```

**⚠️ Validation Rejecting Responses:**

```log
[WARN] Response Validation: Valid: false
[WARN] Reason: No documentation citations found
```

**❌ System Issues:**

```log
[ERROR] Failed to force search: [error message]
[ERROR] Validator error: [error message]
```

### Metrics to Track

1. **Validation Pass Rate:** Should be > 95%
2. **Forced Search Trigger Rate:** Should increase with "yes"/"done" messages
3. **Search Coverage:** % of non-greeting messages that perform searches
4. **Response Time:** Should remain < 10s for most queries

### Production Monitoring

Add to your monitoring dashboard:

```ruby
# In ApplicationController or monitoring service
StatsD.increment('captain.validation.pass') if validation_result[:valid]
StatsD.increment('captain.validation.fail') unless validation_result[:valid]
StatsD.increment('captain.forced_search.triggered') if forced_search
StatsD.timing('captain.response_time', duration)
```

---

## Troubleshooting

### Issue: Model Still Hallucinating

**Symptoms:** Response contains information not in documentation

**Checks:**
1. Verify temperature is low (0.1 or 0.2)
   ```ruby
   captain_assistant.temperature # Should be 0.1
   ```

2. Check validation strictness
   ```ruby
   InstallationConfig.find_by(name: 'CAPTAIN_VALIDATION_STRICTNESS').value
   # Should be 'strict'
   ```

3. Check logs for forced search
   ```
   grep "FORCED SEARCH" production.log
   # Should see triggers for continuation signals
   ```

4. Verify validator is running
   ```
   grep "Response Validation" production.log
   # Should see validation on every response
   ```

**Solutions:**
- Lower temperature to 0.0
- Switch to `strict` validation
- Check if forced search is disabled (shouldn't be)

---

### Issue: Model Failing on Simple Greetings

**Symptoms:** "Hello" triggers validation failure

**Checks:**
1. Check conversation context
   ```
   grep "Conversation context set" production.log
   # First message should be :greeting
   ```

2. Check system prompt
   ```ruby
   # Should explicitly allow greetings without search on first turn
   ```

**Solutions:**
- Ensure `set_conversation_context(:greeting)` is called for first message
- Verify system prompt allows greetings without search

---

### Issue: Forced Search Not Triggering

**Symptoms:** "yes"/"done" responses don't trigger search

**Checks:**
1. Check if continuation signal is recognized
   ```ruby
   # In should_force_search?
   CONTINUATION_SIGNALS.include?(user_message.downcase)
   ```

2. Verify message history length
   ```ruby
   messages.length >= 2  # Need at least one exchange
   ```

3. Check message role keys
   ```ruby
   # Should use symbols, not strings
   m[:role] == 'user'  # ✅
   m['role'] == 'user' # ❌
   ```

**Solutions:**
- Add new continuation signals to `CONTINUATION_SIGNALS` array
- Ensure message history is properly maintained
- Verify role keys are symbols (`:role` not `'role'`)

---

### Issue: User Can't Reach Human After Saying "Yes" to Handoff

**Symptoms:** User confirms handoff request but gets more troubleshooting instead

**Checks:**
1. Check if forced search is intercepting handoff
   ```
   grep "Skipping forced search - assistant offered handoff" production.log
   # Should see this when user confirms handoff
   ```

2. Check assistant's last message before "yes"
   ```
   # Should contain handoff offer language
   "Would you like to speak with a support agent?"
   ```

3. Verify `assistant_just_offered_handoff?` logic
   ```ruby
   # Check patterns match your handoff offer text
   handoff_patterns = [
     'would you like to speak with',
     'speak with a support agent',
     'talk to a human'
   ]
   ```

**Solutions:**
- Ensure `assistant_just_offered_handoff?` method is implemented
- Add your handoff offer patterns if using custom wording
- Check that system prompt instructs model to return `conversation_handoff`
- Verify handoff detection runs before forced search

---

**Symptoms:** No response returned after continuation signal

**Checks:**
1. Check if `force_documentation_search` returns value
   ```ruby
   return force_documentation_search  # ✅ Must return!
   ```

2. Check recursive call returns
   ```ruby
   return request_chat_completion  # ✅ Must return!
   ```

**Solutions:**
- Ensure all methods in call chain have explicit `return` statements
- Check for early exits without returns

---

### Issue: Private Method Error

**Symptoms:** `NoMethodError: private method 'clear' called`

**Solution:**
```ruby
# In ResponseValidatorService
# Move 'clear' from private to public section
def clear
  @tool_results.clear
  @captured_search = false
end
```

---

## Best Practices

### For Developers

1. **Always test continuation signals** ("yes", "done", "ok")
2. **Monitor validation logs** in production
3. **Keep temperature low** (0.1-0.2) for factual domains
4. **Use strict validation** in production
5. **Add new continuation signals** as you discover them
6. **Test with actual user conversations** from support logs

### For System Administrators

1. **Set global defaults conservatively**
   - `CAPTAIN_VALIDATION_STRICTNESS = 'strict'`
   - `CAPTAIN_DEFAULT_TEMPERATURE = 0.1`

2. **Monitor forced search triggers**
   - Should see regular triggers in logs
   - If none, investigate continuation signal detection

3. **Track validation failures**
   - Occasional failures are normal (model testing boundaries)
   - Frequent failures indicate configuration issue

4. **Review model responses periodically**
   - Spot-check citations
   - Verify responses match documentation

### For Content Teams

1. **Keep documentation comprehensive**
   - More docs = better responses
   - Update regularly

2. **Use clear structure**
   - Well-organized docs = better search results

3. **Monitor "no documentation" responses**
   - Identify gaps in knowledge base

---

## Related Documentation

- [LLM-Based Intent Classification](./CAPTAIN_LLM_CLASSIFICATION.md) - **NEW v2.0** Intelligent classification system
- [Response Validation Details](./CAPTAIN_RESPONSE_VALIDATION.md)
- [Handoff Fix Details](./CAPTAIN_HANDOFF_FIX.md)
- [Testing Procedures](./CAPTAIN_HALLUCINATION_FIX_TESTING.md)
- [Enterprise Development](https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38)

---

## Changelog

### v2.0 (December 2025)
- ✅ **LLM-based intent classification**: Replaced pattern matching with intelligent AI classification
- ✅ Multi-language support for continuation/handoff detection
- ✅ Context-aware classification based on conversation flow
- ✅ Handles paraphrases and natural language variations
- ✅ Graceful fallback to pattern matching if LLM fails
- ✅ Cost-optimized with lightweight classification model option

### v1.1 (December 2025)
- ✅ **Handoff confirmation fix**: Skip forced search when assistant offers handoff
- ✅ Added `assistant_just_offered_handoff?` method to detect handoff context
- ✅ Updated system prompt to clarify handoff confirmation behavior
- ✅ Documentation updated with handoff scenario and troubleshooting

### v1.0 (December 2025)
- ✅ Qwen model tool calling fix
- ✅ System prompt hardening
- ✅ Response validation service
- ✅ Context-aware validation
- ✅ Forced search enforcement
- ✅ UI configuration options

---

## Support

If you encounter issues not covered in this document:

1. Check the troubleshooting section
2. Review related documentation
3. Check production logs for error patterns
4. Contact the Captain development team

---

**End of Document**

