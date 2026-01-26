# Phase 1.1: Conversation Memory - Implementation Guide

**Start Date:** January 2026  
**Duration:** 4 weeks  
**Status:** Ready to begin  
**Prerequisites:** Performance optimizations complete ✅

---

## Overview

Phase 1.1 implements conversation state tracking to:
- Remember what solutions were already tried
- Detect frustration levels and auto-escalate when needed
- Track conversation context across multiple turns
- Prevent Captain from repeating failed suggestions

---

## Week-by-Week Plan

### Week 1: Database & Core Service

#### Goals
- Add conversation state storage
- Create conversation state service
- Basic state tracking functional

#### Tasks

**1. Add State Column to Conversations**
```ruby
# db/migrate/XXXXXX_add_captain_state_to_conversations.rb
class AddCaptainStateToConversations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :captain_state, :jsonb, default: {}
    add_index :conversations, :captain_state, using: :gin
    
    # Add resolution tracking
    add_column :conversations, :captain_resolution_status, :string
    add_column :conversations, :captain_last_action_at, :datetime
  end
end
```

**2. Create Conversation State Service**
```ruby
# enterprise/app/services/captain/conversation_state_service.rb
module Captain
  class ConversationStateService
    attr_reader :conversation, :state
    
    def initialize(conversation)
      @conversation = conversation
      @state = load_or_initialize_state
    end
    
    def track_solution_attempt(solution_id, result)
      @state[:attempted_solutions] ||= []
      @state[:attempted_solutions] << {
        solution: solution_id,
        result: result,
        timestamp: Time.current.to_i
      }
      
      # Keep only last 10 attempts to avoid bloat
      @state[:attempted_solutions] = @state[:attempted_solutions].last(10)
      
      save_state
      
      Captain::Logger.info(
        "[ConversationState] Tracked solution attempt",
        conversation_id: @conversation.id,
        solution: solution_id,
        result: result,
        total_attempts: @state[:attempted_solutions].size
      )
    end
    
    def track_sentiment(message_content, sender_type)
      return unless sender_type == 'user' # Only track user sentiment
      
      @state[:sentiment_history] ||= []
      
      # Simple keyword-based sentiment (enhance with LLM in future)
      sentiment = detect_sentiment(message_content)
      
      @state[:sentiment_history] << {
        sentiment: sentiment,
        timestamp: Time.current.to_i
      }
      
      # Keep only last 5 messages for sentiment
      @state[:sentiment_history] = @state[:sentiment_history].last(5)
      
      save_state
    end
    
    def increment_turn_count
      @state[:turn_count] ||= 0
      @state[:turn_count] += 1
      save_state
    end
    
    def update_issue_summary(summary)
      @state[:issue_summary] = summary
      save_state
    end
    
    def get_conversation_summary
      {
        issue: @state[:issue_summary],
        attempted_solutions: @state[:attempted_solutions] || [],
        sentiment_trend: calculate_sentiment_trend,
        turn_count: @state[:turn_count] || 0,
        should_escalate: should_escalate?,
        marked_for_review: marked_for_review?
      }
    end
    
    def should_escalate?
      reasons = []
      
      # Reason 1: Too many turns without resolution
      if (@state[:turn_count] || 0) > 10
        reasons << :too_many_turns
      end
      
      # Reason 2: Repeated failed solutions
      if repeated_failures_count >= 3
        reasons << :repeated_failures
      end
      
      # Reason 3: Negative sentiment trend
      if frustration_level == :angry
        reasons << :user_frustrated
      end
      
      # Reason 4: Same solution attempted multiple times
      if same_solution_repeated?
        reasons << :solution_loop
      end
      
      if reasons.any?
        Captain::Logger.info(
          "[ConversationState] Auto-escalation recommended",
          conversation_id: @conversation.id,
          reasons: reasons
        )
      end
      
      reasons.any?
    end
    
    def get_frustration_level
      calculate_sentiment_trend
    end
    
    private
    
    def load_or_initialize_state
      @conversation.captain_state || {}
    end
    
    def save_state
      @conversation.update_column(:captain_state, @state)
      @conversation.update_column(:captain_last_action_at, Time.current)
    end
    
    def marked_for_review?
      # Use existing label system (see CONVERSATION_MARKING_EVALUATION.md)
      @conversation.labels.include?('记录')
    end
    
    def detect_sentiment(message_content)
      # Simple keyword-based sentiment detection
      negative_keywords = ['frustrated', 'angry', 'upset', 'terrible', 
                          'awful', 'horrible', 'worst', 'hate',
                          '生气', '沮丧', '糟糕', '讨厌'] # Chinese keywords
      
      positive_keywords = ['thanks', 'thank you', 'great', 'perfect',
                          'excellent', 'awesome', 'solved', 'worked',
                          '谢谢', '太好了', '完美', '解决了']
      
      content_lower = message_content.downcase
      
      negative_count = negative_keywords.count { |kw| content_lower.include?(kw) }
      positive_count = positive_keywords.count { |kw| content_lower.include?(kw) }
      
      if negative_count > positive_count && negative_count > 0
        :negative
      elsif positive_count > negative_count && positive_count > 0
        :positive
      else
        :neutral
      end
    end
    
    def calculate_sentiment_trend
      history = @state[:sentiment_history] || []
      return :calm if history.empty?
      
      recent = history.last(3)
      negative_count = recent.count { |h| h[:sentiment] == :negative }
      
      case negative_count
      when 0..1 then :calm
      when 2 then :frustrated
      else :angry
      end
    end
    
    def repeated_failures_count
      attempts = @state[:attempted_solutions] || []
      attempts.count { |a| a[:result] == 'failed' }
    end
    
    def same_solution_repeated?
      attempts = @state[:attempted_solutions] || []
      return false if attempts.size < 2
      
      # Check if last 2 attempts are the same solution
      last_two = attempts.last(2)
      last_two[0][:solution] == last_two[1][:solution]
    end
  end
end
```

