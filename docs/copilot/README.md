# Copilot Sidebar

> Last updated: 2026-02-11

## Overview

A complete restructuring of the Copilot sidebar in the conversation view. The previous design used separate, closable panels for Contact and Copilot (toggled via a floating button group). The new design merges them into a single, always-visible tabbed sidebar with:

- AI-powered conversation summarization with label auto-assignment
- Suggest answer with automatic language detection and translation
- Resizable sidebar width
- Thinking/tool-step messages hidden from the chat UI

---

## Architecture Changes at a Glance

| Aspect | Before | After |
|---|---|---|
| Sidebar visibility | Closable, toggled via floating buttons | Always visible, foldable (collapsible to icon strip) |
| Sidebar width | Fixed | Resizable via drag handle; double-click to reset |
| Contact / Copilot | Two separate panels, mutually exclusive | Two tabs in one unified sidebar |
| Default view | Contact panel | Copilot tab |
| Summarization | Via copilot chat thread (full Captain pipeline) | Dedicated LLM endpoint, single call with transcript only |
| Label assignment | Not available | AI assigns labels during summarization; stale AI labels removed on regeneration |
| Suggest an answer | Hidden inside empty-state prompt list | Prominent standalone button, always visible |
| Suggested answer language | System language only | Customer language with agent-language translation |
| Thinking/tool steps | Shown in collapsible group | Hidden from UI entirely |

---

## Files Changed

### New Files

| File | Purpose |
|---|---|
| `ConversationRightSidebar.vue` | Unified tabbed sidebar (Copilot + Contact), foldable, resizable |
| `CopilotSummary.vue` | Summary display component (loading, error, content + label pills) |
| `conversation_summarization_service.rb` | Direct LLM summarization, single API call |
| `conversation_summarization_job.rb` | Background job for async summarization |

### Key Modified Files

| File | Change |
|---|---|
| `captain/copilot/chat_service.rb` | Server-side language detection, two-call translation, conversation transcript injection, message buffering |
| `captain/llm/system_prompts_service.rb` | Reply suggestion language rules, customer_language JSON field |
| `copilot_threads_controller.rb` | Title truncation to 255 chars |
| `copilot_message.rb` | Allowed customer_language and translation keys in message JSON |
| `CopilotAssistantMessage.vue` | Translation display from message.translation field |
| `Copilot.vue` | Removed thinking/step messages from UI |
| `conversations_controller.rb` | force param to bypass summary cache |
| `conversation.js` (API) | force param in summarize API |
| `conversations/actions.js` | force flag in summarizeConversation |
| `labelable.rb` | Fixed add_labels to work with string arrays + .uniq |
| `conversation_summarization_service.rb` | reassign_labels replaces assign_labels; stale AI labels removed |

---

## Feature Details

### 1. Unified Tabbed Sidebar

**Component:** `ConversationRightSidebar.vue`

- **Non-closable:** Always rendered when a conversation is selected.
- **Foldable:** Collapses to a 48px icon strip; expands to default width. Fold state persists in `uiSettings.is_sidebar_folded`.
- **Resizable:** Drag the left edge to adjust width. Double-click the handle to reset. Width persists in `uiSettings.copilot_sidebar_width`.
- **Tabs:** Copilot (default, iris accent) and Contact (brand accent).
- **Keyboard shortcut:** Alt+O toggles fold/unfold.
- **Scrollable:** Content uses flex-1 min-h-0 overflow-hidden pattern for proper overflow.

### 2. Conversation Summarization

**Service:** `Captain::Llm::ConversationSummarizationService`

A single, direct LLM call. No tools, no document search, no Captain system prompt pipeline.

**Flow:**
1. Formats conversation messages as a transcript with roles.
2. Gathers labels that have `ai_learning_description` set.
3. Builds a prompt asking for a 1-2 sentence summary + label suggestions.
4. Calls the LLM once.
5. Parses JSON response, persists summary in `conversation.captain_summary` (jsonb).
6. Runs `reassign_labels` to update labels.

**Caching:** Returns stored summary if generated within the last hour. Pass `force=true` to bypass.

