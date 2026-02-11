<script setup>
import { computed, ref, onMounted, onUpdated, nextTick } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { useTrack } from 'dashboard/composables';

import { BUS_EVENTS } from 'shared/constants/busEvents';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { COPILOT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  isLastMessage: {
    type: Boolean,
    default: false,
  },
  message: {
    type: Object,
    required: true,
  },
  conversationInboxType: {
    type: String,
    required: true,
  },
});

const messageContentRef = ref(null);
const activeCitation = ref(null);
const citationPosition = ref({ x: 0, y: 0 });
let citationHideTimeout = null;

const hasEmptyMessageContent = computed(() => !props.message?.content);

// Translation comes as a separate field from the backend (second LLM call)
const hasTranslation = computed(() => !!props.message?.translation);

const showTranslation = ref(true);

const showUseButton = computed(() => {
  return (
    !hasEmptyMessageContent.value &&
    props.message.reply_suggestion &&
    props.isLastMessage
  );
});

const messageContent = computed(() => {
  const formatter = new MessageFormatter(props.message.content || '');
  return formatter.formattedMessage;
});

const translationFormattedContent = computed(() => {
  if (!props.message?.translation) return '';
  const formatter = new MessageFormatter(props.message.translation);
  return formatter.formattedMessage;
});

const insertIntoRichEditor = computed(() => {
  return [INBOX_TYPES.WEB, INBOX_TYPES.EMAIL].includes(
    props.conversationInboxType
  );
});

const useCopilotResponse = () => {
  // Insert the primary content (in the customer's language)
  const content = props.message?.content || '';
  if (insertIntoRichEditor.value) {
    emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, content);
  } else {
    emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, content);
  }
  useTrack(COPILOT_EVENTS.USE_CAPTAIN_RESPONSE);
};

const citationTypeLabel = computed(() => {
  const typeMap = {
    article: 'Help Center Article',
    web_url: 'Web Source',
    faq: 'FAQ',
    document: 'Document',
  };
  return typeMap[activeCitation.value?.type] || 'Source';
});

const popupStyle = computed(() => ({
  left: `${citationPosition.value.x}px`,
  top: `${citationPosition.value.y}px`,
}));

const handleCitationEnter = event => {
  // Clear any pending hide timeout
  if (citationHideTimeout) {
    clearTimeout(citationHideTimeout);
    citationHideTimeout = null;
  }
  const chip = event.target;
  const rect = chip.getBoundingClientRect();
  citationPosition.value = {
    x: rect.left + rect.width / 2,
    y: rect.top,
  };
  activeCitation.value = {
    ref: chip.dataset.ref,
    title: chip.dataset.title,
    url: chip.dataset.url,
    type: chip.dataset.type,
  };
};

const handleCitationLeave = () => {
  // Delay hiding to allow mouse to move to popup
  citationHideTimeout = setTimeout(() => {
    activeCitation.value = null;
  }, 100);
};

const handlePopupEnter = () => {
  // Cancel hide when mouse enters popup
  if (citationHideTimeout) {
    clearTimeout(citationHideTimeout);
    citationHideTimeout = null;
  }
};

const handlePopupLeave = () => {
  // Hide popup when mouse leaves it
  activeCitation.value = null;
};

const setupCitationListeners = () => {
  if (!messageContentRef.value) return;
  const citations = messageContentRef.value.querySelectorAll('.citation-chip');
  citations.forEach(chip => {
    chip.removeEventListener('mouseenter', handleCitationEnter);
    chip.removeEventListener('mouseleave', handleCitationLeave);
    chip.addEventListener('mouseenter', handleCitationEnter);
    chip.addEventListener('mouseleave', handleCitationLeave);
  });
};

onMounted(() => {
  nextTick(() => setupCitationListeners());
});

onUpdated(() => {
  nextTick(() => setupCitationListeners());
});
</script>

