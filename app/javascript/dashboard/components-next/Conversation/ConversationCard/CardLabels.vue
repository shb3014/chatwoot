<script setup>
import { ref, computed } from 'vue';

const props = defineProps({
  conversationLabels: {
    type: Array,
    required: true,
  },
  accountLabels: {
    type: Array,
    required: true,
  },
});

const WIDTH_CONFIG = Object.freeze({
  DEFAULT_WIDTH: 80,
  CHAR_WIDTH: {
    SHORT: 8, // For labels <= 5 chars
    LONG: 6, // For labels > 5 chars
  },
  BASE_WIDTH: 12, // dot + gap
  THRESHOLD: 5, // character length threshold
});

const containerRef = ref(null);
const maxLabels = ref(1);

const activeLabels = computed(() => {
  const labelSet = new Set(props.conversationLabels);
  return props.accountLabels?.filter(({ title }) => labelSet.has(title));
});

const calculateLabelWidth = ({ title = '' }) => {
  const charWidth =
    title.length > WIDTH_CONFIG.THRESHOLD
      ? WIDTH_CONFIG.CHAR_WIDTH.LONG
      : WIDTH_CONFIG.CHAR_WIDTH.SHORT;

  return title.length * charWidth + WIDTH_CONFIG.BASE_WIDTH;
};

const getAverageWidth = labels => {
  if (!labels.length) return WIDTH_CONFIG.DEFAULT_WIDTH;

  const totalWidth = labels.reduce(
    (sum, label) => sum + calculateLabelWidth(label),
    0
  );

  return totalWidth / labels.length;
};

const visibleLabels = computed(() =>
  activeLabels.value?.slice(0, maxLabels.value)
);

const updateVisibleLabels = () => {
  if (!containerRef.value) return;

  const containerWidth = containerRef.value.offsetWidth;
  const avgWidth = getAverageWidth(activeLabels.value);

  maxLabels.value = Math.max(1, Math.floor(containerWidth / avgWidth));
};
</script>

<template>
  <div
    ref="containerRef"
    v-resize="updateVisibleLabels"
    class="flex items-center gap-2.5 w-full min-w-0 h-6 overflow-hidden"
  >
    <template v-for="(label, index) in visibleLabels" :key="label.id">
      <span
        class="inline-flex items-center rounded-full px-2 py-[2px] text-[11px] leading-[1.15] font-medium border min-w-0"
        :class="[
          index === visibleLabels.length - 1 ? 'flex-shrink' : 'flex-shrink-0',
        ]"
        :style="{
          backgroundColor: `${label.color}25`,
          color: label.color,
          borderColor: `${label.color}30`,
        }"
      >
        <span
          class="whitespace-nowrap"
          :class="{ truncate: index === visibleLabels.length - 1 }"
        >
          {{ label.title }}
        </span>
      </span>
    </template>
  </div>
</template>