**3. Add Scopes to Conversation Model**
```ruby
# app/models/conversation.rb
class Conversation < ApplicationRecord
  # ... existing code ...
  
  # Phase 1.1: Conversation state scopes
  scope :captain_assisted, lambda {
    where("additional_attributes->>'captain_handled' = 'true'")
  }
  
  scope :marked_for_mining, -> { tagged_with('记录') }
  
  scope :should_escalate, lambda {
    where("captain_state->>'turn_count' > ?", 10)
      .or(where("captain_state->'sentiment_history' @> ?", 
                [{sentiment: 'negative'}].to_json))
  }
  
  def marked_for_mining?
    labels.include?('记录')
  end
  
  def captain_state_summary
    return nil unless captain_state.present?
    
    Captain::ConversationStateService.new(self).get_conversation_summary
  end
end
```

**4. Write Tests**
```ruby
# spec/services/captain/conversation_state_service_spec.rb
require 'rails_helper'

RSpec.describe Captain::ConversationStateService do
  let(:conversation) { create(:conversation) }
  let(:service) { described_class.new(conversation) }
  
  describe '#track_solution_attempt' do
    it 'records solution attempts' do
      service.track_solution_attempt('reset_device', 'failed')
      service.track_solution_attempt('update_firmware', 'success')
      
      summary = service.get_conversation_summary
      expect(summary[:attempted_solutions].size).to eq(2)
      expect(summary[:attempted_solutions].last[:result]).to eq('success')
    end
    
    it 'limits to 10 attempts' do
      15.times { |i| service.track_solution_attempt("solution_#{i}", 'failed') }
      
      summary = service.get_conversation_summary
      expect(summary[:attempted_solutions].size).to eq(10)
    end
  end
  
  describe '#should_escalate?' do
    it 'escalates after 10 turns' do
      11.times { service.increment_turn_count }
      expect(service.should_escalate?).to be true
    end
    
    it 'escalates after 3 failed attempts' do
      3.times { service.track_solution_attempt('reset', 'failed') }
      expect(service.should_escalate?).to be true
    end
    
    it 'escalates on negative sentiment' do
      service.track_sentiment("This is terrible and frustrating", 'user')
      service.track_sentiment("I'm so angry about this", 'user')
      service.track_sentiment("Worst experience ever", 'user')
      
      expect(service.get_frustration_level).to eq(:angry)
      expect(service.should_escalate?).to be true
    end
  end
end
```

