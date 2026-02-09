<script setup>
import { ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SourceForm from './SourceForm.vue';

const emit = defineEmits(['close']);
const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);

const i18nKey = 'CAPTAIN.SOURCES.CREATE';

const handleSubmit = async newSource => {
  try {
    await store.dispatch('captainSources/create', newSource);
    useAlert(t(`${i18nKey}.SUCCESS_MESSAGE`));
    dialogRef.value.close();
  } catch (error) {
    const errorMessage =
      parseAPIErrorResponse(error) || t(`${i18nKey}.ERROR_MESSAGE`);
    useAlert(errorMessage);
  }
};

const handleClose = () => {
  emit('close');
};

const handleCancel = () => {
  dialogRef.value.close();
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="$t(`${i18nKey}.TITLE`)"
    :description="$t('CAPTAIN.SOURCES.FORM_DESCRIPTION')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="handleClose"
  >
    <SourceForm @submit="handleSubmit" @cancel="handleCancel" />
    <template #footer />
  </Dialog>
</template>
