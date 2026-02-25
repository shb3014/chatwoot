<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  label: {
    type: Object,
    default: null,
  },
  isHovered: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['remove', 'hover']);

const chipStyle = computed(() => ({
  backgroundColor: `${props.label.color}25`,
  color: props.label.color,
  borderColor: `${props.label.color}30`,
}));

const handleRemoveLabel = () => {
  emit('remove', props.label);
};

const handleMouseEnter = () => {
  emit('hover', props.label?.id);
};
</script>

<template>
  <div
    class="inline-flex items-center overflow-hidden transition-all duration-300 ease-out rounded-full border px-2 py-[2px] text-[11px] leading-[1.15]"
    :style="chipStyle"
    @mouseenter="handleMouseEnter"
  >
    <span class="text-[11px] font-medium whitespace-nowrap">
      {{ label.title }}
    </span>
    <div
      class="w-0 flex flex-shrink-0 overflow-hidden transition-[width] duration-300 ease-out"
      :class="{ 'w-5': isHovered }"
    >
      <Button
        class="transition-opacity duration-200 !h-5 !w-5 !min-w-0 !p-0 rounded-full bg-transparent"
        :class="{ 'opacity-0': !isHovered, 'opacity-100': isHovered }"
        type="button"
        slate
        xs
        faded
        icon="i-lucide-x"
        @click="handleRemoveLabel"
      />
    </div>
  </div>
</template>
