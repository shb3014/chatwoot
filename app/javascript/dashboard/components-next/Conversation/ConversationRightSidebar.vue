<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConfig } from 'dashboard/composables/useConfig';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import Copilot from 'dashboard/components-next/copilot/Copilot.vue';
import CopilotSummary from 'dashboard/components-next/copilot/CopilotSummary.vue';

const props = defineProps({
  currentChat: {
    required: true,
    type: Object,
  },
});

const store = useStore();
const { uiSettings, updateUISettings } = useUISettings();
const { isEnterprise } = useConfig();

// --- Constants ---
const SIDEBAR_MIN_WIDTH = 280;
const SIDEBAR_MAX_WIDTH = 560;
const SIDEBAR_DEFAULT_WIDTH = 320;
const SIDEBAR_FOLDED_WIDTH = 48;

// --- State ---
const activeTab = ref('copilot');
const isFolded = ref(uiSettings.value.is_sidebar_folded || false);
const sidebarWidth = ref(
  uiSettings.value.sidebar_custom_width || SIDEBAR_DEFAULT_WIDTH
);
const isResizing = ref(false);

// Copilot thread state (per conversation)
const conversationThreadMap = ref({});

// Summary state (per conversation)
const summaryMap = ref({});
const summaryLoadingMap = ref({});
const summaryErrorMap = ref({});

// Suggest answer loading state — shows loader before messages arrive
const isWaitingForSuggest = ref(false);

// --- Getters ---
const assistants = useMapGetter('captainAssistants/getRecords');
const inboxAssistant = useMapGetter('getCopilotAssistant');
const currentAccountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const showCopilotTab = computed(() => {
  if (!isEnterprise) return false;
  return isFeatureEnabledonAccount.value(
    currentAccountId.value,
    FEATURE_FLAGS.CAPTAIN
  );
});

// If copilot is not available, default to contact tab
watch(
  showCopilotTab,
  show => {
    if (!show) {
      activeTab.value = 'contact';
    }
  },
  { immediate: true }
);

const conversationInboxType = computed(
  () => props.currentChat?.meta?.channel || ''
);

// --- Summary state for current conversation ---
const currentConvId = computed(() => props.currentChat?.id);

const currentSummary = computed(
  () => summaryMap.value[currentConvId.value] || null
);
const isSummaryLoading = computed(
  () => summaryLoadingMap.value[currentConvId.value] || false
);
const hasSummaryError = computed(
  () => summaryErrorMap.value[currentConvId.value] || false
);

// --- Copilot thread management ---
const selectedCopilotThreadId = computed(() => {
  const convId = currentConvId.value;
  return convId ? conversationThreadMap.value[convId] || null : null;
});

const messages = computed(() =>
  store.getters['copilotMessages/getMessagesByThreadId'](
    selectedCopilotThreadId.value
  )
);

const streamingContent = computed(() =>
  store.getters['copilotMessages/getStreamingContent'](
    selectedCopilotThreadId.value
  )
);

const activeAssistant = computed(() => {
  const preferredId = uiSettings.value.preferred_captain_assistant_id;
  if (preferredId) {
    const preferred = assistants.value.find(a => a.id === preferredId);
    if (preferred) return preferred;
  }
  if (inboxAssistant.value) {
    const inboxMatch = assistants.value.find(
      a => a.id === inboxAssistant.value.id
    );
    if (inboxMatch) return inboxMatch;
  }
  return assistants.value[0];
});

// --- Actions ---
const toggleFold = () => {
  isFolded.value = !isFolded.value;
  updateUISettings({ is_sidebar_folded: isFolded.value });
};

const unfoldToTab = tab => {
  isFolded.value = false;
  activeTab.value = tab;
  updateUISettings({ is_sidebar_folded: false });
};

