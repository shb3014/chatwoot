<script setup>
import { computed, ref, onMounted, onUpdated, nextTick } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { useTrack } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

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
  streamingTranslation: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();
const messageContentRef = ref(null);
const translationContentRef = ref(null);
const activeCitation = ref(null);
const citationPosition = ref({ x: 0, y: 0 });
let citationHideTimeout = null;

const hasEmptyMessageContent = computed(() => !props.message?.content);

// ==================== Language Helpers ====================
const LANGUAGE_NAMES = {
  en: 'English',
  zh: 'Chinese',
  ja: 'Japanese',
  ko: 'Korean',
  ar: 'Arabic',
  ru: 'Russian',
  de: 'German',
  fr: 'French',
  es: 'Spanish',
  pt: 'Portuguese',
  it: 'Italian',
  nl: 'Dutch',
};

const customerLanguageCode = computed(
  () => props.message?.customer_language || 'en'
);
const customerLanguageName = computed(
  () => LANGUAGE_NAMES[customerLanguageCode.value] || customerLanguageCode.value
);

// No need for systemLanguageName — the translation tab just says "Translation"

// ==================== Tabs ====================
const effectiveTranslation = computed(
  () => props.message?.translation || props.streamingTranslation || ''
);
const hasTranslation = computed(() => !!effectiveTranslation.value);
// Default to translation tab when available
const activeTab = ref('translation');

// ==================== Content Formatting ====================
const messageContent = computed(() => {
  const formatter = new MessageFormatter(props.message.content || '');
  return formatter.formattedMessage;
});

const translationFormattedContent = computed(() => {
  if (!effectiveTranslation.value) return '';
  const formatter = new MessageFormatter(effectiveTranslation.value);
  return formatter.formattedMessage;
});

// ==================== Sources ====================
const sources = computed(() => props.message?.sources || []);
const hasSources = computed(() => sources.value.length > 0);

const sourceTypeLabel = type => {
  const typeMap = {
    article: t('CAPTAIN.COPILOT.SOURCE_TYPE.ARTICLE'),
    web_url: t('CAPTAIN.COPILOT.SOURCE_TYPE.WEB_URL'),
    faq: t('CAPTAIN.COPILOT.SOURCE_TYPE.FAQ'),
    document: t('CAPTAIN.COPILOT.SOURCE_TYPE.DOCUMENT'),
  };
  return typeMap[type] || t('CAPTAIN.COPILOT.SOURCE_TYPE.DEFAULT');
};

const sourceTypeIcon = type => {
  const iconMap = {
    article: 'i-lucide-book-open',
    web_url: 'i-lucide-globe',
    faq: 'i-lucide-help-circle',
    document: 'i-lucide-file-text',
  };
  return iconMap[type] || 'i-lucide-file-text';
};

// ==================== Buttons ====================
const isReplySuggestion = computed(
  () => props.message?.reply_suggestion && !hasEmptyMessageContent.value
);

const showActionButtons = computed(
  () => isReplySuggestion.value && props.isLastMessage
);

const insertIntoRichEditor = computed(() => {
  return [INBOX_TYPES.WEB, INBOX_TYPES.EMAIL].includes(
    props.conversationInboxType
  );
});

const normalizeForEditorInsert = text => text.replace(/^\s*\n+/, '');

// "Use XX" — inserts the customer-language content (ready to send)
const useCustomerLanguage = () => {
  const content = normalizeForEditorInsert(props.message?.content || '');
  if (insertIntoRichEditor.value) {
    emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, content);
  } else {
    emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, content);
  }
  // Tell the editor what language the customer uses (for translate button)
  emitter.emit(BUS_EVENTS.SET_EDITOR_TRANSLATE_LANGUAGE, {
    language: customerLanguageCode.value,
    languageName: customerLanguageName.value,
  });
  useTrack(COPILOT_EVENTS.USE_CAPTAIN_RESPONSE);
};

