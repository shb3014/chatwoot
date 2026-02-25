<script setup>
import { computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useI18n } from 'vue-i18n';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const conversationsPerPage = computed(
  () => uiSettings.value.conversations_per_page || 25
);

function updateConversationsPerPage(value) {
  const num = Math.min(50, Math.max(10, parseInt(value, 10) || 25));
  updateUISettings({ conversations_per_page: num });
}
</script>

<template>
  <div class="flex flex-col max-w-2xl mx-auto w-full">
    <BaseSettingsHeader
      :title="t('GENERAL_PREFERENCES.TITLE')"
      :description="t('GENERAL_PREFERENCES.DESCRIPTION')"
    />
    <section class="grid grid-cols-1 pt-8 gap-5">
      <header>
        <h4 class="text-lg font-medium text-n-slate-12">
          {{ t('GENERAL_PREFERENCES.CONVERSATION.TITLE') }}
        </h4>
        <p class="text-n-slate-11 text-sm mt-2">
          {{ t('GENERAL_PREFERENCES.CONVERSATION.DESCRIPTION') }}
        </p>
      </header>
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('GENERAL_PREFERENCES.CONVERSATION.PER_PAGE.TITLE') }}
        </label>
        <p class="text-xs text-n-slate-11 mb-1">
          {{ t('GENERAL_PREFERENCES.CONVERSATION.PER_PAGE.NOTE') }}
        </p>
        <input
          type="number"
          min="10"
          max="50"
          step="5"
          :value="conversationsPerPage"
          class="w-24 px-2 py-1.5 rounded-md border border-n-weak text-sm text-n-slate-12 bg-n-solid-2"
          @change="updateConversationsPerPage($event.target.value)"
        />
      </div>
    </section>
  </div>
</template>
