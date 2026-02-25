<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  label: { type: String, required: true },
  active: { type: Boolean, default: false },
  labelData: { type: Object, required: true },
});

const unreadCounts = useMapGetter('labels/getLabelUnreadCounts');

const count = computed(() => {
  const raw = unreadCounts.value?.[props.labelData.title] || 0;
  return raw > 99 ? '99+' : raw;
});

const chipStyle = computed(() => ({
  backgroundColor: `${props.labelData.color}25`,
  color: props.labelData.color,
  borderColor: `${props.labelData.color}30`,
}));
</script>

<template>
  <span
    class="inline-flex items-center rounded-full px-2 py-[2px] text-[11px] leading-[1.15] font-medium border max-w-full min-w-0"
    :style="chipStyle"
  >
    <span class="truncate">{{ label }}</span>
  </span>
  <span
    v-if="count"
    class="rounded-full text-[11px] leading-4 font-medium text-center px-1.5 flex-shrink-0 min-w-[20px]"
    :class="{
      'text-n-blue-text bg-n-alpha-2': active,
      'text-n-slate-11 bg-n-slate-3': !active,
    }"
  >
    {{ count }}
  </span>
</template>
