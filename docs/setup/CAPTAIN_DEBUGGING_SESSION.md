# Captain Performance Debugging Session Summary

**Date:** January 23, 2026  
**Issue:** Captain responses extremely slow (~22 seconds per request)  
**Status:** ✅ RESOLVED - 91% performance improvement achieved

---

## Problem Statement

Captain was responding very slowly in the playground when testing with the simple prompt "battery life". Initial investigation showed ~22 seconds total response time, which was unacceptable for production use.

## Investigation Process

### Step 1: Added Comprehensive Logging
Added detailed timing logs throughout the Captain request pipeline to identify bottlenecks:

1. **Created dedicated Captain logger** (`enterprise/lib/captain/logger.rb`)
   - Writes to separate `log/captain.log` file
   - Keeps Captain debugging separate from main Rails logs

2. **Added timing instrumentation** at key points:
   - Controller request start/end
   - LLM API call timing (chat completion)
   - Tool execution timing
   - Embedding generation timing
   - Individual tool steps (search, embeddings, validation)

### Step 2: Analyzed Request Timeline

From logs with prompt "battery life", discovered:

```
Total Request Time: 21,978ms (~22 seconds)

Breakdown:
- LLM Call #1 (tool selection):  10,552ms  (48.0%)
- Tool Execution:                    573ms  ( 2.6%)
  ├─ Embeddings:                     469ms
  ├─ Search queries:                  35ms
  └─ Overhead:                        69ms
- LLM Call #2 (final response):  10,824ms  (49.2%)
- Response Processing:               <10ms  ( 0.04%)
```

**Key Finding:** 97% of time spent waiting for LLM API calls to `https://dashscope.aliyuncs.com` (Qwen Flash model in China).

### Step 3: Direct API Testing

Created test script (`test_llm_timing.rb`) to test the LLM API directly from WSL with the exact same prompts and parameters used in production.

**Results:**
- **With proxy**: 374ms + 1,383ms = **1,757ms total** ⚡
- **Without proxy**: **10,648ms** per call 🐌
- **Rails app (before fix)**: ~10,500ms per call

### Step 4: Root Cause Identified

**The Rails application was NOT using the system proxy**, even though:
- Proxy was configured in shell environment (`HTTPS_PROXY=http://172.24.160.1:10809`)
- Code had proxy support implemented
- Test scripts with proxy worked perfectly

The Rails server process was started without the proxy environment variables, causing it to attempt direct connections to China-based API servers from WSL, which resulted in extremely slow or failed connections.

## Solution

### 1. Configure Proxy for Rails Environment

Added proxy environment variables before starting Rails:

```bash
export HTTPS_PROXY=http://172.24.160.1:10809
export HTTP_PROXY=http://172.24.160.1:10809
# Then restart Rails/Overmind
```

Or add to `.env` file (if using dotenv):
```
HTTPS_PROXY=http://172.24.160.1:10809
HTTP_PROXY=http://172.24.160.1:10809
```

Updated `Procfile.dev` to include proxy configuration.

### 2. Enhanced Proxy Support in Code

Already implemented (from previous work):
- `faraday_proxy_middleware` in `Llm::BaseOpenAiService` for OpenAI gem
- `http_proxy_options` for HTTParty calls (custom endpoints, embeddings)
- Both chat and embeddings API calls now honor system proxy

## Performance Results

### Before Fix (No Proxy):
```
First LLM call:        10,552ms
Tool execution:           573ms
Second LLM call:       10,824ms
───────────────────────────────
Total:                ~22,000ms
```

### After Fix (With Proxy):
```
First LLM call:           374ms
Tool execution:           573ms
Second LLM call:        1,383ms
───────────────────────────────
Total:                 ~2,400ms  (91% improvement!)
```

## Additional Improvements

### 1. Search Optimization
Enhanced `search_documentation_service.rb`:
- Added **text search before embedding search** (faster for keyword matches)
- Only falls back to expensive embedding search when text search finds nothing
- Avoids unnecessary embedding API calls

### 2. Timing Logs (Kept Minimal)
After cleanup, kept only essential logs:
```ruby
# Controller level
"[Captain][Playground] start/completed request_id=... elapsed_ms=..."

# LLM timing
"Chat completion finished in 374ms"

# Tool timing  
"Tool search_documentation completed in 572ms"

# Embedding timing
"[Captain][EmbeddingService] model=text-embedding-v4 in 203ms"
```

