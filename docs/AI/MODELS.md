# Captain Multi-Model Configuration

> Last updated: 2026-02-11

## Overview

Captain supports three distinct model types, each optimized for different workloads. All model-type-specific settings are **optional** — if not configured, they fall back to the main Captain settings.

| Model Type | Config Prefix | Purpose |
|---|---|---|
| **Default (Assistant)** | `CAPTAIN_OPEN_AI_*` | Captain assistant — full pipeline with tools, doc search, validation |
| **Copilot** | `CAPTAIN_COPILOT_*` | Copilot suggest-answer, copilot chat, translation within copilot |
| **Fast** | `CAPTAIN_FAST_*` | Summarization, translation, classification, and other lightweight tasks |

---

## Configuration Keys

### Default (Assistant) Model

The main Captain model. Used by `Captain::Llm::AssistantChatService` and all services that don't specify a model type.

| Config Key | Type | Description |
|---|---|---|
| `CAPTAIN_OPEN_AI_API_KEY` | secret | API key for OpenAI-compatible provider |
| `CAPTAIN_OPEN_AI_MODEL` | text | Model name (default: `gpt-4o-mini`) |
| `CAPTAIN_OPEN_AI_ENDPOINT` | text | API endpoint (default: `https://api.openai.com/`) |
| `CAPTAIN_THINKING_ENABLED` | boolean | Enable reasoning/thinking mode |

### Copilot Model

Used by `Captain::Copilot::ChatService` for copilot-related work. Falls back to the default model if not set.

| Config Key | Type | Description |
|---|---|---|
| `CAPTAIN_COPILOT_API_KEY` | secret | API key (falls back to main key) |
| `CAPTAIN_COPILOT_MODEL` | text | Model name (falls back to main model) |
| `CAPTAIN_COPILOT_ENDPOINT` | text | API endpoint (falls back to main endpoint) |
| `CAPTAIN_COPILOT_THINKING_ENABLED` | boolean | Enable thinking (falls back to main setting) |

### Fast Model

Used for lightweight, high-frequency tasks. Falls back to the default model if not set.

| Config Key | Type | Description |
|---|---|---|
| `CAPTAIN_FAST_API_KEY` | secret | API key (falls back to main key) |
| `CAPTAIN_FAST_MODEL` | text | Model name (falls back to main model) |
| `CAPTAIN_FAST_ENDPOINT` | text | API endpoint (falls back to main endpoint) |
| `CAPTAIN_FAST_THINKING_ENABLED` | boolean | Enable thinking (falls back to main setting) |

---

## Service → Model Type Mapping

| Service | Model Type | Tasks |
|---|---|---|
| `Captain::Llm::AssistantChatService` | Default | Captain assistant (tools, doc search, validation) |
| `Captain::Copilot::ChatService` | Copilot | Copilot chat, suggest answer, in-copilot translation |
| `Captain::Llm::ConversationSummarizationService` | Fast | Conversation summarization + label assignment |
| `Llm::TranslationService` | Fast | Message translation |
| `ChatHelper#classification_model` | Fast (fallback) | Intent classification, continuation detection |
| `Captain::LlmService` (legacy v2) | Default | Legacy multi-agent Captain runtime |

---

## Architecture

### Fallback Chain

```
model-type-specific config → default Captain config → hardcoded default
```

For example, when `CopilotChatService` initializes:

1. Check `CAPTAIN_COPILOT_MODEL` — if set, use it
2. Check `CAPTAIN_OPEN_AI_MODEL` — if set, use it
3. Use hardcoded default (`gpt-4o-mini`)

The same fallback applies to API key, endpoint, and thinking settings.

### Implementation

**`Llm::BaseOpenAiService`** accepts a `model_type:` keyword argument:

```ruby
class Llm::BaseOpenAiService
  def initialize(model_type: nil)
    # model_type: nil (default), :copilot, or :fast
    # Reads model-type-specific configs with fallback to main Captain configs
  end
end
```

Key methods:

| Method | Purpose |
|---|---|
| `fetch_config_for_model_type(aspect)` | Reads config with model-type fallback |
| `model_type_config_key(aspect)` | Maps model type + aspect to config key name |
| `default_config_key(aspect)` | Returns the default Captain config key |
| `setup_thinking` | Resolves thinking setting, stores `@thinking_enabled` |

Subclasses specify their model type in `super()`:

```ruby
class Captain::Copilot::ChatService < Llm::BaseOpenAiService
  def initialize(assistant, config)
    super(model_type: :copilot)
    # ...
  end
end

class Captain::Llm::ConversationSummarizationService < Llm::BaseOpenAiService
  def initialize(conversation)
    super(model_type: :fast)
    # ...
  end
end
```

### Thinking Configuration

The `@thinking_enabled` instance variable is resolved during `BaseOpenAiService` initialization and respects the model-type fallback chain. `ChatHelper#request_chat_completion` uses this pre-resolved value instead of reading `InstallationConfig` directly.

### Classification Model

`ChatHelper#classification_model` follows this priority:

1. `CAPTAIN_CLASSIFICATION_MODEL` (explicit override)
2. `CAPTAIN_FAST_MODEL` (fast model is ideal for classification)
3. `@model` (current service's model)

---

## Super Admin Configuration

All settings are configurable at: `/super_admin/app_config?config=captain`

The settings page groups configs in this order:

1. **Main Captain settings** — API key, model, endpoint, thinking
2. **Embedding settings** — model, endpoint, API key
3. **Copilot model settings** — API key, model, endpoint, thinking
4. **Fast model settings** — API key, model, endpoint, thinking
5. **Other settings** — validation strictness, temperature, v2, streaming

---

## Typical Deployment Configurations

### Single Model (simplest)

Only set the main Captain configs. All services share the same model.

### Two Models (recommended)

Set main Captain configs for the assistant, and set `CAPTAIN_FAST_MODEL` + `CAPTAIN_FAST_ENDPOINT` for a cheaper/faster model. Copilot falls back to the main model.

### Three Models (full separation)

- **Assistant**: High-capability model (e.g., `deepseek-v3.2`, `gpt-4o`)
- **Copilot**: Mid-tier model (e.g., `gpt-4o-mini`, `qwen-plus`)
- **Fast**: Cheapest/fastest model (e.g., `gpt-4o-mini`, `qwen-turbo`)

If the Copilot/Fast model uses the same provider as the main model, you only need to set the model name — the API key and endpoint will fall back to the main config.

---

## Files Changed

| File | Change |
|---|---|
| `config/installation_config.yml` | Added 8 new config entries (4 copilot + 4 fast) |
| `enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb` | Added 8 new keys to `captain_config_options` allowlist |
| `enterprise/app/services/llm/base_open_ai_service.rb` | Added `model_type:` parameter, fallback config resolution, `setup_thinking` |
| `enterprise/app/services/captain/copilot/chat_service.rb` | `super(model_type: :copilot)` |
| `enterprise/app/services/captain/llm/conversation_summarization_service.rb` | `super(model_type: :fast)` |
| `enterprise/app/services/llm/translation_service.rb` | `super(model_type: :fast)` |
| `enterprise/app/helpers/captain/chat_helper.rb` | Uses `@thinking_enabled` from base service; `classification_model` falls back to fast model |