<template>
  <div class="flex flex-col gap-1 text-n-slate-12">
    <div class="font-medium">{{ $t('CAPTAIN.NAME') }}</div>
    <span v-if="hasEmptyMessageContent" class="text-n-ruby-11">
      {{ $t('CAPTAIN.COPILOT.EMPTY_MESSAGE') }}
    </span>
    <template v-else>
      <!-- Customer-language response (primary) -->
      <div
        ref="messageContentRef"
        v-dompurify-html="messageContent"
        class="prose-sm break-words"
      />
      <!-- Agent-language translation (secondary, from separate LLM call) -->
      <div v-if="hasTranslation" class="mt-2">
        <button
          class="flex items-center gap-1 text-xs text-n-slate-10 hover:text-n-slate-12 transition-colors"
          @click="showTranslation = !showTranslation"
        >
          <span
            class="text-[10px] block transition-transform"
            :class="
              showTranslation
                ? 'i-lucide-chevron-down'
                : 'i-lucide-chevron-right'
            "
          />
          {{ $t('CAPTAIN.COPILOT.AGENT_TRANSLATION') }}
        </button>
        <div
          v-if="showTranslation"
          class="mt-1.5 rounded-md border border-n-weak bg-n-slate-2 px-3 py-2"
        >
          <div
            v-dompurify-html="translationFormattedContent"
            class="prose-sm break-words text-n-slate-11 text-xs leading-relaxed"
          />
        </div>
      </div>
    </template>
    <div class="flex flex-row mt-1">
      <Button
        v-if="showUseButton"
        :label="$t('CAPTAIN.COPILOT.USE')"
        faded
        sm
        slate
        @click="useCopilotResponse"
      />
    </div>
    <!-- Citation Popup -->
    <Teleport to="body">
      <div
        v-if="activeCitation"
        class="citation-popup"
        :style="popupStyle"
        @mouseenter="handlePopupEnter"
        @mouseleave="handlePopupLeave"
      >
        <div class="citation-type">
          <svg
            class="type-icon"
            viewBox="0 0 16 16"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M2 3.5A1.5 1.5 0 0 1 3.5 2h9A1.5 1.5 0 0 1 14 3.5v9a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 12.5v-9ZM4.5 5a.5.5 0 0 0 0 1h7a.5.5 0 0 0 0-1h-7Zm0 2.5a.5.5 0 0 0 0 1h7a.5.5 0 0 0 0-1h-7Zm0 2.5a.5.5 0 0 0 0 1h4a.5.5 0 0 0 0-1h-4Z"
              fill="currentColor"
            />
          </svg>
          <span>{{ citationTypeLabel }}</span>
        </div>
        <div class="citation-title">
          <a
            :href="activeCitation.url"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{ activeCitation.title }}
          </a>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped lang="scss">
.prose-sm {
  :deep(a) {
    color: inherit;
    text-decoration: underline;
    text-decoration-thickness: 1px;
    text-underline-offset: 2px;
  }

  :deep(a:hover) {
    text-decoration-color: transparent;
  }

  :deep(hr) {
    @apply border-0 border-t border-n-weak dark:border-n-strong my-3;
  }

  :deep(.citation-chip) {
    @apply inline-flex items-center justify-center min-w-[1.125rem] h-[1.125rem] px-1 text-[10px] font-medium rounded-full cursor-pointer transition-all duration-150;
    @apply bg-n-slate-4 dark:bg-n-slate-6 text-n-slate-11 dark:text-n-slate-11;
    font-style: normal;
    vertical-align: middle;
    margin-left: 2px;
    margin-right: 1px;

    &:hover {
      @apply bg-n-slate-12 dark:bg-n-slate-12 text-white;
    }
  }
}

.citation-popup {
  @apply bg-white dark:bg-n-solid-2 rounded-lg p-3;
  @apply shadow-[0_4px_16px_rgba(0,0,0,0.12)] dark:shadow-[0_4px_16px_rgba(0,0,0,0.4)];
  @apply border border-n-weak dark:border-n-strong;
  z-index: 9999;
  position: fixed;
  transform: translateX(-50%) translateY(-100%);
  margin-top: -8px;
  min-width: 200px;
  max-width: 280px;
  width: max-content;
  overflow: visible;

  &::after {
    content: '';
    position: absolute;
    width: 8px;
    height: 8px;
    @apply bg-white dark:bg-n-solid-2 border-r border-b border-n-weak dark:border-n-strong;
    bottom: -5px;
    left: 50%;
    transform: translateX(-50%) rotate(45deg);
  }

  .citation-type {
    @apply flex items-center gap-1.5 text-xs text-n-slate-10 mb-1;

    .type-icon {
      @apply w-3.5 h-3.5;
    }
  }

  .citation-title {
    @apply text-sm font-semibold text-n-slate-12 leading-snug;

    a {
      @apply text-n-slate-12 no-underline;

      &:hover {
        @apply underline;
      }
    }
  }
}
</style>