**Label reassignment (reassign_labels):**
1. Captures old AI-suggested labels from the previous summary.
2. Removes stale AI labels (previously suggested but no longer relevant).
3. Adds new valid labels (case-insensitive match against account labels).
4. Preserves manually-assigned labels.

### 3. Suggest Answer with Translation

The two-call architecture:

| Call | Purpose | Pipeline |
|---|---|---|
| **Call 1: Generate** | Draft a reply in the customer's language | Full Captain pipeline (tools, doc search, validation) |
| **Call 2: Translate** | Translate the reply to the account language | Lightweight direct LLM call (no tools) |

**Language detection is server-side** (not LLM-based):

`ChatService#detect_customer_language` analyzes all customer messages using Unicode script analysis:

| Script | Language Code |
|---|---|
| Latin (a-zA-Z) | en |
| CJK without Kana | zh |
| Kana + CJK | ja |
| Hangul | ko |
| Arabic script | ar |
| Cyrillic | ru |

Messages shorter than 5 characters are ignored. Falls back to account locale if no substantial messages.

**Translation decision:**
- Compare `detected_customer_language` (ISO 639-1) to `account_locale_code`
- Different: translate. Same: skip.

**Message buffering:**

The assistant message is buffered (not persisted/broadcast) until translation completes. This ensures the frontend receives the complete message with both `content` and `translation` fields in a single ActionCable broadcast.

```
persist_message()         -> buffers assistant messages
                          -> non-assistant (thinking) persist immediately
flush_assistant_message() -> called after translation, persists + broadcasts
```