// "Edit XX" — inserts the system-language translation (agent can edit then translate)
const editSystemLanguage = () => {
  const content = normalizeForEditorInsert(
    effectiveTranslation.value || props.message?.content || ''
  );
  if (insertIntoRichEditor.value) {
    emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, content);
  } else {
    emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, content);
  }
  // Tell the editor what language the customer uses (for translate button)
  emitter.emit(BUS_EVENTS.SET_EDITOR_TRANSLATE_LANGUAGE, {
    language: customerLanguageCode.value,
    languageName: customerLanguageName.value,
  });
  useTrack(COPILOT_EVENTS.USE_CAPTAIN_RESPONSE);
};

// "Add to reply" — appends a source reference at the bottom of the editor
const addSourceToReply = source => {
  const linkText = `\n\n[${source.title}](${source.url})`;
  if (insertIntoRichEditor.value) {
    emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, linkText);
  } else {
    emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, linkText);
  }
};

// Open a source URL in a new tab
const openSource = url => {
  if (url) window.open(url, '_blank', 'noopener,noreferrer');
};

// ==================== Citation Popup ====================
const citationTypeLabel = computed(() => {
  const typeMap = {
    article: t('CAPTAIN.COPILOT.SOURCE_TYPE.ARTICLE'),
    web_url: t('CAPTAIN.COPILOT.SOURCE_TYPE.WEB_URL'),
    faq: t('CAPTAIN.COPILOT.SOURCE_TYPE.FAQ'),
    document: t('CAPTAIN.COPILOT.SOURCE_TYPE.DOCUMENT'),
  };
  return (
    typeMap[activeCitation.value?.type] ||
    t('CAPTAIN.COPILOT.SOURCE_TYPE.DEFAULT')
  );
});

const popupStyle = computed(() => ({
  left: `${citationPosition.value.x}px`,
  top: `${citationPosition.value.y}px`,
}));

const handleCitationEnter = event => {
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
  citationHideTimeout = setTimeout(() => {
    activeCitation.value = null;
  }, 100);
};

const handlePopupEnter = () => {
  if (citationHideTimeout) {
    clearTimeout(citationHideTimeout);
    citationHideTimeout = null;
  }
};

const handlePopupLeave = () => {
  activeCitation.value = null;
};

