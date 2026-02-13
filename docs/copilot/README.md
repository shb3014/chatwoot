# Copilot Sidebar

> Last updated: 2026-02-12

## Overview

A complete restructuring of the Copilot sidebar in the conversation view. The previous design used separate, closable panels for Contact and Copilot (toggled via a floating button group). The new design merges them into a single, always-visible tabbed sidebar with:

- AI-powered conversation summarization with label auto-assignment
- Suggest answer with automatic language detection and translation
- **Real-time streaming** of copilot responses via ActionCable
- **Tabbed reply / translation UI** with dual action buttons
- **Related sources** extracted from tool results, displayed below suggested answers
- **Resizable message editor** with one-click "Translate to XX" button
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
| Translation display | Not available | Tabbed UI (Translation tab default, Reply tab for customer language) |
| Response delivery | Wait for full response + translation | **Two-phase**: immediate display after generation, translation added async |
| Streaming | Not available | Real-time token-by-token streaming via ActionCable |
| Sources | Not available | Extracted from tool results, shown with view/add-to-reply buttons |
| Message editor | Fixed height | Resizable height + "Translate to XX" button |
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
| `translations_controller.rb` | API endpoint for direct text translation |
| `api/captain/translation.js` | Frontend API client for the translation endpoint |

### Key Modified Files

| File | Change |
|---|---|
| `captain/copilot/chat_service.rb` | Two-phase persistence, streaming via ActionCable, source extraction, language detection, translation |
| `captain/llm/system_prompts_service.rb` | Reply suggestion language rules, customer_language JSON field |
| `copilot_threads_controller.rb` | Title truncation to 255 chars |
| `copilot_message.rb` | Allowed `sources` key in message JSON; `after_update_commit` for translation updates |
| `CopilotAssistantMessage.vue` | Tabbed UI, dual action buttons, sources section, citation popup |
| `Copilot.vue` | Streaming content display, removed thinking/step messages |
| `ConversationRightSidebar.vue` | Passes `streamingContent` prop to Copilot |
| `copilotMessages.js` (store) | `streamingContent` state, `SET_STREAMING` / `CLEAR_STREAMING` mutations |
| `actionCable.js` | Handles `copilot.message.streaming` events |
| `ReplyBox.vue` | Resizable editor height, "Translate to XX" button |
| `busEvents.js` | Added `SET_EDITOR_TRANSLATE_LANGUAGE` event |
| `conversations_controller.rb` | `force` param to bypass summary cache |
| `conversation.js` (API) | `force` param in summarize API |
| `conversations/actions.js` | `force` flag in `summarizeConversation` |
| `labelable.rb` | Fixed `add_labels` to work with string arrays + `.uniq` |
| `integrations.json` (i18n) | All new Copilot UI strings (`USE_LANG`, `EDIT_LANG`, `TAB_REPLY`, `TAB_TRANSLATION`, `SOURCES_TITLE`, `SOURCE_TYPE.*`, `STREAMING`, etc.) |
| `conversation.json` (i18n) | `TRANSLATE_ERROR` key |
| `lib/events/types.rb` | Added `COPILOT_MESSAGE_STREAMING` event type |
| `config/routes.rb` | Added `captain/translation` endpoint |
| `llm/translation_service.rb` | Made `conversation` parameter optional |

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

### 3. Real-Time Streaming

Copilot responses are streamed to the frontend in real time via ActionCable, so the agent sees tokens appearing as the LLM generates them.

**Backend (`ChatService`):**

1. `setup_streaming_callback` creates a proc that broadcasts via ActionCable to the user's `pubsub_token` channel.
2. The callback is passed to `stream_chat_completion` (in `ChatHelper`), which invokes it for every `delta['content']` chunk from the SSE stream.
3. **Throttling:** Broadcasts at most every 100ms to avoid flooding the WebSocket. The first ~50 characters broadcast immediately for fast visual feedback.
4. `broadcast_final_streaming_content` sends the complete content one final time after generation completes, ensuring no tokens are lost due to throttling.

