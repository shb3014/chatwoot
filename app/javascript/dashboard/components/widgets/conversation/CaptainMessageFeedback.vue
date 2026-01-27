<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  messageId: {
    type: Number,
    required: true,
  },
  senderType: {
    type: String,
    required: true,
  },
});

const store = useStore();
const showFeedbackMenu = ref(false);
const submitting = ref(false);

// Get feedback from store if it exists
const currentFeedback = computed(() => {
  return store.getters['captainFeedback/getFeedbackForMessage'](
    props.messageId
  );
});

const isCaptainMessage = computed(() => {
  const normalized = (props.senderType || '').toLowerCase();
  return (
    normalized === 'agentbot' ||
    normalized === 'agent_bot' ||
    normalized === 'captain::assistant' ||
    normalized === 'captain_assistant'
  );
});

const feedbackOptions = [
  {
    value: 'helpful',
    label: '✅ Helpful',
    icon: 'thumb-up',
    rating: 1,
    color: 'text-green-600',
  },
  {
    value: 'unhelpful',
    label: '❌ Not Helpful',
    icon: 'thumb-down',
    rating: -1,
    color: 'text-red-600',
  },
  {
    value: 'incorrect',
    label: '⚠️ Incorrect Info',
    icon: 'alert-circle',
    rating: -1,
    color: 'text-orange-600',
  },
  {
    value: 'incomplete',
    label: '📝 Incomplete',
    icon: 'minus-circle',
    rating: 0,
    color: 'text-gray-600',
  },
  {
    value: 'too_technical',
    label: '🔧 Too Technical',
    icon: 'settings',
    rating: 0,
    color: 'text-blue-600',
  },
  {
    value: 'too_vague',
    label: '💬 Too Vague',
    icon: 'message-circle',
    rating: 0,
    color: 'text-purple-600',
  },
];

const submitFeedback = async (feedbackType, rating) => {
  if (submitting.value) return;

  submitting.value = true;

  try {
    await store.dispatch('captainFeedback/create', {
      messageId: props.messageId,
      rating: rating,
      feedbackType: feedbackType,
    });

    useAlert('Feedback recorded successfully');
    showFeedbackMenu.value = false;
  } catch (error) {
    useAlert('Failed to record feedback. Please try again.');
  } finally {
    submitting.value = false;
  }
};

const getFeedbackLabel = feedbackType => {
  const option = feedbackOptions.find(opt => opt.value === feedbackType);
  return option ? option.label : feedbackType;
};

const getFeedbackColor = rating => {
  if (rating > 0) return 'bg-green-100 text-green-800';
  if (rating < 0) return 'bg-red-100 text-red-800';
  return 'bg-gray-100 text-gray-800';
};

const toggleMenu = () => {
  showFeedbackMenu.value = !showFeedbackMenu.value;
};

const closeMenu = () => {
  showFeedbackMenu.value = false;
};
</script>

<template>
  <div
    v-show="isCaptainMessage"
    class="captain-message-feedback relative z-10 pointer-events-auto"
  >
    <div class="flex items-center gap-2 mt-2">
      <!-- Show current feedback if exists -->
      <span
        v-if="currentFeedback"
        class="text-xs px-2 py-1 rounded font-medium"
        :class="getFeedbackColor(currentFeedback.rating)"
      >
        {{ getFeedbackLabel(currentFeedback.feedback_type) }}
      </span>

      <!-- Show feedback button if no feedback yet -->
      <button
        v-else
        class="text-xs text-gray-500 hover:text-gray-700 flex items-center gap-1 px-2 py-1 rounded hover:bg-gray-100 transition-colors"
        :disabled="submitting"
        @click.stop="toggleMenu"
        @mousedown.stop
        @mouseup.stop
      >
        <fluent-icon icon="emoji" size="14" />
        <span>{{ $t('CAPTAIN_MESSAGE_FEEDBACK.RATE_RESPONSE') }}</span>
      </button>

      <!-- Feedback menu -->
      <div
        v-if="showFeedbackMenu"
        v-on-clickaway="closeMenu"
        class="absolute z-50 mt-1 bg-white rounded-lg shadow-lg border border-gray-200 p-2 space-y-1 min-w-[200px]"
        @click.stop
        @mousedown.stop
        @mouseup.stop
      >
        <button
          v-for="option in feedbackOptions"
          :key="option.value"
          :disabled="submitting"
          class="w-full text-left px-3 py-2 text-sm hover:bg-gray-100 rounded flex items-center gap-2 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          :class="option.color"
          @click.stop="submitFeedback(option.value, option.rating)"
          @mousedown.stop
          @mouseup.stop
        >
          <fluent-icon :icon="option.icon" size="16" />
          <span>{{ option.label }}</span>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.captain-message-feedback {
  position: relative;
}
</style>