const setupCitationListeners = () => {
  [messageContentRef.value, translationContentRef.value].forEach(el => {
    if (!el) return;
    const citations = el.querySelectorAll('.citation-chip');
    citations.forEach(chip => {
      chip.removeEventListener('mouseenter', handleCitationEnter);
      chip.removeEventListener('mouseleave', handleCitationLeave);
      chip.addEventListener('mouseenter', handleCitationEnter);
      chip.addEventListener('mouseleave', handleCitationLeave);
    });
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
    <span v-if="hasEmptyMessageContent" class="text-n-ruby-11">
      {{ $t('CAPTAIN.COPILOT.EMPTY_MESSAGE') }}
    </span>
    <template v-else>
      <!-- ==================== Tabs (only for reply suggestions with translation) ==================== -->
      <div
        v-if="hasTranslation && isReplySuggestion"
        class="flex border-b border-n-weak mb-2"
      >
        <button
          class="flex-1 pb-1.5 text-xs font-medium border-b-2 transition-colors text-center"
          :class="
            activeTab === 'translation'
              ? 'text-n-iris-9 border-n-iris-9'
              : 'text-n-slate-10 border-transparent hover:text-n-slate-12'
          "
          @click="activeTab = 'translation'"
        >
          {{ $t('CAPTAIN.COPILOT.TAB_TRANSLATION') }}
        </button>
        <button
          class="flex-1 pb-1.5 text-xs font-medium border-b-2 transition-colors text-center"
          :class="
            activeTab === 'reply'
              ? 'text-n-iris-9 border-n-iris-9'
              : 'text-n-slate-10 border-transparent hover:text-n-slate-12'
          "
          @click="activeTab = 'reply'"
        >
          {{ $t('CAPTAIN.COPILOT.TAB_REPLY', { lang: customerLanguageName }) }}
        </button>
      </div>

      <!-- ==================== Tab Content ==================== -->
      <!-- Translation tab (system language) — default tab -->
      <div
        v-if="
          hasTranslation && isReplySuggestion && activeTab === 'translation'
        "
        ref="translationContentRef"
        v-dompurify-html="translationFormattedContent"
        class="copilot-prose break-words"
      />

      <!-- Reply tab (customer language) -->
      <div
        v-if="!hasTranslation || !isReplySuggestion || activeTab === 'reply'"
        ref="messageContentRef"
        v-dompurify-html="messageContent"
        class="copilot-prose break-words"
      />

      <!-- ==================== Action Buttons ==================== -->
      <div v-if="showActionButtons" class="flex flex-row gap-2 mt-2">
        <Button
          :label="
            $t('CAPTAIN.COPILOT.USE_LANG', { lang: customerLanguageName })
          "
          faded
          sm
          slate
          icon="i-lucide-send"
          @click="useCustomerLanguage"
        />
        <Button
          v-if="hasTranslation"
          :label="
            $t('CAPTAIN.COPILOT.EDIT_LANG', {
              lang: $t('CAPTAIN.COPILOT.TAB_TRANSLATION'),
            })
          "
          faded
          sm
          slate
          icon="i-lucide-pencil"
          @click="editSystemLanguage"
        />
      </div>

      <!-- ==================== Sources Section ==================== -->
      <div
        v-if="hasSources && isReplySuggestion"
        class="mt-3 pt-3 border-t border-n-weak"
      >
        <div
          class="flex items-center gap-1.5 text-xs font-medium text-n-slate-10 mb-2"
        >
          <span class="i-lucide-library text-sm" />
          {{ $t('CAPTAIN.COPILOT.SOURCES_TITLE') }}
        </div>
        <div class="flex flex-col gap-1.5">
          <div
            v-for="(source, index) in sources"
            :key="index"
            class="flex items-center gap-2 rounded-md border border-n-weak bg-n-alpha-1 px-2.5 py-2 group hover:bg-n-alpha-2 transition-colors"
          >
            <span
              :class="sourceTypeIcon(source.type)"
              class="text-n-slate-9 text-sm flex-shrink-0"
            />
            <div class="flex-1 min-w-0">
              <a
                v-if="source.url"
                :href="source.url"
                target="_blank"
                rel="noopener noreferrer"
                class="text-xs font-medium text-n-slate-12 hover:underline truncate block"
              >
                {{ source.title || source.url }}
              </a>
              <span
                v-else
                class="text-xs font-medium text-n-slate-12 truncate block"
              >
                {{ source.title }}
              </span>
              <span class="text-[10px] text-n-slate-9">
                {{ sourceTypeLabel(source.type) }}
              </span>
            </div>
            <div
              class="flex items-center gap-1 flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
            >
              <button
                v-if="source.url"
                v-tooltip="$t('CAPTAIN.COPILOT.VIEW_SOURCE')"
                class="p-1 rounded text-n-slate-9 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
                @click.stop="openSource(source.url)"
              >
                <span class="i-lucide-external-link text-xs block" />
              </button>
              <button
                v-tooltip="$t('CAPTAIN.COPILOT.ADD_TO_REPLY')"
                class="p-1 rounded text-n-slate-9 hover:text-n-iris-11 hover:bg-n-iris-3 transition-colors"
                @click.stop="addSourceToReply(source)"
              >
                <span class="i-lucide-plus text-xs block" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </template>

    <!-- ==================== Citation Popup ==================== -->
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
.copilot-prose {
  font-size: 0.8125rem; /* 13px — slightly smaller than default 14px */
  line-height: 1.625;

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