// --- Resize handlers ---
const onResizeMove = event => {
  if (!isResizing.value) return;
  // Sidebar is on the right: width = viewport width - mouse X position
  const newWidth = window.innerWidth - event.clientX;
  sidebarWidth.value = Math.min(
    SIDEBAR_MAX_WIDTH,
    Math.max(SIDEBAR_MIN_WIDTH, newWidth)
  );
};

const onResizeEnd = () => {
  if (!isResizing.value) return;
  isResizing.value = false;
  document.body.style.cursor = '';
  document.body.style.userSelect = '';
  document.removeEventListener('mousemove', onResizeMove);
  document.removeEventListener('mouseup', onResizeEnd);
  updateUISettings({ sidebar_custom_width: sidebarWidth.value });
};

const onResizeStart = () => {
  isResizing.value = true;
  document.body.style.cursor = 'col-resize';
  document.body.style.userSelect = 'none';
  document.addEventListener('mousemove', onResizeMove);
  document.addEventListener('mouseup', onResizeEnd);
};

onBeforeUnmount(() => {
  document.removeEventListener('mousemove', onResizeMove);
  document.removeEventListener('mouseup', onResizeEnd);
});

const setAssistant = async assistant => {
  await updateUISettings({ preferred_captain_assistant_id: assistant.id });
};

const handleReset = () => {
  const convId = currentConvId.value;
  if (convId) {
    conversationThreadMap.value = {
      ...conversationThreadMap.value,
      [convId]: null,
    };
  }
};

// --- Copilot chat (for freeform questions / suggest answer) ---
const sendMessage = async message => {
  const convId = currentConvId.value;
  if (!convId || !activeAssistant.value) return;
  const threadId = conversationThreadMap.value[convId] || null;

  try {
    if (threadId) {
      await store.dispatch('copilotMessages/create', {
        assistant_id: activeAssistant.value.id,
        conversation_id: convId,
        threadId,
        message,
      });
    } else {
      const response = await store.dispatch('copilotThreads/create', {
        assistant_id: activeAssistant.value.id,
        conversation_id: convId,
        message,
      });
      conversationThreadMap.value = {
        ...conversationThreadMap.value,
        [convId]: response.id,
      };
    }
  } catch (error) {
    useAlert(error.message);
  }
};

const suggestAnswer = () => {
  activeTab.value = 'copilot';
  if (isFolded.value) {
    isFolded.value = false;
    updateUISettings({ is_sidebar_folded: false });
  }
  isWaitingForSuggest.value = true;

  // Simple English prompt — the LLM has access to the full conversation via tools.
  // Language detection and reply language are handled by the system prompt rules.
  const suggestPrompt =
    'Based on the full conversation, draft a reply to the customer.';
  sendMessage(suggestPrompt);
};

// --- Summary management (uses new direct LLM summarization API) ---
const fetchSummary = async (conversationId, force = false) => {
  if (!conversationId) return;
  if (!force && summaryMap.value[conversationId]) return;
  if (summaryLoadingMap.value[conversationId]) return;

  summaryLoadingMap.value = {
    ...summaryLoadingMap.value,
    [conversationId]: true,
  };
  summaryErrorMap.value = {
    ...summaryErrorMap.value,
    [conversationId]: false,
  };

  try {
    const result = await store.dispatch('summarizeConversation', {
      conversationId,
      force,
    });
    if (result?.summary) {
      summaryMap.value = {
        ...summaryMap.value,
        [conversationId]: result.summary,
      };
      // Refresh conversation data to pick up reassigned labels
      store.dispatch('getConversation', conversationId);
    }
  } catch (error) {
    summaryErrorMap.value = {
      ...summaryErrorMap.value,
      [conversationId]: true,
    };
  } finally {
    summaryLoadingMap.value = {
      ...summaryLoadingMap.value,
      [conversationId]: false,
    };
  }
};

const regenerateSummary = () => {
  const convId = currentConvId.value;
  if (convId) {
    summaryMap.value = { ...summaryMap.value, [convId]: null };
    fetchSummary(convId, true);
  }
};

