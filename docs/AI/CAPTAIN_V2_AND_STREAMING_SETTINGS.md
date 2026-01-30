## Captain v2 and streaming settings

This document summarizes the recent changes that move Captain runtime switches to global settings and how they are applied at runtime.

### What was added
- Global installation configs for Captain runtime selection and streaming:
  - `CAPTAIN_V2_ENABLED`
  - `CAPTAIN_STREAMING_ENABLED`
- These are defined in `config/installation_config.yml` and allowed in the super admin Captain config allowlist.

### Where the switches live
- **Super Admin → App Configs → Captain**
  - This is the same config area used for `CAPTAIN_DEFAULT_TEMPERATURE` and other Captain globals.

### Runtime behavior
- `Captain::Conversation::ResponseBuilderJob` now decides:
  - **v2** if `CAPTAIN_V2_ENABLED` is true; otherwise v1 (with account feature flag fallback for `captain_integration_v2`).
  - **streaming** if `CAPTAIN_STREAMING_ENABLED` is true.
- Streaming remains **v1-only**. If v2 is enabled, streaming is skipped.

### Custom endpoint streaming support
- Streaming now works with custom LLM endpoints (e.g., Qwen via DashScope).
- The monkey-patched `chat` method in `Llm::BaseOpenAiService` supports SSE (Server-Sent Events) streaming.
- Uses `Net::HTTP` with proper buffer handling for partial SSE lines across TCP chunks.
- Proxy configuration is respected for streaming requests.

### Streaming UX improvements
- During streaming, only the `response` field from JSON is displayed to users (not the `reasoning` field).
- While the model is generating reasoning, a "..." placeholder is shown.
- The `extract_response_for_streaming` method in `ResponseBuilderJob` handles JSON parsing during stream.

### Learned conversation context improvements
- Background context (from learned conversations) is now treated as an EQUALLY VALID source alongside documentation.
- The model should USE background context confidently to answer questions.
- The only difference: citations [1], [2], etc. are only added for documentation sources, not background context.

### Removed
- Per-assistant UI toggles for v2 and streaming.
- Per-assistant config keys `feature_v2` and `feature_streaming`.

### Key files
- Global config definitions: `config/installation_config.yml`
- Super admin allowlist: `enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb`
- Runtime selection: `enterprise/app/jobs/captain/conversation/response_builder_job.rb`
- Assistant controller cleanup: `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb`
- Removed assistant settings UI toggles: `app/javascript/dashboard/components-next/captain/pageComponents/assistant/settings/AssistantSystemSettingsForm.vue`
- Custom endpoint streaming: `enterprise/app/services/llm/base_open_ai_service.rb` (patched `chat` method supports `stream:` keyword)
