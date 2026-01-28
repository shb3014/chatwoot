<script setup>
import { toRef } from 'vue';
import { useRouter } from 'vue-router';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import HeaderActions from './HeaderActions.vue';
import AvailabilityContainer from 'widget/components/Availability/AvailabilityContainer.vue';
import { useAvailability } from 'widget/composables/useAvailability';

const props = defineProps({
  avatarUrl: { type: String, default: '' },
  title: { type: String, default: '' },
  showPopoutButton: { type: Boolean, default: false },
  showBackButton: { type: Boolean, default: false },
  availableAgents: { type: Array, default: () => [] },
});

const availableAgents = toRef(props, 'availableAgents');

const router = useRouter();
const { isOnline } = useAvailability(availableAgents);

const onBackButtonClick = () => {
  router.replace({ name: 'home' });
};
</script>

<template>
  <header class="chat-header flex justify-between w-full px-4 py-3 gap-2">
    <div class="flex items-center">
      <button
        v-if="showBackButton"
        class="group px-2 ltr:-ml-2 rtl:-mr-2 rounded-md transition-colors duration-150 hover:bg-n-slate-2"
        @click="onBackButtonClick"
      >
        <FluentIcon
          icon="chevron-left"
          size="18"
          class="text-n-slate-12 transition-colors duration-150 group-hover:text-n-slate-11"
        />
      </button>
      <img
        v-if="avatarUrl"
        class="w-7 h-7 ltr:mr-2 rtl:ml-2 rounded-full"
        :src="avatarUrl"
        alt="avatar"
      />
      <div class="flex flex-col gap-1">
        <div
          class="flex items-center text-sm font-semibold leading-4 text-n-slate-12"
        >
          <span v-dompurify-html="title" class="ltr:mr-1 rtl:ml-1" />
          <div
            :class="`h-2 w-2 rounded-full
              ${isOnline ? 'bg-n-teal-10' : 'hidden'}`"
          />
        </div>
        <AvailabilityContainer
          :agents="availableAgents"
          :show-header="false"
          :show-avatars="false"
          text-classes="text-xs leading-3"
        />
      </div>
    </div>
    <HeaderActions :show-popout-button="showPopoutButton" />
  </header>
</template>

<style scoped lang="scss">
.chat-header {
  @apply bg-n-background border-b border-solid;
  border-bottom-color: rgb(229, 231, 235);
}
</style>
