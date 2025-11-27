<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRoute } from 'vue-router';
import allLocales from 'shared/constants/locales.js';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import ArticlesAPI from 'dashboard/api/helpCenter/articles';

const props = defineProps({
  articleId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['success', 'close']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const getPortal = useMapGetter('portals/portalBySlug');

const dialogRef = ref(null);
const isUpdating = ref(false);
const selectedLocale = ref('');

onMounted(() => {
  dialogRef.value?.open();
});

const portal = computed(() => getPortal.value(route.params.portalSlug));

const locales = computed(() => {
  const allowedLocales = portal.value?.config?.allowed_locales || [];

  return allowedLocales.map(localeCode => ({
    value: localeCode,
    label: `${allLocales[localeCode] || localeCode} (${localeCode})`,
  }));
});

const onTranslate = async () => {
  if (!selectedLocale.value) return;

  isUpdating.value = true;
  try {
    await ArticlesAPI.translateArticle({
      portalSlug: route.params.portalSlug,
      articleId: props.articleId,
      targetLocale: selectedLocale.value,
    });

    useAlert(t('HELP_CENTER.TRANSLATE_ARTICLE_DIALOG.API.SUCCESS_MESSAGE'));
    emit('success');
    dialogRef.value?.close();
    emit('close');
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
      error?.message ||
      t('HELP_CENTER.TRANSLATE_ARTICLE_DIALOG.API.ERROR_MESSAGE')
    );
  } finally {
    isUpdating.value = false;
  }
};

const onClose = () => {
  emit('close');
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="confirm"
    :title="t('HELP_CENTER.TRANSLATE_ARTICLE_DIALOG.TITLE')"
    :description="t('HELP_CENTER.TRANSLATE_ARTICLE_DIALOG.DESCRIPTION')"
    :confirm-text="t('HELP_CENTER.TRANSLATE_ARTICLE_DIALOG.CONFIRM')"
    :cancel-text="t('HELP_CENTER.TRANSLATE_ARTICLE_DIALOG.CANCEL')"
    :is-loading="isUpdating"
    @confirm="onTranslate"
    @close="onClose"
  >
    <div class="flex flex-col gap-6">
      <ComboBox
        v-model="selectedLocale"
        :options="locales"
        :placeholder="t('HELP_CENTER.TRANSLATE_ARTICLE_DIALOG.COMBOBOX.PLACEHOLDER')"
        class="[&>div>button:not(.focused)]:!outline-n-slate-5 [&>div>button:not(.focused)]:dark:!outline-n-slate-5"
      />
    </div>
  </Dialog>
</template>

