# Captain Conversation State Integration Example

## Overview

This document shows how to integrate the conversation state tracking into Captain's response generation.

## Integration Points

### 1. In your Captain message handler (wherever Captain generates responses)

```ruby
# Example: When processing an incoming message to Captain
def handle_captain_message(conversation, incoming_message)
  # Initialize conversation handler
  handler = Captain::ConversationHandlerService.new(conversation, incoming_message)
  
  # BEFORE generating response
  handler.before_response
  
  # Get context to inject into system prompt
  state_context = handler.get_prompt_context
  
  # Generate Captain's response (your existing logic)
  captain_response = generate_captain_response(
    conversation, 
    incoming_message,
    additional_context: state_context # Add state context to prompt
  )
  
  # AFTER generating response
  # Extract solution ID if Captain suggested a specific solution
  solution_id = extract_solution_id(captain_response.content)
  handler.after_response(captain_response, solution_id: solution_id)
  
  # Check if should add escalation suggestion
  if handler.should_suggest_escalation?
    captain_response.content += handler.escalation_message
  end
  
  captain_response
end
```

### 2. Auto-Detection of Human Takeover

Human takeover is automatically detected when an agent sends a message:
- The `Message` model has an `after_create` callback
- When an agent sends a message in a conversation where Captain was active
- The system automatically calls `ConversationStateService#track_human_takeover`

No additional code needed!

### 3. Agent Feedback Collection

Agents can provide feedback via the API:

```javascript
// Frontend: When agent clicks feedback button
POST /api/v1/accounts/:account_id/captain/message_feedbacks

{
  message_id: 12345,
  rating: 1,  // 1 = helpful, -1 = unhelpful, 0 = neutral
  feedback_type: "helpful",  // helpful, unhelpful, incorrect, incomplete, too_technical, too_vague
  notes: "This solution worked perfectly"
}
```

The feedback is automatically integrated into the conversation state.

## Key Services

### ConversationStateService
- Tracks turn count, solutions, sentiment, escalation suggestions
- Stores state in `conversations.captain_state` JSON column

### MessageFeedbackService
- Records agent feedback on Captain messages
- Updates conversation state with feedback

### ConversationHandlerService
- Orchestrates state tracking before/after responses
- Provides context for system prompts
- Determines escalation suggestions

## Data Flow

```
User Message
  ↓
ConversationHandlerService.before_response()
  - Track sentiment
  - Increment turn count
  - Update issue summary
  ↓
Generate Captain Response (with state context in prompt)
  ↓
ConversationHandlerService.after_response()
  - Track solution attempt
  - Check escalation need
  ↓
[Optional] Agent provides feedback
  ↓
MessageFeedbackService.record_feedback()
  - Store feedback
  - Update conversation state
  ↓
Next Captain response uses feedback context
```

## Database Schema

### conversations.captain_state (JSONB)
```json
{
  "turn_count": 5,
  "issue_summary": "WiFi connection problems",
  "attempted_solutions": [
    {
      "solution": "reset_router",
      "result": "suggested",
      "timestamp": 1234567890,
      "message_id": 123,
      "agent_feedback": "helpful"
    }
  ],
  "sentiment_history": [
    {"sentiment": "neutral", "timestamp": 1234567890},
    {"sentiment": "frustrated", "timestamp": 1234567900}
  ],
  "escalation_suggested": false,
  "human_intervention": {
    "happened": true,
    "agent_id": 456,
    "at_turn": 5,
    "timestamp": 1234567890
  }
}
```

### captain_message_feedbacks
- message_id, conversation_id, rated_by_id
- rating (-1, 0, 1)
- feedback_type (helpful, unhelpful, incorrect, etc.)
- notes, issue_resolved, resolution_method

## Testing

```ruby
# Test state tracking
conversation = create(:conversation)
message = create(:message, conversation: conversation)
handler = Captain::ConversationHandlerService.new(conversation, message)

handler.before_response
expect(conversation.reload.captain_state['turn_count']).to eq(1)

# Test feedback recording
service = Captain::MessageFeedbackService.new(message, agent)
result = service.record_feedback(rating: 1, feedback_type: 'helpful')
expect(result[:success]).to be true
```

## Production Deployment

1. **Run migrations** on production:
   ```bash
   bundle exec rails db:migrate
   ```

2. **Integrate into existing Captain code**:
   - Find where Captain generates responses
   - Wrap with `ConversationHandlerService` calls
   - Add state context to system prompts

3. **Enable frontend feedback UI** (Phase 1 Sessions 7-9)

4. **Monitor logs**:
   ```bash
   tail -f log/captain.log | grep ConversationState
   ```

## Important Notes

- **No auto-resolve**: System only suggests escalation, never forces status changes
- **Human feedback critical**: Agent feedback improves future responses
- **Safe for production**: Only adds columns, no data loss
- **Cloud deployment**: Migrations are safe to run on cloud Ubuntu environment

## Next Steps

After integration:
1. Test with real conversations
2. Monitor state tracking in logs
3. Collect agent feedback for 1-2 weeks
4. Run historical mining (Phase 1.5) to analyze patterns