**Deliverables:**
- [ ] Migration run successfully
- [ ] ConversationStateService implemented
- [ ] Tests passing (>90% coverage)
- [ ] Code reviewed

---

### Week 2: Integration with Captain Chat

#### Goals
- Integrate state tracking into Captain's chat flow
- Track solutions and sentiment automatically
- System prompt includes conversation state

#### Tasks

**1. Update Assistant Chat Service**
```ruby
# enterprise/app/services/captain/llm/assistant_chat_service.rb
class Captain::Llm::AssistantChatService
  def initialize(conversation:, message:, user: nil, assistant: nil)
    # ... existing initialization ...
    
    # NEW: Initialize conversation state tracker
    @state_tracker = Captain::ConversationStateService.new(conversation)
  end
  
  def perform
    # Track turn count
    @state_tracker.increment_turn_count
    
    # Track user sentiment
    if @message.incoming?
      @state_tracker.track_sentiment(@message.content, 'user')
    end
    
    # Check if should auto-escalate
    if @state_tracker.should_escalate?
      return handle_auto_escalation
    end
    
    # ... existing LLM call logic ...
    
    # After getting response, track if solution was provided
    if solution_suggested?(response)
      @state_tracker.track_solution_attempt(
        extract_solution_id(response),
        'suggested' # Will be 'failed' or 'success' on next turn
      )
    end
    
    # ... rest of existing code ...
  end
  
  private
  
  def build_system_prompt
    base_prompt = Captain::Llm::SystemPromptsService.new(@assistant, @conversation).generate_prompt
    
    # NEW: Add conversation state context
    state_context = build_state_context
    
    "#{base_prompt}\n\n#{state_context}"
  end
  
  def build_state_context
    summary = @state_tracker.get_conversation_summary
    
    return "" if summary[:turn_count] < 2 # Don't add context for first turn
    
    context_parts = []
    
    # Issue summary
    if summary[:issue].present?
      context_parts << "CURRENT ISSUE: #{summary[:issue]}"
    end
    
    # Attempted solutions
    if summary[:attempted_solutions].any?
      solutions_text = summary[:attempted_solutions].map do |s|
        "- #{s[:solution]} (#{s[:result]})"
      end.join("\n")
      
      context_parts << <<~TEXT
        ALREADY ATTEMPTED SOLUTIONS:
        #{solutions_text}
        
        IMPORTANT: Do NOT suggest these solutions again. They were already tried.
      TEXT
    end
    
    # Sentiment warning
    if summary[:sentiment_trend] == :frustrated
      context_parts << "⚠️ USER SENTIMENT: Customer is getting frustrated. Be extra helpful and consider escalating."
    elsif summary[:sentiment_trend] == :angry
      context_parts << "⚠️⚠️ USER SENTIMENT: Customer is very frustrated. Strongly recommend human agent assistance."
    end
    
    # Turn count warning
    if summary[:turn_count] > 7
      context_parts << "⚠️ TURN COUNT: This is turn ##{summary[:turn_count]}. If solution isn't found soon, recommend human agent."
    end
    
    context_parts.join("\n\n")
  end
  
  def handle_auto_escalation
    Captain::Logger.info(
      "[AssistantChat] Auto-escalating conversation",
      conversation_id: @conversation.id,
      reason: @state_tracker.should_escalate?
    )
    
    # Create escalation message
    create_message(
      content: generate_escalation_message,
      message_type: :outgoing,
      private: false
    )
    
    # Update conversation status
    @conversation.update!(
      status: :open,
      captain_resolution_status: 'escalated_auto'
    )
    
    # Optionally assign to team/agent (configure per assistant)
    auto_assign_on_escalation if @assistant.config['auto_assign_on_escalation']
  end
  
  def generate_escalation_message
    summary = @state_tracker.get_conversation_summary
    reasons = []
    
    if summary[:turn_count] > 10
      reasons << "we've discussed this for several turns"
    end
    
    if summary[:attempted_solutions].count { |s| s[:result] == 'failed' } >= 3
      reasons << "several solutions haven't resolved the issue"
    end
    
    reason_text = reasons.any? ? " Since #{reasons.join(' and ')}, " : " "
    
    "I understand this issue needs more specialized attention.#{reason_text}Let me connect you with one of our support specialists who can help you directly. They'll have the full context of our conversation."
  end
  
  def solution_suggested?(response)
    # Simple check - enhance as needed
    response.downcase.include?('try') ||
      response.downcase.include?('you can') ||
      response.downcase.include?('please')
  end
  
  def extract_solution_id(response)
    # Simple extraction - enhance with better parsing
    response[0..100].gsub(/[^a-z0-9]/i, '_').downcase
  end
end
```