**Critical detail — `account_id` in broadcast data:**

The `BaseActionCableConnector.onReceived` handler validates every event with `isAValidEvent(data)`, which checks `data.account_id === getCurrentAccountId`. ALL broadcast data **must** include `account_id` at the top level, otherwise the event is silently dropped on the frontend. This applies to both streaming broadcasts AND `copilot.message.created` events (via `push_event_data`).

**Bug fix:** `CopilotMessage#push_event_data` was missing `account_id` at the top level (it was only nested inside `copilot_thread`). This caused `copilot.message.created` events to be silently dropped by the frontend, preventing assistant messages from appearing after generation. Fixed by adding `account_id: account_id` to the hash.

```ruby
ActionCable.server.broadcast(
  user_token,
  {
    event: 'copilot.message.streaming',
    data: {
      account_id: @account.id,        # ← REQUIRED or event is dropped
      copilot_thread_id: thread_id,
      content: accumulated_content
    }
  }
)
```

**Frontend:**

| Layer | File | Responsibility |
|---|---|---|
| ActionCable handler | `actionCable.js` | Maps `copilot.message.streaming` → dispatches `copilotMessages/setStreamingContent` |
| Store | `copilotMessages.js` | `streamingContent` state map (`threadId → content`), `SET_STREAMING` / `CLEAR_STREAMING` mutations |
| Sidebar | `ConversationRightSidebar.vue` | Reads `getStreamingContent(threadId)` from store, passes as prop |
| Display | `Copilot.vue` | Shows streaming content with pulsing indicator; replaced by real message when `copilot.message.created` arrives |

**Streaming → message transition:**

When the persisted `copilot.message.created` event arrives, the store's `upsert` action calls `CLEAR_STREAMING` for the thread. The streaming UI disappears and the `CopilotAssistantMessage` component renders.

### 4. Two-Phase Message Persistence

Previously, the assistant message was buffered until translation completed (up to ~5 seconds of additional waiting). Now the flow uses two phases:

**Phase 1 — Immediate display (after LLM generation):**
1. `attach_sources_to_buffered_message` extracts sources from tool results
2. `flush_assistant_message` persists the message WITH content + sources but WITHOUT translation
3. `after_create_commit :broadcast_message` fires → frontend shows the response immediately

**Phase 2 — Translation update (async):**
1. `translate_to_account_language(response['content'])` calls the translation LLM
2. `persisted_message.update!(message: message.merge('translation' => translation))`
3. `after_update_commit :broadcast_message` fires → frontend updates the existing message, tabs appear

**Model change:** `CopilotMessage` now has both `after_create_commit :broadcast_message` and `after_update_commit :broadcast_message`.

**Frontend UX timeline:**
```
0s        Agent clicks "Suggest an answer"
0-9s      Streaming content appears (token by token)
~9s       Phase 1: message persists → response shown immediately
~14s      Phase 2: translation arrives → tabs appear smoothly
```

Previously, the agent waited ~14 seconds seeing only a loader.

### 5. Tabbed Reply / Translation UI

**Component:** `CopilotAssistantMessage.vue`

When a reply suggestion has both `content` (customer language) and `translation` (system language), the UI shows two tabs:

| Tab | Content | Default |
|---|---|---|
| Translation | `message.translation` (system/account language) | **Yes** (for agent readability) |
| Reply ({lang}) | `message.content` (customer language) | No |

When translation hasn't arrived yet (Phase 1), content is shown directly without tabs. When translation arrives (Phase 2), tabs appear automatically via Vue reactivity.

**Dual action buttons** (shown only for `reply_suggestion` messages, only on the last message):

| Button | Action |
|---|---|
| **Use {customerLanguage}** | Inserts `message.content` into the reply editor (ready to send to customer) |
| **Edit Translation** | Inserts `message.translation` into the reply editor (for agent editing) |

Both buttons also emit `SET_EDITOR_TRANSLATE_LANGUAGE` to configure the editor's "Translate to XX" button.

### 6. Related Sources