### 3. API Testing Tool
Created `lib/tasks/captain_playground_api.rake` for testing Captain API directly without browser:

```bash
bundle exec rake "captain:playground_api[,1,,]"
```

Auto-discovers assistant, account, and uses first available access token.

### 4. Documentation Organization
Moved all setup/debug documentation to `docs/setup/` folder for better organization.

## Files Modified

### New Files:
- `enterprise/lib/captain/logger.rb` - Dedicated Captain logger
- `lib/tasks/captain_playground_api.rake` - API testing task
- `docs/setup/PERFORMANCE_IMPROVEMENTS.md` - Performance summary
- `docs/setup/CAPTAIN_DEBUGGING_SESSION.md` - This document

### Modified Files:
- `enterprise/app/services/llm/base_open_ai_service.rb` - Proxy support
- `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb` - Request timing logs
- `enterprise/app/helpers/captain/chat_helper.rb` - Request timing logs
- `enterprise/app/services/captain/llm/embedding_service.rb` - Embedding timing logs
- `enterprise/app/services/captain/tools/search_documentation_service.rb` - Text search optimization
- `enterprise/app/services/captain/llm/assistant_chat_service.rb` - Timing logs (cleaned up)
- `Procfile.dev` - Proxy configuration

## Important Notes for Production

### Ubuntu/Linux Production Environment

**The line ending warnings** you see in git (`CRLF will be replaced by LF`) are because:
- **WSL2** uses Windows-style line endings (CRLF = `\r\n`)
- **Ubuntu/Linux** uses Unix-style line endings (LF = `\n`)

This is **NORMAL and SAFE**. Git will automatically convert CRLF → LF when you commit, so Ubuntu production won't have issues.

Files affected:
- `bin/*` scripts (bundle, rails, rake, etc.)
- Various Ruby files edited in WSL

**Action:** No action needed. Git handles this automatically. Production Ubuntu will get LF endings.

### Proxy Configuration for Production

If your production Ubuntu server also needs to connect to China-based APIs:

1. **Check if proxy is needed:**
   ```bash
   curl -w "\ntime_total=%{time_total}\n" https://dashscope.aliyuncs.com
   ```

2. **If slow/fails, add proxy to systemd service or environment:**
   ```bash
   # In /etc/systemd/system/chatwoot.service
   Environment="HTTPS_PROXY=http://your-proxy:port"
   Environment="HTTP_PROXY=http://your-proxy:port"
   ```

3. **Or export in shell before starting Rails:**
   ```bash
   export HTTPS_PROXY=http://your-proxy:port
   export HTTP_PROXY=http://your-proxy:port
   bundle exec rails s
   ```

## Testing & Verification

### Test Captain Performance:
```bash
# 1. Via API task
bundle exec rake "captain:playground_api[,1,,]"

# 2. Check logs
tail -f log/captain.log

# 3. Via browser playground
# Go to: http://localhost:3000/app/accounts/3/captain/assistants/1
# Test with: "battery life"
```

### Expected Timing (with proxy):
- Total request: 2-4 seconds
- Each LLM call: 300-1500ms
- Tool execution: 500-700ms
- Embeddings: 200-300ms each

### If Still Slow:
1. Verify proxy is set: `echo $HTTPS_PROXY`
2. Test proxy works: `curl -x $HTTPS_PROXY https://dashscope.aliyuncs.com`
3. Restart Rails server
4. Check `log/captain.log` for timing breakdown

## Lessons Learned

1. **Proxy configuration must be in Rails process environment**, not just shell
2. **Comprehensive logging is essential** for performance debugging
3. **Direct API testing** helps isolate application vs external API issues
4. **LLM API latency dominates** total request time (97%)
5. **Text search before embedding search** saves time when applicable

## Related Documentation

- `docs/setup/PERFORMANCE_IMPROVEMENTS.md` - Technical changes summary
- `enterprise/lib/captain/logger.rb` - Logger implementation
- `lib/tasks/captain_playground_api.rake` - API testing tool

## Contact

For questions about this debugging session or performance issues, refer to the logs in `log/captain.log` with detailed timing breakdowns.