**2. Add State Context to Messages**
```ruby
# enterprise/app/helpers/captain/chat_helper.rb
module Captain
  module ChatHelper
    # ... existing code ...
    
    def build_messages_for_llm
      messages = []
      
      # System prompt with state context
      messages << {
        role: 'system',
        content: build_system_prompt
      }
      
      # Conversation state summary as system message
      if @conversation.messages.count > 1
        state_summary = conversation_state_summary
        messages << {
          role: 'system',
          content: "CONVERSATION CONTEXT:\n#{state_summary}"
        } if state_summary.present?
      end
      
      # ... existing message building ...
      
      messages
    end
    
    def conversation_state_summary
      state_tracker = Captain::ConversationStateService.new(@conversation)
      summary = state_tracker.get_conversation_summary
      
      parts = []
      parts << "Turn: #{summary[:turn_count]}" if summary[:turn_count] > 0
      parts << "Issue: #{summary[:issue]}" if summary[:issue].present?
      
      if summary[:attempted_solutions].any?
        parts << "Attempted: #{summary[:attempted_solutions].map { |s| s[:solution] }.join(', ')}"
      end
      
      parts.join(" | ")
    end
  end
end
```

**3. Update Captain Logger Calls**
```ruby
# Ensure all state changes are logged
Captain::Logger.info(
  "[ConversationState] State updated",
  conversation_id: conversation.id,
  turn_count: state[:turn_count],
  attempted_solutions: state[:attempted_solutions]&.size || 0,
  sentiment: calculate_sentiment_trend
)
```

**Deliverables:**
- [ ] State tracking integrated into chat flow
- [ ] System prompts include conversation context
- [ ] Auto-escalation functional
- [ ] Logging captures state changes
- [ ] Integration tests passing

---

### Week 3: UI Enhancements & Agent Tools

#### Goals
- Show conversation state to agents
- Add manual escalation with context
- Display solution history in sidebar

#### Tasks