Sources are included directly in the LLM's JSON response. The system prompt instructs the LLM to list only the sources it actually used in its response content, via a `sources` array in the output schema.

**How it works:**

1. The system prompt's `[Sources]` section tells the LLM to populate the `sources` array with `title` and `url` fields from tool results (`search_documentation`, `search_articles`, `get_article`) — but only for sources whose information was directly used in the response.
2. The LLM includes these sources in its JSON output alongside `content`, `reply_suggestion`, and `customer_language`.
3. The backend persists the sources as-is from the LLM response — no backend extraction, filtering, or URL lookup is needed.

This approach is more accurate than backend heuristics because the LLM knows exactly which sources it cited. Previously, source extraction used backend parsing of tool results with keyword-based relevance filtering, which could include irrelevant sources or miss relevant ones.

**Frontend display:**

Each source shows:
- Type icon (book for articles, globe for web, etc.)
- Clickable title (opens in new tab)
- Type label (i18n: "Help Center Article", "Web Source", etc.)
- Hover actions: **View** (external link) and **Add to reply** (appends `[Title](URL)` to editor)

**Message JSON with sources:**
```json
{
  "content": "...",
  "reply_suggestion": true,
  "customer_language": "en",
  "sources": [
    { "title": "How to connect Ivy to Wi-Fi", "url": "https://..." },
    { "title": "Troubleshooting guide", "url": "https://..." }
  ],
  "translation": "..."
}
```

### 7. Resizable Message Editor + Translate Button

**Component:** `ReplyBox.vue`

**Resizable height:**
- A thin drag handle at the top of the reply box (`cursor-row-resize`).
- Drag up/down to resize (min 120px, max 600px).
- Uses `mousedown` / `mousemove` / `mouseup` events.
- CSS transition is disabled during drag (`is-resizing` class).

**"Translate to XX" button:**
- Appears after the agent uses a copilot suggested reply (triggered by `SET_EDITOR_TRANSLATE_LANGUAGE` bus event).
- Button text: "Translate to {customerLanguageName}" (i18n key: `CAPTAIN.COPILOT.TRANSLATE_TO`).
- On click: calls `POST /api/v1/accounts/:id/captain/translation` with the editor content.
- Shows a loading spinner during translation.
- On success: replaces the editor content with the translated text.
- On error: shows alert via `CONVERSATION.REPLYBOX.TRANSLATE_ERROR`.

**Backend translation endpoint:**
- Controller: `Api::V1::Accounts::Captain::TranslationsController`
- Route: `POST /api/v1/accounts/:id/captain/translation`
- Uses `Llm::TranslationService` (no conversation context needed).

### 8. Suggest Answer with Translation

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

### 9. Citation Popup

When the LLM includes `<cite>` tags (citation chips) in its response, hovering over a chip shows a popup with:
- Source type label (using i18n `SOURCE_TYPE.*` keys)
- Clickable title linking to the source URL

Citation listeners are set up on `onMounted` and `onUpdated` for both the message content and translation content refs.

### 10. Conversation Context Injection

`ChatService#current_viewing_history` injects into the LLM system context:

1. **Conversation metadata:** ID and contact ID
2. **Language directive:** "The customer is writing in English. When drafting a reply, you MUST write in this language."
3. **Conversation transcript:** Last 20 messages (both customer and agent)

This ensures the LLM always has the full conversation context without needing to call `get_conversation`.

### 11. System Prompt Output Format

The copilot response JSON:

```json
{
  "content": "...",
  "reply_suggestion": true,
  "customer_language": "en"
}
```

Reply suggestion rules:
- `reply_suggestion=true` only when the agent explicitly asks for a customer reply draft
- Content written in the customer's language (overrides all other language rules)
- Reply based on the full conversation, not just the last message
- `reasoning` field was removed to reduce response size and latency

### 12. Copilot Message Validation

Allowed JSON keys in the message field:

```
content, function_name, reply_suggestion, customer_language, translation, sources
```

Thread title is truncated to 255 characters to respect the database column limit.

### 13. Thinking Steps Hidden

