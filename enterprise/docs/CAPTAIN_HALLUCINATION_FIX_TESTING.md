# Testing Guide: Captain Hallucination Fix

## Problem Fixed

**Issue**: Captain was responding to follow-up messages without searching documentation, leading to hallucinated answers based on training data.

**Example**:
- User: "My Ivy is having trouble connecting to Wifi"
- Captain: *searches docs* ✅ "First, make sure you're connecting Ivy to a 2.4 GHz Wi-Fi network..."
- User: "yes"
- Captain: *doesn't search* ❌ "Great! Next, ensure that your Wi-Fi password doesn't contain special characters like %..." (HALLUCINATED!)

## Changes Made

### 1. **Forced Search Enforcement** (NEW - Most Important!)
**File**: `enterprise/app/helpers/captain/chat_helper.rb`

- **Automatically forces documentation search** when continuation signals are detected
- Detects continuation words: "yes", "ok", "done", "next", "finished", etc.
- Only triggers in ongoing conversations (not first message)
- **Bypasses model's decision** - search happens regardless of what model wants
- Prevents models from ignoring system prompt instructions
- Works even with stubborn models like Qwen that skip tool calls

### 2. Clear Documentation Between Turns
**File**: `enterprise/app/helpers/captain/chat_helper.rb`

- Added logic to clear validator documentation at the start of each new user turn
- This prevents validation against stale documentation from previous turns
- Detects new turns by checking if last message is from user
- Sets conversation context (greeting vs ongoing) for smarter validation

### 3. Context-Aware Validation
**File**: `enterprise/app/services/captain/response_validator_service.rb`

- Distinguishes between **initial greeting** (first message) and **ongoing conversation**
- In ONGOING conversations: Almost ALL responses require documentation search
- In NEW conversations: Only greetings allowed without search
- Automatically detects conversation phase based on message history
- Much stricter validation for follow-up messages like "done", "yes", "ok"

### 4. Validate Fallback Responses
**File**: `enterprise/app/helpers/captain/chat_helper.rb`

- Added validation for non-JSON responses (fallback cases)
- Previously, validation was skipped when model returned plain text instead of JSON
- Now validates ALL responses, regardless of format

### 5. Smart System Prompt with Context Rules
**File**: `enterprise/app/services/captain/llm/system_prompts_service.rb`

- Only allows skipping search for standalone greetings at conversation start
- Explicitly requires search for ALL messages in ongoing conversations
- Includes specific rules for continuation words: "yes", "ok", "done", "next"
- Clear rule of thumb: "If unsure, SEARCH"

## Deployment

```bash
# Pull latest code
cd /home/chatwoot/chatwoot
git pull

# Restart workers (required for backend changes)
sudo systemctl restart chatwoot-worker

# Restart web (required for prompt changes)
sudo systemctl restart chatwoot-web
```

## Testing Steps

### Test 1: Simple Greeting (Should NOT Search)

1. Open Captain playground
2. Start conversation:

```
User: "hi"
Expected: Captain responds naturally WITHOUT searching: "Hello! How can I help you?"
```

### Test 2: Multi-Turn Troubleshooting (MUST Search Each Turn)

1. Open Captain playground
2. Start conversation:

```
User: "My Ivy is having trouble connecting to Wifi"
Expected: Captain searches and provides first troubleshooting step

User: "yes" or "ok"
Expected: Captain SEARCHES AGAIN and provides next step (not hallucinated info)

User: "done"
Expected: Captain SEARCHES AGAIN and provides next step (not hallucinated info)

User: "yes"
Expected: Captain SEARCHES AGAIN and provides next step
```

**Key Point**: Words like "yes", "ok", "done", "next" in an ongoing conversation are **continuation signals** that now **automatically trigger forced documentation search**, regardless of what the model wants to do. The model can no longer skip searching!

### Test 2: Check Logs

Watch the logs in real-time:

```bash
tail -f log/production.log | grep -A 20 "Response Validation"
```

**What to look for**:

#### Turn 1 (Initial Question)
```
Captain::Tools::SearchDocumentationService: Ivy trouble connecting to Wifi
ResponseValidator: Captured result from search_documentation
Response Validation:
Valid: true
Reason: Response appears to be based on documentation
Confidence: 0.8
Should Reject: false
Documentation content available: XXXX chars
```

#### Turn 2 (Follow-up "yes")
```
Starting new conversation turn - clearing previous documentation
ResponseValidator: Conversation context set to :ongoing (4 substantive messages)
Detected continuation signal: 'yes'
🔒 FORCED SEARCH: Detected continuation signal in ongoing conversation
Force searching with query: My Ivy is having trouble connecting to Wifi
Forced search returned XXXX chars of documentation
Captain::Tools::SearchDocumentationService: My Ivy is having trouble connecting to Wifi
ResponseValidator: Captured result from search_documentation
Response Validation:
Valid: true
Confidence: 0.8
Documentation content available: XXXX chars
```

**The model can NO LONGER skip the search** - it's now forced automatically!

