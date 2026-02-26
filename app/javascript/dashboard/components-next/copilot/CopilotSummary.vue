<script setup>
import { computed } from 'vue';
const props = defineProps({
  summary: {
    type: Object,
    default: null,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  hasError: {
    type: Boolean,
    default: false,
  },
  // When true, the summary area has been fetched but no content exists yet.
  isFetched: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['regenerate']);

const summaryContent = computed(() => props.summary?.content || '');
const summaryLabels = computed(() => props.summary?.labels || []);
const hasSummary = computed(
  () => props.summary && summaryContent.value.length > 0
);
</script>

<template>
  <div class="px-3 py-2 flex-shrink-0">
    <!-- Loading state -->
    <div
      v-if="isLoading"
      class="rounded-lg border border-n-weak bg-n-slate-2 p-3"
    >
      <div class="flex items-center gap-2 text-n-slate-10 text-sm">
        <span class="i-lucide-loader-2 animate-spin text-base" />
        <span>{{ $t('CAPTAIN.COPILOT.SUMMARY.GENERATING') }}</span>
      </div>
    </div>

    <!-- Error state -->
    <div
      v-else-if="hasError"
      class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 p-3"
    >
      <div class="flex items-center justify-between">
        <span class="text-n-ruby-11 text-sm">
          {{ $t('CAPTAIN.COPILOT.SUMMARY.ERROR') }}
        </span>
        <button
          class="text-xs text-n-ruby-11 underline hover:text-n-ruby-12"
          @click="emit('regenerate')"
        >
          {{ $t('CAPTAIN.COPILOT.SUMMARY.RETRY') }}
        </button>
      </div>
    </div>

    <!-- Summary content -->
    <div
      v-else-if="hasSummary"
      class="rounded-lg border border-n-weak bg-n-slate-2 p-3 space-y-2"
    >
      <div class="flex items-center justify-between">
        <div
          class="flex items-center gap-1.5 text-xs font-medium text-n-slate-10 uppercase tracking-wider"
        >
          <span class="i-lucide-file-text text-sm" />
          {{ $t('CAPTAIN.COPILOT.SUMMARY.TITLE') }}
        </div>
        <button
          v-tooltip.top="$t('CAPTAIN.COPILOT.SUMMARY.REGENERATE')"
          class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
          @click="emit('regenerate')"
        >
          <span class="i-lucide-refresh-ccw text-xs block" />
        </button>
      </div>
      <p class="text-sm text-n-slate-12 leading-relaxed">
        {{ summaryContent }}
      </p>
      <div v-if="summaryLabels.length > 0" class="flex flex-wrap gap-1.5 pt-1">
        <span
          v-for="label in summaryLabels"
          :key="label"
          class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-n-iris-3 text-n-iris-11 border border-n-iris-6"
        >
          {{ label }}
        </span>
      </div>
    </div>

    <!-- Empty state: fetched but no summary available (e.g. exclusive label skipped auto-summarization) -->
    <div
      v-else-if="isFetched"
      class="rounded-lg border border-n-weak bg-n-slate-2 p-3 space-y-2"
    >
      <div class="flex items-center justify-between">
        <div
          class="flex items-center gap-1.5 text-xs font-medium text-n-slate-10 uppercase tracking-wider"
        >
          <span class="i-lucide-file-text text-sm" />
          {{ $t('CAPTAIN.COPILOT.SUMMARY.TITLE') }}
        </div>
        <button
          v-tooltip.top="$t('CAPTAIN.COPILOT.SUMMARY.GENERATE')"
          class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
          @click="emit('regenerate')"
        >
          <span class="i-lucide-refresh-ccw text-xs block" />
        </button>
      </div>
      <p class="text-sm text-n-slate-10 italic">
        {{ $t('CAPTAIN.COPILOT.SUMMARY.EMPTY') }}
      </p>
    </div>
  </div>
</template>