**1. Add State Display to Conversation Sidebar**
```vue
<!-- NEW: app/javascript/dashboard/routes/dashboard/conversation/ConversationStatePanel.vue -->
<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  conversationId: {
    type: Number,
    required: true,
  },
});

const store = useStore();

const conversation = computed(() => 
  store.getters.getSelectedChat
);

const stateInfo = computed(() => {
  const state = conversation.value?.captain_state || {};
  return {
    turnCount: state.turn_count || 0,
    issue: state.issue_summary || 'Not yet identified',
    attempts: state.attempted_solutions || [],
    sentiment: getSentimentDisplay(state.sentiment_history),
    shouldEscalate: checkEscalation(state),
  };
});

const getSentimentDisplay = (history) => {
  if (!history || history.length === 0) return { text: 'Neutral', color: 'gray' };
  
  const recent = history.slice(-3);
  const negativeCount = recent.filter(h => h.sentiment === 'negative').length;
  
  if (negativeCount >= 2) {
    return { text: 'Frustrated', color: 'red' };
  } else if (negativeCount === 1) {
    return { text: 'Slightly Concerned', color: 'yellow' };
  } else {
    return { text: 'Calm', color: 'green' };
  }
};

const checkEscalation = (state) => {
  const turnCount = state.turn_count || 0;
  const failedAttempts = (state.attempted_solutions || [])
    .filter(a => a.result === 'failed').length;
  
  return turnCount > 10 || failedAttempts >= 3;
};
</script>

<template>
  <div class="conversation-state-panel p-4 border-b">
    <h3 class="text-sm font-semibold mb-3">AI Assistant Status</h3>
    
    <!-- Turn Count -->
    <div class="mb-3">
      <span class="text-xs text-gray-600">Conversation Turns:</span>
      <span class="ml-2 font-medium">{{ stateInfo.turnCount }}</span>
    </div>
    
    <!-- Issue Summary -->
    <div class="mb-3">
      <span class="text-xs text-gray-600">Issue:</span>
      <p class="text-sm mt-1">{{ stateInfo.issue }}</p>
    </div>
    
    <!-- Solution Attempts -->
    <div v-if="stateInfo.attempts.length > 0" class="mb-3">
      <span class="text-xs text-gray-600">Solutions Tried:</span>
      <ul class="mt-1 space-y-1">
        <li 
          v-for="(attempt, index) in stateInfo.attempts"
          :key="index"
          class="text-sm flex items-center"
        >
          <span 
            :class="attempt.result === 'success' ? 'text-green-600' : 'text-red-600'"
            class="mr-2"
          >
            {{ attempt.result === 'success' ? '✓' : '✗' }}
          </span>
          <span class="truncate">{{ attempt.solution }}</span>
        </li>
      </ul>
    </div>
    
    <!-- Sentiment -->
    <div class="mb-3">
      <span class="text-xs text-gray-600">Customer Sentiment:</span>
      <span 
        :class="`ml-2 text-${stateInfo.sentiment.color}-600 font-medium`"
      >
        {{ stateInfo.sentiment.text }}
      </span>
    </div>
    
    <!-- Escalation Warning -->
    <div 
      v-if="stateInfo.shouldEscalate"
      class="p-2 bg-amber-50 border border-amber-200 rounded"
    >
      <span class="text-xs text-amber-800">
        ⚠️ Consider assigning to human agent
      </span>
    </div>
  </div>
</template>
```

**2. Integrate into Sidebar**
```vue
<!-- Update: app/javascript/dashboard/routes/dashboard/conversation/ConversationSidebar.vue -->
<template>
  <div class="conversation-sidebar">
    <!-- Existing sidebar content -->
    
    <!-- NEW: Add conversation state panel -->
    <ConversationStatePanel 
      v-if="currentChat.captain_state"
      :conversation-id="currentChat.id"
    />
    
    <!-- Rest of sidebar -->
  </div>
</template>

<script>
import ConversationStatePanel from './ConversationStatePanel.vue';

export default {
  components: {
    ConversationStatePanel,
  },
  // ... existing code ...
};
</script>
```

**3. Update API to Include State**
```ruby
# app/views/api/v1/models/_conversation.json.jbuilder
json.id conversation.id
# ... existing fields ...

# NEW: Include Captain state for agents
if conversation.captain_state.present?
  json.captain_state do
    json.turn_count conversation.captain_state['turn_count']
    json.issue_summary conversation.captain_state['issue_summary']
    json.attempted_solutions conversation.captain_state['attempted_solutions']
    json.should_escalate Captain::ConversationStateService.new(conversation).should_escalate?
  end
end
```