### Test 3: Verify Tool Calls

Check that tools are being called:

```bash
grep "Captain::Tools::SearchDocumentationService" log/production.log | tail -n 20
```

You should see search calls for EACH user message, not just the first one.

### Test 4: Count Validations

```bash
# Count total validations
grep "Response Validation:" log/production.log | wc -l

# Count validations with no docs (should trigger rejection)
grep "Model provided substantive answer without searching" log/production.log | wc -l

# Count rejections
grep "VALIDATION REJECTED" log/production.log | wc -l
```

## Expected Behavior After Fix

### ✅ GOOD - What Should Happen

1. **Greetings Don't Need Search**:
   - User: "hi" → Captain responds naturally without search ✅
   - User: "hello" → Captain responds naturally without search ✅
   - User: "thank you" → Captain responds naturally without search ✅

2. **Product Questions MUST Search**:
   - Turn 1: User asks question → Captain searches → responds ✅
   - Turn 2: User says "yes" → **FORCED SEARCH** activated → searches → responds with next step ✅
   - Turn 3: User says "done" → **FORCED SEARCH** activated → searches → continues ✅
   
   **New behavior**: The system now **automatically forces** a search when it detects continuation signals, so the model can't skip it!

3. **Log Pattern for Product Questions**:
   ```
   Starting new conversation turn - clearing previous documentation
   Captain::Tools::SearchDocumentationService: [search query]
   ResponseValidator: Captured result from search_documentation
   Response Validation:
   Valid: true
   ```

4. **No Hallucinations**:
   - All product responses cite documentation
   - No made-up technical details (like "special characters in password")
   - No "general knowledge" phrases

### ❌ BAD - What Should NOT Happen

1. **Skipped Searches in Ongoing Conversation**:
   ```
   User: "My Ivy won't connect"
   Captain: [searches] "First, check 2.4 GHz..."
   User: "done"
   Captain: [NO SEARCH] "Great! Next, ensure password doesn't contain %..." ← HALLUCINATION!
   
   Response Validation:
   Valid: false
   Reason: Model responded in ongoing conversation without searching documentation
   Confidence: 0.1
   Should Reject: true
   ```

2. **Validation Against Old Docs**:
   ```
   [Turn 2 response, but still shows Turn 1 documentation length]
   ```

3. **Unvalidated Responses**:
   ```
   [Response logged, but NO validation section at all]
   ```

4. **Greeting Requires Search** (also bad):
   ```
   User: "hi"
   Captain: [searches for greeting] "I couldn't find that..." ← TOO STRICT!
   ```

## Troubleshooting

### Issue: Model Still Not Searching on Follow-ups

**Cause**: Model is too confident and ignoring system prompt

**Solution**: ✅ **SOLVED** with forced search enforcement!

The new forced search feature **automatically triggers** a search when continuation signals are detected, regardless of model behavior. This bypasses the model's decision entirely.

**If it's still not working**:
1. Check logs for `🔒 FORCED SEARCH` message
2. Verify code is deployed: `grep "should_force_search?" enterprise/app/helpers/captain/chat_helper.rb`
3. Restart workers: `sudo systemctl restart chatwoot-worker`

### Issue: Too Many Rejections

**Cause**: Validation is too aggressive

**Solutions**:
1. Lower `validation_strictness` to `lenient`
2. Review logs to see what's being flagged:
   ```bash
   grep "VALIDATION REJECTED" log/production.log -B 5 -A 5
   ```

### Issue: Validation Not Running

**Cause**: Code not deployed or workers not restarted

**Solutions**:
1. Verify file changes exist on server
2. Restart workers: `sudo systemctl restart chatwoot-worker`
3. Check for Ruby errors: `sudo systemctl status chatwoot-worker`

## Configuration Options

### Per-Assistant (UI)
- `validation_strictness`: `strict` | `moderate` | `lenient`
- `temperature`: `0.0` - `2.0` (lower = more deterministic)

### Global (Rails Console)
```ruby
# Set global validation strictness
InstallationConfig.create_or_find_by(name: 'CAPTAIN_VALIDATION_STRICTNESS') do |config|
  config.value = 'strict'  # or 'moderate', 'lenient'
end

# Set global default temperature
InstallationConfig.create_or_find_by(name: 'CAPTAIN_DEFAULT_TEMPERATURE') do |config|
  config.value = '0.7'
end
```

## Success Criteria

✅ **Fix is working if**:
1. Every user message triggers a `search_documentation` call
2. Every response has a validation log entry
3. No responses mention information not in documentation
4. Follow-up responses don't hallucinate details

❌ **Fix is NOT working if**:
1. Follow-up messages don't trigger searches
2. Validation logs missing for some responses
3. Responses still mention made-up technical details
4. Log shows "Documentation content available: 0 chars" for substantive answers

## Contact

If issues persist after following this guide, check:
1. All files were pulled from git
2. All services were restarted
3. No Ruby/syntax errors in logs
4. Model is actually calling tools (check API logs)

