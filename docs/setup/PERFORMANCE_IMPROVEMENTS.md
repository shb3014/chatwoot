# Captain Performance Improvements

## Issue
Captain responses were extremely slow (~22 seconds per request with "battery life" query).

## Root Cause
The Rails application was NOT using the system proxy to connect to the China-based API endpoint (`dashscope.aliyuncs.com`), causing:
- Direct connection attempts that were extremely slow or failed completely
- 10.5+ seconds per LLM API call vs 300-1300ms with proper proxy routing

## Solution
Added proxy configuration to the Rails environment:
```bash
export HTTPS_PROXY=http://172.24.160.1:10809
export HTTP_PROXY=http://172.24.160.1:10809
```

## Performance Results
**Before (no proxy):**
- First LLM call: ~10.5s
- Tool execution: ~0.6s  
- Second LLM call: ~10.8s
- **Total: ~22s**

**After (with proxy):**
- First LLM call: ~0.4s
- Tool execution: ~0.6s
- Second LLM call: ~1.4s
- **Total: ~2.4s** (91% improvement!)

## Additional Improvements

### 1. Captain Logger
Created dedicated logger (`enterprise/lib/captain/logger.rb`) that writes to `log/captain.log` for cleaner debugging separate from main Rails logs.

### 2. Timing Logs
Added strategic timing logs at key points:
- Controller request start/end
- LLM API call timing
- Tool execution timing
- Embedding generation timing

### 3. Search Optimization
Enhanced `search_documentation_service.rb`:
- Added text search before embedding search (faster for keyword matches)
- Falls back to embedding search only when needed
- Better logging for search performance tracking

### 4. Proxy Support
Enhanced `base_open_ai_service.rb`:
- Added `http_proxy_options` for HTTParty calls
- Added `faraday_proxy_middleware` for OpenAI gem
- Ensures all external API calls route through system proxy

### 5. Playground API Test
Added `lib/tasks/captain_playground_api.rake` for direct API testing without browser.

## Files Modified
- `enterprise/lib/captain/logger.rb` (new)
- `enterprise/app/services/llm/base_open_ai_service.rb`
- `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb`
- `enterprise/app/helpers/captain/chat_helper.rb`
- `enterprise/app/services/captain/llm/embedding_service.rb`
- `enterprise/app/services/captain/tools/search_documentation_service.rb`
- `lib/tasks/captain_playground_api.rake` (new)

## Usage
To test Captain performance:
```bash
bundle exec rake "captain:playground_api[,1,,]"
tail -f log/captain.log
```
