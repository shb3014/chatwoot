# DeepSeek‑V3.2 on Volcengine Ark (Chatwoot Captain) – Implementation Notes

## Goal

Make Chatwoot **Captain** work with **DeepSeek‑V3.2** hosted on **Volcengine Ark**, including:

- Tool calling (Captain tools)
- Optional “thinking” mode toggle
- No unexpected bot handoff due to provider parameter incompatibilities

Reference docs:

- Ark model page: `https://console.volcengine.com/ark/region:ark+cn-beijing/model/detail?Id=deepseek-v3-2`
- DeepSeek‑V3.2 model card: `https://huggingface.co/deepseek-ai/DeepSeek-V3.2`

## Key Findings

### 1) Ark uses a **thinking object**, not a boolean/string

Ark’s DeepSeek‑V3.2 expects:

- `thinking: { type: "enabled" }` to enable thinking
- `thinking: { type: "disabled" }` to disable thinking

Sending `thinking: true` or `thinking: "thinking"` caused request failures (HTTP 400) or provider-side parse errors.

### 2) `response_format: { type: "json_object" }` is **not supported** by this model on Ark

When `response_format.type = "json_object"` was sent, Ark returned HTTP 400:

- “`json_object` is not supported by this model”

So for **DeepSeek‑V3.2 on Ark**, we must **never send `response_format`**, regardless of thinking being enabled or disabled.

### 3) Tool calling works better with explicit `tool_choice`

Some OpenAI-compatible gateways require tool choice to be explicit.
When tools are present, we send:

- `tool_choice: "auto"`

## Final Implementation (What the code does now)

### Super Admin toggle (global)

We added a global installation config:

- `CAPTAIN_THINKING_ENABLED` (boolean)

It appears in Super Admin → App Configs → `captain` and controls thinking globally.

Files:

- `enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb`
- `config/installation_config.yml`

### Captain request params

#### Captain “ChatHelper” path (assistant/coplay flows)

File: `enterprise/app/helpers/captain/chat_helper.rb`

- If the model is detected as **DeepSeek‑V3.2**:
  - Always send `thinking: { type: "enabled" | "disabled" }` based on `CAPTAIN_THINKING_ENABLED`
  - Never send `response_format`
  - If tools exist, send `tool_choice: "auto"`
- For non-DeepSeek models:
  - Keep existing behavior (use `response_format: json_object` when thinking is off; omit it when thinking is on)

#### Captain “Agent” path

File: `enterprise/lib/captain/llm_service.rb`

Same idea as above:

- DeepSeek‑V3.2 → `thinking: { type: enabled|disabled }`, never send `response_format`
- Tools → `tool_choice: "auto"`

### Response parsing safety

DeepSeek thinking can introduce `reasoning_content` and sometimes produce non-JSON content.
Captain’s parsing was hardened so:

- If `message.tool_calls` is present → tools run normally.
- Else Captain tries `JSON.parse(message.content)` (after stripping ```json fences).
- If JSON parsing fails → we fall back to a JSON-shaped response so Captain doesn’t crash/handoff just due to formatting.

Primary file:

- `enterprise/app/helpers/captain/chat_helper.rb`

Agent path also has a safe fallback in:

- `enterprise/lib/captain/llm_service.rb`

## Operational Checklist

1. Set Ark endpoint in `CAPTAIN_OPEN_AI_ENDPOINT` to your Ark `/chat/completions` URL.
2. Set `CAPTAIN_OPEN_AI_MODEL` to your model id (e.g. `deepseek-v3-2-251201`).
3. Set `CAPTAIN_THINKING_ENABLED`:
   - `true` → sends `thinking: {type: "enabled"}`
   - `false` → sends `thinking: {type: "disabled"}`
4. Ensure logs show:
   - `tool_choice: "auto"` when tools exist
   - `thinking: {type: "..."}`
   - No `response_format` when using DeepSeek‑V3.2 on Ark

## Why this approach

This keeps Captain stable:

- Avoids Ark parameter errors for DeepSeek‑V3.2
- Keeps tool calling functional
- Prevents JSON parse crashes by providing safe fallbacks when DeepSeek returns non-JSON content