`Copilot.vue` filters out `assistant_thinking` messages AND the hardcoded "Suggest an answer" prompt. Only user freeform questions and assistant messages are rendered. The `CopilotThinkingGroup` component is no longer imported.

### 14. UI Simplifications

- **No sender labels:** "Captain" and "You" labels are removed from copilot messages. Assistant messages render content directly; user messages use a subtle background to distinguish them.
- **No suggest prompt display:** The hardcoded suggest prompt ("Based on the full conversation, draft a reply to the customer.") is filtered from the message list. A loading indicator shows while waiting for the response.
- **Reduced font sizes:** Copilot text uses 13px (from 14px) to better match the compact sidebar layout. The `copilot-prose` CSS class handles consistent sizing across message content and streaming.

---

## Internationalization (i18n)

All new Copilot UI strings are defined in `app/javascript/dashboard/i18n/locale/en/integrations.json` under the `CAPTAIN.COPILOT` namespace (root-level `CAPTAIN`, NOT nested under `INTEGRATION_SETTINGS`).

**Key structure:**
```json
{
  "CAPTAIN": {
    "COPILOT": {
      "USE_LANG": "Use {lang}",
      "EDIT_LANG": "Edit {lang}",
      "TAB_REPLY": "Reply ({lang})",
      "TAB_TRANSLATION": "Translation",
      "SOURCES_TITLE": "Related Sources",
      "ADD_TO_REPLY": "Add to reply",
      "VIEW_SOURCE": "View",
      "TRANSLATE_TO": "Translate to {lang}",
      "TRANSLATING": "Translating...",
      "STREAMING": "Generating response...",
      "SOURCE_TYPE": {
        "ARTICLE": "Help Center Article",
        "WEB_URL": "Web Source",
        "FAQ": "FAQ",
        "DOCUMENT": "Document",
        "DEFAULT": "Source"
      }
    }
  }
}
```

`{lang}` parameters are interpolated at runtime with language names from the `LANGUAGE_NAMES` map (English names like "English", "Chinese" — standard practice for language selectors).

**Translation error** is in `conversation.json`: `CONVERSATION.REPLYBOX.TRANSLATE_ERROR`.

---

## Data Flow: Suggest an Answer (with Streaming + Two-Phase Persistence)

```
[Agent clicks "Suggest an answer"]
       |
       v
ConversationRightSidebar.vue
  -> sendMessage("Based on the full conversation, draft a reply...")
       |
       v
Copilot::ChatService#generate_response
  1. setup_streaming_callback (ActionCable, throttled 100ms)
  2. request_chat_completion (full Captain pipeline with tools)
     |
     +-- During generation: streaming callback fires per token
     |   -> ActionCable broadcast (event: copilot.message.streaming)
     |   -> Frontend: shows streaming content in real time
     |
     +-- After generation: broadcast_final_streaming_content
         (ensures complete text is sent)
       |
       v
  3. attach_sources_to_buffered_message
     - Last search_documentation result + all search_articles/get_article
     - Deduplicate by URL then title
       |
       v
  4. PHASE 1: flush_assistant_message
     -> persist WITH content + sources, WITHOUT translation
     -> after_create_commit broadcasts copilot.message.created
     -> Frontend: streaming clears, CopilotAssistantMessage renders
     -> Agent sees the reply immediately (~9s after click)
       |
       v
  5. PHASE 2: translate_to_account_language (lightweight LLM call ~5s)
     -> persisted_message.update!(message + translation)
     -> after_update_commit broadcasts updated message
     -> Frontend: upsert updates record, tabs appear
     -> Agent sees translation (~14s after click)
       |
       v
CopilotAssistantMessage.vue
  -> Default tab: Translation (system language, for agent readability)
  -> Reply tab: Customer language content
  -> "Use {lang}": inserts customer-language content into editor
  -> "Edit Translation": inserts system-language content into editor
  -> Sources: view links + add-to-reply buttons
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

## Data Flow: Editor Translation

```
[Agent clicks "Use {lang}" or "Edit Translation" in Copilot]
       |
       v