**Frontend display (CopilotAssistantMessage.vue):**
- Primary content: displayed prominently (in customer's language)
- Translation: shown in a collapsible section below (in account language)
- "Use this" button: inserts the primary content (customer's language) into the reply editor

**Suggest prompt:** Hardcoded in English to avoid locale-translated prompts confusing the model:
```
Based on the full conversation, draft a reply to the customer. Be clear, concise, and helpful.
```

**Suggest answer system prompt guidelines** (in `copilot_response_generator`):

When `reply_suggestion=true`, the copilot follows a dedicated set of customer-facing reply rules derived from the Captain assistant prompt. These are organized as `[Suggest — *]` subsections:

| Section | Key Rules |
|---|---|
| Language | Write in customer's language, overrides all other language settings |
| Tone & Style | Professional, warm, empathetic. Markdown allowed, no headings. Numbered steps. |
| Apology Rules | Check conversation history — only apologize if no prior apology exists. Never repeat. Transition sentence after apology. |
| Response Structure | Apology → transition → explanation → solution → closing (in order) |
| Conversation Awareness | Never repeat agent's prior advice. Acknowledge completed steps. Track issue evolution. |
| Content Rules | No citations, no internal references, no "Captain" mention. Only use tool results and context. |
| Scope & Escalation | Don't offer undocumented help. Acknowledge limitations honestly for agent to decide. |
| Prohibited | Citation markers, internal system names, repeated apologies, abrupt tone shifts, generic closings |

These rules are **not applied** when `reply_suggestion=false` (regular copilot informational responses).

### 4. Conversation Context Injection

`ChatService#current_viewing_history` injects into the LLM system context:

1. **Conversation metadata:** ID and contact ID
2. **Language directive:** "The customer is writing in English. When drafting a reply, you MUST write in this language."
3. **Conversation transcript:** Last 20 messages (both customer and agent)

This ensures the LLM always has the full conversation context without needing to call get_conversation.

### 5. System Prompt Output Format

The copilot response JSON includes customer_language for diagnostics:

```json
{
  "reasoning": "...",
  "content": "...",
  "reply_suggestion": true,
  "customer_language": "en"
}
```

Reply suggestion rules:
- `reply_suggestion=true` only when the agent explicitly asks for a customer reply draft
- Content written in the customer's language (overrides all other language rules)
- Reply based on the full conversation, not just the last message

### 6. Copilot Message Validation

Allowed JSON keys in the message field:

```
content, reasoning, function_name, reply_suggestion, customer_language, translation
```

Thread title is truncated to 255 characters to respect the database column limit.

### 7. Thinking Steps Hidden

`Copilot.vue` filters out `assistant_thinking` messages. Only user and assistant messages are rendered. The `CopilotThinkingGroup` component is no longer imported.

---

## Data Flow: Suggest an Answer

```
[Agent clicks "Suggest an answer"]
       |
       v
ConversationRightSidebar.vue
  -> sendMessage("Based on the full conversation, draft a reply...")
       |
       v
Copilot::ChatService#generate_response
  1. detect_customer_language (Unicode script analysis)
  2. build_messages (system prompt + account context + transcript + language directive)
  3. request_chat_completion (full Captain pipeline with tools)
     -> persist_message BUFFERS the assistant response (not broadcast yet)
       |
       v
  4. Check reply_suggestion=true
  5. Compare detected_customer_language vs account_locale_code
     |
     +-- Same language -> skip translation
     |
     +-- Different -> translate_to_account_language (lightweight LLM call)
          -> response['translation'] = translated_text
       |
       v
  6. flush_assistant_message -> persist + broadcast (with translation)
       |
       v
ActionCable -> Frontend
       |
       v
CopilotAssistantMessage.vue
  -> Primary: message.content (customer's language)
  -> Collapsible: message.translation (account language)
  -> "Use this": inserts message.content into reply editor
```

---

## Data Flow: Summarize

```
[Conversation opened / Regenerate clicked]
       |
       v
ConversationRightSidebar.vue
  -> store.dispatch('summarizeConversation', { conversationId, force })
       |
       v
POST /conversations/:id/summarize?force=true
       |
       v
ConversationsController#summarize
  -> Check cache (skip if force=true)
  -> ConversationSummarizationService#generate
       |
       v
  1. Build transcript from conversation messages
  2. Gather labels with ai_learning_description
  3. Single LLM call (no tools)
  4. Parse JSON -> persist captain_summary
  5. reassign_labels:
     a. Capture old AI labels from previous summary
     b. Remove stale AI labels
     c. Add new valid labels (case-insensitive account match)
     d. Preserve manual labels
       |
       v
  6. Frontend dispatches getConversation to refresh labels in UI
```

---

## Logging

All copilot logs go to `log/captain.log` (via `Captain::Logger`).

Key prefixes:
- `[Copilot]` -- Language detection, translation, conversation context
- `[Captain::Summarization]` -- Summarization service (errors only)

Example suggest-answer log output:
```
[Copilot] Account locale: zh, language: chinese
[Copilot] Detected customer language: en
[Copilot] Conversation transcript (4 messages):
Customer: i have trouble connect to wifi
Agent: ...
[Copilot] reply_suggestion detected -- detected_customer_lang=en, account_locale=zh
[Copilot] Languages differ -- translating to chinese...
[Copilot] Translation result: ...
```

---

## Key Design Decisions

1. **Two-call translation.** A single LLM call producing bilingual output was unreliable across models. Splitting into generate + translate is robust and allows independent failure.

2. **Server-side language detection.** Unicode script analysis is deterministic and instant. LLM-based detection was unreliable -- models defaulted to the account language when overwhelmed by Chinese context (docs, system messages).

3. **Conversation transcript injection.** Including the last 20 messages in the system context ensures the LLM always has conversation context. Previously it depended on calling get_conversation via tools, which was inconsistent.

4. **Message buffering.** The assistant message is buffered until translation completes, ensuring the ActionCable broadcast includes the complete response. Without this, the frontend received messages without the translation field.

5. **Label reassignment, not just assignment.** On regeneration, stale AI-suggested labels are removed while manual labels are preserved. This prevents label accumulation across multiple regenerations.

6. **Summarization is separate from copilot chat.** The summary uses a lightweight single LLM call. The copilot "Suggest an answer" uses the full Captain pipeline (tools, doc search) where they are valuable.

7. **Hardcoded English prompts.** The "Suggest an answer" prompt is always in English regardless of account locale. This prevents the i18n-translated prompt from confusing the model about the target language.