// --- Watch conversation changes ---
watch(
  () => props.currentChat?.id,
  (newId, oldId) => {
    if (newId && newId !== oldId) {
      activeTab.value = 'copilot';
      isWaitingForSuggest.value = false;
      // Fetch inbox assistant for this conversation
      store.dispatch('getInboxCaptainAssistantById', newId);
      // Fetch or generate summary for this conversation
      if (showCopilotTab.value) {
        fetchSummary(newId);
      }
    }
  },
  { immediate: true }
);

// Clear waiting state when messages or streaming content arrive
watch([messages, streamingContent], ([msgs, sc]) => {
  if (isWaitingForSuggest.value && (msgs.length > 0 || sc)) {
    isWaitingForSuggest.value = false;
  }
});

// Also fetch summary when copilot becomes available (feature flag loads async)
watch(showCopilotTab, show => {
  if (show && currentConvId.value && !summaryMap.value[currentConvId.value]) {
    fetchSummary(currentConvId.value);
  }
});

// Keyboard shortcut: Alt+O toggles fold/unfold
const keyboardEvents = {
  'Alt+KeyO': { action: toggleFold },
};
useKeyboardEvents(keyboardEvents);

onMounted(() => {
  if (isEnterprise) {
    store.dispatch('captainAssistants/get');
  }
});
</script>

