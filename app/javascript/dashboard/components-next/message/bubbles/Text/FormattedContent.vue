<script setup>
import {
  computed,
  ref,
  nextTick,
  onMounted,
  onUpdated,
  onBeforeUnmount,
} from 'vue';
import { useMessageContext } from '../../provider.js';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { MESSAGE_VARIANTS } from '../../constants';

const props = defineProps({
  content: {
    type: String,
    required: true,
  },
});

const { variant } = useMessageContext();
const formattedContentRef = ref(null);
const activeCitation = ref(null);
const citationPosition = ref({ x: 0, y: 0 });
let citationHideTimeout = null;

const formattedContent = computed(() => {
  if (variant.value === MESSAGE_VARIANTS.ACTIVITY) {
    return props.content;
  }

  return new MessageFormatter(props.content).formattedMessage;
});

const popupStyle = computed(() => ({
  left: `${citationPosition.value.x}px`,
  top: `${citationPosition.value.y}px`,
}));

const citationTypeLabel = computed(() => {
  const typeMap = {
    article: 'Help Center Article',
    web_url: 'Web Source',
    faq: 'FAQ',
    document: 'Document',
  };
  return typeMap[activeCitation.value?.type] || 'Source';
});

const adjustPopupPositionWithinViewport = () => {
  const popup = document.querySelector('.citation-popup');
  if (!popup) return;

  const viewportWidth = window.innerWidth;
  const padding = 12;
  const maxWidth = Math.max(160, viewportWidth - padding * 2);
  popup.style.maxWidth = `${maxWidth}px`;
  popup.style.minWidth = `${Math.min(200, maxWidth)}px`;

  // Force reflow after max/min width changes.
  // eslint-disable-next-line no-unused-expressions
  popup.offsetWidth;
  const popupRect = popup.getBoundingClientRect();

  let x = citationPosition.value.x;
  const halfWidth = popupRect.width / 2;
  const minX = padding + halfWidth;
  const maxX = viewportWidth - padding - halfWidth;

  if (maxX >= minX) {
    x = Math.min(Math.max(x, minX), maxX);
  } else {
    x = viewportWidth / 2;
  }

  let y = citationPosition.value.y;
  const popupTop = y - popupRect.height - 8;
  if (popupTop < padding) {
    y = popupRect.height + padding + 8;
  }

  citationPosition.value = { x, y };
};

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

  nextTick(() => {
    adjustPopupPositionWithinViewport();
  });
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
  if (!formattedContentRef.value) return;

  const citations =
    formattedContentRef.value.querySelectorAll('.citation-chip');
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

onBeforeUnmount(() => {
  if (citationHideTimeout) {
    clearTimeout(citationHideTimeout);
  }
});
</script>

<template>
  <span
    ref="formattedContentRef"
    v-dompurify-html="formattedContent"
    class="prose prose-bubble"
  />
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
        <a :href="activeCitation.url" target="_blank" rel="noopener noreferrer">
          {{ activeCitation.title }}
        </a>
      </div>
    </div>
  </Teleport>
</template>

<style scoped lang="scss">
:deep(.citation-chip) {
  @apply inline-flex items-center justify-center min-w-[1.125rem] h-[1.125rem] px-1 text-[10px] font-medium rounded-full cursor-pointer transition-all duration-150;
  @apply bg-n-slate-5 dark:bg-n-slate-7 text-n-slate-11 dark:text-n-slate-11;
  font-style: normal;
  vertical-align: middle;
  margin-left: 2px;
  margin-right: 1px;

  &:hover {
    @apply bg-n-slate-12 dark:bg-n-slate-12 text-white;
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
