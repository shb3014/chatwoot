<script setup>
import { ref, computed, watch, onMounted, nextTick, useSlots } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';

const props = defineProps({
  conversationId: {
    type: Number,
    required: true,
  },
  conversationLabels: {
    type: Array,
    required: true,
  },
});

const slots = useSlots();
const accountLabels = useMapGetter('labels/getLabels');
const store = useStore();

const activeLabels = computed(() => {
  return accountLabels.value.filter(({ title }) =>
    props.conversationLabels.includes(title)
  );
});

const showAllLabels = ref(false);
const showExpandLabelButton = ref(false);
const labelPosition = ref(-1);
const labelContainer = ref(null);
const hoveredLabelTitle = ref(null);
const isUpdatingLabel = ref(false);

const computeVisibleLabelPosition = () => {
  const beforeSlot = slots.before ? 100 : 0;
  if (!labelContainer.value) {
    return;
  }

  const labels = Array.from(labelContainer.value.querySelectorAll('.label'));
  let labelOffset = 0;
  showExpandLabelButton.value = false;
  labels.forEach((label, index) => {
    labelOffset += label.offsetWidth + 8;

    if (labelOffset < labelContainer.value.clientWidth - beforeSlot) {
      labelPosition.value = index;
    } else {
      showExpandLabelButton.value = labels.length > 1;
    }
  });
};

watch(activeLabels, () => {
  nextTick(() => computeVisibleLabelPosition());
});

onMounted(() => {
  computeVisibleLabelPosition();
});

const onShowLabels = e => {
  e.stopPropagation();
  showAllLabels.value = !showAllLabels.value;
  nextTick(() => computeVisibleLabelPosition());
};

const onRemoveLabel = async labelTitle => {
  if (!labelTitle || isUpdatingLabel.value) return;
  isUpdatingLabel.value = true;
  try {
    const nextLabels = (props.conversationLabels || []).filter(
      title => title !== labelTitle
    );
    await store.dispatch('conversationLabels/update', {
      conversationId: props.conversationId,
      labels: nextLabels,
    });
    // Refresh the conversation object in list for immediate UI sync
    await store.dispatch('getConversation', props.conversationId);
  } finally {
    isUpdatingLabel.value = false;
    hoveredLabelTitle.value = null;
  }
};
</script>

<template>
  <div ref="labelContainer" v-resize="computeVisibleLabelPosition">
    <div
      v-if="activeLabels.length || $slots.before"
      class="flex items-end flex-shrink min-w-0 gap-y-1"
      :class="{ 'h-auto overflow-visible flex-row flex-wrap': showAllLabels }"
    >
      <slot name="before" />
      <div
        v-for="(label, index) in activeLabels"
        :key="label ? label.id : index"
        class="inline-flex"
        :class="{
          'invisible absolute': !showAllLabels && index > labelPosition,
        }"
        @mouseenter="hoveredLabelTitle = label.title"
        @mouseleave="hoveredLabelTitle = null"
        @click.stop
      >
        <woot-label
          :title="label.title"
          :description="label.description"
          :color="label.color"
          variant="smooth"
          class="!mb-0 max-w-[calc(100%-0.5rem)]"
          small
          :show-close="hoveredLabelTitle === label.title"
          @remove="onRemoveLabel"
        />
      </div>
      <button
        v-if="showExpandLabelButton"
        :title="
          showAllLabels
            ? $t('CONVERSATION.CARD.HIDE_LABELS')
            : $t('CONVERSATION.CARD.SHOW_LABELS')
        "
        class="h-5 py-0 px-1 flex-shrink-0 mr-6 ml-0 rtl:ml-6 rtl:mr-0 rtl:rotate-180 text-n-slate-11 border-n-strong dark:border-n-strong"
        @click="onShowLabels"
      >
        <fluent-icon
          :icon="showAllLabels ? 'chevron-left' : 'chevron-right'"
          size="12"
        />
      </button>
    </div>
  </div>
</template>