<template>
  <aside
    class="bg-n-background h-full flex flex-col ltr:border-l rtl:border-r border-n-weak flex-shrink-0 relative"
    :class="{ 'transition-all duration-200 ease-in-out': !isResizing }"
    :style="{
      width: isFolded ? `${SIDEBAR_FOLDED_WIDTH}px` : `${sidebarWidth}px`,
    }"
  >
    <!-- Resize handle (left edge for LTR, right edge for RTL) -->
    <div
      v-if="!isFolded"
      class="absolute top-0 bottom-0 w-1 cursor-col-resize z-10 ltr:left-0 rtl:right-0 group hover:bg-n-iris-6 transition-colors"
      :class="isResizing ? 'bg-n-iris-6' : 'bg-transparent'"
      @mousedown.prevent="onResizeStart"
      @dblclick.prevent="
        () => {
          sidebarWidth = SIDEBAR_DEFAULT_WIDTH;
          updateUISettings({ sidebar_custom_width: SIDEBAR_DEFAULT_WIDTH });
        }
      "
    >
      <div
        class="absolute top-1/2 -translate-y-1/2 ltr:-right-0.5 rtl:-left-0.5 w-1 h-8 rounded-full bg-n-slate-8 opacity-0 group-hover:opacity-100 transition-opacity"
        :class="{ 'opacity-100': isResizing }"
      />
    </div>
    <!-- ==================== Folded State ==================== -->
    <div v-if="isFolded" class="flex flex-col items-center py-3 gap-1 h-full">
      <button
        v-if="showCopilotTab"
        v-tooltip.left="$t('CAPTAIN.COPILOT.TITLE')"
        class="p-2 rounded-lg transition-colors"
        :class="
          activeTab === 'copilot'
            ? 'text-n-iris-9 bg-n-alpha-2'
            : 'text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1'
        "
        @click="unfoldToTab('copilot')"
      >
        <span class="i-woot-captain text-lg block" />
      </button>
      <button
        v-tooltip.left="$t('CONVERSATION.SIDEBAR.CONTACT')"
        class="p-2 rounded-lg transition-colors"
        :class="
          activeTab === 'contact'
            ? 'text-n-brand bg-n-alpha-2'
            : 'text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1'
        "
        @click="unfoldToTab('contact')"
      >
        <span class="i-ph-user-bold text-lg block" />
      </button>
      <div class="flex-1" />
      <button
        v-tooltip.left="$t('CONVERSATION.SIDEBAR.EXPAND')"
        class="p-2 rounded-lg text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
        @click="toggleFold"
      >
        <span class="i-lucide-panel-left-open text-lg block" />
      </button>
    </div>

    <!-- ==================== Expanded State ==================== -->
    <template v-else>
      <!-- Tab Bar -->
      <div
        class="flex items-center border-b border-n-weak h-12 flex-shrink-0 px-1"
      >
        <button
          v-if="showCopilotTab"
          class="flex-1 flex items-center justify-center gap-1.5 h-full text-sm font-medium border-b-2 transition-colors"
          :class="
            activeTab === 'copilot'
              ? 'text-n-iris-9 border-n-iris-9'
              : 'text-n-slate-10 border-transparent hover:text-n-slate-12'
          "
          @click="activeTab = 'copilot'"
        >
          <span class="i-woot-captain text-base" />
          <span>{{ $t('CAPTAIN.COPILOT.TITLE') }}</span>
        </button>
        <button
          class="flex-1 flex items-center justify-center gap-1.5 h-full text-sm font-medium border-b-2 transition-colors"
          :class="
            activeTab === 'contact'
              ? 'text-n-brand border-n-brand'
              : 'text-n-slate-10 border-transparent hover:text-n-slate-12'
          "
          @click="activeTab = 'contact'"
        >
          <span class="i-ph-user-bold text-base" />
          <span>{{ $t('CONVERSATION.SIDEBAR.CONTACT') }}</span>
        </button>
        <!-- Reset button (shown when copilot has messages) -->
        <button
          v-if="activeTab === 'copilot' && messages.length > 0"
          v-tooltip.bottom="$t('CAPTAIN.COPILOT.RESET')"
          class="p-1.5 rounded-md text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
          @click="handleReset"
        >
          <span class="i-lucide-refresh-ccw text-sm block" />
        </button>
        <!-- Fold button -->
        <button
          v-tooltip.bottom="$t('CONVERSATION.SIDEBAR.COLLAPSE')"
          class="p-1.5 mx-0.5 rounded-md text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
          @click="toggleFold"
        >
          <span class="i-lucide-panel-right-close text-base block" />
        </button>
      </div>

      <!-- Copilot Tab Content -->
      <div
        v-if="showCopilotTab"
        v-show="activeTab === 'copilot'"
        class="flex flex-col flex-1 min-h-0 overflow-hidden"
      >
        <!-- Conversation Summary -->
        <CopilotSummary
          :summary="currentSummary"
          :is-loading="isSummaryLoading"
          :has-error="hasSummaryError"
          @regenerate="regenerateSummary"
        />

        <!-- Prominent Suggest Answer Button -->
        <div class="px-3 pb-1 flex-shrink-0">
          <button
            class="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-n-iris-3 text-n-iris-11 hover:bg-n-iris-4 font-medium text-sm transition-colors border border-n-iris-6"
            @click="suggestAnswer"
          >
            <span class="i-lucide-sparkles text-base" />
            {{ $t('CAPTAIN.COPILOT.PROMPTS.SUGGEST.LABEL') }}
          </button>
        </div>

        <!-- Copilot Chat -->
        <div class="flex-1 min-h-0 overflow-hidden">
          <Copilot
            :messages="messages"
            :show-header="false"
            :conversation-inbox-type="conversationInboxType"
            :assistants="assistants"
            :active-assistant="activeAssistant"
            :streaming-content="streamingContent || ''"
            :is-waiting="isWaitingForSuggest"
            @set-assistant="setAssistant"
            @send-message="sendMessage"
            @reset="handleReset"
          />
        </div>
      </div>

      <!-- Contact Tab Content -->
      <div v-show="activeTab === 'contact'" class="flex-1 overflow-auto">
        <ContactPanel
          :conversation-id="currentChat.id"
          :inbox-id="currentChat.inbox_id"
          :show-header="false"
        />
      </div>
    </template>
  </aside>
</template>