**Deliverables:**
- [ ] Conversation state panel component created
- [ ] Integrated into conversation sidebar
- [ ] API returns state information
- [ ] UI displays correctly for agents

---

### Week 4: Testing, Polish & Documentation

#### Goals
- Comprehensive testing
- Performance optimization
- Documentation complete
- Ready for production

#### Tasks

**1. Integration Tests**
```ruby
# spec/requests/captain/conversation_state_spec.rb
require 'rails_helper'

RSpec.describe 'Captain Conversation State', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:assistant) { create(:agent_bot, account: account) }
  
  describe 'State persistence across messages' do
    it 'tracks turn count correctly' do
      3.times do
        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.id}/messages",
             params: { content: 'Test message' },
             headers: auth_headers(user)
      end
      
      conversation.reload
      expect(conversation.captain_state['turn_count']).to eq(3)
    end
  end
  
  describe 'Auto-escalation' do
    it 'escalates after 10 turns' do
      state_service = Captain::ConversationStateService.new(conversation)
      11.times { state_service.increment_turn_count }
      
      # Send message that should trigger escalation
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.id}/messages",
           params: { content: 'Still need help' },
           headers: auth_headers(user)
      
      conversation.reload
      expect(conversation.captain_resolution_status).to eq('escalated_auto')
    end
  end
end
```

**2. Performance Testing**
```ruby
# spec/performance/conversation_state_performance_spec.rb
require 'rails_helper'
require 'benchmark'

RSpec.describe 'ConversationState Performance' do
  it 'handles 1000 state updates efficiently' do
    conversation = create(:conversation)
    service = Captain::ConversationStateService.new(conversation)
    
    time = Benchmark.realtime do
      1000.times do |i|
        service.track_solution_attempt("solution_#{i}", 'failed')
      end
    end
    
    expect(time).to be < 5.0 # Should complete in under 5 seconds
  end
  
  it 'queries marked conversations efficiently' do
    # Create 1000 conversations, 100 marked
    1000.times do |i|
      conv = create(:conversation)
      conv.label_list.add('记录') if i % 10 == 0
      conv.save
    end
    
    time = Benchmark.realtime do
      Conversation.marked_for_mining.count
    end
    
    expect(time).to be < 0.1 # Should complete in under 100ms
  end
end
```

**3. Documentation**
```markdown
# docs/improve/PHASE_1_1_USAGE.md
# Phase 1.1: Conversation Memory - Usage Guide

## For Developers

### Tracking Solution Attempts
```ruby
state_tracker = Captain::ConversationStateService.new(conversation)
state_tracker.track_solution_attempt('reset_wifi', 'failed')
state_tracker.track_solution_attempt('update_firmware', 'success')
```

### Checking Escalation Status
```ruby
if state_tracker.should_escalate?
  # Handle escalation
end
```

### Getting Conversation Summary
```ruby
summary = state_tracker.get_conversation_summary
# => {
#   issue: "WiFi connection problems",
#   attempted_solutions: [...],
#   sentiment_trend: :frustrated,
#   turn_count: 8,
#   should_escalate: true
# }
```

## For Agents

### Viewing Conversation State
1. Open any conversation handled by Captain
2. Look for "AI Assistant Status" panel in sidebar
3. Review:
   - Turn count
   - Issue summary
   - Solutions tried
   - Customer sentiment
   - Escalation recommendation

### Manual Escalation
- If state recommends escalation, assign conversation to yourself or a team
- Full context is preserved for smooth handoff

## For Product/QA

### Testing Checklist
- [ ] Turn count increments correctly
- [ ] Solution attempts are tracked
- [ ] Sentiment detection works (test with negative keywords)
- [ ] Auto-escalation triggers after 10 turns
- [ ] Auto-escalation triggers after 3 failed solutions
- [ ] State persists across page refreshes
- [ ] Sidebar shows state information
- [ ] Performance is acceptable (<100ms for state updates)
```

