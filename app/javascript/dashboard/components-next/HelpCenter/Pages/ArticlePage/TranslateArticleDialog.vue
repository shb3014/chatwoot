<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRoute } from 'vue-router';
import allLocales from 'shared/constants/locales.js';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({
  article: {
    type: Object,
    required: true,
  },
  portal: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['close', 'translate-success']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();

const dialogRef = ref(null);
const isTranslating = ref(false);

const selectedLocale = ref('');

const allowedLocales = computed(() => {
  const { allowed_locales: allowedLocales = [] } = props.portal?.config || {};
  return allowedLocales.map(locale => locale.code);
});

const availableLocales = computed(() => {
  return Object.keys(allLocales)
    .map(key => {
      return {
        value: key,
        label: `${allLocales[key]} (${key})`,
      };
    })
    .filter(locale => allowedLocales.value.includes(locale.value) && locale.value !== props.article.locale);
});

const onTranslate = async () => {
  if (!selectedLocale.value) return;

  isTranslating.value = true;

  try {
    await store.dispatch('articles/translate', {
      portalSlug: route.params.portalSlug,
      articleId: props.article.id,
      targetLocale: selectedLocale.value,
    });

    dialogRef.value?.close();
    useAlert(
      t('HELP_CENTER.TRANSLATE_ARTICLE.API.SUCCESS_MESSAGE')
    );
    emit('translate-success');
  } catch (error) {
    useAlert(
      error?.message ||
        t('HELP_CENTER.TRANSLATE_ARTICLE.API.ERROR_MESSAGE')
    );
  } finally {
    isTranslating.value = false;
  }
};

// Expose the dialogRef to the parent component
defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="t('HELP_CENTER.TRANSLATE_ARTICLE.DIALOG.TITLE')"
    :description="t('HELP_CENTER.TRANSLATE_ARTICLE.DIALOG.DESCRIPTION')"
    @confirm="onTranslate"
    :is-submitting="isTranslating"
  >
    <div class="flex flex-col gap-6">
      <ComboBox
        v-model="selectedLocale"
        :options="availableLocales"
        :placeholder="
          t('HELP_CENTER.TRANSLATE_ARTICLE.DIALOG.COMBOBOX.PLACEHOLDER')
        "
        class="[&>div>button:not(.focused)]:!outline-n-slate-5 [&>div>button:not(.focused)]:dark:!outline-n-slate-5"
      />
    </div>
  </Dialog>
</template>