CopilotAssistantMessage.vue
  -> emitter.emit(INSERT_INTO_RICH_EDITOR, content)
  -> emitter.emit(SET_EDITOR_TRANSLATE_LANGUAGE, { language, languageName })
       |
       v
ReplyBox.vue
  -> Editor content updated
  -> "Translate to {lang}" button appears
       |
       v
[Agent edits content, then clicks "Translate to {lang}"]
       |
       v
ReplyBox.vue#translateContent
  -> POST /api/v1/accounts/:id/captain/translation
     { content: editorText, target_language: customerLanguageName }
       |
       v
TranslationsController#create
  -> Llm::TranslationService.new.translate_message(content, target_language:)
       |
       v
  -> Editor content replaced with translated text
  -> Agent reviews and sends
```

---

## Logging

All copilot logs go to `log/captain.log` (via `Captain::Logger`).

Key prefixes:
- `[Copilot]` — Language detection, translation, conversation context, sources
- `[Copilot][Streaming]` — Streaming setup, broadcast count, content length
- `[Captain::Summarization]` — Summarization service (errors only)

Example suggest-answer log output:
```
[Copilot] Account locale: zh, language: chinese
[Copilot] Detected customer language: en
[Copilot] User input: Based on the full conversation, draft a reply...
[Copilot][Streaming] Enabled for thread=42 user=1
[Copilot][Streaming] Broadcast #1 len=15
[Copilot][Streaming] Broadcast #2 len=87
[Copilot][Streaming] Broadcast #3 len=203
[Copilot] reply_suggestion detected — detected_customer_lang=en, account_locale=zh
[Copilot] Content preview: **Wi-Fi Connection Help for Ivy** ...
[Copilot] Attaching 4 sources to reply suggestion
[Copilot] Languages differ — translating to chinese...
[Copilot] Translation complete, updating message 156
```

---

## Key Design Decisions

1. **Two-phase persistence.** The assistant message is persisted immediately after generation (Phase 1), then updated with translation (Phase 2). This eliminates the ~5-second translation wait — the agent sees the response right after generation completes. The `after_update_commit` callback broadcasts the updated message with translation.

2. **`account_id` in ActionCable broadcasts.** The frontend's `BaseActionCableConnector.onReceived` validates `data.account_id` before dispatching events. All direct `ActionCable.server.broadcast` calls (streaming, etc.) MUST include `account_id` in the data payload, or the event is silently dropped. This was a critical bug that prevented streaming from working.

3. **Throttled streaming.** Broadcasting every token would flood the WebSocket. The callback throttles to every 100ms, with an exception for the first ~50 characters (immediate feedback). A final broadcast after generation ensures completeness.

4. **Last search_documentation wins.** The `ResponseValidator` captures tool results from ALL depths, including forced search (which uses generic queries like "draft a reply to the customer"). Only the LAST `search_documentation` result is used for source extraction — it's the LLM's own targeted search with a specific, relevant query.

5. **Two-call translation.** A single LLM call producing bilingual output was unreliable across models. Splitting into generate + translate is robust and allows independent failure.

6. **Server-side language detection.** Unicode script analysis is deterministic and instant. LLM-based detection was unreliable — models defaulted to the account language when overwhelmed by Chinese context (docs, system messages).

7. **Conversation transcript injection.** Including the last 20 messages in the system context ensures the LLM always has conversation context. Previously it depended on calling `get_conversation` via tools, which was inconsistent.

8. **Label reassignment, not just assignment.** On regeneration, stale AI-suggested labels are removed while manual labels are preserved. This prevents label accumulation across multiple regenerations.

9. **Summarization is separate from copilot chat.** The summary uses a lightweight single LLM call. The copilot "Suggest an answer" uses the full Captain pipeline (tools, doc search) where they are valuable.

10. **Hardcoded English prompts.** The "Suggest an answer" prompt is always in English regardless of account locale. This prevents the i18n-translated prompt from confusing the model about the target language.

---

## Suggest Answer System Prompt Guidelines

(In `system_prompts_service.rb` → `copilot_response_generator`)

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