**4. Performance Monitoring**
```ruby
# Add to metrics service
def conversation_state_metrics(date = Date.today)
  conversations = Conversation.captain_assisted
                              .where(created_at: date.beginning_of_day..date.end_of_day)
  
  {
    total_with_state: conversations.where.not(captain_state: {}).count,
    avg_turn_count: conversations.average("(captain_state->>'turn_count')::int"),
    auto_escalations: conversations.where(captain_resolution_status: 'escalated_auto').count,
    sentiment_breakdown: {
      calm: conversations_by_sentiment(conversations, :calm),
      frustrated: conversations_by_sentiment(conversations, :frustrated),
      angry: conversations_by_sentiment(conversations, :angry)
    }
  }
end
```

**Deliverables:**
- [ ] All tests passing (>90% coverage)
- [ ] Performance benchmarks met
- [ ] Documentation complete
- [ ] Code reviewed and approved
- [ ] Deployed to staging
- [ ] QA sign-off
- [ ] Ready for production deployment

---

## Success Criteria

### Technical
- ✅ All tests passing with >90% coverage
- ✅ State updates < 100ms average
- ✅ No memory leaks (state limited to 10 items max)
- ✅ Zero regression in existing features
- ✅ Logging comprehensive for debugging

### Functional
- ✅ Turn counting works accurately
- ✅ Solution tracking prevents repeats
- ✅ Sentiment detection catches frustration
- ✅ Auto-escalation triggers correctly
- ✅ Agents can view state in UI

### Quality
- ✅ Code reviewed by 2+ engineers
- ✅ Documentation complete
- ✅ QA tested all scenarios
- ✅ Performance tested with realistic data
- ✅ Rollback plan documented

---

## Rollout Plan

### Staging (Week 4, Days 1-2)
1. Deploy to staging environment
2. Run automated tests
3. Manual QA testing
4. Performance validation
5. Fix any issues found

### Production (Week 4, Days 3-5)
1. Deploy during low-traffic window
2. Monitor logs for errors
3. Check performance metrics
4. Verify state tracking working
5. Collect agent feedback

### Monitoring (Week 4+)
- Watch `log/captain.log` for state-related logs
- Monitor database size (captain_state column)
- Track auto-escalation rate
- Collect agent feedback on UI

---

## Troubleshooting

### State Not Persisting
```ruby
# Check if captain_state column exists
Conversation.column_names.include?('captain_state')

# Check state is being saved
conversation.reload
conversation.captain_state
```

### Auto-Escalation Not Triggering
```ruby
# Check escalation logic
state_tracker = Captain::ConversationStateService.new(conversation)
state_tracker.should_escalate? # Should return true/false
state_tracker.get_conversation_summary # Review state
```

### Performance Issues
```ruby
# Check state size
conversation.captain_state.to_json.bytesize # Should be < 5KB

# Check query performance
Conversation.marked_for_mining.explain
```

---

## Next Steps After Phase 1.1

Once Phase 1.1 is complete and stable:

1. **Collect Metrics** (2-4 weeks)
   - How often does auto-escalation trigger?
   - What's the average turn count?
   - How accurate is sentiment detection?

2. **Iterate Based on Feedback**
   - Adjust escalation thresholds
   - Improve sentiment detection
   - Add more solution tracking

3. **Prepare for Phase 1.2** (Search Enhancement)
   - Review conversation state usage patterns
   - Identify search improvement opportunities
   - Plan query expansion implementation

---

**Questions? Check:**
- Technical details: `/enterprise/app/services/captain/conversation_state_service.rb`
- Integration: `/enterprise/app/services/captain/llm/assistant_chat_service.rb`
- UI: `/app/javascript/dashboard/routes/dashboard/conversation/ConversationStatePanel.vue`
- Tests: `/spec/services/captain/conversation_state_service_spec.rb`
