# Captain Conversation Learning Summary

## Overview
This document summarizes the implementation of the automatic conversation learning flow for Captain. The goal is to replace per-message manual rating with an LLM-driven process that learns from full conversations involving both Captain and human agents. The system now:

- Automatically summarizes the issue and resolution for eligible conversations.
- Can reject low-signal conversations and record a rejection reason.
- Stores summaries as embeddings for future retrieval.
- Exposes a learn/learned UI in the conversation header with relearn/forget actions.
- Provides a Captain > Conversations page to browse learned conversations.
- Injects learned conversation context into future Captain replies.

## Goals
- Reduce agent workload by avoiding manual per-message rating.
- Prioritize human responses as source-of-truth for summaries.
- Provide a reusable knowledge memory via embeddings.
- Keep the learning flow automatic but still controllable (learn, relearn, forget).

## Backend Architecture

### Data Model
Learned conversations are stored in `captain_conversation_learnings`:
- `issue_summary`, `resolution_summary`
- `quality_rating` (0–100 scale)
- `rejection_reason`, `rejected_at` (when learning is rejected)
- `embedding` (pgvector)
- `status` (`learned` / `forgotten` / `rejected`)
- `learned_at`, `last_message_at`
- `account_id`, `assistant_id`, `conversation_id` (unique per conversation)

### Learning Service
`Captain::ConversationLearningService` orchestrates the flow:
- Checks eligibility (`captain_learning_eligible?`).
- Summarizes via `Captain::Llm::ConversationLearningSummaryService`.
- Persists summaries + rating + timestamps.
- Stores rejection reason when the LLM rejects learning.
- Touches `conversation.updated_at` to trigger frontend updates.

### Summary Prompt
`Captain::Llm::SystemPromptsService#conversation_learning_summary` instructs the LLM to:
- Decide whether to accept or reject learning and provide a reason when rejected.
- Summarize issue and resolution using only transcript facts.
- Prefer human responses when conflicting.
- Output JSON with `issue_summary`, `resolution_summary`, and `quality_rating`.

### Embeddings
`Captain::ConversationLearning` computes an embedding over:
- `Issue: <issue_summary>`
- `Resolution: <resolution_summary>`

Embeddings are updated asynchronously via `Captain::Llm::UpdateEmbeddingJob`.

### Automatic Trigger
Learning is queued when a human agent takes over a Captain conversation:
- `Message#detect_human_takeover` calls `ConversationLearningService#enqueue_learning`.

### API Endpoints
`Api::V1::Accounts::Captain::LearnedConversationsController` provides:
- `index` (list learned conversations)
- `show` (single learned conversation)
- `create` (learn / relearn)
- `destroy` (forget + clear summaries + embeddings)

### Conversation Serializer
Conversation payload includes:
- `captain_learning_eligible`
- `captain_learning` (summary + status + rating)

## Frontend Experience

### Conversation Header UI
Learn/Learned UI lives in the conversation top bar:
- Shows **Learn** button when eligible and not learned.
- Shows **Learned** badge (and rating) when learned.
- Dropdown provides:
  - **Relearn this conversation**
  - **Forget this conversation**

UI refresh is immediate after learn/forget by:
- Directly updating Vuex conversation state.
- Touching `updated_at` on the backend.

### Captain > Conversations Page
`/captain/conversations` lists learned conversations:
- Issue + resolution summaries.
- Rating (0–100).
- Inline actions: **View conversation** and **Remove**.

### Store + API Client
Dedicated Vuex module and API client manage:
- List fetch/pagination
- Learn/relearn/forget actions

### Rating Scale
The quality rating is normalized and stored on a **0–100** scale.

## Retrieval Into Future Responses
Learned conversations now influence new Captain replies:
- `Captain::Llm::AssistantChatService` injects learned context.
- `Captain::Llm::LearnedConversationsContextService`:
  - Embeds the user’s latest query.
  - Searches `captain_conversation_learnings` by cosine distance.
  - Filters by minimum rating threshold (default 60).
  - Sorts by rating (desc) then distance (asc) for relevance.
  - Injects top results as a system context block.

Result format (system context):
- Conversation identifier (display ID if available)
- Issue summary
- Resolution summary
- Rating (if present)

## Removals and Cleanups
As part of simplifying the flow:
- The per-message “Rate this response” feature was removed.
- The AI Assistant Status sidebar panel was removed.
- The “Add record label” action was removed from the conversation header.

## Key Files (Reference)
- `enterprise/app/models/captain/conversation_learning.rb`
- `enterprise/app/services/captain/conversation_learning_service.rb`
- `enterprise/app/services/captain/llm/conversation_learning_summary_service.rb`
- `enterprise/app/services/captain/llm/learned_conversations_context_service.rb`
- `enterprise/app/controllers/api/v1/accounts/captain/learned_conversations_controller.rb`
- `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue`
- `app/javascript/dashboard/routes/dashboard/captain/conversations/Index.vue`
- `app/javascript/dashboard/store/captain/learnedConversations.js`

## Operational Notes
- Learning only runs when a conversation has both Captain and human agent messages.
- Forgetting a conversation clears summaries, embeddings, and learned status.
- Relearn forces regeneration even if previously learned.

## Current Behavior Summary
Captain automatically learns from eligible conversations, stores them with embeddings, exposes them in the UI, and uses the learned summaries to improve future responses through retrieval at inference time.

## Recent Updates and Fixes (2026-01-27)
- Auto-learn on resolve now forces a learning run to avoid "up-to-date" skips when a conversation is resolved without new messages.
- Conversation learning broadcasts `conversation.updated` after completion so the frontend can update state without refresh.
- ActionCable payloads now include `captain_learning` and `captain_learning_eligible` via the enterprise event presenter, ensuring the learn/learned UI reflects background updates.
- Rejected learning now surfaces a dedicated notification message ("Conversation rejected").
