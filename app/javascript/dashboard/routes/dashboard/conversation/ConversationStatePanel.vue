<script setup>
import { computed, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CaptainLearnedConversationsAPI from 'dashboard/api/captain/learnedConversations';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const currentChat = useMapGetter('getSelectedChat');
const store = useStore();
const { t } = useI18n();
const isLearningMenuOpen = ref(false);
const isLearningAction = ref(false);
const isCurrentConversation = computed(() => {
  if (!currentChat.value?.id) return false;
  return String(currentChat.value.id) === String(props.conversationId);
});

// Extract captain state from conversation
const captainState = computed(() => {
  if (!isCurrentConversation.value) return {};
  return currentChat.value?.captain_state || {};
});

// Check if Captain was involved in this conversation
const learningState = computed(
  () => currentChat.value?.captain_learning || null
);
const learningStatus = computed(() => learningState.value?.status || null);
const learningId = computed(() => learningState.value?.id || null);
const learningEligible = computed(
  () => currentChat.value?.captain_learning_eligible || false
);
const isLearned = computed(() => learningStatus.value === 'learned');

const hasCaptainInteraction = computed(() => {
  if (!isCurrentConversation.value) return false;
  if (learningEligible.value || learningState.value) return true;
  if (
    Object.keys(captainState.value).length > 0 ||
    currentChat.value?.captain_last_action_at != null
  ) {
    return true;
  }

  const messages = currentChat.value?.messages || [];
  return messages.some(message => {
    const senderType =
      message?.sender?.type || message?.sender_type || message?.senderType;
    const normalized = String(senderType || '').toLowerCase();
    return (
      normalized === 'agentbot' ||
      normalized === 'agent_bot' ||
      normalized === 'captain::assistant' ||
      normalized === 'captain_assistant'
    );
  });
});

const learningMenuItems = computed(() => [
  {
    label: t('CAPTAIN_STATE_PANEL.LEARNING_MENU.RELEARN'),
    action: 'relearn',
    value: 'relearn',
  },
  {
    label: t('CAPTAIN_STATE_PANEL.LEARNING_MENU.FORGET'),
    action: 'delete',
    value: 'forget',
  },
]);

const refreshConversation = async () => {
  if (!currentChat.value?.id) return;
  await store.dispatch('conversations/getConversation', currentChat.value.id);
};

const learnConversation = async (force = false) => {
  if (!currentChat.value?.id) return;

  isLearningAction.value = true;
  try {
    await CaptainLearnedConversationsAPI.learn({
      conversationId: currentChat.value.id,
      force,
    });
    useAlert(
      force
        ? t('CAPTAIN_STATE_PANEL.LEARNING.RELEARN_SUCCESS')
        : t('CAPTAIN_STATE_PANEL.LEARNING.LEARN_SUCCESS')
    );
    await refreshConversation();
  } catch (error) {
    useAlert(t('CAPTAIN_STATE_PANEL.LEARNING.LEARN_ERROR'));
  } finally {
    isLearningAction.value = false;
  }
};

const forgetConversation = async () => {
  if (!learningId.value) return;

  isLearningAction.value = true;
  try {
    await CaptainLearnedConversationsAPI.forget(learningId.value);
    useAlert(t('CAPTAIN_STATE_PANEL.LEARNING.FORGET_SUCCESS'));
    await refreshConversation();
  } catch (error) {
    useAlert(t('CAPTAIN_STATE_PANEL.LEARNING.FORGET_ERROR'));
  } finally {
    isLearningAction.value = false;
    isLearningMenuOpen.value = false;
  }
};

const handleLearningAction = async ({ action }) => {
  if (action === 'relearn') {
    await learnConversation(true);
    return;
  }

  if (action === 'delete') {
    await forgetConversation();
  }
};

// Computed properties for display
const turnCount = computed(() => captainState.value.turn_count || 0);

const issueSummary = computed(() => {
  return captainState.value.issue_summary || 'Not yet identified';
});

const attemptedSolutions = computed(() => {
  return captainState.value.attempted_solutions || [];
});

const sentimentTrend = computed(() => {
  const history = captainState.value.sentiment_history || [];
  if (history.length === 0)
    return { text: 'Neutral', color: 'gray', icon: 'emoji' };

  const recent = history.slice(-3);
  const negativeCount = recent.filter(h => h.sentiment === 'negative').length;

  if (negativeCount >= 2) {
    return {
      text: 'Frustrated',
      color: 'red',
      icon: 'alert-triangle',
      bgColor: 'bg-red-50',
      textColor: 'text-red-700',
    };
  }
  if (negativeCount === 1) {
    return {
      text: 'Slightly Concerned',
      color: 'yellow',
      icon: 'alert-circle',
      bgColor: 'bg-yellow-50',
      textColor: 'text-yellow-700',
    };
  }
  const recentSentiments = recent.map(h => h.sentiment);
  const hasPositive = recentSentiments.includes('positive');
  if (hasPositive) {
    return {
      text: 'Positive',
      color: 'green',
      icon: 'smile',
      bgColor: 'bg-green-50',
      textColor: 'text-green-700',
    };
  }
  return {
    text: 'Calm',
    color: 'gray',
    icon: 'minus-circle',
    bgColor: 'bg-gray-50',
    textColor: 'text-gray-700',
  };
});

const escalationSuggested = computed(() => {
  return captainState.value.escalation_suggested || false;
});

const escalationReasons = computed(() => {
  return captainState.value.escalation_reasons || [];
});

const humanIntervention = computed(() => {
  return captainState.value.human_intervention || null;
});

const humanTookOver = computed(() => {
  return humanIntervention.value?.happened || false;
});

// Feedback summary from attempted solutions
const feedbackSummary = computed(() => {
  const solutions = attemptedSolutions.value;
  const helpful = solutions.filter(s => s.agent_feedback === 'helpful').length;
  const unhelpful = solutions.filter(
    s => s.agent_feedback && s.agent_feedback !== 'helpful'
  ).length;

  return {
    total: helpful + unhelpful,
    helpful,
    unhelpful,
  };
});

// Helper to get solution feedback icon
const getSolutionIcon = solution => {
  if (solution.agent_feedback === 'helpful') return '✓';
  if (solution.agent_feedback) return '✗';
  return '•';
};

// Helper to get solution feedback color
const getSolutionColor = solution => {
  if (solution.agent_feedback === 'helpful') return 'text-green-600';
  if (solution.agent_feedback) return 'text-red-600';
  return 'text-gray-600';
};

// Format escalation reasons for display
const escalationReasonsText = computed(() => {
  const reasons = escalationReasons.value;
  const formatted = [];

  if (reasons.includes('too_many_turns')) {
    formatted.push('Too many conversation turns');
  }
  if (reasons.includes('repeated_suggestions')) {
    formatted.push('Repeated unsuccessful suggestions');
  }
  if (reasons.includes('user_frustrated')) {
    formatted.push('Customer showing frustration');
  }

  return formatted.length > 0 ? formatted.join(', ') : 'Multiple factors';
});
</script>

<template>
  <div v-show="hasCaptainInteraction" class="conversation-state-panel">
    <!-- Header -->
    <div
      class="flex items-center justify-between gap-2 mb-3 pb-2 border-b border-gray-200"
    >
      <div class="flex items-center gap-2">
        <fluent-icon icon="bot" size="18" class="text-blue-600" />
        <h4 class="text-sm font-semibold text-gray-800">
          {{ $t('CAPTAIN_STATE_PANEL.TITLE') }}
        </h4>
      </div>
      <div v-if="learningEligible" class="flex items-center gap-2">
        <span
          v-if="isLearned"
          class="text-xs px-2 py-1 rounded bg-green-100 text-green-800 font-medium"
        >
          {{ $t('CAPTAIN_STATE_PANEL.LEARNING.LEARNED_LABEL') }}
        </span>
        <Button
          v-else
          size="xs"
          color="slate"
          :label="$t('CAPTAIN_STATE_PANEL.LEARNING.LEARN_BUTTON')"
          :is-loading="isLearningAction"
          :disabled="isLearningAction"
          @click="learnConversation(true)"
        />
        <OnClickOutside @trigger="isLearningMenuOpen = false">
          <div v-if="isLearned" class="relative">
            <Button
              size="xs"
              color="slate"
              icon="i-lucide-chevron-down"
              @click="isLearningMenuOpen = !isLearningMenuOpen"
            />
            <DropdownMenu
              v-if="isLearningMenuOpen"
              class="mt-2 right-0"
              :menu-items="learningMenuItems"
              @action="handleLearningAction"
            />
          </div>
        </OnClickOutside>
      </div>
    </div>

    <!-- Turn Count -->
    <div class="mb-3">
      <div class="flex items-center justify-between">
        <span class="text-xs text-gray-600 font-medium">
          {{ $t('CAPTAIN_STATE_PANEL.CONVERSATION_TURNS') }}
        </span>
        <span class="text-sm font-semibold text-gray-900">
          {{ turnCount }}
        </span>
      </div>
    </div>

    <!-- Issue Summary -->
    <div v-if="issueSummary !== 'Not yet identified'" class="mb-3">
      <span class="text-xs text-gray-600 font-medium block mb-1">
        {{ $t('CAPTAIN_STATE_PANEL.ISSUE') }}
      </span>
      <p class="text-sm text-gray-800 bg-gray-50 p-2 rounded">
        {{ issueSummary }}
      </p>
    </div>

    <!-- Attempted Solutions -->
    <div v-if="attemptedSolutions.length > 0" class="mb-3">
      <span class="text-xs text-gray-600 font-medium block mb-2">
        {{
          $t('CAPTAIN_STATE_PANEL.SOLUTIONS_TRIED_COUNT', {
            count: attemptedSolutions.length,
          })
        }}
      </span>
      <ul class="space-y-1.5">
        <li
          v-for="(attempt, index) in attemptedSolutions"
          :key="index"
          class="text-sm flex items-start gap-2 bg-gray-50 p-2 rounded"
        >
          <span
            :class="getSolutionColor(attempt)"
            class="font-bold mt-0.5 flex-shrink-0"
          >
            {{ getSolutionIcon(attempt) }}
          </span>
          <div class="flex-1 min-w-0">
            <span class="text-gray-800 break-words">{{
              attempt.solution
            }}</span>
            <span
              v-if="attempt.agent_feedback"
              class="ml-2 text-xs text-gray-500 italic"
            >
              {{
                $t('CAPTAIN_STATE_PANEL.SOLUTION_FEEDBACK', {
                  feedback: attempt.agent_feedback,
                })
              }}
            </span>
          </div>
        </li>
      </ul>
    </div>

    <!-- Agent Feedback Summary -->
    <div v-if="feedbackSummary.total > 0" class="mb-3">
      <span class="text-xs text-gray-600 font-medium block mb-2">
        {{ $t('CAPTAIN_STATE_PANEL.AGENT_FEEDBACK') }}
      </span>
      <div class="flex gap-3 bg-gray-50 p-2 rounded">
        <div class="flex items-center gap-1">
          <fluent-icon icon="thumb-up" size="14" class="text-green-600" />
          <span class="text-sm font-semibold text-green-600">
            {{ feedbackSummary.helpful }}
          </span>
        </div>
        <div class="flex items-center gap-1">
          <fluent-icon icon="thumb-down" size="14" class="text-red-600" />
          <span class="text-sm font-semibold text-red-600">
            {{ feedbackSummary.unhelpful }}
          </span>
        </div>
      </div>
    </div>

    <!-- Customer Sentiment -->
    <div class="mb-3">
      <span class="text-xs text-gray-600 font-medium block mb-2">
        {{ $t('CAPTAIN_STATE_PANEL.CUSTOMER_SENTIMENT') }}
      </span>
      <div
        class="flex items-center gap-2 p-2 rounded"
        :class="sentimentTrend.bgColor"
      >
        <fluent-icon
          :icon="sentimentTrend.icon"
          size="16"
          :class="sentimentTrend.textColor"
        />
        <span class="text-sm font-medium" :class="sentimentTrend.textColor">
          {{ sentimentTrend.text }}
        </span>
      </div>
    </div>

    <!-- Escalation Suggestion -->
    <div
      v-if="escalationSuggested && !humanTookOver"
      class="mb-3 p-3 bg-amber-50 border border-amber-200 rounded"
    >
      <div class="flex items-start gap-2">
        <fluent-icon
          icon="lightbulb"
          size="16"
          class="text-amber-600 mt-0.5 flex-shrink-0"
        />
        <div class="flex-1">
          <p class="text-sm font-semibold text-amber-900 mb-1">
            {{ $t('CAPTAIN_STATE_PANEL.ESCALATION_SUGGESTED') }}
          </p>
          <p class="text-xs text-amber-700">
            {{ escalationReasonsText }}
          </p>
        </div>
      </div>
    </div>

    <!-- Human Takeover -->
    <div
      v-if="humanTookOver"
      class="p-3 bg-blue-50 border border-blue-200 rounded"
    >
      <div class="flex items-center gap-2">
        <fluent-icon icon="person" size="16" class="text-blue-600" />
        <p class="text-sm font-semibold text-blue-900">
          {{ $t('CAPTAIN_STATE_PANEL.HUMAN_TOOK_OVER') }}
        </p>
      </div>
      <p class="text-xs text-blue-700 mt-1 ml-6">
        {{
          $t('CAPTAIN_STATE_PANEL.HUMAN_TOOK_OVER_AT_TURN', {
            turn: humanIntervention.at_turn,
          })
        }}
      </p>
    </div>
  </div>
</template>

<style scoped>
.conversation-state-panel {
  @apply p-3;
}
</style>
